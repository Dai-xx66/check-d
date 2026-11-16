from __future__ import annotations

import uuid
from collections.abc import Callable
from datetime import datetime, timedelta, timezone
from typing import Protocol

from .ledger import ConfirmationLedger
from .models import AgentError, TaskDraft


class TaskRepository(Protocol):
    def authenticated_user_id(self) -> str: ...

    def create_and_verify(
        self,
        draft: TaskDraft,
        *,
        task_id: str,
        now: datetime,
    ) -> dict[str, object]: ...


class TaskCreationService:
    def __init__(
        self,
        ledger: ConfirmationLedger,
        repository: TaskRepository,
        *,
        clock: Callable[[], datetime] | None = None,
        confirmation_ttl: timedelta = timedelta(minutes=10),
        creation_lease_ttl: timedelta = timedelta(minutes=2),
        instance_id: str | None = None,
    ) -> None:
        self._ledger = ledger
        self._repository = repository
        self._clock = clock or (lambda: datetime.now(timezone.utc))
        self._confirmation_ttl = confirmation_ttl
        self._creation_lease_ttl = creation_lease_ttl
        self._instance_id = instance_id or str(uuid.uuid4())

    def prepare_task_creation(
        self,
        draft: TaskDraft,
        *,
        idempotency_key: str,
    ) -> dict[str, object]:
        now = self._now()
        record = self._ledger.prepare(
            draft,
            idempotency_key,
            now=now,
            ttl=self._confirmation_ttl,
        )
        if record.status == "completed" and record.result is not None:
            return record.result
        return {
            "ok": True,
            "status": record.status,
            "confirmation_id": record.confirmation_id,
            "summary": record.draft.summary(),
            "confirmation_phrase": record.confirmation_phrase,
            "expires_at": record.expires_at.isoformat(),
            "duration_storage": "notes_only",
            "write_performed": False,
        }

    def create_task(
        self,
        *,
        confirmation_id: str,
        user_confirmation_text: str,
    ) -> dict[str, object]:
        now = self._now()
        record = self._ledger.claim(
            confirmation_id,
            user_confirmation_text,
            now=now,
            lease_owner=self._instance_id,
            lease_ttl=self._creation_lease_ttl,
        )
        if record.status == "completed" and record.result is not None:
            return record.result
        try:
            user_id = self._repository.authenticated_user_id()
            task_id = record.task_id or str(
                uuid.uuid5(
                    uuid.NAMESPACE_URL,
                    f"checkd-task-agent:{user_id}:{record.idempotency_key}",
                )
            )
            self._ledger.assign_task_id(
                record.confirmation_id,
                task_id,
                now=now,
                lease_owner=self._instance_id,
            )
            verified = self._repository.create_and_verify(
                record.draft,
                task_id=task_id,
                now=now,
            )
            result: dict[str, object] = {
                "ok": True,
                "status": "created",
                "task_id": task_id,
                "readback_verified": True,
                "task": verified,
                "duration_storage": "notes_only",
            }
            return self._ledger.complete(
                record.confirmation_id,
                result,
                now=self._now(),
                lease_owner=self._instance_id,
            ).result or result
        except AgentError as error:
            self._ledger.fail(
                record.confirmation_id,
                error,
                now=self._now(),
                lease_owner=self._instance_id,
            )
            raise
        except Exception as error:
            safe = AgentError(
                "INTERNAL_ERROR",
                "创建任务时发生未预期错误。",
                retryable=True,
            )
            self._ledger.fail(
                record.confirmation_id,
                safe,
                now=self._now(),
                lease_owner=self._instance_id,
            )
            raise safe from error

    def cancel_task_creation(self, *, confirmation_id: str) -> dict[str, object]:
        record = self._ledger.cancel(confirmation_id, now=self._now())
        return {
            "ok": True,
            "status": record.status,
            "confirmation_id": record.confirmation_id,
            "write_performed": False,
        }

    def _now(self) -> datetime:
        value = self._clock()
        if value.tzinfo is None or value.utcoffset() is None:
            raise RuntimeError("clock must return an offset-aware datetime")
        return value.astimezone(timezone.utc)
