#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""快照接线层：把四个快照工具从 mock 内存态切到服务端持久快照。

## 这一层解决什么

`CHECKD_SNAPSHOT_MODE=off`（默认）时，`app._call()` 一律走 `tool_server.call_tool`，
提案活在 `tool_server.STATE["proposals"]` 这个内存字典里 —— 进程一重启就没了，
而且 `base_version` 是 `sha256({snapshot,user})` 现算的，检测不了重放。

`mode=on` 时由本模块接管这四个工具：

| 工具 | 数据来源 | 权威在哪 |
|---|---|---|
| `generate_schedule` | 服务端自己读 tasks/courses/events | 落库的 snapshot + proposal |
| `validate_schedule` | 库里的 plan + 重算的输入摘要 | 库 |
| `request_approval` | 库里的 validation_status / expires_at | 库判过期 |
| `apply_approved_changes` | 库里的 plan（不接收调用方重传） | 库，同事务锁 |

请求体里的 `tasks` / `courses` / `base_version` / `snapshot_ref` **一律拒收**：
M0 2026-11-07T03:36:48Z 工单 §三 第 3 条要求服务端用自己读到的数据，
契约 L514 又明写 apply 时不得接受调用方重新提交的 Proposal。两处都指向同一件事：
**可信输入只能来自服务端**。

## 本层刻意不做的事

- **不改 migration**：库表结构已由 `migrations/0001_snapshot_r3.sql` 定死。
  库里 `proposal.status` 闭集是 `pending/applied/rejected/expired`，没有契约的
  `pending_approval`；出参映射放在 `proposal_assembly.contract_status`，
  本层不往库里写契约值（写了会撞 CHECK）。
- **不建审批表**：库里只有四张表。审批记录仍写 `tool_server` 的 approvals
  （内存 + `approvals.json`）。→ 这是**已知缺口**：apply 前的审批校验不是库内事务，
  进程重启后审批态可能丢。M0 的 B 包没要求这一项，但演示链路会受影响，
  已记进 AUTO-INBOX「待主会话」，不在这里自己扩表。
- **不冒充真实审批**：`approval_url` 仍指向 `approval.mock.local`，
  G5 的 token 链（独立审批服务、私钥签发、撤销、外部确认页）依旧 BLOCKED。
"""

import os

import proposal_assembly as pa
import snapshot_store as ss

TZ = pa.TZ

# 与 app.SNAPSHOT_TOOLS 保持同一集合。两处都写是为了让本模块可单独被测试，
# 不 import app（app 一 import 就会拉起 HTTP server 的模块级状态）。
SNAPSHOT_TOOLS = frozenset({
    "generate_schedule", "validate_schedule",
    "request_approval", "apply_approved_changes",
})

# M0 B 包第 8 条：写白名单为空 → 一律拒绝真实 apply。
WRITE_ALLOWLIST_ENV = "CHECKD_DEMO_WRITE_ALLOWLIST"

_MOCK = None


def _default_mock():
    """延迟 import tool_server。

    它不在 `tools/m1-server/` 里（在 `tools/m1-mock/`），部署时由
    `build_deploy.py` 合并到同一目录。测试里由调用方注入，避免依赖 import 路径。
    """
    global _MOCK
    if _MOCK is None:
        import tool_server as _m
        _MOCK = _m
    return _MOCK


def _bad(code, message, **details):
    raise ss.SnapshotStoreError(code, message, details=details or None)


def _text(value, field):
    if not isinstance(value, str) or not value.strip():
        _bad("INVALID_ARGUMENT", "%s 必须是非空字符串。" % field, field=field)
    return value


class SnapshotTools:
    """四个快照工具的服务端实现。"""

    def __init__(self, store, mock_module=None, assembler=None):
        self._store = store
        self._mock = mock_module
        self._asm = assembler or pa.ProposalAssembler(store)

    # ---------------- 基础设施 ----------------

    def _m(self):
        return self._mock if self._mock is not None else _default_mock()

    def call(self, name, args, user):
        """分派。返回 structuredContent 形状（信封由 app 层统一包）。"""
        if name == "generate_schedule":
            return self._generate(user, args)
        if name == "validate_schedule":
            return self._validate(user, args)
        if name == "request_approval":
            return self._request_approval(user, args)
        if name == "apply_approved_changes":
            return self._apply(user, args)
        _bad("INVALID_ARGUMENT", "未知工具：%s" % name)

    # ---------------- 服务端权威输入 ----------------

    def _inputs(self, user, start, end, external_fixed_events):
        """从服务端数据源读调度输入。**不读请求体**。

        目前服务端数据源仍是 `tool_server.STATE`（演示数据集）。快照模式要解决的
        是"提案有没有持久化"，不是"任务数据存哪里"；后者属 App 侧的库，不在本包范围。
        这条边界必须写清，否则会把"接上了快照"误读成"整套数据都持久化了"。
        """
        m = self._m()
        payload, _digest = m.snapshot_for(user, start, end, external_fixed_events)
        return {
            "tasks": payload["tasks"],
            "courses": payload["courses"],
            "events": m.calendar_events_for(payload),
            "daily_overrides": payload["overrides"],
        }

    def _run_scheduler(self, args, inp, user, ext):
        """跑一次调度，只取内部四部分。

        `tool_generate_schedule` 现在兼作引擎替身，它返回的 dict 里带着
        `proposal_id` / `base_version` / `status` 等**服务端专有字段**。
        这些字段在这里全部丢掉 —— 组装层 `assert_internal_only` 也会拦，
        两道都在，是因为"顺手透传"是这一层最容易犯的错。
        """
        m = self._m()
        clean = dict(args)
        clean["input"] = {"date_range": inp["date_range"]}
        if "preferences" in inp:
            clean["input"]["preferences"] = inp["preferences"]
        if ext:
            clean["input"]["external_fixed_events"] = ext
        out = m.tool_generate_schedule(clean, user)
        return {k: (out.get(k) or []) for k in pa.INTERNAL_PARTS}

    # ---------------- 1. generate_schedule ----------------

    def _generate(self, user, args):
        m = self._m()
        inp = m.validate_envelope(args)
        for key in ("tasks", "courses", "base_version", "snapshot_ref"):
            if key in inp:
                _bad("INVALID_ARGUMENT",
                     "远程调用不得提交 tasks/courses/base_version/snapshot_ref。",
                     field=key)
        start, end = m.date_range(inp)
        ext = inp.get("external_fixed_events") or []
        prefs = inp.get("preferences") or {}

        inputs = self._inputs(user, start, end, ext)
        internal = self._run_scheduler(args, inp, user, ext)

        return self._asm.assemble(
            user, start.isoformat(), end.isoformat(), internal,
            inputs["tasks"], inputs["courses"], inputs["events"],
            daily_overrides=inputs["daily_overrides"],
            preferences=prefs,
            external_fixed_events=ext,
        )

    # ---------------- 2. validate_schedule ----------------

    def _validate(self, user, args):
        m = self._m()
        inp = m.validate_envelope(args)
        pid = _text(inp.get("proposal_id"), "proposal_id")

        gate = self._store.proposal_gate(pid, user)
        if gate["status"] == "applied":
            _bad("ALREADY_APPLIED", "提案已应用，不能再次校验。",
                 proposal_id=pid)
        # P0-1（M3 2026-11-07 审查）：快照过期后不得再校验。
        # 以前只看 proposal.expires_at，快照 TTL 存了却没人读 —— 调短就漏。
        # 复用契约已有的 SNAPSHOT_CONFLICT，不新增错误码。
        if gate["snapshot_expired"]:
            _bad("SNAPSHOT_CONFLICT", "快照已过期，需重新生成提案。",
                 snapshot_id=gate["snapshot_id"])

        snap = self._store.get_snapshot_payload(gate["snapshot_id"], user)
        payload = snap.get("payload") or {}
        ext = payload.get("external_fixed_events") or []
        prefs = payload.get("preferences") or {}

        # 快照是否已过期，用当前服务端数据重算同一份规范化输入再比摘要。
        # 不能在库里"用快照自己算自己"——那样永远相等，等于没校验。
        start = _parse_date(snap["date_from"])
        end = _parse_date(snap["date_to"])
        inputs = self._inputs(user, start, end, ext)
        current = pa.build_snapshot_input(
            snap["date_from"], snap["date_to"], inputs["tasks"], inputs["courses"],
            inputs["events"], daily_overrides=inputs["daily_overrides"],
            preferences=prefs, external_fixed_events=ext, timezone=TZ)
        cur_digest, _nbytes = ss.payload_digest(current)
        if cur_digest != snap["payload_digest"]:
            _bad("SNAPSHOT_CONFLICT", "快照已变化，需重新生成提案。",
                 snapshot_id=snap["snapshot_id"],
                 snapshot_version=snap["version"])

        plan = gate.get("plan") or {}
        if not isinstance(plan, dict):
            _bad("INTERNAL_ERROR", "提案缺少已保存的方案内容，无法校验。")
        changes = pa.validate_changes(plan.get("changes"))
        # 直接用 plan 铺底，而不是只挑三个键：校验函数会读 blocks/changes/
        # unplanned_tasks 以及若干派生字段，少给一个键就是 KeyError（500），
        # 会被误读成"服务端崩了"而不是"这份数据有问题"。
        proxy = dict(plan)
        proxy["proposal_id"] = pid
        proxy["changes"] = changes
        # 这两条用的是 mock 侧既有的校验实现（契约 L… 的硬约束语义已在那边实现过），
        # 本层不重写一份，避免两套判据慢慢分叉。
        m.check_items_exist(proxy)
        violations = m.check_hard_constraints(proxy, inputs["events"])

        validation_status = "invalid" if violations else "valid"
        self._store.set_validation(pid, user, validation_status)

        return {
            "proposal_id": pid,
            "snapshot_ref": gate["snapshot_id"],
            "base_version": gate["base_version"],
            "proposal_status": ("draft" if violations else "pending_approval"),
            "validation_status": validation_status,
            "approval_readiness": ("not_approvable" if violations
                                   else "not_requested"),
            "violations": violations,
            "expires_at": gate["expires_at"],
        }

    # ---------------- 3. request_approval ----------------

    def _request_approval(self, user, args):
        m = self._m()
        inp = m.validate_envelope(args)
        pid = _text(inp.get("proposal_id"), "proposal_id")
        key = _text(inp.get("idempotency_key"), "idempotency_key")

        gate = self._store.proposal_gate(pid, user)
        if gate["status"] == "applied":
            _bad("ALREADY_APPLIED", "提案已应用，不能再次审批。", proposal_id=pid)
        if gate["expired"] or gate["status"] == "expired":
            _bad("PROPOSAL_EXPIRED", "提案已过期。", proposal_id=pid)
        if gate["snapshot_expired"]:
            _bad("SNAPSHOT_CONFLICT", "快照已过期，需重新生成提案。",
                 snapshot_id=gate["snapshot_id"])
        if gate["validation_status"] != "valid":
            _bad("PROPOSAL_INVALID", "提案尚未通过校验。",
                 validation_status=gate["validation_status"])

        idem = (user, "request_approval", key)
        req_digest = m.digest({"proposal": pid, "action": "request_approval"})
        cached = m.STATE["idempotency"].get(idem)
        if cached:
            if cached["digest"] != req_digest:
                _bad("IDEMPOTENCY_CONFLICT", "幂等键被用于其他提案。")
            return cached["result"]

        existing = _latest_approval(m, pid, user)
        if existing is not None:
            result = {
                "approval_id": existing["approval_id"],
                "proposal_id": pid,
                "status": m.apply_approval_status(existing),
                "approval_url": existing["url"],
                "expires_at": existing["expires_at"],
            }
            m.STATE["idempotency"][idem] = {"digest": req_digest, "result": result}
            return result

        aid = m._next_id("appr")
        now = m.now()
        # 审批有效期不得超过提案有效期：提案都过期了还挂着可批的审批，等于给了
        # 一个"批了也不能 apply"的假入口。
        expires_at = min(now + _proposal_ttl(m),
                         m.parse_instant(gate["expires_at"], "expires_at"))
        rec = {
            "approval_id": aid,
            # 演示用审批页。真实审批服务（G5）仍 BLOCKED，这里不冒充真实链接。
            "url": "https://approval.mock.local/p/%s" % aid,
            "proposal_id": pid,
            "base_version": gate["base_version"],
            "user": user,
            "status": "pending",
            "token_issued": False,
            "token_consumed": False,
            "created_at": m.iso(now),
            "expires_at": m.iso(expires_at),
            "idempotency_key": key,
        }
        m.STATE["approvals"][aid] = rec
        approvals = m.read_approvals()
        approvals[aid] = rec
        m.write_approvals(approvals)

        result = {
            "approval_id": aid,
            "proposal_id": pid,
            "status": "pending",
            "approval_url": rec["url"],
            "expires_at": rec["expires_at"],
        }
        m.STATE["idempotency"][idem] = {"digest": req_digest, "result": result}
        return result

    # ---------------- 4. apply_approved_changes ----------------

    def _apply(self, user, args):
        m = self._m()
        inp = m.validate_envelope(args)
        pid = _text(inp.get("proposal_id"), "proposal_id")
        base_version = _text(inp.get("base_version"), "base_version")

        # 写白名单：M0 B 包第 8 条。空集一律拒绝，不退化成"谁都能写"。
        allowed = {s.strip() for s in
                   os.environ.get(WRITE_ALLOWLIST_ENV, "").split(",") if s.strip()}
        if not allowed:
            _bad("WRITE_BLOCKED",
                 "写白名单为空（%s），拒绝真实 apply。" % WRITE_ALLOWLIST_ENV)
        if user not in allowed:
            _bad("WRITE_BLOCKED", "当前身份不在写白名单内，拒绝真实 apply。")

        gate = self._store.proposal_gate(pid, user)
        if gate["status"] == "applied":
            _bad("ALREADY_APPLIED", "该提案已应用过，不重复写入。",
                 proposal_id=pid)
        if gate["expired"] or gate["status"] == "expired":
            _bad("PROPOSAL_EXPIRED", "提案已过期。", proposal_id=pid)
        if gate["snapshot_expired"]:
            _bad("SNAPSHOT_CONFLICT", "快照已过期，需重新生成提案。",
                 snapshot_id=gate["snapshot_id"])
        if gate["validation_status"] != "valid":
            _bad("PROPOSAL_INVALID", "提案未通过校验，不能应用。")
        if str(gate["base_version"]) != str(base_version):
            _bad("SNAPSHOT_CONFLICT", "base_version 与当前可信版本不一致。",
                 expected=gate["base_version"], provided=base_version)

        # 审批必须已通过。**这不是库内事务**：approval 不在库里，见模块 docstring
        # 的"已知缺口"。放在 apply 之前是为了让错误码准确，不是替代事务校验。
        rec = _latest_approval(m, pid, user)
        if rec is None:
            _bad("APPROVAL_REQUIRED", "该提案没有审批记录，不能应用。")
        st = m.apply_approval_status(rec)
        if st == "pending":
            _bad("APPROVAL_PENDING", "审批尚未完成。", approval_id=rec["approval_id"])
        if st == "expired":
            _bad("APPROVAL_EXPIRED", "审批已过期。", approval_id=rec["approval_id"])
        if st == "rejected":
            _bad("APPROVAL_REJECTED", "审批已被驳回。", approval_id=rec["approval_id"])
        if st in ("consumed", "token_issued"):
            _bad("APPROVAL_CONSUMED", "审批凭据已使用。", approval_id=rec["approval_id"])
        if st != "approved":
            _bad("APPROVAL_REQUIRED", "审批状态为 %s，不能应用。" % st,
                 approval_id=rec["approval_id"])

        applied = self._store.apply_proposal(pid, user, base_version)

        # 写完立刻回读。只回"成功"而不读回来，等于信任自己刚才那条 insert —— 
        # 而 apply 要证明的恰恰是"库里真有这条"。
        back = self._store.get_applied_change(pid, user)
        plan_digest = ss.payload_digest(gate.get("plan") or {})[0]
        read_digest = ss.payload_digest(back.get("result") or {})[0]
        readback_ok = (plan_digest == read_digest)

        if not readback_ok:
            _bad("READBACK_MISMATCH", "写入后回读与方案不一致。",
                 proposal_id=pid)

        return {
            "proposal_id": applied["proposal_id"],
            "status": "applied",
            "base_version": applied["base_version"],
            "snapshot_ref": applied["snapshot_id"],
            "snapshot_version": applied["snapshot_version"],
            "applied_at": back["applied_at"],
            "apply_id": back["apply_id"],
            "readback": {"verified": True,
                         "result_digest": read_digest,
                         "plan_digest": plan_digest},
        }


# ---------------------------------------------------------------- 小工具


def _parse_date(value):
    from datetime import date as _date
    return _date.fromisoformat(str(value))


def _proposal_ttl(m):
    """提案有效期。契约 §5.7 写死 30 分钟（L336-338），不读环境变量。

    库里 `proposal_ttl` 已随 `SnapshotStore` 默认值对齐 1800 s（旧值 600 s 是历史遗留，
    会让库里的 expires_at 比契约允许的提前 20 分钟到期），
    这里按契约取 30 分钟，且不做成可配置 —— 契约原文是
    「服务端不得接受客户端指定或延长该 TTL」，做成 env 就等于给了延长口子。
    """
    from datetime import timedelta
    return timedelta(minutes=30)


def _latest_approval(m, proposal_id, user):
    """取该提案最近一条审批记录（任意状态）。

    `find_approval_for_proposal` 只看 pending/approved/token_issued，
    会把已消费、已驳回的记录藏起来，导致 apply 报 APPROVAL_REQUIRED 而不是
    APPROVAL_CONSUMED —— 错误码错了，调用方的处理分支就错了。
    """
    best = None
    for _aid, rec in m.STATE["approvals"].items():
        if rec.get("proposal_id") != proposal_id or rec.get("user") != user:
            continue
        if best is None or str(rec.get("created_at", "")) >= str(best.get("created_at", "")):
            best = rec
    return best
