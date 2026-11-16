from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import date, datetime, timezone
from typing import Protocol
from uuid import UUID

from .models import AgentError, DEFAULT_TIMEZONE


@dataclass(frozen=True, slots=True)
class QueryPage:
    items: list[dict[str, object]]
    next_offset: int | None


class TaskQueryRepository(Protocol):
    def list_one_time_tasks(
        self, *, include_completed: bool, limit: int, offset: int
    ) -> QueryPage: ...

    def search_one_time_tasks(
        self, query: str, *, include_completed: bool, limit: int, offset: int
    ) -> QueryPage: ...

    def list_overdue_one_time_tasks(
        self, *, now: datetime, limit: int, offset: int
    ) -> QueryPage: ...

    def list_one_time_tasks_by_date(
        self, day: str, *, include_completed: bool, limit: int, offset: int
    ) -> QueryPage: ...

    def get_one_time_task_detail(self, task_id: str) -> dict[str, object]: ...


class TaskQueryService:
    """Argument gates and response envelopes for read-only one-time task tools."""

    def __init__(
        self,
        repository: TaskQueryRepository,
        *,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._clock = clock or (lambda: datetime.now(timezone.utc))

    def list_tasks(
        self,
        *,
        include_completed: bool = False,
        limit: int = 20,
        offset: int = 0,
    ) -> dict[str, object]:
        limit, offset = _page(limit, offset)
        page = self._repository.list_one_time_tasks(
            include_completed=_bool(include_completed, "include_completed"),
            limit=limit,
            offset=offset,
        )
        return _page_response(page, limit=limit, offset=offset)

    def search_tasks(
        self,
        *,
        query: str,
        include_completed: bool = False,
        limit: int = 20,
        offset: int = 0,
    ) -> dict[str, object]:
        value = query.strip() if isinstance(query, str) else ""
        if not value:
            raise AgentError("QUERY_REQUIRED", "query 不能为空。")
        if len(value) > 100:
            raise AgentError("QUERY_TOO_LONG", "query 不能超过 100 个字符。")
        limit, offset = _page(limit, offset)
        page = self._repository.search_one_time_tasks(
            value,
            include_completed=_bool(include_completed, "include_completed"),
            limit=limit,
            offset=offset,
        )
        return _page_response(page, limit=limit, offset=offset, query=value)

    def get_tasks_by_date(
        self,
        *,
        date: str,
        include_completed: bool = True,
        limit: int = 20,
        offset: int = 0,
        timezone_name: str = DEFAULT_TIMEZONE,
    ) -> dict[str, object]:
        _require_shanghai(timezone_name)
        day = _date_string(date, "date")
        limit, offset = _page(limit, offset)
        page = self._repository.list_one_time_tasks_by_date(
            day,
            include_completed=_bool(include_completed, "include_completed"),
            limit=limit,
            offset=offset,
        )
        return _page_response(
            page,
            limit=limit,
            offset=offset,
            date=day,
            view="calendar",
        )

    def list_overdue_tasks(
        self, *, limit: int = 20, offset: int = 0, timezone_name: str = DEFAULT_TIMEZONE
    ) -> dict[str, object]:
        _require_shanghai(timezone_name)
        limit, offset = _page(limit, offset)
        now = self._clock()
        if now.tzinfo is None or now.utcoffset() is None:
            raise RuntimeError("clock must return an offset-aware datetime")
        page = self._repository.list_overdue_one_time_tasks(
            now=now.astimezone(timezone.utc), limit=limit, offset=offset
        )
        return _page_response(page, limit=limit, offset=offset, as_of=now.astimezone(timezone.utc).isoformat())

    def get_task_detail(self, *, task_id: str) -> dict[str, object]:
        try:
            parsed = UUID(task_id)
        except (AttributeError, ValueError) as error:
            raise AgentError("INVALID_TASK_ID", "task_id 必须为 UUID。") from error
        item = self._repository.get_one_time_task_detail(str(parsed))
        return {
            "ok": True,
            "coverage": _coverage(),
            "timezone": DEFAULT_TIMEZONE,
            "item": item,
        }


def _coverage() -> dict[str, object]:
    return {"task_types": ["one_time"], "recurring_included": False}


def _page_response(
    page: QueryPage,
    *,
    limit: int,
    offset: int,
    **extra: object,
) -> dict[str, object]:
    return {
        "ok": True,
        "coverage": _coverage(),
        "timezone": DEFAULT_TIMEZONE,
        **extra,
        "items": page.items,
        "pagination": {
            "limit": limit,
            "offset": offset,
            "next_offset": page.next_offset,
        },
    }


def _page(limit: object, offset: object) -> tuple[int, int]:
    if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= 50:
        raise AgentError("INVALID_PAGINATION", "limit 必须为 1 到 50 的整数。")
    if not isinstance(offset, int) or isinstance(offset, bool) or not 0 <= offset <= 10000:
        raise AgentError("INVALID_PAGINATION", "offset 必须为 0 到 10000 的整数。")
    return limit, offset


def _bool(value: object, field: str) -> bool:
    if not isinstance(value, bool):
        raise AgentError("INVALID_ARGUMENTS", f"{field} 必须为布尔值。")
    return value


def _date_string(value: object, field: str) -> str:
    if not isinstance(value, str):
        raise AgentError("INVALID_DATE", f"{field} 必须为 YYYY-MM-DD。")
    try:
        parsed = date.fromisoformat(value)
    except ValueError as error:
        raise AgentError("INVALID_DATE", f"{field} 必须为 YYYY-MM-DD。") from error
    if parsed.isoformat() != value:
        raise AgentError("INVALID_DATE", f"{field} 必须为 YYYY-MM-DD。")
    return value


def _require_shanghai(value: object) -> None:
    if value != DEFAULT_TIMEZONE:
        raise AgentError("INVALID_TIMEZONE", "当前只支持 Asia/Shanghai。")
