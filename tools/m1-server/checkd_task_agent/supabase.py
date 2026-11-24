from __future__ import annotations

import base64
import ipaddress
import json
import logging
import re
import socket
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from collections.abc import Callable
from datetime import datetime, timedelta, timezone
from typing import Any, Protocol
from zoneinfo import ZoneInfo

from .models import AgentError, TaskDraft
from .query_service import QueryPage


_SHANGHAI = ZoneInfo("Asia/Shanghai")
_ONE_TIME_SELECT = (
    "task_id,user_id,scheduled_at,has_scheduled_date,available_from,planned_date,"
    "due_date,due_at,remind_before_minutes,is_timed,completed_at,created_at,updated_at,"
    "tasks!inner(id,user_id,name,type,color,icon_name,notes,status,created_at,updated_at,deleted_at,remaining_effort_minutes)"
)
_REMINDER_RULE_SELECT = (
    "id,reminder_kind,enabled,scheduled_minute_of_day,remind_before_minutes,"
    "local_date,timezone,updated_at"
)
_LOGGER = logging.getLogger("checkd_task_agent.supabase")


@dataclass(frozen=True, slots=True)
class HttpResponse:
    status: int
    body: bytes

    def json(self) -> Any:
        if not self.body:
            return None
        return json.loads(self.body.decode("utf-8"))


class HttpTransport(Protocol):
    def request(
        self,
        method: str,
        url: str,
        *,
        headers: dict[str, str],
        body: bytes | None = None,
        timeout: float = 15,
    ) -> HttpResponse: ...


class UrllibTransport:
    def request(
        self,
        method: str,
        url: str,
        *,
        headers: dict[str, str],
        body: bytes | None = None,
        timeout: float = 15,
    ) -> HttpResponse:
        request = urllib.request.Request(
            url=url,
            data=body,
            method=method,
            headers=headers,
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return HttpResponse(status=response.status, body=response.read())
        except urllib.error.HTTPError as error:
            return HttpResponse(status=error.code, body=error.read())
        except (urllib.error.URLError, TimeoutError, socket.timeout) as error:
            raise AgentError(
                "NETWORK_ERROR",
                "无法连接 CheckD 云端，请稍后用同一确认重试。",
                retryable=True,
            ) from error


class SupabaseTaskRepository:
    def __init__(
        self,
        *,
        url: str,
        publishable_key: str,
        user_access_token: str,
        transport: HttpTransport | None = None,
        timeout: float = 15,
    ) -> None:
        self._url = url.rstrip("/")
        self._publishable_key = publishable_key.strip()
        self._token = user_access_token.strip()
        self._transport = transport or UrllibTransport()
        self._timeout = timeout
        self._user_id: str | None = None
        parsed_url = urllib.parse.urlsplit(self._url)
        local_http = parsed_url.scheme == "http" and (
            parsed_url.hostname == "localhost"
            or (parsed_url.hostname is not None
                and ipaddress.ip_address(parsed_url.hostname).is_loopback)
        )
        if parsed_url.scheme != "https" and not local_http:
            raise AgentError("CONFIG_INVALID", "SUPABASE_URL 必须使用 HTTPS。")
        if not self._publishable_key or not self._token:
            raise AgentError("CONFIG_MISSING", "Supabase 公开项目配置或用户会话缺失。")
        if _looks_privileged(self._publishable_key) or _looks_privileged(self._token):
            raise AgentError(
                "SERVICE_ROLE_FORBIDDEN",
                "不允许使用 service_role 凭据。",
            )

    def authenticated_user_id(self) -> str:
        if self._user_id is not None:
            return self._user_id
        response = self._request("GET", "/auth/v1/user")
        if response.status == 401:
            raise AgentError("AUTH_EXPIRED", "用户会话无效或已过期。", retryable=True)
        if response.status == 403:
            raise AgentError("AUTH_FORBIDDEN", "当前用户无权访问 CheckD。")
        if not 200 <= response.status < 300:
            raise AgentError(
                "AUTH_UNAVAILABLE",
                "无法验证 CheckD 用户会话。",
                retryable=response.status >= 500,
            )
        payload = _safe_json(response)
        user_id = payload.get("id") if isinstance(payload, dict) else None
        if not isinstance(user_id, str) or not user_id:
            raise AgentError("AUTH_INVALID_RESPONSE", "用户会话响应中缺少可验证的 UID。")
        self._user_id = user_id
        return user_id

    def create_and_verify(
        self,
        draft: TaskDraft,
        *,
        task_id: str,
        now: datetime,
    ) -> dict[str, object]:
        draft = draft.validated()
        user_id = self.authenticated_user_id()
        now_utc = now.astimezone(timezone.utc)
        timestamp = now_utc.isoformat().replace("+00:00", "Z")
        planned = datetime.fromisoformat(draft.planned_at) if draft.planned_at else None
        planned_date = (
            planned.astimezone(ZoneInfo(draft.timezone)).date().isoformat()
            if planned is not None
            else None
        )
        task_row: dict[str, object] = {
            "id": task_id,
            "user_id": user_id,
            "name": draft.name,
            "type": "one_time",
            "color": draft.color,
            "icon_name": draft.icon_name,
            "notes": draft.persisted_notes(),
            "status": "active",
            "created_at": timestamp,
            "updated_at": timestamp,
            "deleted_at": None,
        }
        reminder_row: dict[str, object] = {
            "task_id": task_id,
            "user_id": user_id,
            "scheduled_at": draft.planned_at or timestamp,
            "has_scheduled_date": draft.planned_at is not None,
            "available_from": None,
            "planned_date": planned_date,
            "due_date": draft.deadline_date,
            "due_at": draft.deadline_at,
            "remind_before_minutes": None,
            "is_timed": False,
            "completed_at": None,
            "created_at": timestamp,
            "updated_at": timestamp,
        }
        expected_task = {
            key: task_row[key]
            for key in ("id", "user_id", "name", "type", "color", "icon_name", "notes", "status", "deleted_at")
        }
        expected_reminder = {
            key: reminder_row[key]
            for key in (
                "task_id",
                "user_id",
                "has_scheduled_date",
                "planned_date",
                "due_date",
                "due_at",
                "is_timed",
                "completed_at",
            )
        }
        if draft.planned_at is not None:
            expected_reminder["scheduled_at"] = draft.planned_at

        # Confirmation retries use the same task ID. Insert only missing rows
        # and check an existing parent before inserting the dependent reminder.
        task_filters = {"id": task_id, "user_id": user_id}
        task_fields = ",".join(expected_task)
        self._insert_once("tasks", task_row, on_conflict="id")
        task = self._select_one("tasks", filters=task_filters, fields=task_fields)
        if not _rows_match(task, expected_task):
            raise AgentError(
                "READBACK_MISMATCH",
                "云端已有同一任务，但内容与已确认草稿不同。请查看现有任务。",
            )

        self._insert_once("one_time_reminders", reminder_row, on_conflict="task_id")
        task = self._select_one("tasks", filters=task_filters, fields=task_fields)
        reminder = self._select_one(
            "one_time_reminders",
            filters={"task_id": task_id, "user_id": user_id},
            fields=",".join(expected_reminder),
        )
        if not _rows_match(task, expected_task) or not _rows_match(reminder, expected_reminder):
            raise AgentError(
                "READBACK_MISMATCH",
                "云端回读结果与已确认任务不一致，不返回创建成功。",
                retryable=True,
            )
        return {
            "id": task_id,
            "name": draft.name,
            "type": "one_time",
            "status": "active",
            "deadline_date": draft.deadline_date,
            "deadline_at": draft.deadline_at,
            "planned_at": draft.planned_at,
            "expected_duration_minutes": draft.expected_duration_minutes,
        }

    def list_one_time_tasks(
        self, *, include_completed: bool, limit: int, offset: int
    ) -> QueryPage:
        return self._one_time_page(
            include_completed=include_completed,
            limit=limit,
            offset=offset,
        )

    def search_one_time_tasks(
        self, query: str, *, include_completed: bool, limit: int, offset: int
    ) -> QueryPage:
        return self._one_time_page(
            include_completed=include_completed,
            limit=limit,
            offset=offset,
            extra_filters=[("tasks.name", f"ilike.*{_escape_like(query)}*")],
        )

    def list_one_time_tasks_by_date(
        self, day: str, *, include_completed: bool, limit: int, offset: int
    ) -> QueryPage:
        try:
            local_day = datetime.fromisoformat(f"{day}T00:00:00+08:00")
        except ValueError as error:
            raise AgentError("INVALID_DATE", "date 必须为 YYYY-MM-DD。") from error
        if local_day.date().isoformat() != day:
            raise AgentError("INVALID_DATE", "date 必须为 YYYY-MM-DD。")
        next_day = local_day.replace(hour=0) + _one_day()
        start = _iso_utc(local_day)
        end = _iso_utc(next_day)
        return self._one_time_page(
            include_completed=include_completed,
            limit=limit,
            offset=offset,
            extra_filters=[
                (
                    "or",
                    "(and(has_scheduled_date.eq.true,"
                    f"scheduled_at.gte.{start},scheduled_at.lt.{end}),"
                    f"and(has_scheduled_date.eq.false,planned_date.eq.{day}))",
                )
            ],
            item_filter=lambda item: _matches_calendar_date(item, day),
        )

    def list_overdue_one_time_tasks(
        self, *, now: datetime, limit: int, offset: int
    ) -> QueryPage:
        if now.tzinfo is None or now.utcoffset() is None:
            raise ValueError("now must include a UTC offset")
        now_utc = now.astimezone(timezone.utc)
        local_day = now_utc.astimezone(_SHANGHAI).date().isoformat()
        return self._one_time_page(
            include_completed=False,
            limit=limit,
            offset=offset,
            extra_filters=[
                ("or", f"(due_date.lt.{local_day},due_at.lt.{_iso_utc(now_utc)})")
            ],
            item_filter=lambda item: _is_overdue(item, now_utc),
        )

    def get_one_time_task_detail(self, task_id: str) -> dict[str, object]:
        user_id = self.authenticated_user_id()
        rows = self._read_many(
            "one_time_reminders",
            self._one_time_filters(user_id, include_completed=True)
            + [("task_id", f"eq.{task_id}"), ("limit", "2")],
        )
        owned = [row for row in rows if _belongs_to_user(row, user_id)]
        if not owned:
            # RLS deliberately makes a different user's row indistinguishable
            # from an unknown UUID.
            raise AgentError("NOT_FOUND", "未找到该单次事项。")
        if len(owned) != 1:
            raise AgentError("REMOTE_RESPONSE_INVALID", "云端返回了重复的单次事项。")
        detail = _one_time_dto(owned[0], include_detail=True)
        rules = self._read_many(
            "reminder_rules",
            [
                ("select", _REMINDER_RULE_SELECT),
                ("user_id", f"eq.{user_id}"),
                ("owner_type", "eq.oneTime"),
                ("owner_id", f"eq.{task_id}"),
                ("deleted_at", "is.null"),
                ("order", "updated_at.desc,id.desc"),
                ("limit", "50"),
            ],
        )
        detail["reminder_rules"] = [_reminder_rule_dto(rule) for rule in rules]
        return detail

    def get_one_time_task_snapshot(self, task_id: str) -> dict[str, object]:
        user_id = self.authenticated_user_id()
        rows = self._read_many(
            "one_time_reminders",
            self._one_time_filters(user_id, include_completed=True)
            + [("task_id", f"eq.{task_id}"), ("limit", "2")],
        )
        owned = [row for row in rows if _belongs_to_user(row, user_id)]
        if not owned:
            raise AgentError("NOT_FOUND", "未找到该单次事项。")
        if len(owned) != 1:
            raise AgentError("REMOTE_RESPONSE_INVALID", "云端返回了重复的单次事项。")
        return _one_time_snapshot(owned[0])

    def update_one_time_task(
        self,
        original_snapshot: dict[str, object],
        target_snapshot: dict[str, object],
        *,
        write_receipts: dict[str, str] | None = None,
        record_write: Callable[[str, str], None] | None = None,
    ) -> dict[str, object]:
        user_id = self.authenticated_user_id()
        task_id = _required_string(original_snapshot, "id")
        current = self.get_one_time_task_snapshot(task_id)
        component_fields = {
            "task": ("name", "notes"),
            "reminder": ("scheduled_at", "has_scheduled_date", "planned_at", "planned_date", "deadline_date", "deadline_at"),
        }
        pending = {
            component
            for component, fields in component_fields.items()
            if any(original_snapshot.get(field) != target_snapshot.get(field) for field in fields)
        }
        expected = dict(original_snapshot)
        completed: set[str] = set()

        def accept_write(component: str, version: str) -> None:
            for field in component_fields[component]:
                expected[field] = target_snapshot.get(field)
            expected[f"{component}_updated_at"] = version
            completed.add(component)

        # A matching value alone doesn't prove this approval wrote it. Verify
        # the exact version returned by the accepted PATCH before resuming.
        for component, version in (write_receipts or {}).items():
            if component not in pending:
                raise AgentError("CONCURRENT_MODIFICATION", "已记录的修改和确认范围不一致，请重新准备。")
            accept_write(component, version)
        if not _snapshot_equal(current, expected):
            raise AgentError("CONCURRENT_MODIFICATION", "任务版本与本次确认不符，请重新读取并准备修改。")

        def remember_write(component: str, version: str) -> None:
            accept_write(component, version)
            if record_write is not None:
                record_write(component, version)

        try:
            if "task" in pending - completed:
                version = self._conditional_update(
                    "tasks",
                    {
                        "name": target_snapshot.get("name"),
                        "notes": target_snapshot.get("notes"),
                    },
                    [
                        ("id", f"eq.{task_id}"),
                        ("user_id", f"eq.{user_id}"),
                        ("type", "eq.one_time"),
                        ("status", "eq.active"),
                        ("deleted_at", "is.null"),
                        ("updated_at", f"eq.{original_snapshot.get('task_updated_at')}"),
                    ],
                    component="task",
                    return_field="id",
                    expected_id=task_id,
                )
                remember_write("task", version)
            if "reminder" in pending - completed:
                version = self._conditional_update(
                    "one_time_reminders",
                    {
                        "scheduled_at": target_snapshot.get("scheduled_at"),
                        "has_scheduled_date": target_snapshot.get("has_scheduled_date"),
                        "planned_date": target_snapshot.get("planned_date"),
                        "due_date": target_snapshot.get("deadline_date"),
                        "due_at": target_snapshot.get("deadline_at"),
                    },
                    [
                        ("task_id", f"eq.{task_id}"),
                        ("user_id", f"eq.{user_id}"),
                        ("updated_at", f"eq.{original_snapshot.get('reminder_updated_at')}"),
                    ],
                    component="reminder",
                    return_field="task_id",
                    expected_id=task_id,
                )
                remember_write("reminder", version)
        except AgentError as error:
            if completed:
                raise AgentError(
                    "PARTIAL_UPDATE",
                    "任务只完成了部分云端写入。"
                    + ("请重试以核对已写入的部分。" if error.retryable else "请重新读取任务，核对后再确认。"),
                    retryable=error.retryable,
                    details={"failed_component": "task_or_reminder"},
                ) from error
            raise

        readback = self.get_one_time_task_snapshot(task_id)
        if not _snapshot_equal(readback, expected):
            raise AgentError(
                "READBACK_MISMATCH",
                "修改后的云端任务与预期不一致，不返回成功。",
                retryable=True,
            )
        return _snapshot_dto(readback)

    def _conditional_update(
        self,
        table: str,
        values: dict[str, object],
        filters: list[tuple[str, str]],
        *,
        component: str,
        return_field: str,
        expected_id: str,
    ) -> str:
        # one_time_reminders uses task_id as its primary key; it has no id
        # column. The returned primary key and version identify this write.
        params = [("select", f"{return_field},updated_at"), *filters]
        response = self._request(
            "PATCH",
            f"/rest/v1/{table}?{urllib.parse.urlencode(params)}",
            body=json.dumps(values, ensure_ascii=False, separators=(",", ":")).encode("utf-8"),
            extra_headers={"Content-Type": "application/json", "Prefer": "return=representation"},
        )
        if response.status == 401:
            raise AgentError("AUTH_EXPIRED", "用户会话无效或已过期。", retryable=True)
        if response.status == 403:
            raise AgentError("RLS_DENIED", "RLS 拒绝了任务修改。")
        if response.status in {409, 412}:
            raise AgentError("CONCURRENT_MODIFICATION", "任务在确认后已发生变化，请重新准备修改。")
        if not 200 <= response.status < 300:
            details = _safe_postgrest_error_details(response, stage=component)
            _LOGGER.warning("remote update failed: %s", json.dumps(details, ensure_ascii=False, sort_keys=True))
            raise AgentError(
                "REMOTE_UPDATE_FAILED",
                "云端任务修改失败。",
                retryable=response.status >= 500,
                details=details,
            )
        payload = _safe_json(response)
        if (
            not isinstance(payload, list)
            or len(payload) != 1
            or not isinstance(payload[0], dict)
            or payload[0].get(return_field) != expected_id
        ):
            raise AgentError("CONCURRENT_MODIFICATION", f"云端 {component} 记录已变化或不存在。")
        version = _instant_or_none(payload[0].get("updated_at"), "updated_at")
        if version is None:
            raise AgentError("REMOTE_RESPONSE_INVALID", "云端未返回修改版本，请重新读取任务。")
        return version

    def _one_time_page(
        self,
        *,
        include_completed: bool,
        limit: int,
        offset: int,
        extra_filters: list[tuple[str, str]] | None = None,
        item_filter=None,
    ) -> QueryPage:
        user_id = self.authenticated_user_id()
        rows = self._read_many(
            "one_time_reminders",
            self._one_time_filters(user_id, include_completed=include_completed)
            + (extra_filters or [])
            + [("order", "updated_at.desc,task_id.desc"), ("limit", str(limit + 1)), ("offset", str(offset))],
        )
        items: list[dict[str, object]] = []
        for row in rows[:limit]:
            if not _belongs_to_user(row, user_id):
                continue
            if _embedded_task(row).get("type") != "one_time":
                # The server-side relation filter is the authority; retaining
                # this guard keeps an unexpected row from leaking into a
                # one-time-only response.
                continue
            item = _one_time_dto(row, include_detail=False)
            if not include_completed and item["completion_status"] != "pending":
                continue
            if item_filter is not None and not item_filter(item):
                continue
            items.append(item)
        return QueryPage(
            items=items,
            next_offset=offset + limit if len(rows) > limit else None,
        )

    @staticmethod
    def _one_time_filters(
        user_id: str, *, include_completed: bool
    ) -> list[tuple[str, str]]:
        filters = [
            ("select", _ONE_TIME_SELECT),
            ("user_id", f"eq.{user_id}"),
            ("tasks.user_id", f"eq.{user_id}"),
            ("tasks.type", "eq.one_time"),
            ("tasks.status", "eq.active"),
            ("tasks.deleted_at", "is.null"),
        ]
        if not include_completed:
            filters.append(("completed_at", "is.null"))
        return filters

    def _read_many(
        self, table: str, params: list[tuple[str, str]]
    ) -> list[dict[str, object]]:
        response = self._request(
            "GET", f"/rest/v1/{table}?{urllib.parse.urlencode(params)}"
        )
        if response.status == 401:
            raise AgentError("AUTH_EXPIRED", "用户会话无效或已过期。", retryable=True)
        if response.status == 403:
            raise AgentError("RLS_DENIED", "RLS 拒绝了当前用户的只读查询。")
        if not 200 <= response.status < 300:
            raise AgentError(
                "REMOTE_READ_FAILED",
                "无法读取 CheckD 云端任务。",
                retryable=response.status >= 500,
            )
        payload = _safe_json(response)
        if not isinstance(payload, list) or any(not isinstance(row, dict) for row in payload):
            raise AgentError("REMOTE_RESPONSE_INVALID", "云端返回了无法解析的任务数据。")
        return [dict(row) for row in payload]

    def _insert_once(self, table: str, row: dict[str, object], *, on_conflict: str) -> None:
        query = urllib.parse.urlencode({"on_conflict": on_conflict})
        response = self._request(
            "POST",
            f"/rest/v1/{table}?{query}",
            body=json.dumps(row, ensure_ascii=False, separators=(",", ":")).encode("utf-8"),
            extra_headers={
                "Content-Type": "application/json",
                "Prefer": "resolution=ignore-duplicates,return=minimal",
            },
        )
        self._require_write_success(response, table)

    def _select_one(
        self,
        table: str,
        *,
        filters: dict[str, str],
        fields: str,
    ) -> dict[str, object]:
        params: list[tuple[str, str]] = [("select", fields)]
        params.extend((key, f"eq.{value}") for key, value in filters.items())
        response = self._request("GET", f"/rest/v1/{table}?{urllib.parse.urlencode(params)}")
        if response.status == 401:
            raise AgentError("AUTH_EXPIRED", "用户会话无效或已过期。", retryable=True)
        if response.status == 403:
            raise AgentError("RLS_DENIED", "RLS 拒绝了当前用户的回读。")
        if not 200 <= response.status < 300:
            raise AgentError("READBACK_FAILED", "无法回读创建结果。", retryable=response.status >= 500)
        payload = _safe_json(response)
        if not isinstance(payload, list) or len(payload) != 1 or not isinstance(payload[0], dict):
            raise AgentError("READBACK_MISMATCH", "回读未找到唯一的新任务。", retryable=True)
        return payload[0]

    def _require_write_success(self, response: HttpResponse, table: str) -> None:
        details: dict[str, object] = {"table": table, "http_status": response.status}
        # Keep only PostgreSQL's five-character diagnostic code. Error messages
        # and details can echo submitted task values, so never place them in the
        # Agent response or logs.
        try:
            error_payload = json.loads(response.body.decode("utf-8")) if response.body else {}
            pg_code = error_payload.get("code") if isinstance(error_payload, dict) else None
            if isinstance(pg_code, str) and re.fullmatch(r"[0-9A-Z]{5}", pg_code):
                details["postgrest_code"] = pg_code
        except (UnicodeDecodeError, json.JSONDecodeError):
            pass
        if response.status == 401:
            raise AgentError("AUTH_EXPIRED", "用户会话无效或已过期。", retryable=True,
                             details=details)
        if response.status == 403:
            raise AgentError("RLS_DENIED", f"RLS 拒绝了对 {table} 的写入。", details=details)
        if response.status in {409, 422}:
            raise AgentError("DATA_CONSTRAINT_FAILED", f"{table} 写入不符合云端约束。",
                             details=details)
        if not 200 <= response.status < 300:
            raise AgentError(
                "REMOTE_WRITE_FAILED",
                f"{table} 写入失败。",
                retryable=response.status >= 500,
                details=details,
            )

    def _request(
        self,
        method: str,
        path: str,
        *,
        body: bytes | None = None,
        extra_headers: dict[str, str] | None = None,
    ) -> HttpResponse:
        headers = {
            "apikey": self._publishable_key,
            "Authorization": f"Bearer {self._token}",
            "Accept": "application/json",
        }
        if extra_headers:
            headers.update(extra_headers)
        return self._transport.request(
            method,
            f"{self._url}{path}",
            headers=headers,
            body=body,
            timeout=self._timeout,
        )


def _safe_json(response: HttpResponse) -> Any:
    try:
        return response.json()
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise AgentError("REMOTE_RESPONSE_INVALID", "云端返回了无法解析的响应。", retryable=True) from error


def _safe_postgrest_error_details(response: HttpResponse, *, stage: str) -> dict[str, object]:
    """Keep diagnostics useful without echoing response payloads or credentials."""
    details: dict[str, object] = {"stage": stage, "http_status": response.status}
    try:
        payload = json.loads(response.body.decode("utf-8")) if response.body else None
    except (UnicodeDecodeError, json.JSONDecodeError):
        payload = None
    if isinstance(payload, dict):
        for source, target in (("code", "postgrest_code"), ("hint", "hint"), ("message", "message")):
            value = payload.get(source)
            if isinstance(value, str) and value:
                details[target] = _sanitize_remote_text(value)
    return details


def _sanitize_remote_text(value: str) -> str:
    value = re.sub(r"(?i)bearer\s+[^\s,;]+", "Bearer [redacted]", value)
    value = re.sub(r"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b", "[redacted]", value)
    return value[:240]


def _jwt_role(token: str) -> str | None:
    parts = token.split(".")
    if len(parts) != 3:
        return None
    try:
        payload = parts[1] + "=" * (-len(parts[1]) % 4)
        value = json.loads(base64.urlsafe_b64decode(payload).decode("utf-8"))
    except (ValueError, UnicodeDecodeError, json.JSONDecodeError):
        return None
    return value.get("role") if isinstance(value, dict) and isinstance(value.get("role"), str) else None


def _looks_privileged(value: str) -> bool:
    normalized = value.strip().lower()
    return (
        normalized.startswith("sb_secret_")
        or normalized == "service_role"
        or _jwt_role(value) == "service_role"
    )


def _rows_match(actual: dict[str, object], expected: dict[str, object]) -> bool:
    for key, value in expected.items():
        if key not in actual:
            return False
        actual_value = actual.get(key)
        if key in {"due_at", "scheduled_at"} and isinstance(actual_value, str) and isinstance(value, str):
            try:
                if _parse_instant(actual_value, key) != _parse_instant(value, key):
                    return False
            except AgentError:
                return False
        elif actual_value != value:
            return False
    return True


def _one_day() -> timedelta:
    return timedelta(days=1)


def _iso_utc(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat()


def _escape_like(value: str) -> str:
    """Escape PostgREST/SQL LIKE wildcards without interpolating a filter."""
    return (
        value.replace("\\", "\\\\")
        .replace("%", "\\%")
        .replace("_", "\\_")
        .replace("*", "\\*")
    )


def _belongs_to_user(row: dict[str, object], user_id: str) -> bool:
    task = _embedded_task(row)
    return row.get("user_id") == user_id and task.get("user_id") == user_id


def _embedded_task(row: dict[str, object]) -> dict[str, object]:
    task = row.get("tasks")
    if isinstance(task, list):
        if len(task) != 1 or not isinstance(task[0], dict):
            raise AgentError("REMOTE_RESPONSE_INVALID", "云端返回了无法关联的任务数据。")
        task = task[0]
    if not isinstance(task, dict):
        raise AgentError("REMOTE_RESPONSE_INVALID", "云端任务缺少父记录。")
    return task


def _one_time_dto(row: dict[str, object], *, include_detail: bool) -> dict[str, object]:
    task = _embedded_task(row)
    if task.get("type") != "one_time":
        raise AgentError("REMOTE_RESPONSE_INVALID", "云端返回了非单次事项。")
    task_id = _required_string(row, "task_id")
    if task.get("id") != task_id:
        raise AgentError("REMOTE_RESPONSE_INVALID", "任务父子记录不匹配。")
    has_scheduled_date = row.get("has_scheduled_date")
    if not isinstance(has_scheduled_date, bool):
        raise AgentError("REMOTE_RESPONSE_INVALID", "单次事项缺少排期状态。")
    deadline_date = _date_or_none(row.get("due_date"), "due_date")
    deadline_at = _instant_or_none(row.get("due_at"), "due_at")
    if deadline_date is not None and deadline_at is not None:
        raise AgentError("REMOTE_RESPONSE_INVALID", "单次事项截止日期结构无效。")
    planned_at = _instant_or_none(row.get("scheduled_at"), "scheduled_at") if has_scheduled_date else None
    result: dict[str, object] = {
        "id": task_id,
        "name": _required_string(task, "name"),
        "task_type": "one_time",
        "lifecycle_status": _required_string(task, "status"),
        "completion_status": "completed" if row.get("completed_at") is not None else "pending",
        "planned_at": planned_at,
        "planned_date": _date_or_none(row.get("planned_date"), "planned_date"),
        "deadline_date": deadline_date,
        "deadline_at": deadline_at,
        "updated_at": _instant_or_none(task.get("updated_at"), "tasks.updated_at"),
    }
    if include_detail:
        result.update(
            {
                "color": _required_int(task, "color"),
                "icon_name": _required_string(task, "icon_name"),
                "notes": _string_or_none(task.get("notes"), "notes"),
                "remaining_effort_minutes": _int_or_none(
                    task.get("remaining_effort_minutes"), "remaining_effort_minutes"
                ),
                "available_from": _date_or_none(row.get("available_from"), "available_from"),
                "is_timed": _required_bool(row, "is_timed"),
                "completed_at": _instant_or_none(row.get("completed_at"), "completed_at"),
                "created_at": _instant_or_none(task.get("created_at"), "tasks.created_at"),
                "remind_before_minutes": _int_or_none(
                    row.get("remind_before_minutes"), "remind_before_minutes"
                ),
            }
        )
    return result


def _one_time_snapshot(row: dict[str, object]) -> dict[str, object]:
    task = _embedded_task(row)
    task_id = _required_string(row, "task_id")
    if task.get("id") != task_id or task.get("type") != "one_time":
        raise AgentError("REMOTE_RESPONSE_INVALID", "云端任务父子记录不匹配。")
    has_scheduled_date = row.get("has_scheduled_date")
    if not isinstance(has_scheduled_date, bool):
        raise AgentError("REMOTE_RESPONSE_INVALID", "单次事项缺少排期状态。")
    scheduled_at = _instant_or_none(row.get("scheduled_at"), "scheduled_at")
    if scheduled_at is None:
        raise AgentError("REMOTE_RESPONSE_INVALID", "单次事项缺少必需的 scheduled_at。")
    planned_at = scheduled_at if has_scheduled_date else None
    return {
        "id": task_id,
        "name": _required_string(task, "name"),
        "task_type": "one_time",
        "lifecycle_status": _required_string(task, "status"),
        "completion_status": "completed" if row.get("completed_at") is not None else "pending",
        "deleted_at": task.get("deleted_at"),
        "notes": _string_or_none(task.get("notes"), "notes"),
        "remaining_effort_minutes": _int_or_none(
            task.get("remaining_effort_minutes"), "remaining_effort_minutes"
        ),
        "scheduled_at": scheduled_at,
        "has_scheduled_date": has_scheduled_date,
        "planned_at": planned_at,
        "planned_date": _date_or_none(row.get("planned_date"), "planned_date"),
        "deadline_date": _date_or_none(row.get("due_date"), "due_date"),
        "deadline_at": _instant_or_none(row.get("due_at"), "due_at"),
        "task_updated_at": _instant_or_none(task.get("updated_at"), "tasks.updated_at"),
        "reminder_updated_at": _instant_or_none(row.get("updated_at"), "reminder.updated_at"),
    }


def _snapshot_business_equal(left: dict[str, object], right: dict[str, object]) -> bool:
    return all(left.get(key) == right.get(key) for key in (
        "id", "name", "task_type", "lifecycle_status", "completion_status", "deleted_at",
        "notes", "scheduled_at", "has_scheduled_date", "planned_at", "planned_date",
        "deadline_date", "deadline_at", "remaining_effort_minutes",
    ))


def _snapshot_equal(left: dict[str, object], right: dict[str, object]) -> bool:
    return _snapshot_business_equal(left, right) and all(
        left.get(key) == right.get(key)
        for key in ("task_updated_at", "reminder_updated_at")
    )


def _snapshot_dto(snapshot: dict[str, object]) -> dict[str, object]:
    return {
        "id": snapshot["id"],
        "name": snapshot["name"],
        "task_type": "one_time",
        "lifecycle_status": snapshot["lifecycle_status"],
        "completion_status": snapshot["completion_status"],
        "planned_at": snapshot.get("planned_at"),
        "planned_date": snapshot.get("planned_date"),
        "deadline_date": snapshot.get("deadline_date"),
        "deadline_at": snapshot.get("deadline_at"),
        "notes": snapshot.get("notes"),
        "readback_verified": True,
    }


def _reminder_rule_dto(row: dict[str, object]) -> dict[str, object]:
    reminder_kind = _required_string(row, "reminder_kind")
    if reminder_kind not in {"due", "advance"}:
        raise AgentError("REMOTE_RESPONSE_INVALID", "提醒类型无效。")
    return {
        "id": _required_string(row, "id"),
        "reminder_kind": reminder_kind,
        "enabled": _required_bool(row, "enabled"),
        "scheduled_minute_of_day": _int_or_none(
            row.get("scheduled_minute_of_day"), "scheduled_minute_of_day"
        ),
        "remind_before_minutes": _int_or_none(
            row.get("remind_before_minutes"), "remind_before_minutes"
        ),
        "local_date": _date_or_none(row.get("local_date"), "local_date"),
        "timezone": _required_string(row, "timezone"),
        "updated_at": _instant_or_none(row.get("updated_at"), "updated_at"),
    }


def _matches_calendar_date(item: dict[str, object], day: str) -> bool:
    planned_at = item.get("planned_at")
    if isinstance(planned_at, str):
        return _parse_instant(planned_at, "planned_at").astimezone(_SHANGHAI).date().isoformat() == day
    return item.get("planned_date") == day


def _is_overdue(item: dict[str, object], now: datetime) -> bool:
    if item.get("completion_status") != "pending":
        return False
    due_date = item.get("deadline_date")
    due_at = item.get("deadline_at")
    if isinstance(due_date, str):
        return now.astimezone(_SHANGHAI).date() > datetime.fromisoformat(due_date).date()
    if isinstance(due_at, str):
        return now.astimezone(timezone.utc) > _parse_instant(due_at, "deadline_at").astimezone(timezone.utc)
    return False


def _required_string(row: dict[str, object], field: str) -> str:
    value = row.get(field)
    if not isinstance(value, str) or not value:
        raise AgentError("REMOTE_RESPONSE_INVALID", f"云端任务缺少 {field}。")
    return value


def _string_or_none(value: object, field: str) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise AgentError("REMOTE_RESPONSE_INVALID", f"云端任务字段 {field} 无效。")
    return value


def _required_int(row: dict[str, object], field: str) -> int:
    value = row.get(field)
    if not isinstance(value, int) or isinstance(value, bool):
        raise AgentError("REMOTE_RESPONSE_INVALID", f"云端任务字段 {field} 无效。")
    return value


def _int_or_none(value: object, field: str) -> int | None:
    if value is None:
        return None
    if not isinstance(value, int) or isinstance(value, bool):
        raise AgentError("REMOTE_RESPONSE_INVALID", f"云端任务字段 {field} 无效。")
    return value


def _required_bool(row: dict[str, object], field: str) -> bool:
    value = row.get(field)
    if not isinstance(value, bool):
        raise AgentError("REMOTE_RESPONSE_INVALID", f"云端任务字段 {field} 无效。")
    return value


def _date_or_none(value: object, field: str) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise AgentError("REMOTE_RESPONSE_INVALID", f"云端任务字段 {field} 无效。")
    try:
        parsed = datetime.fromisoformat(f"{value}T00:00:00+00:00").date()
    except ValueError as error:
        raise AgentError("REMOTE_RESPONSE_INVALID", f"云端任务字段 {field} 无效。") from error
    if parsed.isoformat() != value:
        raise AgentError("REMOTE_RESPONSE_INVALID", f"云端任务字段 {field} 无效。")
    return value


def _instant_or_none(value: object, field: str) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise AgentError("REMOTE_RESPONSE_INVALID", f"云端任务字段 {field} 无效。")
    try:
        parsed = _parse_instant(value, field)
    except AgentError as error:
        raise AgentError("REMOTE_RESPONSE_INVALID", f"云端任务字段 {field} 无效。") from error
    return parsed.astimezone(_SHANGHAI).isoformat()


def _parse_instant(value: str, field: str) -> datetime:
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as error:
        raise AgentError("INVALID_DATETIME", f"{field} 必须为 ISO 8601 时间。") from error
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise AgentError("TIMEZONE_REQUIRED", f"{field} 必须带明确 UTC 偏移。")
    return parsed
