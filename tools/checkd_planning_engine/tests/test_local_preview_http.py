from http.client import HTTPConnection
import json
import threading
import unittest

from checkd_planning_engine.local_preview_http import make_local_preview_server


class LocalPreviewHttpTests(unittest.TestCase):
    def test_bridge_refuses_non_loopback_bind(self):
        with self.assertRaisesRegex(ValueError, "127.0.0.1"):
            make_local_preview_server(token="a-local-only-test-token-value", host="0.0.0.0")

    def setUp(self):
        self.server = make_local_preview_server(
            token="test-only-local-preview-token-1234567890",
            host="127.0.0.1",
            port=0,
        )
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.server.shutdown)
        self.addCleanup(self.server.server_close)

    def post(self, path, payload, token="test-only-local-preview-token-1234567890"):
        connection = HTTPConnection("127.0.0.1", self.server.server_port)
        connection.request(
            "POST", path, json.dumps(payload),
            {"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        )
        response = connection.getresponse()
        result = response.status, json.loads(response.read())
        connection.close()
        return result

    def snapshot(self):
        return {
            "schema_version": "checkd.planning.snapshot.v1",
            "subject_ref": "local-test-user",
            "source": "isolated_test",
            "captured_at": "2026-11-15T00:00:00Z",
            "version": "local-v1",
            "sync_state": "current",
            "provisional": False,
            "timezone": "Asia/Shanghai",
            "now": "2026-11-15T09:00:00+08:00",
            "horizon_end": "2026-11-15T18:00:00+08:00",
            "tasks": [{
                "task_id": "task-1", "remaining_seconds": 1800,
                "deadline_date": "2026-11-15",
                "earliest_start": "2026-11-15T09:00:00+08:00",
                "completion_status": "pending",
            }],
            "course_occurrences": [{
                "starts_at": "2026-11-15T10:00:00+08:00",
                "ends_at": "2026-11-15T11:00:00+08:00", "kind": "course",
            }],
            "occupied_blocks": [],
        }

    def test_preview_computes_from_submitted_snapshot_and_never_enables_execution(self):
        status, result = self.post("/v0/preview", {"snapshot": self.snapshot()})
        self.assertEqual(status, 200)
        self.assertTrue(result["ok"])
        self.assertTrue(result["schedule"]["feasible"])
        self.assertFalse(result["execution_eligible"])
        self.assertEqual(result["snapshot_version"], "local-v1")
        for block in result["schedule"]["blocks"]:
            self.assertLessEqual(block["ends_at"], "2026-11-15T10:00:00+08:00")
            self.assertFalse(
                block["starts_at"] < "2026-11-15T11:00:00+08:00"
                and "2026-11-15T10:00:00+08:00" < block["ends_at"]
            )

    def test_delay_and_risk_routes_use_same_planning_service(self):
        snapshot = self.snapshot()
        status, delay = self.post("/v0/delay", {
            "snapshot": snapshot, "task_id": "task-1",
            "until": "2026-11-15T12:00:00+08:00",
        })
        self.assertEqual(status, 200)
        self.assertIn("delay_analysis", delay)
        self.assertTrue(delay["delay_analysis"]["before_feasible"])
        status, risks = self.post("/v0/risks", {"snapshot": snapshot})
        self.assertEqual(status, 200)
        self.assertIn("risks", risks)

    def test_local_token_and_user_id_spoofing_fail_closed(self):
        status, result = self.post("/v0/preview", {"snapshot": self.snapshot()}, token="wrong")
        self.assertEqual(status, 401)
        self.assertEqual(result["error"]["code"], "AUTH_REQUIRED")
        status, result = self.post("/v0/preview", {
            "user_id": "other-user", "snapshot": self.snapshot(),
        })
        self.assertEqual(status, 400)
        self.assertEqual(result["error"]["code"], "INVALID_INPUT")


if __name__ == "__main__":
    unittest.main()
