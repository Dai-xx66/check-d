from __future__ import annotations

import unittest
from datetime import datetime
from zoneinfo import ZoneInfo

from checkd_task_agent.models import AgentError
from checkd_task_agent.timeparse import resolve_deadline


class ResolveDeadlineTest(unittest.TestCase):
    def setUp(self) -> None:
        self.now = datetime(2026, 11, 11, 12, 0, tzinfo=ZoneInfo("Asia/Shanghai"))

    def test_resolves_tomorrow_evening_eight(self) -> None:
        result = resolve_deadline("明天晚上八点", now=self.now)
        self.assertEqual(result["deadline_at"], "2026-11-12T20:00:00+08:00")

    def test_resolves_day_after_tomorrow_date_only(self) -> None:
        result = resolve_deadline("后天", now=self.now)
        self.assertEqual(result["deadline_date"], "2026-11-13")

    def test_resolves_across_year_boundary(self) -> None:
        now = datetime(2026, 12, 31, 23, 0, tzinfo=ZoneInfo("Asia/Shanghai"))
        result = resolve_deadline("明天 09:30", now=now)
        self.assertEqual(result["deadline_at"], "2027-01-01T09:30:00+08:00")

    def test_rejects_ambiguous_time_without_date(self) -> None:
        with self.assertRaises(AgentError) as caught:
            resolve_deadline("晚上八点", now=self.now)
        self.assertEqual(caught.exception.code, "AMBIGUOUS_DEADLINE")

    def test_exact_iso_time_requires_offset(self) -> None:
        with self.assertRaises(AgentError) as caught:
            resolve_deadline("2026-11-12T20:00:00", now=self.now)
        self.assertEqual(caught.exception.code, "TIMEZONE_REQUIRED")


if __name__ == "__main__":
    unittest.main()
