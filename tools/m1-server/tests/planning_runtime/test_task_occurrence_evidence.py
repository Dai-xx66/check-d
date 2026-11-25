"""M3 2026-11-23: long-term task occurrence evidence chain (synthetic data).

M0 2026-11-23 dispatch: M2 owns the client-side publication of long-term /
recurring task occurrences; M3 owns the server-side schema, RPC, MCP wiring,
end-to-end validation and final acceptance.

The server NEVER expands a recurring rule. It only accepts a version-consistent,
device-owned, digest-consistent snapshot that the client already built. Every
B/C freshness state and every mismatch keeps
``recurring_occurrences_not_resolved`` fail-closed.

Synthetic data only: no production schema, no real task/course/calendar data,
no writes. Run with:

    PYTHONPATH=. python -m unittest tests.planning_runtime.test_task_occurrence_evidence -v
"""
import json
import os
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch
from urllib.parse import urlparse

from checkd_planning_engine.importer import import_snapshot
from checkd_planning_engine.remote_mcp import RemoteIdentity
from checkd_planning_engine.supabase_remote import SupabaseRestSnapshotProvider


class Response:
    def __init__(self, status, value):
        self.status = status
        self.raw = json.dumps(value).encode()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return None

    def read(self, size=-1):
        return self.raw[:size]


DEVICE = "00000000-0000-4000-8000-0000000000a1"
DEVICE2 = "00000000-0000-4000-8000-0000000000a2"
START, END = "2026-11-23", "2026-11-30"
TASK_LONG = "task-long-english"
TASK_DIGEST = "task-digest-abcdef0123456789"


def iso_ago(**kw):
    return (datetime.now(timezone.utc) - timedelta(**kw)).isoformat()


def watermark(version=42, generation=5, ack=None, device=DEVICE):
    return {"device_id": device, "server_data_version": version,
            "local_generation": generation,
            "acknowledged_at": ack or iso_ago(minutes=1), "device_status": "active"}


def course_snapshot(version=42, generation=5, digest="digest-a", device=DEVICE):
    return {"device_id": device, "from_date": START, "through_date": END,
            "timezone": "Asia/Shanghai",
            "builder_version": "checkd_flutter_course_occurrence_v1",
            "course_data_version": "sha256:fixture",
            "generated_at": iso_ago(minutes=1),
            "server_data_version": version, "occurrence_digest": digest,
            "local_generation": generation,
            "occurrences": [{"occurrence_id": "course:rule-a:2026-11-24",
                             "course_id": "course-a", "schedule_rule_id": "rule-a",
                             "local_date": "2026-11-24", "start_minute": 540,
                             "end_minute": 600, "timezone": "Asia/Shanghai"}]}


def occurrence(local_date="2026-11-24", task_id=TASK_LONG,
               occurrence_id="long:2026-11-24", start=480, finish=510,
               zone="Asia/Shanghai"):
    return {"occurrence_id": occurrence_id, "task_id": task_id,
            "local_date": local_date, "start_minute": start,
            "end_minute": finish, "timezone": zone}


def task_snapshot(version=42, generation=5, digest=TASK_DIGEST, device=DEVICE,
                  occurrences=None):
    return {"device_id": device, "from_date": START, "through_date": END,
            "timezone": "Asia/Shanghai",
            "builder_version": "checkd_flutter_task_occurrence_v1",
            "task_data_version": "sha256:fixture",
            "generated_at": iso_ago(minutes=1),
            "server_data_version": version, "occurrence_digest": digest,
            "local_generation": generation,
            "occurrences": occurrences if occurrences is not None
                           else [occurrence()]}


def base_rows(*, recurring=True, watermarks=None, course_snapshots=None,
              task_snapshots=None):
    rows = {
        "tasks": [{"id": "task-a", "name": "合成一次性任务", "type": "one_time",
                   "status": "active", "remaining_effort_minutes": 30,
                   "updated_at": "2026-11-15T08:00:00+08:00"}],
        "one_time_reminders": [{"task_id": "task-a", "due_date": "2026-11-25",
                                "available_from": "2026-11-15", "completed_at": None}],
        "courses": [{"id": "course-a", "name": "合成课程", "status": "active"}],
        "course_schedule_rules": [{"id": "rule-a", "course_id": "course-a"}],
        "agent_device_sync_watermarks": watermarks if watermarks is not None
                                        else [watermark()],
        "agent_course_occurrence_snapshots": course_snapshots
            if course_snapshots is not None else [course_snapshot()],
        "agent_task_occurrence_snapshots": task_snapshots
            if task_snapshots is not None else [task_snapshot()],
    }
    if recurring:
        rows["tasks"].append({"id": TASK_LONG, "name": "英语单词",
                              "type": "long_term", "status": "active",
                              "remaining_effort_minutes": None,
                              "updated_at": "2026-11-15T08:00:00+08:00"})
    return rows


CHECKPOINT = {"planning_ready": True, "device_checkpoints_current": True,
              "course_occurrences_cover_window": True,
              "known_device_count": 1, "server_data_version": 42}
FENCE = {"ok": True, "ready": True, "blockers": [],
         "snapshot_version": "trusted-v1", "data_version": 42,
         "course_occurrence_digest": "digest-a"}


class TaskOccurrenceEvidenceTests(unittest.TestCase):
    def run_case(self, rows, *, enabled=True, version_mode=True,
                 checkpoint=None, fence=None):
        calls = []

        def opener(request, timeout):
            calls.append(request)
            name = urlparse(request.full_url).path.rsplit("/", 1)[-1]
            if name == "get_agent_planning_checkpoint_status":
                return Response(200, checkpoint or CHECKPOINT)
            if name == "get_agent_planning_fence":
                return Response(200, fence or FENCE)
            return Response(200, rows.get(name, []))

        provider = SupabaseRestSnapshotProvider(
            supabase_url="https://supabase.test", publishable_key="k",
            opener=opener)
        identity = RemoteIdentity("user-a", "t", frozenset({"planning:read"}),
                                  2 ** 31, "jwt-a")
        env = {
            "CHECKD_PLANNING_FRESHNESS_MODE": "version" if version_mode else "legacy",
            "CHECKD_TASK_OCCURRENCE_EVIDENCE_ENABLED": "1" if enabled else "0",
        }
        with patch.dict(os.environ, env, clear=False):
            snap = provider.fetch_authenticated(identity, START, END)
        return snap, calls

    @staticmethod
    def table_calls(calls, table):
        return [c for c in calls
                if urlparse(c.full_url).path.rsplit("/", 1)[-1] == table]

    # T1 长期任务已展开、版本/generation/digest 一致 -> blocker 解除
    def test_t1_published_occurrences_clear_blocker(self):
        snap, calls = self.run_case(base_rows())
        self.assertNotIn("recurring_occurrences_not_resolved",
                         snap["planning_blockers"])
        self.assertTrue(snap["task_occurrence_evidence"]["validated"])
        self.assertEqual(snap["task_occurrence_evidence"]["reason"],
                         "task_occurrences_version_current")
        self.assertEqual(len(snap["task_occurrences"]), 1)
        self.assertEqual(snap["task_occurrences"][0]["kind"], "task_occurrence")
        self.assertTrue(snap["planning_ready"])
        self.assertEqual(snap["readiness_blockers"], [])
        self.assertEqual(len(self.table_calls(calls, "agent_task_occurrence_snapshots")), 1)
        # 快照身份必须绑定任务证据，避免旧提案匹配新快照
        self.assertIn(TASK_DIGEST[:16], snap["source_snapshot_version"])

    # T2 客户端未上报（表为空）-> 维持 fail closed
    def test_t2_not_published_keeps_blocker(self):
        snap, _ = self.run_case(base_rows(task_snapshots=[]))
        self.assertIn("recurring_occurrences_not_resolved",
                      snap["planning_blockers"])
        self.assertFalse(snap["task_occurrence_evidence"]["validated"])

    # T3 版本落后 -> 维持 fail closed（不得采信旧证据）
    def test_t3_stale_version_keeps_blocker(self):
        snap, _ = self.run_case(base_rows(task_snapshots=[task_snapshot(version=41)]))
        self.assertIn("recurring_occurrences_not_resolved",
                      snap["planning_blockers"])
        self.assertEqual(snap["task_occurrence_evidence"]["reason"],
                         "task_snapshot_version_behind")

    # T4 跨设备 digest 不一致 -> 维持 fail closed
    def test_t4_cross_device_digest_mismatch_keeps_blocker(self):
        rows = base_rows(
            watermarks=[watermark(), watermark(device=DEVICE2)],
            course_snapshots=[course_snapshot(),
                              course_snapshot(device=DEVICE2)],
            task_snapshots=[task_snapshot(),
                            task_snapshot(device=DEVICE2, digest="other-digest")])
        snap, _ = self.run_case(rows)
        self.assertIn("recurring_occurrences_not_resolved",
                      snap["planning_blockers"])
        self.assertEqual(snap["task_occurrence_evidence"]["reason"],
                         "task_digest_mismatch")

    # T5 开关默认关闭 -> 零新 REST 调用、返回结构零新增字段、原 blocker 保留
    def test_t5_opt_in_off_is_no_op(self):
        snap, calls = self.run_case(base_rows(), enabled=False)
        self.assertEqual(self.table_calls(calls, "agent_task_occurrence_snapshots"), [])
        self.assertNotIn("task_occurrences", snap)
        self.assertNotIn("task_occurrence_evidence", snap)
        self.assertEqual(snap["planning_blockers"],
                         ["recurring_occurrences_not_resolved"])

    # T6 无长期任务 -> 无需证据，也不读新表
    def test_t6_no_recurring_task_needs_no_evidence(self):
        snap, calls = self.run_case(base_rows(recurring=False))
        self.assertEqual(snap["planning_blockers"], [])
        self.assertEqual(self.table_calls(calls, "agent_task_occurrence_snapshots"), [])
        self.assertEqual(snap["task_occurrence_evidence"]["reason"],
                         "no_recurring_tasks")

    # T7a 窗口外条目裁剪，窗口内仍严格校验
    def test_t7a_out_of_window_occurrences_are_cropped(self):
        rows = base_rows(task_snapshots=[task_snapshot(occurrences=[
            occurrence(local_date="2026-11-24", occurrence_id="in"),
            occurrence(local_date="2026-12-05", occurrence_id="out")])])
        snap, _ = self.run_case(rows)
        self.assertTrue(snap["task_occurrence_evidence"]["validated"])
        self.assertEqual([i["occurrence_id"] for i in snap["task_occurrences"]],
                         ["in"])

    # T7b 窗口内的非法条目（非本人长期任务 / 时间倒挂）-> fail closed
    def test_t7b_invalid_in_window_occurrence_is_rejected(self):
        for bad in (occurrence(task_id="task-not-mine"),
                    occurrence(start=600, finish=540)):
            with self.subTest(bad=bad):
                rows = base_rows(task_snapshots=[task_snapshot(occurrences=[bad])])
                snap, _ = self.run_case(rows)
                self.assertIn("recurring_occurrences_not_resolved",
                              snap["planning_blockers"])
                self.assertEqual(snap["task_occurrence_evidence"]["reason"],
                                 "task_occurrence_invalid")

    # T8 B/C 新鲜度态下证据链不得放行（M0：审批/apply 对 B/C fail closed）
    def test_t8_non_trusted_freshness_keeps_blocker(self):
        rows = base_rows(watermarks=[watermark(version=41)])
        snap, _ = self.run_case(rows)
        self.assertIn("recurring_occurrences_not_resolved",
                      snap["planning_blockers"])
        self.assertIn(snap["task_occurrence_evidence"]["reason"],
                      {"freshness_not_trusted", "task_snapshot_version_behind",
                       "missing_task_snapshot_for_device"})

    # T9 归一化后的任务 occurrence 必须进入排程占用块，而不是只清 blocker
    def test_t9_importer_consumes_task_occurrences_as_busy_blocks(self):
        payload = {
            "subject_ref": "user-a", "source": "supabase_postgrest_user_jwt",
            "captured_at": "2026-11-23T12:00:00+00:00", "version": "read:test",
            "sync_state": "current", "timezone": "Asia/Shanghai",
            "now": "2026-11-23T12:00:00+08:00",
            "horizon_end": "2026-11-30T23:59:59+08:00",
            "tasks": [], "course_occurrences": [], "occupied_blocks": [],
            "task_occurrences": [{
                "starts_at": "2026-11-24T08:00:00+08:00",
                "ends_at": "2026-11-24T08:30:00+08:00",
                "task_id": TASK_LONG, "occurrence_id": "long:2026-11-24",
                "kind": "task_occurrence"}],
        }
        snap = import_snapshot(payload)
        kinds = [block.kind for block in snap.planning_input.fixed_blocks]
        self.assertIn("task_occurrence", kinds)
        self.assertEqual(len(snap.planning_input.fixed_blocks), 1)


if __name__ == "__main__":
    unittest.main()
