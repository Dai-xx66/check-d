from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .ledger import ConfirmationLedger
from .models import AgentError, TaskDraft
from .query_service import TaskQueryService
from .service import TaskCreationService
from .supabase import SupabaseTaskRepository
from .timeparse import resolve_deadline
from .update_service import TaskUpdateService


SERVER_NAME = "checkd-personal-task-agent"
SERVER_VERSION = "0.3.0"
PROTOCOL_VERSION = "2025-03-26"


TOOLS: list[dict[str, Any]] = [
    {
        "name": "resolve_deadline",
        "description": "将用户的中文相对日期转为 CheckD 可用的绝对截止日期或带偏移时间；不写入数据。",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "minLength": 1},
                "timezone": {"type": "string", "default": "Asia/Shanghai"},
            },
            "required": ["text"],
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": True, "destructiveHint": False},
    },
    {
        "name": "prepare_task_creation",
        "description": "校验并保存待用户确认的单次事项草稿。此工具绝不写入 Supabase。",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "minLength": 1, "maxLength": 100},
                "expected_duration_minutes": {"type": "integer", "minimum": 1, "maximum": 1440},
                "deadline_date": {"type": ["string", "null"], "format": "date"},
                "deadline_at": {"type": ["string", "null"], "format": "date-time"},
                "planned_at": {"type": ["string", "null"], "format": "date-time"},
                "notes": {"type": ["string", "null"], "maxLength": 2000},
                "timezone": {"type": "string", "default": "Asia/Shanghai"},
                "idempotency_key": {"type": "string", "minLength": 1, "maxLength": 128},
            },
            "required": ["name", "expected_duration_minutes", "idempotency_key"],
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": False, "destructiveHint": False, "idempotentHint": True},
    },
    {
        "name": "create_task",
        "description": "只在用户原样回复 prepare_task_creation 返回的确认短语后，写入 CheckD 单次事项并回读核验。",
        "inputSchema": {
            "type": "object",
            "properties": {
                "confirmation_id": {"type": "string", "format": "uuid"},
                "user_confirmation_text": {"type": "string", "minLength": 1},
            },
            "required": ["confirmation_id", "user_confirmation_text"],
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": False, "destructiveHint": True, "idempotentHint": True},
    },
    {
        "name": "cancel_task_creation",
        "description": "取消一个尚未写入的任务草稿；不删除已创建任务。",
        "inputSchema": {
            "type": "object",
            "properties": {"confirmation_id": {"type": "string", "format": "uuid"}},
            "required": ["confirmation_id"],
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": False, "destructiveHint": False, "idempotentHint": True},
    },
    {
        "name": "list_tasks",
        "description": "分页查询当前用户未完成的 CheckD 单次事项；不包含周期任务。",
        "inputSchema": {
            "type": "object",
            "properties": {
                "include_completed": {"type": "boolean", "default": False},
                "limit": {"type": "integer", "minimum": 1, "maximum": 50, "default": 20},
                "offset": {"type": "integer", "minimum": 0, "maximum": 10000, "default": 0},
            },
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": True, "destructiveHint": False},
    },
    {
        "name": "search_tasks",
        "description": "按名称部分匹配分页查询当前用户的 CheckD 单次事项；不包含周期任务。",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "minLength": 1, "maxLength": 100},
                "include_completed": {"type": "boolean", "default": False},
                "limit": {"type": "integer", "minimum": 1, "maximum": 50, "default": 20},
                "offset": {"type": "integer", "minimum": 0, "maximum": 10000, "default": 0},
            },
            "required": ["query"],
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": True, "destructiveHint": False},
    },
    {
        "name": "get_tasks_by_date",
        "description": "按日历归属查询当前用户指定日期的单次事项；不混入逾期滞留，也不包含周期 occurrence。",
        "inputSchema": {
            "type": "object",
            "properties": {
                "date": {"type": "string", "format": "date"},
                "include_completed": {"type": "boolean", "default": True},
                "limit": {"type": "integer", "minimum": 1, "maximum": 50, "default": 20},
                "offset": {"type": "integer", "minimum": 0, "maximum": 10000, "default": 0},
                "timezone": {"type": "string", "enum": ["Asia/Shanghai"], "default": "Asia/Shanghai"},
            },
            "required": ["date"],
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": True, "destructiveHint": False},
    },
    {
        "name": "list_overdue_tasks",
        "description": "查询当前用户逾期且未完成的 CheckD 单次事项；日期型与精确截止时间按不同规则处理。",
        "inputSchema": {
            "type": "object",
            "properties": {
                "limit": {"type": "integer", "minimum": 1, "maximum": 50, "default": 20},
                "offset": {"type": "integer", "minimum": 0, "maximum": 10000, "default": 0},
                "timezone": {"type": "string", "enum": ["Asia/Shanghai"], "default": "Asia/Shanghai"},
            },
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": True, "destructiveHint": False},
    },
    {
        "name": "get_task_detail",
        "description": "读取当前用户一条 CheckD 单次事项的完整详情、截止/执行时间和提醒规则摘要。",
        "inputSchema": {
            "type": "object",
            "properties": {"task_id": {"type": "string", "format": "uuid"}},
            "required": ["task_id"],
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": True, "destructiveHint": False},
    },
    {
        "name": "prepare_task_update",
        "description": "读取当前用户的单次事项，生成修改前后预览和确认短语；此工具绝不写入 Supabase。",
        "inputSchema": {
            "type": "object",
            "properties": {
                "task_id": {"type": "string", "format": "uuid"},
                "changes": {
                    "type": "object",
                    "properties": {
                        "name": {"type": ["string", "null"], "maxLength": 100},
                        "planned_at": {"type": ["string", "null"], "format": "date-time"},
                        "planned_date": {"type": ["string", "null"], "format": "date"},
                        "deadline_at": {"type": ["string", "null"], "format": "date-time"},
                        "deadline_date": {"type": ["string", "null"], "format": "date"},
                        "notes": {"type": ["string", "null"], "maxLength": 2000},
                    },
                    "minProperties": 1,
                    "additionalProperties": False,
                },
                "idempotency_key": {"type": "string", "minLength": 1, "maxLength": 128},
            },
            "required": ["task_id", "changes", "idempotency_key"],
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": False, "destructiveHint": False, "idempotentHint": True},
    },
    {
        "name": "update_task",
        "description": "在用户原样确认修改短语后更新 CheckD 单次事项，并在回读一致后才返回成功。",
        "inputSchema": {
            "type": "object",
            "properties": {
                "update_confirmation_id": {"type": "string", "format": "uuid"},
                "user_confirmation_text": {"type": "string", "minLength": 1},
            },
            "required": ["update_confirmation_id", "user_confirmation_text"],
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": False, "destructiveHint": True, "idempotentHint": True},
    },
    {
        "name": "cancel_task_update",
        "description": "取消尚未执行的任务修改草稿；不能撤销已经完成的修改。",
        "inputSchema": {
            "type": "object",
            "properties": {"update_confirmation_id": {"type": "string", "format": "uuid"}},
            "required": ["update_confirmation_id"],
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": False, "destructiveHint": False, "idempotentHint": True},
    },
]


class McpApplication:
    def __init__(
        self,
        service: TaskCreationService,
        *,
        query_service: TaskQueryService | None = None,
        update_service: TaskUpdateService | None = None,
        clock=None,
    ) -> None:
        self._service = service
        self._query_service = query_service
        self._update_service = update_service
        self._clock = clock or (lambda: datetime.now(timezone.utc))

    def handle(self, message: dict[str, Any]) -> dict[str, Any] | None:
        request_id = message.get("id")
        method = message.get("method")
        if request_id is None:
            return None
        try:
            if method == "initialize":
                requested = (message.get("params") or {}).get("protocolVersion")
                return self._result(
                    request_id,
                    {
                        "protocolVersion": requested or PROTOCOL_VERSION,
                        "capabilities": {"tools": {"listChanged": False}},
                        "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
                    },
                )
            if method == "ping":
                return self._result(request_id, {})
            if method == "tools/list":
                return self._result(request_id, {"tools": TOOLS})
            if method == "tools/call":
                params = message.get("params") or {}
                name = params.get("name")
                arguments = params.get("arguments") or {}
                if not isinstance(arguments, dict):
                    raise AgentError("INVALID_ARGUMENTS", "工具参数必须是 JSON object。")
                try:
                    payload = self.call_tool(name, arguments)
                    return self._tool_result(request_id, payload, is_error=False)
                except AgentError as error:
                    return self._tool_result(request_id, error.to_dict(), is_error=True)
            return self._error(request_id, -32601, "Method not found")
        except AgentError as error:
            return self._tool_result(request_id, error.to_dict(), is_error=True)
        except Exception:
            return self._error(request_id, -32603, "Internal error")

    def call_tool(self, name: str, arguments: dict[str, Any]) -> dict[str, object]:
        if name == "resolve_deadline":
            return {
                "ok": True,
                **resolve_deadline(
                    str(arguments.get("text", "")),
                    now=self._clock(),
                    timezone=str(arguments.get("timezone", "Asia/Shanghai")),
                ),
            }
        if name == "prepare_task_creation":
            draft = TaskDraft(
                name=arguments.get("name", ""),
                expected_duration_minutes=arguments.get("expected_duration_minutes"),
                deadline_date=arguments.get("deadline_date"),
                deadline_at=arguments.get("deadline_at"),
                planned_at=arguments.get("planned_at"),
                notes=arguments.get("notes"),
                timezone=arguments.get("timezone", "Asia/Shanghai"),
            )
            return self._service.prepare_task_creation(
                draft,
                idempotency_key=str(arguments.get("idempotency_key", "")),
            )
        if name == "create_task":
            return self._service.create_task(
                confirmation_id=str(arguments.get("confirmation_id", "")),
                user_confirmation_text=str(arguments.get("user_confirmation_text", "")),
            )
        if name == "cancel_task_creation":
            return self._service.cancel_task_creation(
                confirmation_id=str(arguments.get("confirmation_id", ""))
            )
        if name == "list_tasks":
            return self._queries().list_tasks(
                include_completed=arguments.get("include_completed", False),
                limit=arguments.get("limit", 20),
                offset=arguments.get("offset", 0),
            )
        if name == "search_tasks":
            return self._queries().search_tasks(
                query=arguments.get("query", ""),
                include_completed=arguments.get("include_completed", False),
                limit=arguments.get("limit", 20),
                offset=arguments.get("offset", 0),
            )
        if name == "get_tasks_by_date":
            return self._queries().get_tasks_by_date(
                date=arguments.get("date", ""),
                include_completed=arguments.get("include_completed", True),
                limit=arguments.get("limit", 20),
                offset=arguments.get("offset", 0),
                timezone_name=arguments.get("timezone", "Asia/Shanghai"),
            )
        if name == "list_overdue_tasks":
            return self._queries().list_overdue_tasks(
                limit=arguments.get("limit", 20),
                offset=arguments.get("offset", 0),
                timezone_name=arguments.get("timezone", "Asia/Shanghai"),
            )
        if name == "get_task_detail":
            return self._queries().get_task_detail(task_id=arguments.get("task_id", ""))
        if name == "prepare_task_update":
            return self._updates().prepare_task_update(
                task_id=arguments.get("task_id", ""),
                changes=arguments.get("changes", {}),
                idempotency_key=arguments.get("idempotency_key", ""),
            )
        if name == "update_task":
            return self._updates().update_task(
                update_confirmation_id=arguments.get("update_confirmation_id", ""),
                user_confirmation_text=arguments.get("user_confirmation_text", ""),
            )
        if name == "cancel_task_update":
            return self._updates().cancel_task_update(
                update_confirmation_id=arguments.get("update_confirmation_id", "")
            )
        raise AgentError("TOOL_NOT_FOUND", "未知工具。")

    def _queries(self) -> TaskQueryService:
        if self._query_service is None:
            raise AgentError("QUERY_UNAVAILABLE", "任务查询服务尚未配置。", retryable=True)
        return self._query_service

    def _updates(self) -> TaskUpdateService:
        if self._update_service is None:
            raise AgentError("UPDATE_UNAVAILABLE", "任务修改服务尚未配置。", retryable=True)
        return self._update_service

    @staticmethod
    def _result(request_id: Any, result: dict[str, Any]) -> dict[str, Any]:
        return {"jsonrpc": "2.0", "id": request_id, "result": result}

    @staticmethod
    def _error(request_id: Any, code: int, message: str) -> dict[str, Any]:
        return {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}}

    @classmethod
    def _tool_result(cls, request_id: Any, payload: dict[str, Any], *, is_error: bool) -> dict[str, Any]:
        return cls._result(
            request_id,
            {
                "content": [
                    {
                        "type": "text",
                        "text": json.dumps(payload, ensure_ascii=False, sort_keys=True),
                    }
                ],
                "structuredContent": payload,
                "isError": is_error,
            },
        )


def build_application_from_environment() -> McpApplication:
    url = os.environ.get("SUPABASE_URL", "")
    key = os.environ.get("SUPABASE_PUBLISHABLE_KEY") or os.environ.get("SUPABASE_ANON_KEY", "")
    token = os.environ.pop("SUPABASE_USER_ACCESS_TOKEN", "")
    state_path = os.environ.get(
        "CHECKD_AGENT_STATE_PATH",
        str(Path.home() / ".checkd-task-agent" / "state.sqlite3"),
    )
    repository = SupabaseTaskRepository(
        url=url,
        publishable_key=key,
        user_access_token=token,
    )
    ledger = ConfirmationLedger(state_path)
    return McpApplication(
        TaskCreationService(ledger, repository),
        query_service=TaskQueryService(repository),
        update_service=TaskUpdateService(ledger, repository),
    )


def serve(application: McpApplication, *, input_stream=None, output_stream=None) -> None:
    source = input_stream or sys.stdin
    sink = output_stream or sys.stdout
    for raw_line in source:
        line = raw_line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
            if not isinstance(message, dict):
                raise ValueError
            response = application.handle(message)
        except (json.JSONDecodeError, ValueError):
            response = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}}
        if response is not None:
            sink.write(json.dumps(response, ensure_ascii=False, separators=(",", ":")) + "\n")
            sink.flush()


def main() -> None:
    try:
        application = build_application_from_environment()
    except AgentError as error:
        print(f"{error.code}: {error.message}", file=sys.stderr)
        raise SystemExit(2) from None
    serve(application)


if __name__ == "__main__":
    main()
