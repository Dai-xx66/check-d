#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""服务端包装层：把 M2 内部调度结果组装成契约完整 Proposal（方案 A）。

## 这一层为什么必须存在

契约 §5.7（`39f7f965` L324-329）把责任划得很死：

    M2 纯调度函数只输出内部调度结果，不得生成或输出
    proposal_id / snapshot_ref / base_version / input_digest /
    generated_at / expires_at / status。
    服务端包装层负责生成并持久化这些字段，
    再把内部 blocks/changes/unplanned/explanations 组装成完整 Proposal。

所以本模块做四件事，**只做这四件**：

1. 守卫：引擎结果里一旦出现服务端专有字段 → 拒绝（PROPOSAL_INVALID 422），
   不"take the first one"、不覆盖、不忽略。默许等于把可信字段交回给引擎侧。
2. 快照：把服务端自己读到的数据（Task/Course/Event/Override/偏好/外部固定事件
   + horizon + 固定时区）规范化，交给 `SnapshotStore.create_snapshot` 落库，
   拿到 `snapshot_id` 与 `version`。
3. 提案：把净化后的四部分存进 `create_proposal`（契约 L514：apply 时必须加载
   服务端自己保存的那一份，不接受调用方重传）。
4. 组装：返回完整 Proposal。`base_version` **只从库读回**，本文件不拼字符串
   （拼了必然与生成列漂移，P1-2 防的就是这个）。

## 顺序为什么固定「先快照后提案」

反过来的话，`create_proposal` 会因为没有 `snapshot_id` 无法绑定，或者先落一条
指向不存在快照的提案。更要紧的是：**结构校验必须发生在任何写库动作之前**，
否则一次非法提案会留下一份无人引用的快照，把 `snapshot_seq` 的版本号白推一格
（版本号单调，推上去就回不来）。

## 本层不做什么

- 不做调度语义（那是 M2）、不做约束校验（那是 validate_schedule）。
- 不做 apply 的三道闸（在 `snapshot_store.apply_proposal` 里）。
- **不证明持久化可用**。本文件全绿只等于 LOCAL-LOGIC 通过（Recording 执行器），
  真实持久化仍是 BLOCKED，直到有可连的库（M0 §一.4）。

## 已知口径缺口（本轮如实记录，未擅自改）

- 库里 `proposal.status` 默认值是 `'pending'`（migration `0001_snapshot_r3.sql`
  L133），而契约 §5.7 的状态枚举里没有 `pending`，新建提案应为 `draft`。
  本层只在**出参**上做映射（`pending`+未验证 → `draft`），**不改库、不改默认值**：
  改库属于 migration 变更，得由契约方定。已上交 AUTO-INBOX「待主会话」。
"""

import copy

import explanations_filter
import snapshot_store as ss

# 契约 §5.7：这些字段只能由服务端产出。引擎/模型一旦回传就是越界。
SERVER_ONLY_FIELDS = (
    "proposal_id",
    "snapshot_ref",
    "base_version",
    "input_digest",
    "generated_at",
    "expires_at",
    "status",
)

# 内部调度结果的四部分。四个键之外的顶层键一律拒绝。
INTERNAL_PARTS = ("blocks", "changes", "unplanned_tasks", "explanations")

# 契约 §5.7 状态机里的八个状态。
CONTRACT_STATUSES = frozenset({
    "draft", "pending_approval", "applying", "readback_pending",
    "applied", "rejected", "expired", "failed",
})

TZ = "Asia/Shanghai"

# 契约 L348-354 的 change 白名单，逐字段抄下来。多一个字段都要拒。
_CHANGE_SPEC = {
    "schedule_one_time": {
        "required": ("change_id", "type", "task_id", "planned_date"),
        "optional": ("scheduled_at",),
    },
    "upsert_daily_override": {
        "required": ("change_id", "type", "item_type", "item_id", "local_date",
                     "action", "planned_start_minute", "planned_end_minute"),
        "optional": ("existing_override_id",),
    },
}

_ITEM_TYPES = ("recurring", "one_time")


class ProposalAssemblyError(ss.SnapshotStoreError):
    """组装层错误。继承 Store 错误，上层只需按 `.code` 组信封。"""


def _bad(message, **details):
    raise ProposalAssemblyError(
        "PROPOSAL_INVALID", message, details=details or None)


# ============================================================
# 一、引擎结果的边界守卫
# ============================================================


def assert_internal_only(result):
    """引擎结果只能是内部四部分，且不得夹带服务端专有字段。

    这条不是"防君子"：Mock 与引擎共用同一份 DTO 时，最容易发生的就是引擎
    顺手把 `status` 或 `base_version` 带出来，然后服务端"看起来能用"就直接透传。
    一旦透传，客户端就拿回了它不该拥有的字段。
    """
    if not isinstance(result, dict):
        _bad("引擎调度结果必须是对象。", got=type(result).__name__)

    smuggled = [k for k in SERVER_ONLY_FIELDS if k in result]
    if smuggled:
        _bad("引擎结果包含服务端专有字段，拒绝组装。", fields=smuggled)

    unknown = [k for k in result if k not in INTERNAL_PARTS]
    if unknown:
        _bad("引擎结果包含未登记字段。", fields=sorted(unknown))

    for key in INTERNAL_PARTS:
        if key in result and not isinstance(result[key], list):
            _bad("字段 %s 必须是数组。" % key, field=key,
                 got=type(result[key]).__name__)


# ============================================================
# 二、快照输入规范化
# ============================================================


def _as_list(value, field):
    if value is None:
        return []
    if not isinstance(value, list):
        _bad("字段 %s 必须是数组。" % field, field=field)
    return value


def _sort_key(names):
    """稳定排序键：先按契约业务键，再用规范化 JSON 兜底。

    兜底那一段是必要的：引擎换了事件字段名时，业务键取不到就全是空串，
    排序退化成"输入顺序"，摘要就会随调用顺序漂移。
    """

    def key(item):
        if isinstance(item, dict):
            return tuple(str(item.get(n, "")) for n in names) + (
                ss.canonical_payload(item),)
        return (str(item),)

    return key


def _sorted(items, names):
    return sorted(items, key=_sort_key(names))


def build_snapshot_input(date_from, date_to, tasks, courses, events,
                         daily_overrides=None, preferences=None,
                         external_fixed_events=None, timezone=TZ):
    """把服务端读到的调度输入整理成可摘要的规范结构。

    契约 L366-374 规定 `input_digest` 必须覆盖 Task、Course、有效 Calendar
    Event、Daily Override、外部固定事件、调度偏好、horizon 起止 instant 与
    固定时区；且「其他输入完全相同时，只要 horizon 不同，摘要就必须不同」——
    所以 horizon 必须进摘要输入，不能只当参数用。

    `user_id` **不进摘要**：同一个人换账号只会是另一条库记录，而摘要描述的是
    "这份调度输入长什么样"。把 user_id 掺进去会让同一份输入在不同账号下摘要不同，
    反而不利于比对。
    """
    if not isinstance(preferences, dict) and preferences is not None:
        _bad("preferences 必须是对象。", field="preferences")

    horizon = {
        # 闭区间：date_to 当天 23:59:59 是本次调度的最后一个可排时刻。
        "start": "%sT00:00:00+08:00" % date_from,
        "end": "%sT23:59:59+08:00" % date_to,
        "timezone": timezone,
    }

    return {
        "schema": "checkd.schedule_input.v1",
        "timezone": timezone,
        "horizon": horizon,
        "tasks": _sorted(_as_list(tasks, "tasks"), ("task_id",)),
        "courses": _sorted(_as_list(courses, "courses"), ("course_id",)),
        # 事件是逐日 occurrence，同一天可能多条，所以业务键取 (start, event_id)
        "events": _sorted(_as_list(events, "events"), ("start", "event_id")),
        "daily_overrides": _sorted(
            _as_list(daily_overrides, "daily_overrides"),
            ("local_date", "item_type", "item_id")),
        "preferences": copy.deepcopy(preferences or {}),
        "external_fixed_events": _sorted(
            _as_list(external_fixed_events, "external_fixed_events"),
            ("start", "event_id")),
    }


# ============================================================
# 三、changes 结构校验（契约 L348-354）
# ============================================================


def _require_text_field(change, field, index):
    value = change.get(field)
    if not isinstance(value, str) or not value.strip():
        _bad("change[%d].%s 必须是非空字符串。" % (index, field),
             index=index, field=field)


def _require_minute(change, field, index):
    value = change.get(field)
    # bool 是 int 的子类，`True` 会被当成 1 分钟混过去，显式排除。
    if isinstance(value, bool) or not isinstance(value, int):
        _bad("change[%d].%s 必须是整数分钟。" % (index, field),
             index=index, field=field)


def validate_changes(changes):
    """只做结构校验：类型、必填、未知字段、以及契约里写明的额外约束。

    语义校验（Task 是否真是 one_time、override 归属、资源是否存在）留给
    validate_schedule —— 那是要读可信快照才有答案的事，本层不越权。
    """
    if changes is None:
        return []
    if not isinstance(changes, list):
        _bad("changes 必须是数组。", field="changes")

    seen_ids = set()
    one_time_tasks = set()

    for index, change in enumerate(changes):
        if not isinstance(change, dict):
            _bad("change[%d] 必须是对象。" % index, index=index)

        ctype = change.get("type")
        if ctype not in _CHANGE_SPEC:
            _bad("change[%d].type 不在 v1 白名单内。" % index,
                 index=index, type=ctype)

        spec = _CHANGE_SPEC[ctype]
        allowed = set(spec["required"]) | set(spec["optional"])
        unknown = sorted(set(change) - allowed)
        if unknown:
            _bad("change[%d] 含未列出的字段。" % index, index=index, fields=unknown)

        for field in spec["required"]:
            if field not in change:
                _bad("change[%d] 缺少必填字段 %s。" % (index, field),
                     index=index, field=field)

        for field in ("change_id", "type"):
            _require_text_field(change, field, index)

        cid = change["change_id"]
        if cid in seen_ids:
            # 重复 change_id 会让下游按 id 去重时静默丢掉一条变更。
            _bad("change_id 在同一提案内重复。", change_id=cid)
        seen_ids.add(cid)

        if ctype == "schedule_one_time":
            _require_text_field(change, "task_id", index)
            _require_text_field(change, "planned_date", index)
            scheduled_at = change.get("scheduled_at")
            if scheduled_at is not None:
                if not isinstance(scheduled_at, str):
                    _bad("change[%d].scheduled_at 必须是字符串。" % index, index=index)
                # 契约：具体时间必须与计划日期同日。先看字面前缀，跨日立刻能抓到。
                if not scheduled_at.startswith(str(change["planned_date"])):
                    _bad("change[%d].scheduled_at 与 planned_date 不同日。" % index,
                         index=index)
            if change["task_id"] in one_time_tasks:
                _bad("同一 Task 在一个提案里最多一条 schedule_one_time。",
                     task_id=change["task_id"])
            one_time_tasks.add(change["task_id"])

        else:  # upsert_daily_override
            if change["item_type"] not in _ITEM_TYPES:
                _bad("change[%d].item_type 只能是 recurring/one_time。" % index,
                     index=index, item_type=change["item_type"])
            if change["action"] != "reschedule":
                _bad("change[%d].action 在 v1 只允许 reschedule。" % index,
                     index=index, action=change["action"])
            _require_text_field(change, "item_id", index)
            _require_text_field(change, "local_date", index)
            _require_minute(change, "planned_start_minute", index)
            _require_minute(change, "planned_end_minute", index)
            if change["planned_end_minute"] <= change["planned_start_minute"]:
                _bad("change[%d] 结束分钟必须晚于开始分钟。" % index, index=index)

    return changes


# ============================================================
# 四、状态映射
# ============================================================


def contract_status(db_status):
    """库里的 status → 契约 §5.7 的状态。

    库里新建提案是 `pending`（含义：还没验证过），契约枚举里对应 `draft`。
    只映射出参，不写库——改库要动 migration，得契约方拍。
    """
    if db_status in CONTRACT_STATUSES:
        return db_status
    if db_status == "pending":
        return "draft"
    raise ProposalAssemblyError(
        "INTERNAL_ERROR", "库里出现契约状态机之外的状态：%s" % db_status,
        details={"db_status": db_status})


# ============================================================
# 五、组装
# ============================================================


class ProposalAssembler:
    """把一个用户、一个日期范围的一次调度结果，变成一条可审批的提案。"""

    def __init__(self, store, timezone=TZ, explanation_stats=None):
        self._store = store
        self._tz = timezone
        self._stats = explanation_stats

    def assemble(self, user_id, date_from, date_to, scheduler_result,
                 tasks, courses, events, daily_overrides=None,
                 preferences=None, external_fixed_events=None):
        """返回完整 Proposal（契约 §5.7）。写两条记录：snapshot + proposal。"""

        # ---- 1) 先校验，再碰库 ----
        assert_internal_only(scheduler_result)
        changes = validate_changes(scheduler_result.get("changes"))
        blocks = scheduler_result.get("blocks") or []
        unplanned = scheduler_result.get("unplanned_tasks") or []

        raw_explanations = scheduler_result.get("explanations") or []
        public_explanations = explanations_filter.filter_explanations(
            raw_explanations, self._stats)
        dropped = len(raw_explanations) - len(public_explanations)

        snapshot_input = build_snapshot_input(
            date_from, date_to, tasks, courses, events,
            daily_overrides=daily_overrides, preferences=preferences,
            external_fixed_events=external_fixed_events, timezone=self._tz)

        plan = {
            "blocks": copy.deepcopy(blocks),
            "changes": copy.deepcopy(changes),
            "unplanned_tasks": copy.deepcopy(unplanned),
            "explanations": copy.deepcopy(public_explanations),
        }

        # ---- 2) 快照（服务端自己读到的输入，先落库） ----
        snap = self._store.create_snapshot(user_id, date_from, date_to, snapshot_input)

        # ---- 3) 提案（存的是服务端自己那份 plan，apply 时从这里读） ----
        prop = self._store.create_proposal(
            user_id, snap["snapshot_id"], snap["version"], plan)

        # ---- 4) 组装 ----
        generated_at = prop.get("generated_at")
        if not generated_at:
            # 宁可报错也不拿进程时钟顶替：契约要的是服务端 instant，
            # 容器与本机时区不同，自己取时间必然偏移。
            raise ProposalAssemblyError(
                "INTERNAL_ERROR", "提案缺少 generated_at（时间必须来自库）。",
                details={"proposal_id": prop.get("proposal_id")})

        return {
            "proposal_id": prop["proposal_id"],
            "snapshot_ref": snap["snapshot_id"],
            # 库里的生成列，原样透传；本文件绝不自己拼。
            "base_version": prop["base_version"],
            # 摘要覆盖的就是第 2 步落库的那份规范化输入，两处同源，不会漂。
            "input_digest": snap["payload_digest"],
            "input_bytes": snap["payload_bytes"],
            "status": contract_status(prop.get("status")),
            "generated_at": generated_at,
            "expires_at": prop.get("expires_at"),
            "blocks": plan["blocks"],
            "changes": plan["changes"],
            "unplanned_tasks": plan["unplanned_tasks"],
            "explanations": plan["explanations"],
            "snapshot_version": snap["version"],
            "explanations_dropped": dropped,
        }
