from __future__ import annotations

import base64
import json
import unittest
import urllib.parse
from datetime import datetime, timezone

from checkd_task_agent.models import AgentError
from checkd_task_agent.supabase import HttpResponse, SupabaseTaskRepository


USER_ID = "00000000-0000-0000-0000-000000000001"
TASK_A = "10000000-0000-0000-0000-000000000001"
TASK_B = "10000000-0000-0000-0000-000000000002"


def jwt(role: str = "authenticated") -> str:
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")

    return f"{encode({'alg': 'none'})}.{encode({'role': role})}.signature"


def row(
    *,
    task_id: str = TASK_A,
    name: str = "实验报告",
    completed_at: str | None = None,
    has_scheduled_date: bool = True,
    scheduled_at: str = "2026-11-12T02:00:00Z",
    planned_date: str | None = "2026-11-12",
    due_date: str | None = None,
    due_at: str | None = "2026-11-12T12:00:00Z",
    task_type: str = "one_time",
) -> dict[str, object]:
    return {
        "task_id": task_id,
        "user_id": USER_ID,
        "scheduled_at": scheduled_at,
        "has_scheduled_date": has_scheduled_date,
        "available_from": None,
        "planned_date": planned_date,
        "due_date": due_date,
        "due_at": due_at,
        "remind_before_minutes": None,
        "is_timed": False,
        "completed_at": completed_at,
        "created_at": "2026-11-10T00:00:00Z",
        "updated_at": "2026-11-11T00:00:00Z",
        "tasks": {
            "id": task_id,
            "user_id": USER_ID,
            "name": name,
            "type": task_type,
            "color": 4293301573,
            "icon_name": "event",
            "notes": "private note",
            "status": "active",
            "created_at": "2026-11-10T00:00:00Z",
            "updated_at": "2026-11-11T00:00:00Z",
            "deleted_at": None,
        },
    }


class QueryTransport:
    def __init__(self) -> None:
        self.rows: list[dict[str, object]] = []
        self.reminder_rules: list[dict[str, object]] = []
        self.requests: list[tuple[str, str, dict[str, str]]] = []
        self.auth_status = 200
        self.table_status = 200
        self.network_error = False

    def request(self, method, url, *, headers, body=None, timeout=15):
        self.requests.append((method, url, headers))
        path = urllib.parse.urlsplit(url).path
        if path == "/auth/v1/user":
            return HttpResponse(self.auth_status, json.dumps({"id": USER_ID}).encode())
        if method != "GET":
            raise AssertionError("read query attempted a write")
        if self.network_error:
            raise AgentError("NETWORK_ERROR", "simulated network failure", retryable=True)
        if self.table_status != 200:
            return HttpResponse(self.table_status, b"")
        table = path.rsplit("/", 1)[-1]
        payload = self.reminder_rules if table == "reminder_rules" else self.rows
        return HttpResponse(200, json.dumps(payload).encode())


class QueryRepositoryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.transport = QueryTransport()
        self.repository = SupabaseTaskRepository(
            url="https://example.supabase.co",
            publishable_key="public-key",
            user_access_token=jwt(),
            transport=self.transport,
        )

    def params(self, index: int = -1) -> dict[str, list[str]]:
        return urllib.parse.parse_qs(urllib.parse.urlsplit(self.transport.requests[index][1]).query)

    def test_empty_list_uses_verified_user_filters_and_performs_only_gets(self) -> None:
        page = self.repository.list_one_time_tasks(include_completed=False, limit=20, offset=0)

        self.assertEqual(page.items, [])
        self.assertIsNone(page.next_offset)
        self.assertEqual([method for method, _, _ in self.transport.requests], ["GET", "GET"])
        params = self.params()
        self.assertEqual(params["user_id"], [f"eq.{USER_ID}"])
        self.assertEqual(params["tasks.user_id"], [f"eq.{USER_ID}"])
        self.assertEqual(params["tasks.type"], ["eq.one_time"])
        self.assertEqual(params["tasks.deleted_at"], ["is.null"])
        self.assertEqual(params["completed_at"], ["is.null"])
        self.assertEqual(params["limit"], ["21"])

    def test_multiple_same_name_rows_are_preserved_and_paginated(self) -> None:
        self.transport.rows = [row(task_id=TASK_A), row(task_id=TASK_B)]
        page = self.repository.list_one_time_tasks(include_completed=False, limit=1, offset=4)

        self.assertEqual([item["id"] for item in page.items], [TASK_A])
        self.assertEqual(page.next_offset, 5)

    def test_completed_and_recurring_rows_are_never_returned_by_default(self) -> None:
        self.transport.rows = [
            row(task_id=TASK_A, completed_at="2026-11-11T01:00:00Z"),
            row(task_id=TASK_B, task_type="long_term"),
        ]
        page = self.repository.list_one_time_tasks(include_completed=False, limit=20, offset=0)
        self.assertEqual(page.items, [])

    def test_calendar_date_uses_scheduled_instant_or_planned_date_not_deadline(self) -> None:
        scheduled = row(task_id=TASK_A, due_date="2026-11-12", due_at=None)
        unscheduled = row(
            task_id=TASK_B,
            has_scheduled_date=False,
            planned_date="2026-11-12",
            due_date="2026-10-01",
            due_at=None,
        )
        deadline_only = row(
            task_id="10000000-0000-0000-0000-000000000003",
            has_scheduled_date=False,
            planned_date=None,
            due_date="2026-11-12",
            due_at=None,
        )
        self.transport.rows = [scheduled, unscheduled, deadline_only]

        page = self.repository.list_one_time_tasks_by_date(
            "2026-11-12", include_completed=True, limit=20, offset=0
        )
        self.assertEqual([item["id"] for item in page.items], [TASK_A, TASK_B])
        params = self.params()
        self.assertIn("scheduled_at.gte.2026-11-11T16:00:00+00:00", params["or"][0])
        self.assertNotIn("due_date", params["or"][0])
        self.assertIsNone(page.items[1]["planned_at"])

    def test_overdue_matches_date_and_exact_deadline_semantics(self) -> None:
        self.transport.rows = [
            row(task_id=TASK_A, due_date="2026-11-10", due_at=None),
            row(task_id=TASK_B, due_date=None, due_at="2026-11-11T03:59:00Z"),
            row(task_id="10000000-0000-0000-0000-000000000003", due_date="2026-11-12", due_at=None),
            row(task_id="10000000-0000-0000-0000-000000000004", due_date=None, due_at="2026-11-11T04:00:00Z"),
        ]
        page = self.repository.list_overdue_one_time_tasks(
            now=datetime(2026, 11, 11, 4, 0, tzinfo=timezone.utc), limit=20, offset=0
        )
        self.assertEqual([item["id"] for item in page.items], [TASK_A, TASK_B])

    def test_search_escapes_like_special_characters(self) -> None:
        self.transport.rows = [row(name="100%_\\* 完成")]
        self.repository.search_one_time_tasks(
            "100%_\\*", include_completed=False, limit=20, offset=0
        )
        self.assertEqual(self.params()["tasks.name"], [r"ilike.*100\%\_\\\**"])

    def test_detail_normalizes_times_and_returns_only_owned_one_time_task(self) -> None:
        self.transport.rows = [row(due_date="2026-11-13", due_at=None)]
        self.transport.reminder_rules = [
            {
                "id": "20000000-0000-0000-0000-000000000001",
                "reminder_kind": "advance",
                "enabled": True,
                "scheduled_minute_of_day": None,
                "remind_before_minutes": 30,
                "local_date": "2026-11-12",
                "timezone": "Asia/Shanghai",
                "updated_at": "2026-11-11T00:00:00Z",
            }
        ]
        detail = self.repository.get_one_time_task_detail(TASK_A)
        self.assertEqual(detail["task_type"], "one_time")
        self.assertEqual(detail["planned_at"], "2026-11-12T10:00:00+08:00")
        self.assertEqual(detail["deadline_date"], "2026-11-13")
        self.assertIsNone(detail["deadline_at"])
        self.assertEqual(detail["reminder_rules"][0]["reminder_kind"], "advance")
        self.assertNotIn("user_id", detail)

    def test_not_found_and_other_user_are_indistinguishable(self) -> None:
        for rows in ([], [row()]):
            self.transport.rows = rows
            if rows:
                rows[0]["user_id"] = "00000000-0000-0000-0000-000000000099"
            with self.subTest(rows=bool(rows)), self.assertRaises(AgentError) as caught:
                self.repository.get_one_time_task_detail(TASK_A)
            self.assertEqual(caught.exception.code, "NOT_FOUND")

    def test_auth_expiry_and_rls_read_errors_are_safe(self) -> None:
        self.transport.auth_status = 401
        with self.assertRaises(AgentError) as caught:
            self.repository.list_one_time_tasks(include_completed=False, limit=20, offset=0)
        self.assertEqual(caught.exception.code, "AUTH_EXPIRED")

        self.transport.auth_status = 200
        self.repository._user_id = None
        self.transport.table_status = 403
        with self.assertRaises(AgentError) as caught:
            self.repository.list_one_time_tasks(include_completed=False, limit=20, offset=0)
        self.assertEqual(caught.exception.code, "RLS_DENIED")

    def test_network_error_is_propagated_without_fallback_data(self) -> None:
        self.transport.network_error = True
        with self.assertRaises(AgentError) as caught:
            self.repository.list_one_time_tasks(include_completed=False, limit=20, offset=0)
        self.assertEqual(caught.exception.code, "NETWORK_ERROR")
        self.assertTrue(caught.exception.retryable)

    def test_http_client_errors_are_not_misreported_as_network_errors(self) -> None:
        for status in (400, 404):
            with self.subTest(status=status):
                self.repository._user_id = USER_ID
                self.transport.table_status = status
                with self.assertRaises(AgentError) as caught:
                    self.repository.list_one_time_tasks(
                        include_completed=False, limit=20, offset=0
                    )
                self.assertEqual(caught.exception.code, "REMOTE_READ_FAILED")


if __name__ == "__main__":
    unittest.main()
