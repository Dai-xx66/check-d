from __future__ import annotations

import io
import json
import os
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch
from zoneinfo import ZoneInfo

from checkd_task_agent.ledger import ConfirmationLedger
from checkd_task_agent.mcp_server import (
    McpApplication,
    TOOLS,
    build_application_from_environment,
    serve,
)
from checkd_task_agent.models import AgentError
from .test_update_service import TASK_ID, snapshot


class FakeService:
    def prepare_task_creation(self, draft, *, idempotency_key):
        return {"ok": True, "status": "pending", "name": draft.name}

    def create_task(self, *, confirmation_id, user_confirmation_text):
        if user_confirmation_text != "确认 123456":
            raise AgentError("EXPLICIT_CONFIRMATION_REQUIRED", "confirmation required")
        return {"ok": True, "status": "created", "readback_verified": True}

    def cancel_task_creation(self, *, confirmation_id):
        return {"ok": True, "status": "cancelled"}


class FakeQueryService:
    def list_tasks(self, **kwargs):
        return {"ok": True, "tool": "list_tasks", "arguments": kwargs}

    def search_tasks(self, **kwargs):
        return {"ok": True, "tool": "search_tasks", "arguments": kwargs}

    def get_tasks_by_date(self, **kwargs):
        return {"ok": True, "tool": "get_tasks_by_date", "arguments": kwargs}

    def list_overdue_tasks(self, **kwargs):
        return {"ok": True, "tool": "list_overdue_tasks", "arguments": kwargs}

    def get_task_detail(self, **kwargs):
        return {"ok": True, "tool": "get_task_detail", "arguments": kwargs}


class FakeUpdateService:
    def prepare_task_update(self, **kwargs):
        return {"ok": True, "tool": "prepare_task_update", "arguments": kwargs}

    def update_task(self, **kwargs):
        return {"ok": True, "tool": "update_task", "arguments": kwargs}

    def cancel_task_update(self, **kwargs):
        return {"ok": True, "tool": "cancel_task_update", "arguments": kwargs}


class McpApplicationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.app = McpApplication(
            FakeService(),
            query_service=FakeQueryService(),
            update_service=FakeUpdateService(),
            clock=lambda: datetime(2026, 11, 11, 12, 0, tzinfo=ZoneInfo("Asia/Shanghai")),
        )

    def test_initialize_and_tools_list(self) -> None:
        initialized = self.app.handle(
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-03-26"}}
        )
        listed = self.app.handle({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        self.assertEqual(initialized["result"]["serverInfo"]["name"], "checkd-personal-task-agent")
        names = [tool["name"] for tool in listed["result"]["tools"]]
        self.assertEqual(names[:4], [
            "resolve_deadline",
            "prepare_task_creation",
            "create_task",
            "cancel_task_creation",
        ])
        self.assertEqual(names[4:], [
            "list_tasks",
            "search_tasks",
            "get_tasks_by_date",
            "list_overdue_tasks",
            "get_task_detail",
            "prepare_task_update",
            "update_task",
            "cancel_task_update",
        ])
        self.assertEqual(len(names), len(set(names)))
        create = next(tool for tool in TOOLS if tool["name"] == "create_task")
        self.assertTrue(create["annotations"]["destructiveHint"])
        self.assertFalse(create["annotations"]["readOnlyHint"])
        for tool in TOOLS[4:9]:
            self.assertTrue(tool["annotations"]["readOnlyHint"])
            self.assertFalse(tool["annotations"]["destructiveHint"])
        for tool in TOOLS[9:]:
            if tool["name"] in {"update_task", "cancel_task_update"}:
                self.assertFalse(tool["annotations"]["readOnlyHint"])
                self.assertEqual(tool["name"] == "update_task", tool["annotations"]["destructiveHint"])
            else:
                self.assertFalse(tool["annotations"]["destructiveHint"])

    def test_query_tools_dispatch_without_changing_creation_tools(self) -> None:
        cases = [
            ("list_tasks", {}, "list_tasks"),
            ("search_tasks", {"query": "实验"}, "search_tasks"),
            ("get_tasks_by_date", {"date": "2026-11-12"}, "get_tasks_by_date"),
            ("list_overdue_tasks", {}, "list_overdue_tasks"),
            (
                "get_task_detail",
                {"task_id": "10000000-0000-0000-0000-000000000001"},
                "get_task_detail",
            ),
        ]
        for index, (name, arguments, expected) in enumerate(cases, 10):
            with self.subTest(name=name):
                response = self.app.handle(
                    {
                        "jsonrpc": "2.0",
                        "id": index,
                        "method": "tools/call",
                        "params": {"name": name, "arguments": arguments},
                    }
                )
                self.assertFalse(response["result"]["isError"])
                self.assertEqual(response["result"]["structuredContent"]["tool"], expected)

    def test_update_tools_dispatch_without_changing_creation_or_query_tools(self) -> None:
        cases = [
            ("prepare_task_update", {"task_id": "id", "changes": {"name": "新"}, "idempotency_key": "k"}),
            ("update_task", {"update_confirmation_id": "id", "user_confirmation_text": "确认"}),
            ("cancel_task_update", {"update_confirmation_id": "id"}),
        ]
        for index, (name, arguments) in enumerate(cases, 20):
            with self.subTest(name=name):
                response = self.app.handle(
                    {"jsonrpc": "2.0", "id": index, "method": "tools/call", "params": {"name": name, "arguments": arguments}}
                )
                self.assertFalse(response["result"]["isError"])
                self.assertEqual(response["result"]["structuredContent"]["tool"], name)

    def test_tool_error_is_structured_and_does_not_leak_arguments(self) -> None:
        response = self.app.handle(
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {
                    "name": "create_task",
                    "arguments": {
                        "confirmation_id": "abc",
                        "user_confirmation_text": "wrong-secret-text",
                    },
                },
            }
        )
        self.assertTrue(response["result"]["isError"])
        text = response["result"]["content"][0]["text"]
        self.assertIn("EXPLICIT_CONFIRMATION_REQUIRED", text)
        self.assertNotIn("wrong-secret-text", text)

    def test_resolve_deadline_tool(self) -> None:
        response = self.app.handle(
            {
                "jsonrpc": "2.0",
                "id": 4,
                "method": "tools/call",
                "params": {"name": "resolve_deadline", "arguments": {"text": "明天晚上八点"}},
            }
        )
        payload = response["result"]["structuredContent"]
        self.assertEqual(payload["deadline_at"], "2026-11-12T20:00:00+08:00")

    def test_stdio_server_uses_one_json_object_per_line(self) -> None:
        source = io.StringIO(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": "ping"}) + "\n"
            + json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n"
        )
        sink = io.StringIO()
        serve(self.app, input_stream=source, output_stream=sink)
        lines = sink.getvalue().splitlines()
        self.assertEqual(len(lines), 1)
        self.assertEqual(json.loads(lines[0])["result"], {})

    def test_access_token_is_consumed_from_child_environment(self) -> None:
        secret = "temporary-user-access-token"
        with tempfile.TemporaryDirectory() as directory:
            application = self._start_standalone(directory, token=secret)
            self.assertIsInstance(application, McpApplication)
            (database,) = Path(directory).glob("state.*.sqlite3")
            self.assertNotIn(secret.encode(), database.read_bytes())

    def _start_standalone(
        self,
        directory,
        *,
        user_id="test-user",
        url="https://example.supabase.co",
        token="temporary-user-access-token",
    ):
        with patch.dict(os.environ, {
            "SUPABASE_URL": url,
            "SUPABASE_PUBLISHABLE_KEY": "public-placeholder",
            "SUPABASE_USER_ACCESS_TOKEN": token,
            "CHECKD_AGENT_STATE_PATH": f"{directory}/state.sqlite3",
        }), patch("checkd_task_agent.mcp_server.SupabaseTaskRepository") as repository_type:
            repository = repository_type.return_value
            repository.authenticated_user_id.return_value = user_id
            repository.get_one_time_task_snapshot.return_value = snapshot()
            application = build_application_from_environment()
            repository.authenticated_user_id.assert_called_once_with()
            self.assertNotIn("SUPABASE_USER_ACCESS_TOKEN", os.environ)
            return application

    def test_standalone_keeps_approvals_in_the_verified_project_and_account(self) -> None:
        create_arguments = {
            "name": "任务草稿",
            "expected_duration_minutes": 10,
            "deadline_date": "2026-11-28",
            "idempotency_key": "create",
        }
        update_arguments = {
            "task_id": TASK_ID,
            "changes": {"name": "任务改名"},
            "idempotency_key": "edit",
        }
        with tempfile.TemporaryDirectory() as directory:
            legacy_state = Path(directory, "state.sqlite3")
            ConfirmationLedger(legacy_state)
            legacy_contents = legacy_state.read_bytes()
            owner = self._start_standalone(directory)
            creation = owner.call_tool("prepare_task_creation", create_arguments)
            update = owner.call_tool("prepare_task_update", update_arguments)
            same_account = self._start_standalone(directory, token="refreshed-access-token")
            self.assertEqual(same_account.call_tool("prepare_task_creation", create_arguments), creation)
            self.assertEqual(same_account.call_tool("prepare_task_update", update_arguments), update)
            for account in (
                self._start_standalone(directory, user_id="other-verified-user"),
                self._start_standalone(directory, url="https://other-project.supabase.co"),
            ):
                with self.assertRaises(AgentError) as rejected_creation:
                    account.call_tool("create_task", {
                        "confirmation_id": creation["confirmation_id"],
                        "user_confirmation_text": creation["confirmation_phrase"],
                    })
                self.assertEqual(rejected_creation.exception.code, "CONFIRMATION_NOT_FOUND")
                with self.assertRaises(AgentError) as rejected_update:
                    account.call_tool("update_task", {
                        "update_confirmation_id": update["update_confirmation_id"],
                        "user_confirmation_text": update["confirmation_phrase"],
                    })
                self.assertEqual(rejected_update.exception.code, "UPDATE_CONFIRMATION_NOT_FOUND")
                self.assertNotEqual(
                    account.call_tool("prepare_task_creation", create_arguments)["confirmation_id"],
                    creation["confirmation_id"],
                )
                self.assertNotEqual(
                    account.call_tool("prepare_task_update", update_arguments)["update_confirmation_id"],
                    update["update_confirmation_id"],
                )
            self.assertEqual(same_account.call_tool("prepare_task_creation", create_arguments), creation)
            self.assertEqual(same_account.call_tool("prepare_task_update", update_arguments), update)
            self.assertEqual(legacy_state.read_bytes(), legacy_contents)


if __name__ == "__main__":
    unittest.main()
