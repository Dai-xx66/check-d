from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from checkd_task_agent.ledger import ConfirmationLedger
from checkd_task_agent.models import AgentError
from checkd_task_agent.update_service import TaskUpdateService


TASK_ID = "10000000-0000-0000-0000-000000000001"
NOW = datetime(2026, 11, 11, 4, 0, tzinfo=timezone.utc)


def snapshot(**overrides):
    value = {
        "id": TASK_ID,
        "name": "实验报告",
        "task_type": "one_time",
        "lifecycle_status": "active",
        "completion_status": "pending",
        "deleted_at": None,
        "notes": "旧备注",
        "scheduled_at": "2026-11-12T10:00:00+08:00",
        "has_scheduled_date": True,
        "planned_at": "2026-11-12T10:00:00+08:00",
        "planned_date": "2026-11-12",
        "deadline_date": None,
        "deadline_at": "2026-11-12T15:00:00+08:00",
        "task_updated_at": "2026-11-11T11:00:00+08:00",
        "reminder_updated_at": "2026-11-11T11:00:00+08:00",
    }
    value.update(overrides)
    return value


class FakeUpdateRepository:
    def __init__(self, value=None):
        self.snapshot = value or snapshot()
        self.get_calls = 0
        self.update_calls = []
        self.update_result = None
        self.update_error = None

    def get_one_time_task_snapshot(self, task_id):
        self.get_calls += 1
        if task_id != self.snapshot["id"]:
            raise AgentError("NOT_FOUND", "未找到该单次事项。")
        return dict(self.snapshot)

    def authenticated_user_id(self):
        return "synthetic-user"

    def update_one_time_task(self, original_snapshot, target_snapshot, *, write_receipts=None, record_write=None):
        self.update_calls.append((original_snapshot, target_snapshot))
        if self.update_error:
            raise self.update_error
        if self.snapshot != original_snapshot:
            raise AgentError("CONCURRENT_MODIFICATION", "changed")
        self.snapshot = dict(target_snapshot)
        return self.update_result or {
            "id": target_snapshot["id"],
            "name": target_snapshot["name"],
            "task_type": "one_time",
            "lifecycle_status": "active",
            "completion_status": "pending",
            "planned_at": target_snapshot["planned_at"],
            "planned_date": target_snapshot["planned_date"],
            "deadline_date": target_snapshot["deadline_date"],
            "deadline_at": target_snapshot["deadline_at"],
            "notes": target_snapshot["notes"],
            "readback_verified": True,
        }


class TaskUpdateServiceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = FakeUpdateRepository()
        self.ledger = ConfirmationLedger(Path(self.temp.name) / "state.sqlite3")
        self.service = TaskUpdateService(self.ledger, self.repo, clock=lambda: NOW, instance_id="test")

    def prepare(self, changes=None, key="update-1"):
        return self.service.prepare_task_update(
            task_id=TASK_ID,
            changes=changes or {"name": "课程实验报告"},
            idempotency_key=key,
        )

    def test_prepare_reads_server_snapshot_and_performs_zero_updates(self):
        result = self.prepare({"name": "课程实验报告", "notes": None})
        self.assertTrue(result["ok"])
        self.assertEqual(result["original"]["name"], "实验报告")
        self.assertEqual(result["updated"]["name"], "课程实验报告")
        self.assertEqual(result["updated"]["notes"], None)
        self.assertFalse(result["write_performed"])
        self.assertEqual(self.repo.update_calls, [])

    def test_planned_time_and_deadline_shapes_are_normalized(self):
        result = self.prepare(
            {
                "planned_at": "2026-11-12T17:30:00+08:00",
                "deadline_date": "2026-11-13",
                "notes": "新的备注",
            }
        )
        self.assertEqual(result["updated"]["planned_date"], "2026-11-12")
        self.assertEqual(result["updated"]["deadline_date"], "2026-11-13")
        self.assertIsNone(result["updated"]["deadline_at"])

    def test_clear_planned_time_clears_planned_date_but_keeps_nonnull_storage_placeholder(self):
        result = self.prepare({"planned_at": None})
        self.assertIsNone(result["updated"]["planned_at"])
        self.assertIsNone(result["updated"]["planned_date"])
        self.assertNotIn("scheduled_at", result["updated"])

    def test_forbidden_fields_and_invalid_shapes_are_rejected(self):
        with self.assertRaises(AgentError) as caught:
            self.service.prepare_task_update(
                task_id="not-a-uuid", changes={"name": "新"}, idempotency_key="invalid-id"
            )
        self.assertEqual(caught.exception.code, "INVALID_TASK_ID")
        for changes, code in (
            ({"user_id": "other"}, "FIELD_NOT_EDITABLE"),
            ({"expected_duration_minutes": 60}, "FIELD_NOT_EDITABLE"),
            ({"deadline_at": "2026-11-12T16:00:00+08:00", "deadline_date": "2026-11-12"}, "DEADLINE_SHAPE_INVALID"),
            ({"planned_at": "2026-11-13T10:00:00+08:00"}, "PLANNED_AFTER_DEADLINE"),
        ):
            with self.subTest(changes=changes), self.assertRaises(AgentError) as caught:
                self.prepare(changes, key=f"key-{len(self.repo.update_calls)}-{code}")
            self.assertEqual(caught.exception.code, code)
        self.assertEqual(self.repo.update_calls, [])

    def test_confirmation_phrase_required_then_duplicate_is_idempotent(self):
        draft = self.prepare()
        with self.assertRaises(AgentError) as caught:
            self.service.update_task(
                update_confirmation_id=draft["update_confirmation_id"],
                user_confirmation_text="好的",
            )
        self.assertEqual(caught.exception.code, "EXPLICIT_CONFIRMATION_REQUIRED")
        result = self.service.update_task(
            update_confirmation_id=draft["update_confirmation_id"],
            user_confirmation_text=draft["confirmation_phrase"],
        )
        repeated = self.service.update_task(
            update_confirmation_id=draft["update_confirmation_id"],
            user_confirmation_text=draft["confirmation_phrase"],
        )
        self.assertTrue(result["readback_verified"])
        self.assertEqual(repeated, result)
        self.assertEqual(len(self.repo.update_calls), 1)

    def test_cancelled_draft_never_updates_and_completed_cannot_be_cancelled(self):
        draft = self.prepare()
        cancelled = self.service.cancel_task_update(
            update_confirmation_id=draft["update_confirmation_id"]
        )
        self.assertEqual(cancelled["status"], "cancelled")
        with self.assertRaises(AgentError) as caught:
            self.service.update_task(
                update_confirmation_id=draft["update_confirmation_id"],
                user_confirmation_text=draft["confirmation_phrase"],
            )
        self.assertEqual(caught.exception.code, "UPDATE_CONFIRMATION_CANCELLED")
        self.assertEqual(self.repo.update_calls, [])

        fresh = self.prepare(key="update-2")
        self.service.update_task(
            update_confirmation_id=fresh["update_confirmation_id"],
            user_confirmation_text=fresh["confirmation_phrase"],
        )
        with self.assertRaises(AgentError) as caught:
            self.service.cancel_task_update(update_confirmation_id=fresh["update_confirmation_id"])
        self.assertEqual(caught.exception.code, "ALREADY_UPDATED")

    def test_prepare_repeated_after_apply_returns_original_result(self):
        prepared = self.prepare()
        applied = self.service.update_task(
            update_confirmation_id=prepared["update_confirmation_id"],
            user_confirmation_text=prepared["confirmation_phrase"],
        )
        self.assertEqual(self.prepare(), applied)
        self.assertEqual(len(self.repo.update_calls), 1)

    def test_prepare_repeated_after_snapshot_change_keeps_original_approval(self):
        prepared = self.prepare()
        self.repo.snapshot["notes"] = "已在手机操作"
        self.assertEqual(self.prepare(), prepared)
        with self.assertRaises(AgentError) as caught:
            self.prepare({"name": "不同目标"})
        self.assertEqual(caught.exception.code, "IDEMPOTENCY_CONFLICT")

    def test_server_snapshot_change_blocks_write(self):
        draft = self.prepare()
        self.repo.snapshot["name"] = "被其他设备修改"
        with self.assertRaises(AgentError) as caught:
            self.service.update_task(
                update_confirmation_id=draft["update_confirmation_id"],
                user_confirmation_text=draft["confirmation_phrase"],
            )
        self.assertEqual(caught.exception.code, "CONCURRENT_MODIFICATION")
        self.assertEqual(len(self.repo.update_calls), 1)
        self.assertEqual(self.repo.snapshot["name"], "被其他设备修改")

    def test_other_user_or_completed_task_is_not_editable(self):
        self.repo.get_one_time_task_snapshot = lambda task_id: (_ for _ in ()).throw(
            AgentError("NOT_FOUND", "未找到该单次事项。")
        )
        with self.assertRaises(AgentError) as caught:
            self.prepare()
        self.assertEqual(caught.exception.code, "NOT_FOUND")

        self.repo.get_one_time_task_snapshot = lambda task_id: snapshot(completion_status="completed")
        with self.assertRaises(AgentError) as caught:
            self.prepare(key="update-completed")
        self.assertEqual(caught.exception.code, "NOT_EDITABLE")


if __name__ == "__main__":
    unittest.main()
