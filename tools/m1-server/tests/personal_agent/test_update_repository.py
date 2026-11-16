from __future__ import annotations

import json
import unittest
import urllib.parse

from checkd_task_agent.models import AgentError
from checkd_task_agent.supabase import HttpResponse, SupabaseTaskRepository
from .test_query_repository import TASK_A, USER_ID, jwt, row


class UpdateTransport:
    def __init__(self):
        self.rows = [row()]
        self.requests: list[tuple[str, str, dict[str, str], bytes | None]] = []
        self.patch_status = 200
        self.patch_body = b""
        self.auth_status = 200
        self.network_on_patch = False
        self.fail_on_child_patch = False
        self.patch_count = 0

    def request(self, method, url, *, headers, body=None, timeout=15):
        self.requests.append((method, url, headers, body))
        path = urllib.parse.urlsplit(url).path
        if path == "/auth/v1/user":
            return HttpResponse(self.auth_status, json.dumps({"id": USER_ID}).encode())
        table = path.rsplit("/", 1)[-1]
        if method == "GET":
            return HttpResponse(200, json.dumps(self.rows).encode())
        if method != "PATCH":
            raise AssertionError(f"unexpected method {method}")
        self.patch_count += 1
        if self.network_on_patch:
            raise AgentError("NETWORK_ERROR", "simulated", retryable=True)
        if table == "one_time_reminders" and self.fail_on_child_patch:
            raise AgentError("NETWORK_ERROR", "simulated child failure", retryable=True)
        if self.patch_status != 200:
            return HttpResponse(self.patch_status, self.patch_body)
        values = json.loads(body.decode()) if body else {}
        if table == "tasks":
            self.rows[0]["tasks"].update(values)
            return HttpResponse(200, json.dumps([{"id": TASK_A}]).encode())
        if table == "one_time_reminders":
            self.rows[0].update(values)
            return HttpResponse(200, json.dumps([{"id": TASK_A}]).encode())
        raise AssertionError(table)


class UpdateRepositoryTest(unittest.TestCase):
    def setUp(self):
        self.transport = UpdateTransport()
        self.repository = SupabaseTaskRepository(
            url="https://example.supabase.co",
            publishable_key="public-key",
            user_access_token=jwt(),
            transport=self.transport,
        )

    def test_parent_and_child_are_conditionally_patched_and_read_back(self):
        original = self.repository.get_one_time_task_snapshot(TASK_A)
        target = dict(original)
        target["name"] = "课程实验报告"
        target["planned_at"] = "2026-11-12T17:30:00+08:00"
        target["scheduled_at"] = target["planned_at"]
        target["planned_date"] = "2026-11-12"
        result = self.repository.update_one_time_task(original, target)

        self.assertEqual(result["name"], "课程实验报告")
        self.assertTrue(result["readback_verified"])
        self.assertEqual([method for method, *_ in self.transport.requests], ["GET", "GET", "GET", "PATCH", "PATCH", "GET"])
        self.assertNotIn("user_id", result)
        for method, _, _, body in self.transport.requests:
            if method == "PATCH":
                self.assertNotIn("user_id", json.loads(body.decode()))

    def test_execution_time_13_00_to_13_30_updates_scheduled_at_and_planned_date(self):
        self.transport.rows[0]["scheduled_at"] = "2026-11-11T05:00:00Z"
        self.transport.rows[0]["planned_date"] = "2026-11-11"
        original = self.repository.get_one_time_task_snapshot(TASK_A)
        target = dict(
            original,
            scheduled_at="2026-11-11T13:30:00+08:00",
            planned_at="2026-11-11T13:30:00+08:00",
            planned_date="2026-11-11",
        )
        result = self.repository.update_one_time_task(original, target)
        self.assertEqual(result["planned_at"], "2026-11-11T13:30:00+08:00")
        self.assertEqual(result["planned_date"], "2026-11-11")
        reminder_patch = next(
            json.loads(body.decode())
            for method, url, _, body in self.transport.requests
            if method == "PATCH" and urlsplit_table(url) == "one_time_reminders"
        )
        self.assertEqual(reminder_patch["scheduled_at"], "2026-11-11T13:30:00+08:00")
        self.assertEqual(reminder_patch["planned_date"], "2026-11-11")
        reminder_url = next(
            url
            for method, url, _, _ in self.transport.requests
            if method == "PATCH" and urlsplit_table(url) == "one_time_reminders"
        )
        self.assertEqual(urllib.parse.parse_qs(urllib.parse.urlsplit(reminder_url).query)["select"], ["task_id"])

    def test_execution_time_update_does_not_require_reminder_rules(self):
        """A missing reminder_rules row must not block schedule editing."""
        original = self.repository.get_one_time_task_snapshot(TASK_A)
        target = dict(
            original,
            scheduled_at="2026-11-11T13:30:00+08:00",
            planned_at="2026-11-11T13:30:00+08:00",
            planned_date="2026-11-11",
        )
        self.repository.update_one_time_task(original, target)
        self.assertFalse(any("reminder_rules" in url for _, url, _, _ in self.transport.requests))

    def test_missing_one_time_reminder_is_not_patched_unconditionally(self):
        self.transport.rows = []
        with self.assertRaises(AgentError) as caught:
            self.repository.get_one_time_task_snapshot(TASK_A)
        self.assertEqual(caught.exception.code, "NOT_FOUND")
        self.assertEqual(self.transport.patch_count, 0)

    def test_execution_time_update_leaves_existing_reminder_rules_untouched(self):
        """Reminder rules are separate records and are not rewritten by rescheduling."""
        original = self.repository.get_one_time_task_snapshot(TASK_A)
        target = dict(
            original,
            scheduled_at="2026-11-11T13:30:00+08:00",
            planned_at="2026-11-11T13:30:00+08:00",
            planned_date="2026-11-11",
        )
        self.repository.update_one_time_task(original, target)
        self.assertFalse(any("reminder_rules" in url for _, url, _, _ in self.transport.requests))

    def test_clear_planned_time_updates_both_semantic_fields_without_null_scheduled_at(self):
        original = self.repository.get_one_time_task_snapshot(TASK_A)
        target = dict(original, has_scheduled_date=False, planned_at=None, planned_date=None)
        result = self.repository.update_one_time_task(original, target)
        self.assertIsNone(result["planned_at"])
        self.assertIsNone(result["planned_date"])
        reminder_patch = next(
            json.loads(body.decode())
            for method, url, _, body in self.transport.requests
            if method == "PATCH" and urlsplit_table(url) == "one_time_reminders"
        )
        self.assertIsNone(reminder_patch["planned_date"])
        self.assertFalse(reminder_patch["has_scheduled_date"])
        self.assertIsNotNone(reminder_patch["scheduled_at"])

    def test_deadline_switch_clears_the_other_shape(self):
        original = self.repository.get_one_time_task_snapshot(TASK_A)
        target = dict(original, deadline_at=None, deadline_date="2026-11-13")
        result = self.repository.update_one_time_task(original, target)
        self.assertEqual(result["deadline_date"], "2026-11-13")
        self.assertIsNone(result["deadline_at"])
        patch = next(
            json.loads(body.decode())
            for method, url, _, body in self.transport.requests
            if method == "PATCH" and urlsplit_table(url) == "one_time_reminders"
        )
        self.assertEqual(patch["due_date"], "2026-11-13")
        self.assertIsNone(patch["due_at"])

    def test_owner_snapshot_conflict_returns_zero_patches(self):
        original = self.repository.get_one_time_task_snapshot(TASK_A)
        self.transport.rows[0]["tasks"]["name"] = "其他设备已改"
        with self.assertRaises(AgentError) as caught:
            self.repository.update_one_time_task(original, dict(original, name="新名称"))
        self.assertEqual(caught.exception.code, "CONCURRENT_MODIFICATION")
        self.assertEqual([method for method, *_ in self.transport.requests], ["GET", "GET", "GET"])

    def test_other_user_and_expired_jwt_are_not_editable(self):
        self.transport.rows[0]["user_id"] = "00000000-0000-0000-0000-000000000099"
        self.transport.rows[0]["tasks"]["user_id"] = "00000000-0000-0000-0000-000000000099"
        with self.assertRaises(AgentError) as caught:
            self.repository.get_one_time_task_snapshot(TASK_A)
        self.assertEqual(caught.exception.code, "NOT_FOUND")

        self.transport = UpdateTransport()
        self.repository = SupabaseTaskRepository(
            url="https://example.supabase.co",
            publishable_key="public-key",
            user_access_token=jwt(),
            transport=self.transport,
        )
        self.transport.auth_status = 401
        with self.assertRaises(AgentError) as caught:
            self.repository.get_one_time_task_snapshot(TASK_A)
        self.assertEqual(caught.exception.code, "AUTH_EXPIRED")

    def test_rls_and_network_errors_are_not_hidden(self):
        original = self.repository.get_one_time_task_snapshot(TASK_A)
        target = dict(original, name="新名称")
        self.transport.patch_status = 403
        with self.assertRaises(AgentError) as caught:
            self.repository.update_one_time_task(original, target)
        self.assertEqual(caught.exception.code, "RLS_DENIED")

        self.transport.patch_status = 200
        self.transport.network_on_patch = True
        with self.assertRaises(AgentError) as caught:
            self.repository.update_one_time_task(original, target)
        self.assertEqual(caught.exception.code, "NETWORK_ERROR")
        self.assertTrue(caught.exception.retryable)

    def test_remote_update_failure_keeps_safe_postgrest_diagnostics(self):
        original = self.repository.get_one_time_task_snapshot(TASK_A)
        self.transport.patch_status = 400
        self.transport.patch_body = json.dumps(
            {
                "code": "23514",
                "message": "new row violates check constraint",
                "hint": "Bearer eyJsecret.payload.signature",
            }
        ).encode()
        with self.assertRaises(AgentError) as caught:
            self.repository.update_one_time_task(original, dict(original, planned_at="2026-11-12T13:30:00+08:00", scheduled_at="2026-11-12T13:30:00+08:00"))
        self.assertEqual(caught.exception.code, "REMOTE_UPDATE_FAILED")
        self.assertEqual(caught.exception.details["stage"], "reminder")
        self.assertEqual(caught.exception.details["http_status"], 400)
        self.assertEqual(caught.exception.details["postgrest_code"], "23514")
        self.assertNotIn("Bearer eyJ", str(caught.exception.details))

    def test_child_failure_is_reported_as_partial_update(self):
        original = self.repository.get_one_time_task_snapshot(TASK_A)
        self.transport.fail_on_child_patch = True
        with self.assertRaises(AgentError) as caught:
            self.repository.update_one_time_task(
                original,
                dict(
                    original,
                    name="新名称",
                    planned_at="2026-11-12T17:30:00+08:00",
                    scheduled_at="2026-11-12T17:30:00+08:00",
                    planned_date="2026-11-12",
                ),
            )
        self.assertEqual(caught.exception.code, "PARTIAL_UPDATE")
        self.assertTrue(caught.exception.retryable)
        self.assertEqual(self.transport.rows[0]["tasks"]["name"], "新名称")

    def test_readback_mismatch_never_returns_verified_success(self):
        original = self.repository.get_one_time_task_snapshot(TASK_A)
        original_request = self.transport.request

        def corrupting_request(method, url, **kwargs):
            response = original_request(method, url, **kwargs)
            if method == "PATCH" and self.transport.patch_count == 2:
                self.transport.rows[0]["planned_date"] = "2026-11-30"
            return response

        self.transport.request = corrupting_request
        target = dict(
            original,
            name="新名称",
            planned_at="2026-11-12T17:30:00+08:00",
            scheduled_at="2026-11-12T17:30:00+08:00",
            planned_date="2026-11-12",
        )
        with self.assertRaises(AgentError) as caught:
            self.repository.update_one_time_task(original, target)
        self.assertEqual(caught.exception.code, "READBACK_MISMATCH")

    def test_update_never_uses_insert_delete_or_put(self):
        original = self.repository.get_one_time_task_snapshot(TASK_A)
        self.repository.update_one_time_task(original, dict(original, notes="新的备注"))
        self.assertTrue(all(method == "GET" or method == "PATCH" for method, *_ in self.transport.requests))


def urlsplit_table(url: str) -> str:
    return urllib.parse.urlsplit(url).path.rsplit("/", 1)[-1]


if __name__ == "__main__":
    unittest.main()
