from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from checkd_task_agent.ledger import ConfirmationLedger
from checkd_task_agent.models import AgentError, TaskDraft
from checkd_task_agent.service import TaskCreationService


NOW = datetime(2026, 11, 11, 4, 0, tzinfo=timezone.utc)


class FakeRepository:
    def __init__(self) -> None:
        self.calls: list[str] = []
        self.fail_once: AgentError | None = None

    def authenticated_user_id(self) -> str:
        return "00000000-0000-0000-0000-000000000001"

    def create_and_verify(self, draft, *, task_id: str, now: datetime):
        self.calls.append(task_id)
        if self.fail_once is not None:
            error = self.fail_once
            self.fail_once = None
            raise error
        return {
            "id": task_id,
            "name": draft.name,
            "deadline_at": draft.deadline_at,
        }


class TaskCreationServiceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repository = FakeRepository()
        self.now = NOW
        self.service = TaskCreationService(
            ConfirmationLedger(Path(self.temp.name) / "state.sqlite3"),
            self.repository,
            clock=lambda: self.now,
            confirmation_ttl=timedelta(minutes=10),
        )
        self.draft = TaskDraft(
            name="学习 Python",
            expected_duration_minutes=60,
            deadline_at="2026-11-12T20:00:00+08:00",
        )

    def prepare(self, key: str = "conversation-1") -> dict[str, object]:
        return self.service.prepare_task_creation(self.draft, idempotency_key=key)

    def test_missing_explicit_confirmation_performs_zero_writes(self) -> None:
        prepared = self.prepare()
        with self.assertRaises(AgentError) as caught:
            self.service.create_task(
                confirmation_id=str(prepared["confirmation_id"]),
                user_confirmation_text="确认",
            )
        self.assertEqual(caught.exception.code, "EXPLICIT_CONFIRMATION_REQUIRED")
        self.assertEqual(self.repository.calls, [])

    def test_confirmed_task_is_created_and_read_back_once(self) -> None:
        prepared = self.prepare()
        result = self.service.create_task(
            confirmation_id=str(prepared["confirmation_id"]),
            user_confirmation_text=str(prepared["confirmation_phrase"]),
        )
        replay = self.service.create_task(
            confirmation_id=str(prepared["confirmation_id"]),
            user_confirmation_text=str(prepared["confirmation_phrase"]),
        )
        self.assertTrue(result["readback_verified"])
        self.assertEqual(result, replay)
        self.assertEqual(len(self.repository.calls), 1)

    def test_prepare_is_idempotent_and_conflicting_payload_is_rejected(self) -> None:
        first = self.prepare()
        second = self.prepare()
        self.assertEqual(first["confirmation_id"], second["confirmation_id"])
        with self.assertRaises(AgentError) as caught:
            self.service.prepare_task_creation(
                TaskDraft(
                    name="不同的任务",
                    expected_duration_minutes=60,
                    deadline_date="2026-11-12",
                ),
                idempotency_key="conversation-1",
            )
        self.assertEqual(caught.exception.code, "IDEMPOTENCY_CONFLICT")

    def test_cancelled_task_never_writes(self) -> None:
        prepared = self.prepare()
        cancelled = self.service.cancel_task_creation(
            confirmation_id=str(prepared["confirmation_id"])
        )
        self.assertEqual(cancelled["status"], "cancelled")
        with self.assertRaises(AgentError) as caught:
            self.service.create_task(
                confirmation_id=str(prepared["confirmation_id"]),
                user_confirmation_text=str(prepared["confirmation_phrase"]),
            )
        self.assertEqual(caught.exception.code, "CONFIRMATION_CANCELLED")
        self.assertEqual(self.repository.calls, [])

    def test_expired_confirmation_never_writes(self) -> None:
        prepared = self.prepare()
        self.now += timedelta(minutes=10)
        with self.assertRaises(AgentError) as caught:
            self.service.create_task(
                confirmation_id=str(prepared["confirmation_id"]),
                user_confirmation_text=str(prepared["confirmation_phrase"]),
            )
        self.assertEqual(caught.exception.code, "CONFIRMATION_EXPIRED")
        self.assertEqual(self.repository.calls, [])

    def test_retryable_network_failure_reuses_the_same_task_id(self) -> None:
        self.repository.fail_once = AgentError(
            "NETWORK_ERROR", "network unavailable", retryable=True
        )
        prepared = self.prepare()
        with self.assertRaises(AgentError):
            self.service.create_task(
                confirmation_id=str(prepared["confirmation_id"]),
                user_confirmation_text=str(prepared["confirmation_phrase"]),
            )
        result = self.service.create_task(
            confirmation_id=str(prepared["confirmation_id"]),
            user_confirmation_text=str(prepared["confirmation_phrase"]),
        )
        self.assertTrue(result["readback_verified"])
        self.assertEqual(len(self.repository.calls), 2)
        self.assertEqual(self.repository.calls[0], self.repository.calls[1])

    def test_expired_auth_is_safe_and_retryable(self) -> None:
        self.repository.fail_once = AgentError(
            "AUTH_EXPIRED", "expired", retryable=True
        )
        prepared = self.prepare()
        with self.assertRaises(AgentError) as caught:
            self.service.create_task(
                confirmation_id=str(prepared["confirmation_id"]),
                user_confirmation_text=str(prepared["confirmation_phrase"]),
            )
        self.assertEqual(caught.exception.code, "AUTH_EXPIRED")

    def test_completed_result_survives_service_restart_without_another_write(self) -> None:
        prepared = self.prepare()
        first = self.service.create_task(
            confirmation_id=str(prepared["confirmation_id"]),
            user_confirmation_text=str(prepared["confirmation_phrase"]),
        )
        restarted_repository = FakeRepository()
        restarted = TaskCreationService(
            ConfirmationLedger(Path(self.temp.name) / "state.sqlite3"),
            restarted_repository,
            clock=lambda: self.now,
        )
        replay = restarted.create_task(
            confirmation_id=str(prepared["confirmation_id"]),
            user_confirmation_text=str(prepared["confirmation_phrase"]),
        )
        self.assertEqual(first, replay)
        self.assertEqual(restarted_repository.calls, [])

    def test_stale_creating_lease_can_be_reclaimed_after_restart(self) -> None:
        prepared = self.prepare()
        ledger = ConfirmationLedger(Path(self.temp.name) / "state.sqlite3")
        ledger.claim(
            str(prepared["confirmation_id"]),
            str(prepared["confirmation_phrase"]),
            now=self.now,
            lease_owner="crashed-process",
            lease_ttl=timedelta(seconds=30),
        )
        restarted_repository = FakeRepository()
        restarted = TaskCreationService(
            ledger,
            restarted_repository,
            clock=lambda: self.now,
            creation_lease_ttl=timedelta(seconds=30),
            instance_id="new-process",
        )
        with self.assertRaises(AgentError) as caught:
            restarted.create_task(
                confirmation_id=str(prepared["confirmation_id"]),
                user_confirmation_text=str(prepared["confirmation_phrase"]),
            )
        self.assertEqual(caught.exception.code, "IDEMPOTENCY_IN_PROGRESS")
        self.now += timedelta(seconds=31)
        result = restarted.create_task(
            confirmation_id=str(prepared["confirmation_id"]),
            user_confirmation_text=str(prepared["confirmation_phrase"]),
        )
        self.assertTrue(result["readback_verified"])
        self.assertEqual(len(restarted_repository.calls), 1)


if __name__ == "__main__":
    unittest.main()
