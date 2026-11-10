#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""proposal_assembly 逻辑单测（无库环境）。

## 能证明 / 不能证明

能证明：
- 引擎结果里夹带服务端专有字段会被拒，且拒绝发生在**任何写库动作之前**
- 落库顺序是 snapshot → proposal（反过来会留下指向不存在快照的提案）
- `base_version` 是库值原样透传，不是本地按 `snapshot_id:version` 拼的
- `input_digest` 与落库快照的 payload 摘要同源
- 内部 explanation 码不会进 plan、也不进最终响应

**不能证明**：PostgreSQL 接受这些 SQL、持久化真的落盘。
层级标注：LOCAL-LOGIC（非持久化），全绿不等于持久化 PASS。

跑法：
    cd work/repo/check-d
    python -m unittest discover -s tools/m1-server/tests -v
"""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import proposal_assembly as pa  # noqa: E402
import snapshot_store as ss  # noqa: E402


def _replies(prop_row=None, base_version="sv:snap-1:v1"):
    """四条语句的预设回答：发号 / supersede / 插快照 / 插提案。"""
    row = prop_row or ("prop-1", base_version, "pending",
                       "2026-11-07T12:45:00+08:00", "2026-11-07T12:15:00+08:00")
    return [
        [(1,)],
        [(None,)],
        [("snap-1", "2026-11-07T12:30:00+08:00")],
        [row],
    ]


def _assembler(**kw):
    ex = ss.RecordingExecutor(replies=_replies(**kw))
    store = ss.SnapshotStore(executor=ex)
    return pa.ProposalAssembler(store), ex


def _result(**over):
    base = {
        "blocks": [{"task_id": "t1", "start_minute": 540, "end_minute": 600}],
        "changes": [{"change_id": "c1", "type": "schedule_one_time",
                     "task_id": "t1", "planned_date": "2026-11-08"}],
        "unplanned_tasks": [],
        "explanations": [{"code": "SCHEDULED", "message": "已安排"}],
    }
    base.update(over)
    return base


def _assemble(assembler, result=None, **over):
    kw = dict(user_id="u1", date_from="2026-11-08", date_to="2026-11-08",
              scheduler_result=result or _result(),
              tasks=[{"task_id": "t1", "type": "one_time"}],
              courses=[], events=[])
    kw.update(over)
    return assembler.assemble(**kw)


class TestGuard(unittest.TestCase):
    def test_rejects_each_server_only_field(self):
        """契约 §5.7：这七个字段只能服务端产出，引擎回传即越界。"""
        for field in pa.SERVER_ONLY_FIELDS:
            with self.subTest(field=field):
                asm, ex = _assembler()
                with self.assertRaises(pa.ProposalAssemblyError) as ctx:
                    _assemble(asm, _result(**{field: "x"}))
                self.assertEqual(ctx.exception.code, "PROPOSAL_INVALID")
                self.assertEqual(ex.statements, [], "非法结果不该打库")

    def test_rejects_unknown_top_level_key(self):
        asm, ex = _assembler()
        with self.assertRaises(pa.ProposalAssemblyError) as ctx:
            _assemble(asm, _result(schedule=[1, 2]))
        self.assertEqual(ctx.exception.code, "PROPOSAL_INVALID")
        self.assertEqual(ex.statements, [])

    def test_rejects_non_object(self):
        asm, ex = _assembler()
        with self.assertRaises(pa.ProposalAssemblyError):
            _assemble(asm, ["blocks"])
        self.assertEqual(ex.statements, [])

    def test_rejects_non_list_part(self):
        asm, ex = _assembler()
        with self.assertRaises(pa.ProposalAssemblyError):
            _assemble(asm, _result(blocks={"task_id": "t1"}))
        self.assertEqual(ex.statements, [])


class TestOrder(unittest.TestCase):
    def test_snapshot_lands_before_proposal(self):
        """先快照后提案：反过来提案会绑定一个还不存在的 snapshot_id。"""
        asm, ex = _assembler()
        _assemble(asm)
        sqls = [s.lower() for s, _ in ex.statements]
        self.assertEqual(len(sqls), 4)
        self.assertIn("snapshot_seq", sqls[0])
        self.assertIn("insert into checkd_demo.snapshot", sqls[2])
        self.assertIn("insert into checkd_demo.proposal", sqls[3])

    def test_proposal_params_carry_snapshot_id(self):
        asm, ex = _assembler()
        _assemble(asm)
        _, prop_params = ex.statements[3]
        self.assertEqual(prop_params[0], "u1")
        self.assertEqual(prop_params[1], "snap-1")
        self.assertEqual(prop_params[2], 1)

    def test_bad_change_blocks_all_writes(self):
        """结构非法时一条 SQL 都不该发——否则白推一格版本号。"""
        asm, ex = _assembler()
        bad = _result(changes=[{"change_id": "c1", "type": "move_task",
                                "task_id": "t1"}])
        with self.assertRaises(pa.ProposalAssemblyError) as ctx:
            _assemble(asm, bad)
        self.assertEqual(ctx.exception.code, "PROPOSAL_INVALID")
        self.assertEqual(ex.statements, [])


class TestServerOwnedFields(unittest.TestCase):
    def test_base_version_passed_through_not_composed(self):
        """库值故意写成拼不出来的形态；能对上才说明是透传而非本地拼接。"""
        asm, _ = _assembler(base_version="sv:snap-1:v1")
        out = _assemble(asm)
        self.assertEqual(out["base_version"], "sv:snap-1:v1")

    def test_snapshot_ref_is_snapshot_id(self):
        asm, _ = _assembler()
        out = _assemble(asm)
        self.assertEqual(out["snapshot_ref"], "snap-1")
        self.assertEqual(out["snapshot_version"], 1)

    def test_input_digest_equals_persisted_payload_digest(self):
        """摘要必须覆盖真正落库的那份输入，两处同源。"""
        asm, _ = _assembler()
        out = _assemble(asm)
        expected, nbytes = ss.payload_digest(pa.build_snapshot_input(
            "2026-11-08", "2026-11-08",
            [{"task_id": "t1", "type": "one_time"}], [], []))
        self.assertEqual(out["input_digest"], expected)
        self.assertEqual(out["input_bytes"], nbytes)

    def test_missing_generated_at_is_error_not_clock_fallback(self):
        """库没给时间就报错，不用进程时钟顶替（容器时区与契约无关）。"""
        row = ("prop-1", "sv:snap-1:v1", "pending", "2026-11-07T12:45:00+08:00")
        ex = ss.RecordingExecutor(replies=_replies(prop_row=row))
        asm = pa.ProposalAssembler(ss.SnapshotStore(executor=ex))
        with self.assertRaises(pa.ProposalAssemblyError) as ctx:
            _assemble(asm)
        self.assertEqual(ctx.exception.code, "INTERNAL_ERROR")


class TestExplanations(unittest.TestCase):
    def test_internal_codes_never_reach_plan(self):
        asm, ex = _assembler()
        out = _assemble(asm, _result(explanations=[
            {"code": "SCHEDULED", "message": "已安排"},
            {"code": "DISPLACED_BY_FIXED", "message": "内部"},
            {"code": "REPAIR_SUMMARY", "message": "内部"},
        ]))
        self.assertEqual([e["code"] for e in out["explanations"]], ["SCHEDULED"])
        self.assertEqual(out["explanations_dropped"], 2)
        stored = ex.statements[3][1][4]
        self.assertNotIn("DISPLACED_BY_FIXED", stored)
        self.assertNotIn("REPAIR_SUMMARY", stored)


class TestChangeValidation(unittest.TestCase):
    def _reject(self, change):
        asm, ex = _assembler()
        with self.assertRaises(pa.ProposalAssemblyError) as ctx:
            _assemble(asm, _result(changes=[change]))
        self.assertEqual(ctx.exception.code, "PROPOSAL_INVALID")
        self.assertEqual(ex.statements, [])
        return ctx.exception

    def test_unknown_field_rejected(self):
        exc = self._reject({"change_id": "c1", "type": "schedule_one_time",
                            "task_id": "t1", "planned_date": "2026-11-08",
                            "duration": 30})
        self.assertIn("duration", str(exc.details))

    def test_duplicate_change_id_rejected(self):
        asm, ex = _assembler()
        with self.assertRaises(pa.ProposalAssemblyError):
            _assemble(asm, _result(changes=[
                {"change_id": "c1", "type": "schedule_one_time",
                 "task_id": "t1", "planned_date": "2026-11-08"},
                {"change_id": "c1", "type": "schedule_one_time",
                 "task_id": "t2", "planned_date": "2026-11-08"},
            ]))
        self.assertEqual(ex.statements, [])

    def test_two_one_time_changes_for_same_task_rejected(self):
        asm, ex = _assembler()
        with self.assertRaises(pa.ProposalAssemblyError) as ctx:
            _assemble(asm, _result(changes=[
                {"change_id": "c1", "type": "schedule_one_time",
                 "task_id": "t1", "planned_date": "2026-11-08"},
                {"change_id": "c2", "type": "schedule_one_time",
                 "task_id": "t1", "planned_date": "2026-11-09"},
            ]))
        self.assertEqual(ctx.exception.code, "PROPOSAL_INVALID")
        self.assertEqual(ex.statements, [])

    def test_scheduled_at_must_be_same_day(self):
        self._reject({"change_id": "c1", "type": "schedule_one_time",
                      "task_id": "t1", "planned_date": "2026-11-08",
                      "scheduled_at": "2026-11-09T09:00:00+08:00"})

    def test_override_end_must_be_after_start(self):
        self._reject({"change_id": "c1", "type": "upsert_daily_override",
                      "item_type": "recurring", "item_id": "r1",
                      "local_date": "2026-11-08", "action": "reschedule",
                      "planned_start_minute": 600, "planned_end_minute": 600})

    def test_override_action_whitelist(self):
        self._reject({"change_id": "c1", "type": "upsert_daily_override",
                      "item_type": "recurring", "item_id": "r1",
                      "local_date": "2026-11-08", "action": "delete",
                      "planned_start_minute": 540, "planned_end_minute": 600})

    def test_missing_required_field_rejected(self):
        self._reject({"change_id": "c1", "type": "schedule_one_time",
                      "task_id": "t1"})

    def test_bool_is_not_a_minute(self):
        self._reject({"change_id": "c1", "type": "upsert_daily_override",
                      "item_type": "one_time", "item_id": "t1",
                      "local_date": "2026-11-08", "action": "reschedule",
                      "planned_start_minute": True, "planned_end_minute": 600})

    def test_valid_override_passes(self):
        asm, ex = _assembler()
        out = _assemble(asm, _result(changes=[
            {"change_id": "c1", "type": "upsert_daily_override",
             "item_type": "recurring", "item_id": "r1",
             "local_date": "2026-11-08", "action": "reschedule",
             "planned_start_minute": 540, "planned_end_minute": 600},
        ]))
        self.assertEqual(len(out["changes"]), 1)


class TestSnapshotInput(unittest.TestCase):
    def test_horizon_and_timezone_included(self):
        """契约 L366-374：horizon 不同摘要必须不同，所以它必须进摘要输入。"""
        payload = pa.build_snapshot_input("2026-11-08", "2026-11-10", [], [], [])
        self.assertEqual(payload["horizon"]["start"], "2026-11-08T00:00:00+08:00")
        self.assertEqual(payload["horizon"]["end"], "2026-11-10T23:59:59+08:00")
        self.assertEqual(payload["timezone"], "Asia/Shanghai")

    def test_digest_differs_on_horizon(self):
        a, _ = ss.payload_digest(pa.build_snapshot_input("2026-11-08", "2026-11-09", [], [], []))
        b, _ = ss.payload_digest(pa.build_snapshot_input("2026-11-08", "2026-11-10", [], [], []))
        self.assertNotEqual(a, b)

    def test_digest_ignores_preference_key_order(self):
        a, _ = ss.payload_digest(pa.build_snapshot_input(
            "2026-11-08", "2026-11-08", [], [], [],
            preferences={"day_start_minute": 480, "day_end_minute": 1320}))
        b, _ = ss.payload_digest(pa.build_snapshot_input(
            "2026-11-08", "2026-11-08", [], [], [],
            preferences={"day_end_minute": 1320, "day_start_minute": 480}))
        self.assertEqual(a, b)

    def test_digest_ignores_input_array_order(self):
        """引擎换了事件字段名时只剩兜底键，也不能让摘要随调用顺序漂。"""
        e1 = {"start": "2026-11-08T09:00:00+08:00", "event_id": "e1"}
        e2 = {"start": "2026-11-08T14:00:00+08:00", "event_id": "e2"}
        a, _ = ss.payload_digest(pa.build_snapshot_input(
            "2026-11-08", "2026-11-08", [], [], [e1, e2]))
        b, _ = ss.payload_digest(pa.build_snapshot_input(
            "2026-11-08", "2026-11-08", [], [], [e2, e1]))
        self.assertEqual(a, b)

    def test_rejects_non_list_part(self):
        with self.assertRaises(pa.ProposalAssemblyError):
            pa.build_snapshot_input("2026-11-08", "2026-11-08", {}, [], [])

    def test_rejects_non_object_preferences(self):
        with self.assertRaises(pa.ProposalAssemblyError):
            pa.build_snapshot_input("2026-11-08", "2026-11-08", [], [], [],
                                    preferences=[1, 2])


class TestContractStatus(unittest.TestCase):
    def test_db_pending_maps_to_draft(self):
        self.assertEqual(pa.contract_status("pending"), "draft")

    def test_contract_status_passthrough(self):
        for status in ("draft", "pending_approval", "applied", "expired"):
            self.assertEqual(pa.contract_status(status), status)

    def test_unknown_status_is_internal_error(self):
        with self.assertRaises(pa.ProposalAssemblyError) as ctx:
            pa.contract_status("weird")
        self.assertEqual(ctx.exception.code, "INTERNAL_ERROR")

    def test_assembled_status_is_draft(self):
        asm, _ = _assembler()
        self.assertEqual(_assemble(asm)["status"], "draft")


class TestPlanPersistence(unittest.TestCase):
    def test_plan_written_to_db_is_jsonb_not_python_repr(self):
        asm, ex = _assembler()
        _assemble(asm)
        raw = ex.statements[3][1][4]
        self.assertIsInstance(raw, str)
        parsed = json.loads(raw)
        self.assertEqual(set(parsed), {"blocks", "changes", "unplanned_tasks",
                                       "explanations"})
        self.assertNotIn("'", raw, "必须是 JSON 双引号，不能是 Python repr")


if __name__ == "__main__":
    unittest.main()
