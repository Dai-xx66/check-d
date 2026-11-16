from __future__ import annotations

import unittest
from datetime import datetime, timezone

from checkd_task_agent.models import AgentError
from checkd_task_agent.query_service import QueryPage, TaskQueryService


class FakeQueryRepository:
    def __init__(self) -> None:
        self.calls: list[tuple[str, dict[str, object]]] = []
        self.page = QueryPage(items=[{"id": "task-1", "task_type": "one_time"}], next_offset=None)
        self.detail: dict[str, object] = {"id": "task-1", "task_type": "one_time"}

    def list_one_time_tasks(self, **kwargs):
        self.calls.append(("list", kwargs))
        return self.page

    def search_one_time_tasks(self, query: str, **kwargs):
        self.calls.append(("search", {"query": query, **kwargs}))
        return self.page

    def list_overdue_one_time_tasks(self, *, now: datetime, **kwargs):
        self.calls.append(("overdue", {"now": now, **kwargs}))
        return self.page

    def list_one_time_tasks_by_date(self, day: str, **kwargs):
        self.calls.append(("date", {"day": day, **kwargs}))
        return self.page

    def get_one_time_task_detail(self, task_id: str):
        self.calls.append(("detail", {"task_id": task_id}))
        return self.detail


class TaskQueryServiceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.repository = FakeQueryRepository()
        self.now = datetime(2026, 11, 12, 4, 0, tzinfo=timezone.utc)
        self.service = TaskQueryService(self.repository, clock=lambda: self.now)

    def test_list_defaults_to_pending_one_time_and_bounded_pagination(self) -> None:
        result = self.service.list_tasks()

        self.assertTrue(result["ok"])
        self.assertEqual(result["coverage"], {"task_types": ["one_time"], "recurring_included": False})
        self.assertEqual(result["pagination"], {"limit": 20, "offset": 0, "next_offset": None})
        self.assertEqual(self.repository.calls, [("list", {"include_completed": False, "limit": 20, "offset": 0})])

    def test_page_bounds_are_validated_before_repository_access(self) -> None:
        for arguments in ({"limit": 0}, {"limit": 51}, {"offset": -1}, {"offset": 10001}):
            with self.subTest(arguments=arguments), self.assertRaises(AgentError) as caught:
                self.service.list_tasks(**arguments)
            self.assertEqual(caught.exception.code, "INVALID_PAGINATION")
        self.assertEqual(self.repository.calls, [])

    def test_search_requires_a_meaningful_query_and_keeps_same_task_names(self) -> None:
        with self.assertRaises(AgentError) as caught:
            self.service.search_tasks(query="   ")
        self.assertEqual(caught.exception.code, "QUERY_REQUIRED")

        self.repository.page = QueryPage(
            items=[{"id": "a", "name": "实验报告"}, {"id": "b", "name": "实验报告"}],
            next_offset=2,
        )
        result = self.service.search_tasks(query="实验报告", limit=2)
        self.assertEqual([item["id"] for item in result["items"]], ["a", "b"])
        self.assertEqual(result["pagination"]["next_offset"], 2)
        self.assertEqual(self.repository.calls[-1], ("search", {"query": "实验报告", "include_completed": False, "limit": 2, "offset": 0}))

    def test_calendar_date_accepts_date_only_and_does_not_supply_a_deadline(self) -> None:
        result = self.service.get_tasks_by_date(date="2026-11-12")
        self.assertEqual(result["date"], "2026-11-12")
        self.assertEqual(result["view"], "calendar")
        self.assertEqual(self.repository.calls[-1], ("date", {"day": "2026-11-12", "include_completed": True, "limit": 20, "offset": 0}))
        with self.assertRaises(AgentError) as caught:
            self.service.get_tasks_by_date(date="2026-11-12T20:00:00+08:00")
        self.assertEqual(caught.exception.code, "INVALID_DATE")

    def test_overdue_passes_an_aware_clock_to_repository(self) -> None:
        self.service.list_overdue_tasks(limit=5, offset=10)
        method, arguments = self.repository.calls[-1]
        self.assertEqual(method, "overdue")
        self.assertEqual(arguments["now"], self.now)
        self.assertEqual(arguments["limit"], 5)
        self.assertEqual(arguments["offset"], 10)

    def test_detail_requires_uuid_and_returns_one_time_coverage(self) -> None:
        with self.assertRaises(AgentError) as caught:
            self.service.get_task_detail(task_id="not-a-uuid")
        self.assertEqual(caught.exception.code, "INVALID_TASK_ID")

        result = self.service.get_task_detail(task_id="10000000-0000-0000-0000-000000000001")
        self.assertEqual(result["item"]["id"], "task-1")
        self.assertFalse(result["coverage"]["recurring_included"])


if __name__ == "__main__":
    unittest.main()
