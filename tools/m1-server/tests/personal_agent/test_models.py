from __future__ import annotations

import unittest

from checkd_task_agent.models import AgentError, TaskDraft


class TaskDraftTest(unittest.TestCase):
    def test_valid_date_only_draft_is_normalized(self) -> None:
        draft = TaskDraft(
            name="  学习 Python  ",
            expected_duration_minutes=60,
            deadline_date="2026-11-12",
        ).validated()

        self.assertEqual(draft.name, "学习 Python")
        self.assertEqual(draft.deadline_date, "2026-11-12")
        self.assertIsNone(draft.deadline_at)

    def test_exact_deadline_requires_offset(self) -> None:
        with self.assertRaises(AgentError) as caught:
            TaskDraft(
                name="学习 Python",
                expected_duration_minutes=60,
                deadline_at="2026-11-12T20:00:00",
            ).validated()
        self.assertEqual(caught.exception.code, "TIMEZONE_REQUIRED")

    def test_rejects_both_deadline_shapes(self) -> None:
        with self.assertRaises(AgentError) as caught:
            TaskDraft(
                name="学习 Python",
                expected_duration_minutes=60,
                deadline_date="2026-11-12",
                deadline_at="2026-11-12T20:00:00+08:00",
            ).validated()
        self.assertEqual(caught.exception.code, "DEADLINE_SHAPE_INVALID")

    def test_rejects_invalid_duration_and_blank_name(self) -> None:
        for draft, code in (
            (TaskDraft(name=" ", expected_duration_minutes=60, deadline_date="2026-11-12"), "NAME_REQUIRED"),
            (TaskDraft(name="x", expected_duration_minutes=0, deadline_date="2026-11-12"), "INVALID_DURATION"),
            (TaskDraft(name="x", expected_duration_minutes=True, deadline_date="2026-11-12"), "INVALID_DURATION"),
        ):
            with self.subTest(code=code), self.assertRaises(AgentError) as caught:
                draft.validated()
            self.assertEqual(caught.exception.code, code)

    def test_rejects_plan_after_exact_deadline(self) -> None:
        with self.assertRaises(AgentError) as caught:
            TaskDraft(
                name="x",
                expected_duration_minutes=60,
                deadline_at="2026-11-12T20:00:00+08:00",
                planned_at="2026-11-12T21:00:00+08:00",
            ).validated()
        self.assertEqual(caught.exception.code, "PLANNED_AFTER_DEADLINE")

    def test_estimated_duration_is_labelled_as_notes_only(self) -> None:
        draft = TaskDraft(
            name="x",
            expected_duration_minutes=60,
            deadline_date="2026-11-12",
            notes="课程作业",
        )
        self.assertIn("课程作业", draft.persisted_notes())
        self.assertIn("非 CheckD 结构化时长目标", draft.persisted_notes())
        self.assertIn("60 分钟", draft.persisted_notes())


if __name__ == "__main__":
    unittest.main()
