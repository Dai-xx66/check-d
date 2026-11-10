#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""snapshot_tools 接线层单测（无库环境）。

## 能证明 / 不能证明

能证明：
- 四个工具在 `SNAPSHOT_MODE=on` 时改读服务端持久快照，提案字段**取自库**而不是本地拼
- 请求体夹带 `tasks/courses/base_version/snapshot_ref` 会被拒（可信输入只能来自服务端）
- 快照摘要变化 → `SNAPSHOT_CONFLICT`，不是"照旧通过"
- 三个 409 分码各自命中：`PROPOSAL_EXPIRED` / `SNAPSHOT_CONFLICT` / `ALREADY_APPLIED`
- 写白名单为空一律 `WRITE_BLOCKED`，不退化
- apply 只认审批已通过，且写入后做回读核验

**不能证明**：PostgreSQL 接受这些 SQL、数据真的落盘、并发下锁序正确。
层级标注：LOCAL-LOGIC（非持久化）。SQL 层由 `test_snapshot_store.py` 覆盖，
真实持久化仍是 BLOCKED 直到有可连的库。

跑法：
    cd work/repo/check-d
    python -m unittest discover -s tools/m1-server/tests -v
"""

import os
import sys
import tempfile
import unittest
from datetime import timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER_DIR = os.path.abspath(os.path.join(HERE, ".."))
MOCK_DIR = os.path.abspath(os.path.join(HERE, "..", "..", "m1-mock"))

sys.path.insert(0, SERVER_DIR)
sys.path.insert(0, MOCK_DIR)

# tool_server 在 import 时读环境变量决定审批文件位置，必须在 import 之前设好，
# 否则会在仓库里落一个 mock_approvals.json（已踩过，会让 git status 不干净）。
_TMP = tempfile.mkdtemp(prefix="checkd-snaptools-")
os.environ.setdefault("MOCK_APPROVAL_FILE", os.path.join(_TMP, "approvals.json"))
os.environ.pop("MOCK_TEST_FLAGS", None)

import snapshot_store as ss  # noqa: E402
import snapshot_tools as st  # noqa: E402
import tool_server as mock  # noqa: E402

API = "checkd.agent.v1"
TZ = "Asia/Shanghai"


def _env(inner, rid="req-1"):
    return {"api_version": API, "timezone": TZ, "request_id": rid, "input": inner}


def _reset_mock():
    mock.STATE["proposals"].clear()
    mock.STATE["internal"].clear()
    mock.STATE["approvals"].clear()
    mock.STATE["tokens"].clear()
    mock.STATE["idempotency"].clear()
    mock.STATE["applied_proposals"].clear()
    mock.STATE["overrides"].clear()
    mock.STATE["writes"] = 0


class _FakeStore:
    """按 SnapshotStore 的**返回值契约**实现的假库。

    只模拟业务语义（状态、过期、版本、回读），不模拟 SQL —— 那部分归
    `test_snapshot_store.py`。这样做的好处是：接线层坏了会直接挂在这里，
    而不会因为 SQL 文本对不上把两个层次的失败混在一起。
    """

    def __init__(self):
        self.snapshots = {}
        self.proposals = {}
        self.applied = {}
        self.dropped = []
        self._n = 0
        # 有效期必须相对"当前时刻"算。写死日期会在几天后自己过期，
        # 届时失败原因变成"审批过期"，与要测的接线逻辑无关。
        self._snap_exp = mock.iso(mock.now() + timedelta(minutes=120))
        self._prop_exp = mock.iso(mock.now() + timedelta(minutes=100))

    # --- 写 ---

    def create_snapshot(self, user_id, date_from, date_to, payload):
        self._n += 1
        sid = "snap-%02d" % self._n
        digest, nbytes = ss.payload_digest(payload)
        self.snapshots[sid] = {
            "snapshot_id": sid, "version": self._n, "user_id": user_id,
            "date_from": date_from, "date_to": date_to, "payload": payload,
            "payload_digest": digest, "payload_bytes": nbytes,
            "expires_at": self._snap_exp, "superseded": False,
        }
        return {"snapshot_id": sid, "version": self._n,
                "base_version": "%s:%d" % (sid, self._n),
                "payload_digest": digest, "payload_bytes": nbytes,
                "expires_at": self.snapshots[sid]["expires_at"]}

    def create_proposal(self, user_id, snapshot_id, snapshot_version, plan):
        pid = "prop-%02d" % (len(self.proposals) + 1)
        self.proposals[pid] = {
            "proposal_id": pid, "user_id": user_id, "snapshot_id": snapshot_id,
            "snapshot_version": int(snapshot_version),
            "base_version": "%s:%d" % (snapshot_id, int(snapshot_version)),
            "status": "pending", "validation_status": "unvalidated",
            "plan": plan, "expires_at": self._prop_exp,
            "applied_at": None, "expired": False,
        }
        return {"proposal_id": pid, "base_version": self.proposals[pid]["base_version"],
                "status": "pending", "expires_at": self.proposals[pid]["expires_at"],
                "generated_at": "2026-11-07T12:15:00+08:00",
                "snapshot_id": snapshot_id, "snapshot_version": int(snapshot_version),
                "plan_digest": "x"}

    def set_validation(self, proposal_id, user_id, validation_status):
        self.proposals[proposal_id]["validation_status"] = validation_status
        return True

    def apply_proposal(self, proposal_id, user_id, base_version):
        p = self.proposals[proposal_id]
        if p["status"] == "applied":
            raise ss.SnapshotStoreError("ALREADY_APPLIED", "已应用过。")
        if str(p["base_version"]) != str(base_version):
            raise ss.SnapshotStoreError("SNAPSHOT_CONFLICT", "版本不一致。")
        p["status"] = "applied"
        self.applied[proposal_id] = {
            "apply_id": "apply-1", "proposal_id": proposal_id, "user_id": user_id,
            "snapshot_id": p["snapshot_id"],
            "applied_at": "2026-11-07T12:20:00+08:00", "result": p["plan"],
        }
        return {"proposal_id": proposal_id, "status": "applied",
                "base_version": p["base_version"], "snapshot_id": p["snapshot_id"],
                "snapshot_version": p["snapshot_version"]}

    # --- 读 ---

    def proposal_gate(self, proposal_id, user_id):
        p = self.proposals.get(proposal_id)
        if p is None or p["user_id"] != user_id:
            raise ss.SnapshotStoreError("NOT_FOUND", "提案不存在。")
        snap = self.snapshots[p["snapshot_id"]]
        return dict(p, date_from=snap["date_from"], date_to=snap["date_to"],
                    snapshot_payload_digest=snap["payload_digest"],
                    # P0-1：快照自己的 TTL 判定结果，真实 store 由 SQL 的
                    # (s.expires_at <= now()) 算出来；这里用标记位模拟。
                    snapshot_expired=snap.get("snapshot_expired", False))

    def get_snapshot_payload(self, snapshot_id, user_id):
        snap = self.snapshots.get(snapshot_id)
        if snap is None or snap["user_id"] != user_id:
            raise ss.SnapshotStoreError("NOT_FOUND", "快照不存在。")
        return snap

    def get_applied_change(self, proposal_id, user_id):
        rec = self.applied.get(proposal_id)
        if rec is None:
            raise ss.SnapshotStoreError("NOT_FOUND", "没有应用记录。")
        return rec


class _Base(unittest.TestCase):
    def setUp(self):
        _reset_mock()
        os.environ.pop(st.WRITE_ALLOWLIST_ENV, None)
        self._seed_overrides("2026-10-30")
        self.store = _FakeStore()
        self.tools = st.SnapshotTools(self.store)

    @staticmethod
    def _seed_overrides(day):
        """给周期任务预置一条当日例外。

        **不是为了让测试变简单，是为了让测试数据符合契约。**
        `tool_server.schedule()` 对"当天本来没有落点"的周期任务会产
        `action: "assign"`，而契约 L361 写的是「`action` 在 v1 暂定仅 `reschedule`」。
        两者冲突：`proposal_assembly.validate_changes` 按契约拒收 assign，
        所以真实演示数据（TASKS 里 `scheduled_minute_of_day` 全为 None）在
        `SNAPSHOT_MODE=on` 下必然 422。这是需要裁的口径缺口，已记 AUTO-INBOX；
        测试里先用"已有落点"的合法形态验证接线本身。
        """
        for tid in ("t_1003", "t_1004"):
            mock.STATE["overrides"][(tid, day)] = {
                "override_id": "ov_%s" % tid, "item_id": tid, "item_type": "recurring",
                "local_date": day, "action": "reschedule",
                "planned_start_minute": 480, "planned_end_minute": 510,
                "existing_override_id": None,
            }

    def tearDown(self):
        os.environ.pop(st.WRITE_ALLOWLIST_ENV, None)

    def _approval_for(self, prop):
        """按 proposal 找审批 id。不硬编码 appr_0001：那个计数器是进程级共享的，
        测试顺序一变就换号，硬编码会让失败原因看起来像业务问题。"""
        for aid, rec in mock.STATE["approvals"].items():
            if rec.get("proposal_id") == prop["proposal_id"]:
                return aid
        self.fail("没有为提案建出审批记录：%s" % prop["proposal_id"])

    # 走完整条链：generate → validate → request_approval → apply
    def _full_chain(self, user="u_alice", date_from="2026-10-30", date_to="2026-10-30"):
        prop = self.tools.call("generate_schedule",
                               _env({"date_range": {"start": date_from, "end": date_to}}),
                               user)
        self.tools.call("validate_schedule", _env({"proposal_id": prop["proposal_id"]}), user)
        self.tools.call("request_approval",
                        _env({"proposal_id": prop["proposal_id"],
                              "idempotency_key": "k1"}), user)
        return prop


class TestGenerate(_Base):
    def test_assemble_writes_snapshot_then_proposal(self):
        prop = self.tools.call(
            "generate_schedule",
            _env({"date_range": {"start": "2026-10-30", "end": "2026-10-30"}}),
            "u_alice")
        self.assertEqual(len(self.store.snapshots), 1)
        self.assertEqual(len(self.store.proposals), 1)
        # 服务端字段来自库，不是本地拼的
        self.assertEqual(prop["base_version"], "snap-01:1")
        self.assertEqual(prop["snapshot_ref"], "snap-01")
        self.assertEqual(prop["status"], "draft")
        self.assertTrue(prop["generated_at"])

    def test_rejects_client_supplied_tasks(self):
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            self.tools.call(
                "generate_schedule",
                _env({"date_range": {"start": "2026-10-30", "end": "2026-10-30"},
                      "tasks": [{"task_id": "x"}]}),
                "u_alice")
        self.assertEqual(ctx.exception.code, "INVALID_ARGUMENT")
        # 拒收必须发生在写库之前
        self.assertEqual(self.store.snapshots, {})

    def test_rejects_base_version_from_client(self):
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            self.tools.call(
                "generate_schedule",
                _env({"date_range": {"start": "2026-10-30", "end": "2026-10-30"},
                      "base_version": "forged"}),
                "u_alice")
        self.assertEqual(ctx.exception.code, "INVALID_ARGUMENT")


class TestValidate(_Base):
    def test_valid_proposal_becomes_pending_approval(self):
        prop = self.tools.call(
            "generate_schedule",
            _env({"date_range": {"start": "2026-10-30", "end": "2026-10-30"}}),
            "u_alice")
        out = self.tools.call("validate_schedule",
                              _env({"proposal_id": prop["proposal_id"]}), "u_alice")
        self.assertEqual(out["validation_status"], "valid")
        self.assertEqual(out["proposal_status"], "pending_approval")
        self.assertEqual(out["violations"], [])
        self.assertEqual(self.store.proposals[prop["proposal_id"]]["validation_status"],
                         "valid")

    def test_snapshot_drift_is_conflict(self):
        prop = self.tools.call(
            "generate_schedule",
            _env({"date_range": {"start": "2026-10-30", "end": "2026-10-30"}}),
            "u_alice")
        # 模拟"生成后任务被改过"：库里摘要不再等于重算值
        self.store.snapshots["snap-01"]["payload_digest"] = "0" * 64
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            self.tools.call("validate_schedule",
                            _env({"proposal_id": prop["proposal_id"]}), "u_alice")
        self.assertEqual(ctx.exception.code, "SNAPSHOT_CONFLICT")

    def test_already_applied_cannot_validate(self):
        prop = self._full_chain()
        os.environ[st.WRITE_ALLOWLIST_ENV] = "u_alice"
        mock.STATE["approvals"][self._approval_for(prop)]["status"] = "approved"
        self.tools.call("apply_approved_changes",
                        _env({"proposal_id": prop["proposal_id"],
                              "base_version": prop["base_version"]}), "u_alice")
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            self.tools.call("validate_schedule",
                            _env({"proposal_id": prop["proposal_id"]}), "u_alice")
        self.assertEqual(ctx.exception.code, "ALREADY_APPLIED")


class TestRequestApproval(_Base):
    def test_requires_valid_first(self):
        prop = self.tools.call(
            "generate_schedule",
            _env({"date_range": {"start": "2026-10-30", "end": "2026-10-30"}}),
            "u_alice")
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            self.tools.call("request_approval",
                            _env({"proposal_id": prop["proposal_id"],
                                  "idempotency_key": "k1"}), "u_alice")
        self.assertEqual(ctx.exception.code, "PROPOSAL_INVALID")

    def test_base_version_comes_from_db(self):
        prop = self._full_chain()
        aid = [a for a, r in mock.STATE["approvals"].items()
               if r["proposal_id"] == prop["proposal_id"]][0]
        self.assertEqual(mock.STATE["approvals"][aid]["base_version"],
                         self.store.proposals[prop["proposal_id"]]["base_version"])

    def test_idempotent_replay(self):
        prop = self._full_chain()
        again = self.tools.call("request_approval",
                                _env({"proposal_id": prop["proposal_id"],
                                      "idempotency_key": "k1"}), "u_alice")
        self.assertEqual(len(mock.STATE["approvals"]), 1)
        self.assertTrue(again["approval_id"])

    def test_expired_proposal_is_409(self):
        prop = self._full_chain()
        self.store.proposals[prop["proposal_id"]]["expired"] = True
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            self.tools.call("request_approval",
                            _env({"proposal_id": prop["proposal_id"],
                                  "idempotency_key": "k2"}), "u_alice")
        self.assertEqual(ctx.exception.code, "PROPOSAL_EXPIRED")


class TestApply(_Base):
    def test_empty_allowlist_blocks_write(self):
        prop = self._full_chain()
        mock.STATE["approvals"][self._approval_for(prop)]["status"] = "approved"
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            self.tools.call("apply_approved_changes",
                            _env({"proposal_id": prop["proposal_id"],
                                  "base_version": prop["base_version"]}), "u_alice")
        self.assertEqual(ctx.exception.code, "WRITE_BLOCKED")
        self.assertEqual(self.store.applied, {})

    def test_requires_approved(self):
        prop = self._full_chain()
        os.environ[st.WRITE_ALLOWLIST_ENV] = "u_alice"
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            self.tools.call("apply_approved_changes",
                            _env({"proposal_id": prop["proposal_id"],
                                  "base_version": prop["base_version"]}), "u_alice")
        self.assertEqual(ctx.exception.code, "APPROVAL_PENDING")

    def test_success_reads_back(self):
        prop = self._full_chain()
        os.environ[st.WRITE_ALLOWLIST_ENV] = "u_alice"
        mock.STATE["approvals"][self._approval_for(prop)]["status"] = "approved"
        out = self.tools.call("apply_approved_changes",
                              _env({"proposal_id": prop["proposal_id"],
                                    "base_version": prop["base_version"]}), "u_alice")
        self.assertEqual(out["status"], "applied")
        self.assertTrue(out["readback"]["verified"])
        self.assertEqual(out["readback"]["result_digest"], out["readback"]["plan_digest"])

    def test_version_mismatch_is_conflict(self):
        prop = self._full_chain()
        os.environ[st.WRITE_ALLOWLIST_ENV] = "u_alice"
        mock.STATE["approvals"][self._approval_for(prop)]["status"] = "approved"
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            self.tools.call("apply_approved_changes",
                            _env({"proposal_id": prop["proposal_id"],
                                  "base_version": "snap-01:99"}), "u_alice")
        self.assertEqual(ctx.exception.code, "SNAPSHOT_CONFLICT")


class TestSnapshotTTL(_Base):
    """P0-1（M3 2026-11-07 审查）：快照 TTL 没接入任何判定路径。

    原先 validate / request_approval / apply 三条路都只看 proposal.expires_at，
    snapshot.expires_at 存了却从没被读过。当时默认 proposal TTL(600s) < snapshot TTL(900s)，
    所以正常流程永远掩盖它；一旦把 snapshot TTL 调短，就能拿过期快照照样校验、审批、apply。
    （两处默认现已改为 1800/1800，此处仍显式置 expired 位，不依赖 TTL 大小关系。）

    这里把三个入口分别钉住，并额外证明「proposal 没过期也一样被拦」——
    否则可能只是 proposal 过期先报，测试假绿。
    """

    DATE = {"date_range": {"start": "2026-10-30", "end": "2026-10-30"}}

    def _generate(self, user="u_alice"):
        return self.tools.call("generate_schedule", _env(self.DATE), user)

    def _expire_snapshot(self, prop):
        # 从 store 反查 snap_id：generate 的返回里叫 snapshot_ref，不叫 snapshot_id
        sid = self.store.proposals[prop["proposal_id"]]["snapshot_id"]
        self.store.snapshots[sid]["snapshot_expired"] = True

    def test_validate_rejects_expired_snapshot(self):
        prop = self._generate()
        self._expire_snapshot(prop)
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            self.tools.call("validate_schedule",
                            _env({"proposal_id": prop["proposal_id"]}), "u_alice")
        self.assertEqual(ctx.exception.code, "SNAPSHOT_CONFLICT")

    def test_approval_rejects_expired_snapshot(self):
        prop = self._generate()
        self.tools.call("validate_schedule", _env({"proposal_id": prop["proposal_id"]}), "u_alice")
        self._expire_snapshot(prop)
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            self.tools.call("request_approval",
                            _env({"proposal_id": prop["proposal_id"],
                                  "idempotency_key": "k-ttl"}), "u_alice")
        self.assertEqual(ctx.exception.code, "SNAPSHOT_CONFLICT")

    def test_apply_rejects_expired_snapshot(self):
        prop = self._full_chain()
        os.environ[st.WRITE_ALLOWLIST_ENV] = "u_alice"
        mock.STATE["approvals"][self._approval_for(prop)]["status"] = "approved"
        self._expire_snapshot(prop)
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            self.tools.call("apply_approved_changes",
                            _env({"proposal_id": prop["proposal_id"],
                                  "base_version": prop["base_version"]}), "u_alice")
        self.assertEqual(ctx.exception.code, "SNAPSHOT_CONFLICT")
        self.assertEqual(self.store.applied, {}, "快照过期时一行都不能写")

    def test_proposal_alive_but_snapshot_dead_still_blocked(self):
        """proposal 没过期、只有快照过期 —— 必须仍然被拦，证明判的是快照的 TTL。"""
        prop = self._generate()
        self.tools.call("validate_schedule", _env({"proposal_id": prop["proposal_id"]}), "u_alice")
        # proposal 明确未过期
        self.store.proposals[prop["proposal_id"]]["expired"] = False
        self._expire_snapshot(prop)
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            self.tools.call("request_approval",
                            _env({"proposal_id": prop["proposal_id"],
                                  "idempotency_key": "k-ttl2"}), "u_alice")
        self.assertEqual(ctx.exception.code, "SNAPSHOT_CONFLICT")
        self.assertNotEqual(ctx.exception.code, "PROPOSAL_EXPIRED",
                            "不能靠 proposal 过期蒙对")

    def test_no_false_positive_when_both_alive(self):
        """两个 TTL 都没过期时必须照常通过，否则上面几条就是「一律拒绝」的假绿。"""
        prop = self._full_chain()
        self.assertEqual(prop["proposal_id"][:5], "prop-")


if __name__ == "__main__":
    unittest.main()
