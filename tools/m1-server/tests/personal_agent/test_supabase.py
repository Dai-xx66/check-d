from __future__ import annotations

import base64
import json
import unittest
import urllib.parse
import urllib.error
from unittest.mock import patch
from datetime import datetime, timezone

from checkd_task_agent.models import AgentError, TaskDraft
from checkd_task_agent.supabase import HttpResponse, SupabaseTaskRepository, UrllibTransport


USER_ID = "00000000-0000-0000-0000-000000000001"


def jwt(role: str) -> str:
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")

    return f"{encode({'alg': 'none'})}.{encode({'role': role})}.signature"


class FakeTransport:
    def __init__(self) -> None:
        self.rows: dict[str, dict[str, object]] = {}
        self.requests: list[tuple[str, str]] = []
        self.auth_status = 200
        self.write_status: dict[str, int] = {}
        self.mutate_readback = False
        self.reminder_readback: dict[str, object] = {}
        self.readback_utc = False

    def request(self, method, url, *, headers, body=None, timeout=15):
        self.requests.append((method, url))
        path = urllib.parse.urlsplit(url).path
        if path == "/auth/v1/user":
            return HttpResponse(self.auth_status, json.dumps({"id": USER_ID}).encode())
        table = path.rsplit("/", 1)[-1]
        if method == "POST":
            status = self.write_status.get(table, 201)
            if 200 <= status < 300 and (
                table not in self.rows or "resolution=ignore-duplicates" not in headers["Prefer"]
            ):
                self.rows[table] = json.loads(body)
            return HttpResponse(status, b"")
        if method == "GET":
            row = dict(self.rows.get(table, {}))
            if self.mutate_readback and table == "tasks":
                row["name"] = "unexpected"
            if table == "one_time_reminders":
                if self.readback_utc:
                    for field in ("scheduled_at", "due_at"):
                        if isinstance(row.get(field), str):
                            row[field] = datetime.fromisoformat(row[field]).astimezone(
                                timezone.utc
                            ).isoformat().replace("+00:00", "Z")
                row.update(self.reminder_readback)
            return HttpResponse(200, json.dumps([row]).encode())
        raise AssertionError((method, url))


class SupabaseTaskRepositoryTest(unittest.TestCase):
    task_id = "10000000-0000-0000-0000-000000000001"
    now = datetime(2026, 11, 11, 4, 0, tzinfo=timezone.utc)

    def make_repository(self, transport: FakeTransport, *, token: str | None = None):
        return SupabaseTaskRepository(
            url="https://example.supabase.co",
            publishable_key="public-key",
            user_access_token=token or jwt("authenticated"),
            transport=transport,
        )

    def draft(self) -> TaskDraft:
        return TaskDraft(
            name="学习 Python",
            expected_duration_minutes=60,
            deadline_at="2026-11-12T20:00:00+08:00",
        )

    def scheduled_draft(self) -> TaskDraft:
        return TaskDraft(
            name="复习计划",
            expected_duration_minutes=30,
            planned_at="2026-11-11T17:20:00Z",
            deadline_at="2026-11-12T07:00:00+08:00",
        )

    def test_readback_rejects_a_changed_scheduled_instant(self) -> None:
        transport = FakeTransport()
        transport.reminder_readback = {"scheduled_at": "2026-11-11T17:21:00Z"}
        with self.assertRaises(AgentError) as caught:
            self.make_repository(transport).create_and_verify(
                self.scheduled_draft(), task_id=self.task_id, now=self.now,
            )
        self.assertEqual(caught.exception.code, "READBACK_MISMATCH")

    def test_readback_accepts_equivalent_utc_instants_and_uses_shanghai_date(self) -> None:
        transport = FakeTransport()
        transport.readback_utc = True
        result = self.make_repository(transport).create_and_verify(
            self.scheduled_draft(), task_id=self.task_id, now=self.now,
        )
        self.assertEqual(result["planned_at"], "2026-11-11T17:20:00+00:00")
        self.assertEqual(transport.rows["one_time_reminders"]["planned_date"], "2026-11-12")

    def test_retry_after_reminder_failure_preserves_parent_creation_metadata(self) -> None:
        transport = FakeTransport()
        repository = self.make_repository(transport)
        transport.write_status["one_time_reminders"] = 503
        with self.assertRaises(AgentError) as caught:
            repository.create_and_verify(self.draft(), task_id=self.task_id, now=self.now)
        self.assertEqual(caught.exception.code, "REMOTE_WRITE_FAILED")
        self.assertTrue(caught.exception.retryable)
        parent = dict(transport.rows["tasks"])
        transport.write_status.clear()

        result = repository.create_and_verify(
            self.draft(), task_id=self.task_id, now=self.now.replace(hour=5),
        )
        self.assertEqual(result["id"], self.task_id)
        self.assertEqual(transport.rows["tasks"], parent)
        self.assertEqual(transport.rows["one_time_reminders"]["task_id"], self.task_id)

    def test_retry_does_not_overwrite_an_existing_task_edit(self) -> None:
        transport = FakeTransport()
        repository = self.make_repository(transport)
        transport.write_status["one_time_reminders"] = 503
        with self.assertRaises(AgentError):
            repository.create_and_verify(self.draft(), task_id=self.task_id, now=self.now)
        transport.rows["tasks"]["name"] = "手机上修改的名称"
        transport.write_status.clear()

        with self.assertRaises(AgentError) as caught:
            repository.create_and_verify(
                self.draft(), task_id=self.task_id, now=self.now.replace(hour=5),
            )
        self.assertEqual(caught.exception.code, "READBACK_MISMATCH")
        self.assertEqual(transport.rows["tasks"]["name"], "手机上修改的名称")
        self.assertNotIn("one_time_reminders", transport.rows)

    def test_retry_keeps_the_original_unscheduled_placeholder(self) -> None:
        transport = FakeTransport()
        repository = self.make_repository(transport)
        repository.create_and_verify(self.draft(), task_id=self.task_id, now=self.now)
        original_reminder = dict(transport.rows["one_time_reminders"])
        result = repository.create_and_verify(
            self.draft(), task_id=self.task_id, now=self.now.replace(hour=5),
        )
        self.assertIsNone(result["planned_at"])
        self.assertEqual(transport.rows["one_time_reminders"], original_reminder)

    def test_normal_user_inserts_parent_and_child_then_reads_back(self) -> None:
        transport = FakeTransport()
        repository = self.make_repository(transport)
        result = repository.create_and_verify(
            self.draft(),
            task_id="10000000-0000-0000-0000-000000000001",
            now=datetime(2026, 11, 11, 4, 0, tzinfo=timezone.utc),
        )
        self.assertEqual(result["name"], "学习 Python")
        self.assertEqual(transport.rows["tasks"]["user_id"], USER_ID)
        self.assertEqual(transport.rows["tasks"]["type"], "one_time")
        self.assertEqual(transport.rows["one_time_reminders"]["due_at"], "2026-11-12T20:00:00+08:00")
        self.assertFalse(transport.rows["one_time_reminders"]["has_scheduled_date"])
        self.assertIn("非 CheckD 结构化时长目标", transport.rows["tasks"]["notes"])
        self.assertEqual([method for method, _ in transport.requests].count("POST"), 2)
        self.assertEqual([method for method, _ in transport.requests].count("GET"), 4)

    def test_service_role_token_is_rejected_before_network_access(self) -> None:
        transport = FakeTransport()
        with self.assertRaises(AgentError) as caught:
            self.make_repository(transport, token=jwt("service_role"))
        self.assertEqual(caught.exception.code, "SERVICE_ROLE_FORBIDDEN")
        self.assertEqual(transport.requests, [])

    def test_secret_key_prefix_is_rejected_before_network_access(self) -> None:
        transport = FakeTransport()
        with self.assertRaises(AgentError) as caught:
            SupabaseTaskRepository(
                url="https://example.supabase.co",
                publishable_key="sb_secret_not_allowed",
                user_access_token=jwt("authenticated"),
                transport=transport,
            )
        self.assertEqual(caught.exception.code, "SERVICE_ROLE_FORBIDDEN")
        self.assertEqual(transport.requests, [])

    def test_expired_user_token_is_reported_safely(self) -> None:
        transport = FakeTransport()
        transport.auth_status = 401
        repository = self.make_repository(transport)
        with self.assertRaises(AgentError) as caught:
            repository.authenticated_user_id()
        self.assertEqual(caught.exception.code, "AUTH_EXPIRED")
        self.assertTrue(caught.exception.retryable)

    def test_rls_denial_stops_before_child_write(self) -> None:
        transport = FakeTransport()
        transport.write_status["tasks"] = 403
        repository = self.make_repository(transport)
        with self.assertRaises(AgentError) as caught:
            repository.create_and_verify(
                self.draft(),
                task_id="10000000-0000-0000-0000-000000000001",
                now=datetime(2026, 11, 11, 4, 0, tzinfo=timezone.utc),
            )
        self.assertEqual(caught.exception.code, "RLS_DENIED")
        self.assertNotIn("one_time_reminders", transport.rows)

    def test_write_error_keeps_only_safe_postgrest_code_and_status(self) -> None:
        repository = self.make_repository(FakeTransport())
        body = json.dumps({"code":"42703", "message":"column missing; secret task text"}).encode()
        with self.assertRaises(AgentError) as caught:
            repository._require_write_success(HttpResponse(400, body), "tasks")
        self.assertEqual(caught.exception.code, "REMOTE_WRITE_FAILED")
        self.assertEqual(caught.exception.details, {
            "table":"tasks", "http_status":400, "postgrest_code":"42703"})
        self.assertNotIn("secret", json.dumps(caught.exception.to_dict()))

    def test_token_expiry_during_child_write_never_reports_success(self) -> None:
        transport = FakeTransport()
        transport.write_status["one_time_reminders"] = 401
        repository = self.make_repository(transport)
        with self.assertRaises(AgentError) as caught:
            repository.create_and_verify(
                self.draft(),
                task_id="10000000-0000-0000-0000-000000000001",
                now=datetime(2026, 11, 11, 4, 0, tzinfo=timezone.utc),
            )
        self.assertEqual(caught.exception.code, "AUTH_EXPIRED")
        self.assertTrue(caught.exception.retryable)
        self.assertIn("tasks", transport.rows)
        self.assertNotIn("one_time_reminders", transport.rows)

    def test_readback_mismatch_does_not_report_success(self) -> None:
        transport = FakeTransport()
        transport.mutate_readback = True
        repository = self.make_repository(transport)
        with self.assertRaises(AgentError) as caught:
            repository.create_and_verify(
                self.draft(),
                task_id="10000000-0000-0000-0000-000000000001",
                now=datetime(2026, 11, 11, 4, 0, tzinfo=timezone.utc),
            )
        self.assertEqual(caught.exception.code, "READBACK_MISMATCH")

    def test_network_failure_is_safe_and_retryable(self) -> None:
        with patch(
            "urllib.request.urlopen",
            side_effect=urllib.error.URLError("connection refused"),
        ):
            with self.assertRaises(AgentError) as caught:
                UrllibTransport().request(
                    "GET",
                    "https://example.supabase.co/auth/v1/user",
                    headers={},
                )
        self.assertEqual(caught.exception.code, "NETWORK_ERROR")
        self.assertTrue(caught.exception.retryable)


if __name__ == "__main__":
    unittest.main()
