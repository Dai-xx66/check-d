from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass
from datetime import date, datetime
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


DEFAULT_TIMEZONE = "Asia/Shanghai"
DEFAULT_COLOR = 0xFFE69545
DEFAULT_ICON = "event"


class AgentError(Exception):
    """Safe, structured error intended for an Agent tool response."""

    def __init__(
        self,
        code: str,
        message: str,
        *,
        retryable: bool = False,
        details: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.retryable = retryable
        self.details = details or {}

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": False,
            "error": {
                "code": self.code,
                "message": self.message,
                "retryable": self.retryable,
                "details": self.details,
            },
        }


def _parse_date(value: str | None, field: str) -> date | None:
    if value is None:
        return None
    try:
        parsed = date.fromisoformat(value)
    except ValueError as error:
        raise AgentError("INVALID_DATE", f"{field} 必须为 YYYY-MM-DD。") from error
    if parsed.isoformat() != value:
        raise AgentError("INVALID_DATE", f"{field} 必须为 YYYY-MM-DD。")
    return parsed


def _parse_instant(value: str | None, field: str) -> datetime | None:
    if value is None:
        return None
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as error:
        raise AgentError("INVALID_DATETIME", f"{field} 必须为 ISO 8601 时间。") from error
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise AgentError(
            "TIMEZONE_REQUIRED",
            f"{field} 必须带明确 UTC 偏移，例如 +08:00。",
        )
    return parsed


@dataclass(frozen=True, slots=True)
class TaskDraft:
    name: str
    expected_duration_minutes: int
    deadline_date: str | None = None
    deadline_at: str | None = None
    planned_at: str | None = None
    notes: str | None = None
    timezone: str = DEFAULT_TIMEZONE
    color: int = DEFAULT_COLOR
    icon_name: str = DEFAULT_ICON

    def validated(self) -> "TaskDraft":
        name = self.name.strip()
        if not name:
            raise AgentError("NAME_REQUIRED", "请提供任务名称。")
        if len(name) > 100:
            raise AgentError("NAME_TOO_LONG", "任务名称不能超过 100 个字符。")
        if not isinstance(self.expected_duration_minutes, int) or isinstance(
            self.expected_duration_minutes, bool
        ):
            raise AgentError("INVALID_DURATION", "预计时长必须是整数分钟。")
        if not 1 <= self.expected_duration_minutes <= 1440:
            raise AgentError("INVALID_DURATION", "预计时长必须在 1 到 1440 分钟之间。")
        if (self.deadline_date is None) == (self.deadline_at is None):
            raise AgentError(
                "DEADLINE_SHAPE_INVALID",
                "deadline_date 与 deadline_at 必须且只能提供一个。",
            )
        try:
            timezone = ZoneInfo(self.timezone)
        except ZoneInfoNotFoundError as error:
            raise AgentError("INVALID_TIMEZONE", "不支持的 IANA 时区。") from error
        due_date = _parse_date(self.deadline_date, "deadline_date")
        due_at = _parse_instant(self.deadline_at, "deadline_at")
        planned_at = _parse_instant(self.planned_at, "planned_at")
        if planned_at is not None:
            local_plan_date = planned_at.astimezone(timezone).date()
            if due_date is not None and local_plan_date > due_date:
                raise AgentError("PLANNED_AFTER_DEADLINE", "计划时间不能晚于截止日期。")
            if due_at is not None and planned_at > due_at:
                raise AgentError("PLANNED_AFTER_DEADLINE", "计划时间不能晚于截止时间。")
        notes = self.notes.strip() if self.notes and self.notes.strip() else None
        if notes is not None and len(notes) > 2000:
            raise AgentError("NOTES_TOO_LONG", "备注不能超过 2000 个字符。")
        return TaskDraft(
            name=name,
            expected_duration_minutes=self.expected_duration_minutes,
            deadline_date=due_date.isoformat() if due_date else None,
            deadline_at=due_at.isoformat() if due_at else None,
            planned_at=planned_at.isoformat() if planned_at else None,
            notes=notes,
            timezone=self.timezone,
            color=self.color,
            icon_name=self.icon_name,
        )

    def canonical_json(self) -> str:
        return json.dumps(asdict(self.validated()), ensure_ascii=False, sort_keys=True, separators=(",", ":"))

    def digest(self) -> str:
        return hashlib.sha256(self.canonical_json().encode("utf-8")).hexdigest()

    def persisted_notes(self) -> str:
        estimate = (
            f"预计时长（Agent 输入，非 CheckD 结构化时长目标）："
            f"{self.expected_duration_minutes} 分钟"
        )
        return f"{self.notes}\n\n{estimate}" if self.notes else estimate

    def summary(self) -> str:
        deadline = self.deadline_at or self.deadline_date
        planned = f"，计划时间 {self.planned_at}" if self.planned_at else ""
        return (
            f"将创建单次事项：{self.name}，截止 {deadline}{planned}，"
            f"预计时长 {self.expected_duration_minutes} 分钟。"
        )

    @classmethod
    def from_json(cls, payload: str) -> "TaskDraft":
        value = json.loads(payload)
        if not isinstance(value, dict):
            raise AgentError("INVALID_STATE", "本地草稿状态无效。")
        return cls(**value).validated()
