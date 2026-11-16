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

    def request(self, method, url, *, headers, body=None, timeout=15):
        self.requests.append((method, url))
        path = urllib.parse.urlsplit(url).path
        if path == "/auth/v1/user":
            return HttpResponse(self.auth_status, json.dumps({"id": USER_ID}).encode())
        table = path.rsplit("/", 1)[-1]
        if method == "POST":
            status = self.write_status.get(table, 201)
            if 200 <= status < 300:
                self.rows[table] = json.loads(body)
            return HttpResponse(status, b"")
        if method == "GET":
            row = dict(self.rows.get(table, {}))
            if self.mutate_readback and table == "tasks":
                row["name"] = "unexpected"
            return HttpResponse(200, json.dumps([row]).encode())
        raise AssertionError((method, url))


class SupabaseTaskRepositoryTest(unittest.TestCase):
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

    def test_normal_user_upserts_parent_and_child_then_reads_back(self) -> None:
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
        self.assertEqual([method for method, _ in transport.requests].count("GET"), 3)

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
