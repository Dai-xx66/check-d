from __future__ import annotations

import hashlib
import json
import uuid
from collections.abc import Callable
from datetime import datetime, timedelta, timezone
from typing import Protocol

from .ledger import ConfirmationLedger, UpdateConfirmationRecord
from .models import AgentError, DEFAULT_TIMEZONE, _parse_date, _parse_instant


EDITABLE_FIELDS = frozenset(
    {"name", "planned_at", "planned_date", "deadline_at", "deadline_date", "notes"}
)
_SNAPSHOT_KEYS = (
    "id",
    "name",
    "task_type",
    "lifecycle_status",
    "completion_status",
    "deleted_at",
    "notes",
    "scheduled_at",
    "has_scheduled_date",
    "planned_at",
    "planned_date",
    "deadline_date",
    "deadline_at",
    "task_updated_at",
    "reminder_updated_at",
)


class TaskUpdateRepository(Protocol):
    def authenticated_user_id(self) -> str: ...

    def get_one_time_task_snapshot(self, task_id: str) -> dict[str, object]: ...

    def update_one_time_task(
        self,
        original_snapshot: dict[str, object],
        target_snapshot: dict[str, object],
        *,
        write_receipts: dict[str, str] | None = None,
        record_write: Callable[[str, str], None] | None = None,
    ) -> dict[str, object]: ...


class TaskUpdateService:
    def __init__(
        self,
        ledger: ConfirmationLedger,
        repository: TaskUpdateRepository,
        *,
        clock: Callable[[], datetime] | None = None,
        confirmation_ttl: timedelta = timedelta(minutes=10),
        update_lease_ttl: timedelta = timedelta(minutes=2),
        instance_id: str | None = None,
    ) -> None:
        self._ledger = ledger
        self._repository = repository
        self._clock = clock or (lambda: datetime.now(timezone.utc))
        self._confirmation_ttl = confirmation_ttl
        self._update_lease_ttl = update_lease_ttl
        self._instance_id = instance_id or str(uuid.uuid4())

    def prepare_task_update(
        self,
        *,
        task_id: str,
        changes: dict[str, object],
        idempotency_key: str,
    ) -> dict[str, object]:
        task_id = _require_uuid(task_id)
        normalized_changes = _validate_changes(changes)
        existing = self._ledger.find_prepared_update(idempotency_key, task_id, normalized_changes)
        if existing is not None:
            self._repository.authenticated_user_id()
            return self._prepared_response(existing)
        original = self._repository.get_one_time_task_snapshot(task_id)
        _assert_editable(original)
        target = _apply_changes(original, normalized_changes)
        changed_fields = _changed_fields(original, target)
        if not changed_fields:
            raise AgentError("NO_CHANGES", "没有检测到需要修改的字段。")
        digest = _digest(task_id, normalized_changes, original)
        now = self._now()
        record = self._ledger.prepare_update(
            task_id=task_id,
            changes=normalized_changes,
            original_snapshot=original,
            digest=digest,
            idempotency_key=idempotency_key,
            now=now,
            ttl=self._confirmation_ttl,
        )
        return self._prepared_response(record)

    def _prepared_response(self, record: UpdateConfirmationRecord) -> dict[str, object]:
        if record.status == "completed" and record.result is not None:
            return record.result
        original = record.original_snapshot
        target = _apply_changes(original, record.changes)
        return {
            "ok": True,
            "status": record.status,
            "update_confirmation_id": record.confirmation_id,
            "task_id": record.task_id,
            "original": _public_snapshot(original),
            "updated": _public_snapshot(target),
            "changed_fields": _changed_fields(original, target),
            "confirmation_phrase": record.confirmation_phrase,
            "expires_at": record.expires_at.isoformat(),
            "write_performed": False,
        }

    def update_task(
        self,
        *,
        update_confirmation_id: str,
        user_confirmation_text: str,
    ) -> dict[str, object]:
        now = self._now()
        lease_owner = f"{self._instance_id}:{uuid.uuid4()}"
        record = self._ledger.claim_update(
            update_confirmation_id,
            user_confirmation_text,
            now=now,
            lease_owner=lease_owner,
            lease_ttl=self._update_lease_ttl,
        )
        if record.status == "completed" and record.result is not None:
            self._repository.authenticated_user_id()
            return record.result

        def record_write(component: str, version: str) -> None:
            self._ledger.record_update_write(
                record.confirmation_id,
                component,
                version,
                now=self._now(),
                lease_owner=lease_owner,
            )

        try:
            target = _apply_changes(record.original_snapshot, record.changes)
            verified = self._repository.update_one_time_task(
                record.original_snapshot,
                target,
                write_receipts=self._ledger.update_write_receipts(record.confirmation_id),
                record_write=record_write,
            )
            result = {
                "ok": True,
                "status": "updated",
                "update_confirmation_id": record.confirmation_id,
                "task_id": record.task_id,
                "readback_verified": True,
                "task": verified,
            }
            return self._ledger.complete_update(
                record.confirmation_id,
                result,
                now=self._now(),
                lease_owner=lease_owner,
            ).result or result
        except AgentError as error:
            self._ledger.fail_update(
                record.confirmation_id,
                error,
                now=self._now(),
                lease_owner=lease_owner,
            )
            raise
        except Exception as error:
            safe = AgentError("INTERNAL_ERROR", "修改任务时发生未预期错误。", retryable=True)
            self._ledger.fail_update(
                record.confirmation_id,
                safe,
                now=self._now(),
                lease_owner=lease_owner,
            )
            raise safe from error

    def cancel_task_update(self, *, update_confirmation_id: str) -> dict[str, object]:
        record = self._ledger.cancel_update(update_confirmation_id, now=self._now())
        return {
            "ok": True,
            "status": record.status,
            "update_confirmation_id": record.confirmation_id,
            "write_performed": False,
        }

    def _now(self) -> datetime:
        value = self._clock()
        if value.tzinfo is None or value.utcoffset() is None:
            raise RuntimeError("clock must return an offset-aware datetime")
        return value.astimezone(timezone.utc)


def _require_uuid(value: object) -> str:
    try:
        return str(uuid.UUID(str(value)))
    except (AttributeError, ValueError) as error:
        raise AgentError("INVALID_TASK_ID", "task_id 必须为 UUID。") from error


def _validate_changes(value: object) -> dict[str, object]:
    if not isinstance(value, dict) or not value:
        raise AgentError("INVALID_UPDATE", "changes 必须包含至少一个修改字段。")
    unknown = sorted(set(value) - EDITABLE_FIELDS)
    if unknown:
        raise AgentError("FIELD_NOT_EDITABLE", "包含不允许修改的字段。", details={"fields": unknown})
    result = dict(value)
    if "name" in result:
        if not isinstance(result["name"], str) or not result["name"].strip():
            raise AgentError("NAME_REQUIRED", "任务名称不能为空。")
        if len(result["name"].strip()) > 100:
            raise AgentError("NAME_TOO_LONG", "任务名称不能超过 100 个字符。")
        result["name"] = result["name"].strip()
    for field in ("planned_at", "deadline_at"):
        if field in result and result[field] is not None:
            if not isinstance(result[field], str):
                raise AgentError("INVALID_DATETIME", f"{field} 必须为带偏移的 ISO 8601 时间。")
            _parse_instant(result[field], field)
    for field in ("planned_date", "deadline_date"):
        if field in result and result[field] is not None:
            if not isinstance(result[field], str):
                raise AgentError("INVALID_DATE", f"{field} 必须为 YYYY-MM-DD。")
            _parse_date(result[field], field)
    if "notes" in result:
        if result["notes"] is not None and not isinstance(result["notes"], str):
            raise AgentError("INVALID_NOTES", "notes 必须为字符串或 null。")
        result["notes"] = result["notes"].strip() or None if result["notes"] is not None else None
        if result["notes"] is not None and len(result["notes"]) > 2000:
            raise AgentError("NOTES_TOO_LONG", "备注不能超过 2000 个字符。")
    return result


def _assert_editable(snapshot: dict[str, object]) -> None:
    if snapshot.get("task_type") != "one_time":
        raise AgentError("NOT_EDITABLE", "当前只支持编辑单次事项。")
    if snapshot.get("lifecycle_status") != "active":
        raise AgentError("NOT_EDITABLE", "已完成、归档或非 active 任务暂不支持编辑。")
    if snapshot.get("completion_status") != "pending":
        raise AgentError("NOT_EDITABLE", "已完成任务暂不支持编辑。")
    if snapshot.get("deleted_at") is not None:
        raise AgentError("NOT_EDITABLE", "已删除任务暂不支持编辑。")


def _apply_changes(snapshot: dict[str, object], changes: dict[str, object]) -> dict[str, object]:
    target = dict(snapshot)
    if "name" in changes:
        target["name"] = changes["name"]
    if "notes" in changes:
        target["notes"] = changes["notes"]
    if "planned_at" in changes or "planned_date" in changes:
        planned_at = changes.get("planned_at") if "planned_at" in changes else None
        planned_date = changes.get("planned_date") if "planned_date" in changes else None
        if planned_at is not None:
            instant = _parse_instant(planned_at, "planned_at")
            derived = instant.astimezone(_shanghai()).date().isoformat()
            if planned_date is not None and planned_date != derived:
                raise AgentError("PLANNED_DATE_MISMATCH", "planned_date 必须与 planned_at 的上海本地日期一致。")
            planned_date = derived
            normalized = instant.astimezone(_shanghai()).isoformat()
            target["scheduled_at"] = normalized
            target["planned_at"] = normalized
        else:
            if planned_date is not None:
                _parse_date(planned_date, "planned_date")
            target["planned_at"] = None
            target["scheduled_at"] = snapshot.get("scheduled_at")
        target["planned_date"] = planned_date
        target["has_scheduled_date"] = planned_at is not None
    if "deadline_at" in changes or "deadline_date" in changes:
        deadline_at = changes.get("deadline_at") if "deadline_at" in changes else None
        deadline_date = changes.get("deadline_date") if "deadline_date" in changes else None
        if deadline_at is not None and deadline_date is not None:
            raise AgentError("DEADLINE_SHAPE_INVALID", "deadline_date 与 deadline_at 必须且只能提供一个。")
        target["deadline_at"] = (
            _parse_instant(deadline_at, "deadline_at").astimezone(_shanghai()).isoformat()
            if deadline_at is not None else None
        )
        target["deadline_date"] = deadline_date
    _validate_time_order(target)
    return target


def _validate_time_order(snapshot: dict[str, object]) -> None:
    planned = snapshot.get("planned_at")
    due_date = snapshot.get("deadline_date")
    due_at = snapshot.get("deadline_at")
    if not isinstance(planned, str):
        return
    instant = _parse_instant(planned, "planned_at")
    if isinstance(due_date, str) and instant.astimezone(_shanghai()).date().isoformat() > due_date:
        raise AgentError("PLANNED_AFTER_DEADLINE", "计划时间不能晚于截止日期。")
    if isinstance(due_at, str) and instant > _parse_instant(due_at, "deadline_at"):
        raise AgentError("PLANNED_AFTER_DEADLINE", "计划时间不能晚于截止时间。")


def _changed_fields(original: dict[str, object], target: dict[str, object]) -> list[str]:
    pairs = (
        ("name", "name"),
        ("planned_at", "planned_at"),
        ("planned_date", "planned_date"),
        ("deadline_at", "deadline_at"),
        ("deadline_date", "deadline_date"),
        ("notes", "notes"),
    )
    return [label for label, key in pairs if original.get(key) != target.get(key)]


def _public_snapshot(snapshot: dict[str, object]) -> dict[str, object]:
    return {
        key: snapshot.get(key)
        for key in _SNAPSHOT_KEYS
        if key
        not in {
            "task_updated_at",
            "reminder_updated_at",
            "deleted_at",
            "scheduled_at",
            "has_scheduled_date",
        }
    }


def _digest(task_id: str, changes: dict[str, object], original: dict[str, object]) -> str:
    payload = {"task_id": task_id, "changes": changes, "original": original}
    return hashlib.sha256(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def _shanghai():
    from zoneinfo import ZoneInfo

    return ZoneInfo(DEFAULT_TIMEZONE)
