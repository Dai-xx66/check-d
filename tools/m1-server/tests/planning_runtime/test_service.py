import unittest

from checkd_planning_engine.service import PlanningService

SNAPSHOT = {
    "subject_ref": "user-a", "source": "fixture", "captured_at": "2026-11-14T01:00:00Z",
    "version": "v1", "sync_state": "unknown", "timezone": "Asia/Shanghai",
    "now": "2026-11-14T09:00:00+08:00", "horizon_end": "2026-11-14T18:00:00+08:00",
    "tasks": [{"task_id": "t1", "remaining_seconds": 1800, "deadline_date": "2026-11-14",
               "earliest_start": "2026-11-14T09:00:00+08:00", "completion_status": "pending"}],
    "course_occurrences": [{"starts_at": "2026-11-14T10:00:00+08:00", "ends_at": "2026-11-14T11:00:00+08:00", "kind": "course"}],
    "occupied_blocks": [], "unmodeled_recurring_occurrence_ids": [],
}


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.service = PlanningService(lambda context: context["subject"] if context else None)

    def call(self, **kwargs):
        return self.service.handle({"snapshot": SNAPSHOT, **kwargs}, {"subject": "user-a"})

    def test_preview_is_structured_and_never_write_eligible(self):
        result = self.call()
        self.assertTrue(result["ok"])
        self.assertEqual(result["outcome"], "found_feasible")
        self.assertFalse(result["execution_eligible"])
        self.assertTrue(result["provisional"])

    def test_missing_effort_is_unknown_not_zero_or_infeasible(self):
        snapshot = dict(SNAPSHOT, tasks=[dict(SNAPSHOT["tasks"][0], remaining_seconds=None)])
        result = self.service.handle({"snapshot": snapshot}, {"subject": "user-a"})
        self.assertEqual(result["outcome"], "unknown_due_to_missing_data")
        self.assertEqual(result["missing_data"]["unknown_effort_task_ids"], ["t1"])
        risk = self.service.handle({"snapshot": snapshot, "operation": "risk"}, {"subject": "user-a"})
        self.assertEqual(risk["risk_status"], "unknown_due_to_missing_data")
        self.assertNotIn("capacity_insufficient", [item["risk_type"] for item in risk["risks"]])

    def test_principal_mismatch_fails_closed(self):
        result = self.service.handle({"snapshot": SNAPSHOT}, {"subject": "user-b"})
        self.assertEqual(result["error"]["code"], "NOT_FOUND")

    def test_missing_auth_and_spoofed_user_id_rejected(self):
        self.assertEqual(self.service.handle({"snapshot": SNAPSHOT}, None)["error"]["code"], "AUTH_REQUIRED")
        result = self.service.handle({"snapshot": SNAPSHOT, "user_id": "user-b"}, {"subject": "user-a"})
        self.assertEqual(result["error"]["code"], "INVALID_INPUT")
        self.assertEqual(result["outcome"], "invalid_input")

    def test_snapshot_version_mismatch_rejected(self):
        result = self.call(expected_version="old")
        self.assertEqual(result["error"]["code"], "SNAPSHOT_STALE")

    def test_delay_and_risk_operations(self):
        delay = self.call(operation="delay", delay={"task_id": "t1", "until": "2026-11-14T11:00:00+08:00"})
        self.assertTrue(delay["delay_analysis"]["before_feasible"])
        risk = self.call(operation="risk")
        self.assertIn("risks", risk)

    def test_missed_existing_plan_reenters_risk_scan(self):
        snapshot = dict(SNAPSHOT, tasks=[dict(SNAPSHOT["tasks"][0],
            planned_at="2026-11-14T08:00:00+08:00", remaining_seconds=None)])
        result = self.service.handle({"snapshot":snapshot,"operation":"risk"},{"subject":"user-a"})
        self.assertIn("plan_missed",[risk["risk_type"] for risk in result["risks"]])


if __name__ == "__main__":
    unittest.main()
