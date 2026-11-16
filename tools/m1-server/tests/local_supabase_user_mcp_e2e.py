"""Disposable non-production Supabase -> M1 account MCP isolation check.

Run only against an isolated Supabase project. Creates two synthetic users and
one task/reminder/effort row per user using the publishable key and each user's
own access token. It never uses service_role and prints no token, key, task ID,
email, or task name.
"""
from __future__ import annotations

import json
import os
import secrets
import shutil
import socket
import subprocess
import sys
import time
import tempfile
import urllib.error
from urllib.parse import urlparse
import urllib.request
import uuid

SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
M1_DIR = os.path.dirname(SERVER_DIR)
REPO_DIR = os.path.dirname(os.path.dirname(M1_DIR))
MOCK_DIR = os.path.join(REPO_DIR, "tools", "m1-mock")


def _request(url: str, *, method="GET", payload=None, headers=None):
    data = None if payload is None else json.dumps(payload).encode()
    request = urllib.request.Request(url, data=data, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=12) as response:
            raw = response.read(1_000_001)
            if len(raw) > 1_000_000:
                raise RuntimeError("response limit exceeded")
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        # Do not include upstream response text: Auth/PostgREST may echo user data.
        raise RuntimeError(f"HTTP {exc.code} at {urlparse(url).path}") from None


def _auth(base: str, key: str, label: str):
    email = f"{label}-{uuid.uuid4().hex}@example.invalid"
    password = secrets.token_urlsafe(24)
    headers = {"apikey": key, "Content-Type": "application/json"}
    _, result = _request(base + "/auth/v1/signup", method="POST",
                         payload={"email": email, "password": password}, headers=headers)
    token = result.get("access_token") if isinstance(result, dict) else None
    user = result.get("user") if isinstance(result, dict) else None
    if not token:
        _, result = _request(base + "/auth/v1/token?grant_type=password", method="POST",
                             payload={"email": email, "password": password}, headers=headers)
        token = result.get("access_token") if isinstance(result, dict) else None
        user = result.get("user") if isinstance(result, dict) else None
    if not isinstance(token, str) or not isinstance(user, dict) or not isinstance(user.get("id"), str):
        raise RuntimeError("isolated Auth did not issue a user session")
    return user["id"], token


def _insert(base: str, key: str, token: str, table: str, row: dict):
    _request(base + "/rest/v1/" + table, method="POST", payload=row, headers={
        "apikey": key,
        "Authorization": "Bearer " + token,
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    })


def _rpc(base: str, port: int, token: str, method: str, params=None):
    return _request(f"http://127.0.0.1:{port}/mcp/user", method="POST",
        payload={"jsonrpc": "2.0", "id": secrets.token_hex(4), "method": method,
                 **({"params": params} if params is not None else {})},
        headers={"Authorization": "Bearer " + token,
                 "Content-Type": "application/json",
                 "Accept": "application/json, text/event-stream"})[1]


def main():
    base = os.environ.get("CHECKD_TEST_SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("CHECKD_TEST_SUPABASE_PUBLISHABLE_KEY", "")
    if not base or not key or "127.0.0.1" not in base and "localhost" not in base:
        raise RuntimeError("Set isolated local Supabase URL and publishable key")

    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    service_url = f"http://127.0.0.1:{port}"
    state_dir = tempfile.mkdtemp(prefix="checkd-agent-e2e-state-")
    env = dict(os.environ)
    env.update({
        "PORT": str(port), "BIND": "127.0.0.1",
        "CHECKD_DEMO_TOKEN": "local-route-compatibility-only",
        "CHECKD_USER_MCP_ENABLED": "1",
        "CHECKD_USER_MCP_ENV": "development",
        "CHECKD_USER_SUPABASE_URL": base,
        "CHECKD_USER_SUPABASE_PUBLISHABLE_KEY": key,
        "CHECKD_USER_MCP_PUBLIC_URL": service_url,
        "CHECKD_USER_SUPABASE_ISSUER": base + "/auth/v1",
        "CHECKD_USER_MCP_UPSTREAM_TIMEOUT_SECONDS": "8",
        "CHECKD_USER_MCP_TASK_WRITES_ENABLED": "1",
        "CHECKD_USER_AGENT_STATE_DIR": state_dir,
        "PYTHONPATH": os.pathsep.join([M1_DIR, MOCK_DIR]),
    })
    server = subprocess.Popen([sys.executable, os.path.join(M1_DIR, "app.py")],
        cwd=M1_DIR, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.time() + 20
        while time.time() < deadline:
            if server.poll() is not None:
                raise RuntimeError("isolated M1 service failed to start")
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=.25):
                    break
            except OSError:
                time.sleep(.1)
        else:
            raise RuntimeError("isolated M1 service did not start")

        users = [_auth(base, key, f"checkd-user-{i}") for i in ("a", "b")]
        task_ids = []
        for index, (user_id, token) in enumerate(users):
            task_id = str(uuid.uuid4())
            task_ids.append(task_id)
            _insert(base, key, token, "tasks", {
                "id": task_id, "user_id": user_id,
                "name": f"isolated-agent-task-{index}", "type": "one_time",
                "color": 1, "status": "active",
            })
            _insert(base, key, token, "one_time_reminders", {
                "task_id": task_id, "user_id": user_id,
                "scheduled_at": "2026-11-18T10:00:00+08:00",
                "available_from": "2026-11-16", "planned_date": "2026-11-18",
                "due_date": "2026-11-20",
            })
            _insert(base, key, token, "task_effort_estimates", {
                "user_id": user_id, "task_id": task_id,
                "estimated_seconds": 1800, "remaining_seconds": 1800,
                "source": "isolated-integration-fixture",
            })

        listed = _rpc(base, port, users[0][1], "tools/list")["result"]["tools"]
        names = {tool["name"] for tool in listed}
        if len(names) != 21 or len(names) != len(listed) or "list_tasks" not in names:
            raise RuntimeError("account route did not expose 12 personal + 9 planning tools")
        visible = []
        for _, token in users:
            result = _rpc(base, port, token, "tools/call", {"name": "list_tasks",
                "arguments": {}})
            list_content = result["result"].get("structuredContent", {})
            if not list_content.get("ok"):
                error = list_content.get("error") or {}
                details = error.get("details") or {}
                raise RuntimeError(f"personal list_tasks failed; code={error.get('code', 'none')}; field={details.get('invalid_field', ','.join(details.get('unknown_fields', [])))}")
            tasks = list_content.get("items", [])
            visible.append([task.get("name") for task in tasks])
            searched = _rpc(base, port, token, "tools/call", {"name": "search_tasks",
                "arguments": {"query": f"isolated-agent-task-{len(visible)-1}"}})
            search_content = searched["result"].get("structuredContent", {})
            search_count = len(search_content.get("items", []))
            if search_count != 1:
                error_code = (search_content.get("error") or {}).get("code", "none")
                raise RuntimeError(f"per-user task search failed; code={error_code}; count={search_count}")
            preview = _rpc(base, port, token, "tools/call", {"name": "preview_schedule",
                "arguments": {"from": "2026-11-16", "to": "2026-11-20"}})
            content = preview["result"].get("structuredContent", {})
            if (not content.get("ok") or not content.get("provisional")
                    or content.get("execution_eligible") is not False):
                raise RuntimeError("planning preview did not remain provisional/read-only")
            proposals = _rpc(base, port, token, "tools/call", {
                "name":"list_plan_proposals", "arguments":{"limit":5}})
            proposal_content = proposals["result"].get("structuredContent", {})
            if not proposal_content.get("ok") or proposal_content.get("execution_eligible") is not False:
                code = (proposal_content.get("error") or {}).get("code", "none")
                raise RuntimeError(f"user proposal listing failed; code={code}")
            missing_proposal = _rpc(base, port, token, "tools/call", {
                "name":"get_plan_proposal", "arguments":{"proposal_id":str(uuid.uuid4())}})
            missing_content = missing_proposal["result"].get("structuredContent", {})
            if missing_content.get("error", {}).get("code") != "NOT_FOUND":
                raise RuntimeError("absent/foreign proposal was not concealed")
        created_ids = []
        for index, (user_id, token) in enumerate(users):
            # Same idempotency key across users verifies that confirmation state is
            # scoped by the Auth principal rather than shared globally.
            prepared = _rpc(base, port, token, "tools/call", {"name":"prepare_task_creation",
                "arguments":{"name":f"isolated-created-task-{index}",
                    "expected_duration_minutes":25,"deadline_date":"2026-11-25",
                    "idempotency_key":"same-key-for-separate-users"}})
            draft = prepared["result"].get("structuredContent", {})
            if not draft.get("ok") or draft.get("write_performed") is not False:
                error = draft.get("error") or {}
                raise RuntimeError(
                    f"task preparation did not remain a no-write draft; "
                    f"code={error.get('code', 'none')}; "
                    f"detail_keys={','.join(sorted((error.get('details') or {}).keys()))}"
                )
            if not isinstance(draft.get("confirmation_id"), str):
                raise RuntimeError(
                    f"task preparation response missing confirmation id; "
                    f"keys={','.join(sorted(draft.keys()))}; status={draft.get('status', 'none')}"
                )
            created = _rpc(base, port, token, "tools/call", {"name":"create_task",
                "arguments":{"confirmation_id":draft["confirmation_id"],
                    "user_confirmation_text":draft["confirmation_phrase"]}})
            created_payload = created["result"].get("structuredContent", {})
            if not created_payload.get("ok") or not created_payload.get("readback_verified"):
                error = created_payload.get("error") or {}
                details = error.get("details") or {}
                raise RuntimeError(
                    f"confirmed task create/readback failed; code={error.get('code', 'none')}; "
                    f"stage={details.get('table', 'unknown')}; http={details.get('http_status', 'unknown')}; "
                    f"postgrest={details.get('postgrest_code', 'unknown')}"
                )
            replay = _rpc(base, port, token, "tools/call", {"name":"create_task",
                "arguments":{"confirmation_id":draft["confirmation_id"],
                    "user_confirmation_text":draft["confirmation_phrase"]}})
            replay_payload = replay["result"].get("structuredContent", {})
            if replay_payload.get("task_id") != created_payload.get("task_id"):
                raise RuntimeError("duplicate create did not return the idempotent result")
            search_created = _rpc(base, port, token, "tools/call", {"name":"search_tasks",
                "arguments":{"query":f"isolated-created-task-{index}"}})
            if len(search_created["result"].get("structuredContent", {}).get("items", [])) != 1:
                raise RuntimeError("duplicate create produced more than one business task")
            task_id = created_payload.get("task_id")
            created_ids.append(task_id)

            update_draft = _rpc(base, port, token, "tools/call", {"name":"prepare_task_update",
                "arguments":{"task_id":task_id,"changes":{"name":f"isolated-updated-task-{index}"},
                    "idempotency_key":"same-update-key-for-separate-users"}})
            update_proposal = update_draft["result"].get("structuredContent", {})
            if not update_proposal.get("ok") or update_proposal.get("write_performed") is not False:
                error = update_proposal.get("error") or {}
                raise RuntimeError(f"task update preparation failed; code={error.get('code', 'none')}")
            if not isinstance(update_proposal.get("update_confirmation_id"), str):
                raise RuntimeError("task update preparation response missing confirmation id")
            updated = _rpc(base, port, token, "tools/call", {"name":"update_task",
                "arguments":{"update_confirmation_id":update_proposal["update_confirmation_id"],
                    "user_confirmation_text":update_proposal["confirmation_phrase"]}})
            updated_payload = updated["result"].get("structuredContent", {})
            if not updated_payload.get("ok") or not updated_payload.get("readback_verified"):
                code = (updated_payload.get("error") or {}).get("code", "none")
                raise RuntimeError(f"confirmed task update/readback failed; code={code}")

            cancel_draft = _rpc(base, port, token, "tools/call", {"name":"prepare_task_creation",
                "arguments":{"name":f"isolated-cancelled-task-{index}",
                    "expected_duration_minutes":10,"deadline_date":"2026-11-26",
                    "idempotency_key":f"cancel-key-{index}-{uuid.uuid4().hex}"}})
            cancel_proposal = cancel_draft["result"].get("structuredContent", {})
            if not isinstance(cancel_proposal.get("confirmation_id"), str):
                error = cancel_proposal.get("error") or {}
                raise RuntimeError(f"cancel draft preparation failed; code={error.get('code', 'none')}")
            cancelled = _rpc(base, port, token, "tools/call", {"name":"cancel_task_creation",
                "arguments":{"confirmation_id":cancel_proposal["confirmation_id"]}})
            if cancelled["result"].get("structuredContent", {}).get("write_performed") is not False:
                raise RuntimeError("cancelled task draft unexpectedly wrote business data")
            search_cancelled = _rpc(base, port, token, "tools/call", {"name":"search_tasks",
                "arguments":{"query":f"isolated-cancelled-task-{index}"}})
            if search_cancelled["result"].get("structuredContent", {}).get("items"):
                raise RuntimeError("cancelled task draft created a business task")
        if visible[0] != ["isolated-agent-task-0"] or visible[1] != ["isolated-agent-task-1"]:
            raise RuntimeError("RLS/account isolation assertion failed")
        cross_user = _rpc(base, port, users[1][1], "tools/call", {"name": "get_task_detail",
            "arguments": {"task_id": str(task_ids[0])}})
        cross_payload = cross_user["result"].get("structuredContent", {})
        if cross_payload.get("error", {}).get("code") != "NOT_FOUND":
            raise RuntimeError("cross-user task detail was not concealed")
        cross_created = _rpc(base, port, users[1][1], "tools/call", {"name":"get_task_detail",
            "arguments":{"task_id":str(created_ids[0])}})
        if cross_created["result"].get("structuredContent", {}).get("error", {}).get("code") != "NOT_FOUND":
            raise RuntimeError("cross-user access to newly created task was not concealed")
        print("local Supabase -> M1 /mcp/user: 2 Auth scopes isolated; read, create, duplicate replay, edit/readback, cancel, planning preview, and owner-scoped Proposal status GET passed; planning remains provisional and no Proposal was created/applied")
    finally:
        if server.poll() is None:
            server.terminate()
            server.wait(timeout=8)
        shutil.rmtree(state_dir, ignore_errors=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"integration failed: {type(exc).__name__}: {exc}", file=sys.stderr)
        raise SystemExit(1)
