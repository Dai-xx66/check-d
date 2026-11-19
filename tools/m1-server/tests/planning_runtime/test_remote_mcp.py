from datetime import datetime, timedelta, timezone
from datetime import date
from zoneinfo import ZoneInfo
from hashlib import sha256
import http.client
import json
import tempfile
from pathlib import Path
import threading
import unittest
import importlib.util
import os
from unittest.mock import patch

_M1_TOOLS_DIR = Path(__file__).resolve().parents[2] / ".." / "m1-mock"
_M1_TOOL_FILE = _M1_TOOLS_DIR.resolve() / "tool_server.py"
_saved_mock_env = {name: os.environ.pop(name, None) for name in (
    "MOCK_TASKS_FILE", "MOCK_FLAGS_FILE", "MOCK_APPROVAL_FILE")}
_legacy_spec = importlib.util.spec_from_file_location("checkd_original_m1_tool_server", _M1_TOOL_FILE)
legacy_m1 = importlib.util.module_from_spec(_legacy_spec)
_legacy_spec.loader.exec_module(legacy_m1)
for _name, _value in _saved_mock_env.items():
    if _value is not None:
        os.environ[_name] = _value

from checkd_planning_engine.remote_mcp import (
    IntrospectionTokenVerifier, RemoteMcpApplication, TestJwtAuthority,
    make_http_server,
)


class RemoteMcpTests(unittest.TestCase):
    def setUp(self):
        self.audience="https://planning.example.test/mcp"
        self.metadata_url="https://planning.example.test/.well-known/oauth-protected-resource"
        self.issuer_url="https://checkd-auth.example.test"
        self.authority=TestJwtAuthority(b"local-test-only-secret-value-for-unit-tests")
        self.provider_calls=[]
        def provider(user_id, start, end):
            self.provider_calls.append((user_id,start,end))
            return {
                "schema_version":"checkd.planning.snapshot.v1",
                "subject_ref":user_id,"source":"isolated_test_fixture",
                "captured_at":"2026-11-15T02:00:00+00:00","version":f"server-{user_id}-1",
                "sync_state":"current","provisional":False,"timezone":"Asia/Shanghai",
                "now":"2026-11-15T10:00:00+08:00","horizon_end":"2026-11-15T18:00:00+08:00",
                "tasks":[{"task_id":f"task-{user_id}","name":f"task for {user_id}",
                    "task_type":"one_time","remaining_effort_state":"known",
                    "remaining_seconds":1800,
                    "deadline_date":"2026-11-15","earliest_start":"2026-11-15T10:00:00+08:00",
                    "planned_at":"2026-11-15T09:00:00+08:00",
                    "completion_status":"pending"},
                    {"task_id":f"done-{user_id}","name":"done","completion_status":"completed"}],
                "current_plan":{"status":"confirmed","blocks":[]},
                "course_occurrences":[],"occupied_blocks":[],
                "unmodeled_recurring_occurrence_ids":[],
            }
        proposal_rows = {
            "checkd-a": [{"id":"00000000-0000-4000-8000-000000000001",
                "status":"proposed","base_version":"v-a","changes":[{"task_id":"task-a"}],
                "approval":{"id":"approval-a","status":"pending"}}],
            "checkd-b": [{"id":"00000000-0000-4000-8000-000000000002",
                "status":"applied","base_version":"v-b","changes":[{"task_id":"task-b"}],
                "approval":{"id":"approval-b","status":"consumed"}}],
        }
        def fetch_plan_proposals(identity, *, proposal_id=None, limit=20):
            rows = proposal_rows.get(identity.checkd_user_id, [])
            if proposal_id:
                rows = [row for row in rows if row["id"] == proposal_id]
            return rows[:limit]
        provider.fetch_plan_proposals = fetch_plan_proposals
        provider.fetch_legacy_tasks = lambda identity, *, statuses: [{
            "task_id": f"task-{identity.checkd_user_id}", "kind": "one_time",
            "name": "test task", "status": "active", "execution_mode": "unknown",
            "available_from": None, "planned_date": None, "scheduled_at": None,
            "deadline": None, "duration_target_seconds": None,
            "completed_today": False,
        }]
        self.app=RemoteMcpApplication(
            verifier=self.authority,audience=self.audience,snapshot_provider=provider,
            resource_metadata_url=self.metadata_url,authorization_server_url=self.issuer_url,
            legacy_module=legacy_m1,
        )
        self.server=make_http_server(self.app)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True)
        self.thread.start()
        self.addCleanup(self.server.shutdown)
        self.addCleanup(self.server.server_close)

    def token(self, checkd_user, *, subject=None, scopes=("planning:read",), expires=None,
              audience=None, token_id=None):
        return self.authority.issue(
            workbuddy_subject=subject or f"wb-{checkd_user}",checkd_user_id=checkd_user,
            audience=audience or self.audience,scopes=scopes,
            expires_at=expires if expires is not None else int(datetime.now(timezone.utc).timestamp())+3600,
            token_id=token_id,
        )

    def request(self, message, token=None, *, method="POST", path="/mcp"):
        conn=http.client.HTTPConnection(*self.server.server_address)
        headers={"Accept":"application/json, text/event-stream","Content-Type":"application/json"}
        if token is not None: headers["Authorization"]=f"Bearer {token}"
        body=json.dumps(message) if method == "POST" else None
        conn.request(method,path,body=body,headers=headers)
        response=conn.getresponse()
        raw=response.read()
        result=(response.status,{key.lower():value for key,value in response.getheaders()},raw)
        conn.close()
        return result

    def rpc(self, method, params=None, token=None, request_id=1):
        return self.request({"jsonrpc":"2.0","id":request_id,"method":method,"params":params or {}},token)

    def test_unauthorized_request_challenges_and_metadata_is_public(self):
        status,headers,body=self.rpc("tools/list")
        self.assertEqual(status,401)
        self.assertIn(self.metadata_url,headers["www-authenticate"])
        self.assertEqual(json.loads(body),{"error":"invalid_token"})

    def test_unauthorized_user_route_preserves_sharecode_in_metadata_challenge(self):
        path="/mcp/user?sharecode=share-code_123"
        status,headers,body=self.request({"jsonrpc":"2.0","id":8,
            "method":"tools/list"},path=path)
        self.assertEqual(status,401)
        self.assertIn(
            f'resource_metadata="{self.metadata_url}?sharecode=share-code_123"',
            headers["www-authenticate"])
        self.assertNotIn("sharecode",body.decode())
        status,_,body=self.request({},method="GET",
            path="/.well-known/oauth-protected-resource/mcp/user?sharecode=share-code_123")
        self.assertEqual(status,200)
        self.assertEqual(json.loads(body)["resource"],self.audience)
        status,headers,_=self.request({"jsonrpc":"2.0","id":9,
            "method":"tools/list"},path="/mcp/user?sharecode=bad%0d%0aInjected")
        self.assertEqual(status,401)
        self.assertNotIn("sharecode=",headers["www-authenticate"])
        status,_,body=self.request({},method="GET",path="/.well-known/oauth-protected-resource")
        self.assertEqual(status,200)
        metadata=json.loads(body)
        self.assertEqual(metadata["resource"],self.audience)
        self.assertEqual(metadata["authorization_servers"],[self.issuer_url])
        status,_,body=self.request({},method="GET",
            path="/.well-known/oauth-protected-resource/mcp/user")
        self.assertEqual(status,200)
        self.assertEqual(json.loads(body),metadata)
        status,headers,body=self.request({},method="GET",path="/mcp")
        self.assertEqual(status,401)
        self.assertIn(self.metadata_url,headers["www-authenticate"])
        self.assertEqual(json.loads(body),{"error":"invalid_token"})
        status,_,body=self.request({},method="GET",path="/healthz")
        self.assertEqual(status,200)
        self.assertEqual(json.loads(body)["status"],"ok")

    def test_streamable_http_initialize_and_tools_list_are_read_only(self):
        token=self.token("user-a")
        status,_,body=self.rpc("initialize",{"protocolVersion":"2025-11-25","capabilities":{},
            "clientInfo":{"name":"test-client","version":"1"}},token)
        self.assertEqual(status,200)
        self.assertEqual(json.loads(body)["result"]["protocolVersion"],"2025-11-25")
        status,_,body=self.rpc("tools/list",token=token)
        tools=json.loads(body)["result"]["tools"]
        self.assertEqual(status,200)
        contract_path = (Path(__file__).resolve().parents[2]
                         / "checkd_planning_engine/agent-planning-v0.json")
        contract = json.loads(contract_path.read_text(encoding="utf-8"))
        planning_names = {tool["name"] for tool in contract["registered_read_only_tools"]} - {"list_tasks"}
        self.assertTrue(planning_names.issubset({tool["name"] for tool in tools}))
        self.assertFalse(contract["production_ready"])
        names={x["name"] for x in tools}
        self.assertEqual(len(names),len(tools))
        self.assertEqual(len(tools),22)
        self.assertTrue({"list_tasks","search_tasks","get_tasks_by_date","list_overdue_tasks",
                         "get_task_detail","resolve_deadline","get_calendar_events",
                         "list_one_time_tasks"}.issubset(names))
        from checkd_task_agent.mcp_server import TOOLS as personal_tools
        personal_list = next(tool for tool in personal_tools if tool["name"] == "list_tasks")
        alias = next(tool for tool in tools if tool["name"] == "list_one_time_tasks")
        self.assertEqual(alias["inputSchema"], personal_list["inputSchema"])
        for original in legacy_m1.tool_defs():
            self.assertEqual(next(tool for tool in tools if tool["name"] == original["name"]), original)
        self.assertTrue(all(x["_meta"]["checkd/permission"]=="read:self"
                            for x in contract["registered_read_only_tools"] if x["name"] != "list_tasks"))

    def test_task_write_tools_are_opt_in_and_per_user_state_is_required(self):
        with self.assertRaisesRegex(ValueError, "state directory"):
            RemoteMcpApplication(verifier=self.authority,audience=self.audience,
                snapshot_provider=lambda *_: {},resource_metadata_url=self.metadata_url,
                authorization_server_url=self.issuer_url,task_writes_enabled=True)
        with tempfile.TemporaryDirectory() as state_dir:
            app=RemoteMcpApplication(verifier=self.authority,audience=self.audience,
                snapshot_provider=lambda *_: {},resource_metadata_url=self.metadata_url,
                authorization_server_url=self.issuer_url,task_writes_enabled=True,
                task_agent_state_dir=state_dir,legacy_module=legacy_m1)
        names=[tool["name"] for tool in app.tools]
        self.assertEqual(len(names),28)
        self.assertEqual(len(names),len(set(names)))
        self.assertTrue({"prepare_task_creation","create_task","prepare_task_update",
                         "update_task"}.issubset(names))

    def test_personal_list_alias_and_confirmation_ledger_are_user_scoped_after_restart(self):
        from checkd_planning_engine.remote_mcp import RemoteIdentity
        from checkd_task_agent.query_service import QueryPage

        owners = {"token-a": "user-a", "token-b": "user-b"}
        writes = []

        class Repository:
            def __init__(self, *, user_access_token, **_kwargs):
                self.owner = owners[user_access_token]

            def authenticated_user_id(self):
                return self.owner

            def list_one_time_tasks(self, *, include_completed, limit, offset):
                return QueryPage([{"task_id": self.owner, "name": self.owner}], None)

            def create_and_verify(self, draft, *, task_id, now):
                writes.append((self.owner, task_id))
                return {"task_id": task_id, "name": draft.name}

        def identity(owner):
            return RemoteIdentity(owner, "test-" + owner,
                                  frozenset({"planning:read", "task:write"}),
                                  2**31, "token-a" if owner == "user-a" else "token-b")

        with tempfile.TemporaryDirectory() as state_dir, patch(
                "checkd_planning_engine.remote_mcp.SupabaseTaskRepository", Repository):
            def app():
                return RemoteMcpApplication(
                    verifier=self.authority, audience=self.audience,
                    snapshot_provider=lambda *_: {},
                    resource_metadata_url=self.metadata_url,
                    authorization_server_url=self.issuer_url,
                    supabase_url="https://supabase.invalid",
                    supabase_publishable_key="public-test-key",
                    task_writes_enabled=True, task_agent_state_dir=state_dir,
                    legacy_module=legacy_m1)

            first = app()
            for owner in ("user-a", "user-b"):
                listed = first._call_tool(identity(owner), "list_one_time_tasks", {})
                self.assertEqual(listed["items"][0]["task_id"], owner)
            a = first._call_tool(identity("user-a"), "prepare_task_creation", {
                "name": "A task", "expected_duration_minutes": 60,
                "deadline_date": "2099-01-01", "idempotency_key": "same-key"})
            b = first._call_tool(identity("user-b"), "prepare_task_creation", {
                "name": "B task", "expected_duration_minutes": 30,
                "deadline_date": "2099-01-01", "idempotency_key": "same-key"})
            self.assertTrue(a["ok"])
            self.assertTrue(b["ok"])
            self.assertNotEqual(a["confirmation_id"], b["confirmation_id"])
            denied = first._call_tool(identity("user-b"), "create_task", {
                "confirmation_id": a["confirmation_id"],
                "user_confirmation_text": a["confirmation_phrase"]})
            self.assertFalse(denied["ok"])
            self.assertEqual(writes, [])
            restarted = app()
            created = restarted._call_tool(identity("user-a"), "create_task", {
                "confirmation_id": a["confirmation_id"],
                "user_confirmation_text": a["confirmation_phrase"]})
            self.assertTrue(created["readback_verified"])
            replay = restarted._call_tool(identity("user-a"), "create_task", {
                "confirmation_id": a["confirmation_id"],
                "user_confirmation_text": a["confirmation_phrase"]})
            self.assertEqual(replay["task_id"], created["task_id"])
            self.assertEqual(len(writes), 1)

    def test_original_seven_tools_keep_envelope_schema_and_route_to_scoped_handlers(self):
        from checkd_planning_engine.remote_mcp import RemoteIdentity
        expected = {tool["name"]: tool for tool in legacy_m1.tool_defs()}
        actual = {tool["name"]: tool for tool in self.app.tools
                  if tool["name"] in expected}
        self.assertEqual(actual, expected)
        self.assertEqual(set(actual), {
            "list_tasks", "get_calendar_events", "generate_schedule",
            "validate_schedule", "apply_approved_changes", "request_approval",
            "get_approval_status",
        })
        identity = RemoteIdentity("checkd-a", "supabase-auth:checkd-a",
            frozenset({"planning:read"}), 2**31, "request-scoped-user-token")
        legacy_list = {
            "api_version": "checkd.agent.v1", "request_id": "legacy-list-1",
            "timezone": "Asia/Shanghai", "input": {
                "date_range": {"start": "2026-11-15", "end": "2026-11-15"},
                "kinds": ["one_time"], "statuses": ["active"],
            },
        }
        listed = self.app._call_tool(identity, "list_tasks", legacy_list)
        self.assertEqual(listed["status"], "success")
        self.assertEqual(listed["request_id"], "legacy-list-1")
        self.assertEqual(listed["data"]["tasks"][0]["task_id"], "task-checkd-a")
        self.assertNotIn("checkd-b", json.dumps(listed))

        # The same exact v1 envelope is accepted at the mounted route path too.
        status, _, body = self.app.dispatch_http(method="POST", path="/mcp/user", headers={
            "authorization": f"Bearer {self.token('checkd-a')}",
            "accept": "application/json, text/event-stream",
            "content-type": "application/json",
        }, body=json.dumps({"jsonrpc":"2.0","id":91,"method":"tools/call",
            "params":{"name":"list_tasks","arguments":legacy_list}}).encode())
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["result"]["structuredContent"]["status"], "success")

        preview_args = {
            "api_version": "checkd.agent.v1", "request_id": "legacy-preview-1",
            "timezone": "Asia/Shanghai", "input": {
                "date_range": {"start": "2026-11-15", "end": "2026-11-15"},
            },
        }
        preview = self.app._call_tool(identity, "generate_schedule", preview_args)
        self.assertEqual(preview["status"], "success")
        self.assertEqual(preview["data"]["proposal_status"], "preview_only")
        self.assertFalse(preview["execution_eligible"])
        for name, inputs, code in (
            ("request_approval", {"proposal_id":"p","idempotency_key":"i"}, "WRITE_BLOCKED"),
            ("apply_approved_changes", {"proposal_id":"p","base_version":"v",
                "approval_token":"never-accept-demo-token","idempotency_key":"i"}, "WRITE_BLOCKED"),
        ):
            result = self.app._call_tool(identity, name, {
                "api_version":"checkd.agent.v1", "request_id":f"{name}-1",
                "timezone":"Asia/Shanghai", "input":inputs,
            })
            self.assertEqual(result["error"]["code"], code)
            self.assertFalse(result["execution_eligible"])

    def test_legacy_schema_rejects_unknown_nested_fields_and_never_uses_demo_fallback(self):
        identity = self.token("checkd-a")
        bad = {"api_version":"checkd.agent.v1", "request_id":"bad-1",
            "timezone":"Asia/Shanghai", "input":{
                "date_range":{"start":"2026-11-15","end":"2026-11-15",
                               "user_id":"checkd-b"}}}
        status, _, body = self.rpc("tools/call", {"name":"list_tasks","arguments":bad}, identity)
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["error"]["code"], -32602)
        self.assertEqual(self.provider_calls, [])

    def test_expired_token_is_rejected_and_calendar_query_uses_authenticated_snapshot(self):
        expired = self.token("checkd-a", expires=int(datetime.now(timezone.utc).timestamp()))
        status,headers,body=self.rpc("tools/list",token=expired)
        self.assertEqual(status,401)
        self.assertIn('error="invalid_token"',headers["www-authenticate"])
        self.assertEqual(json.loads(body),{"error":"invalid_token"})

        token=self.token("checkd-a")
        original_provider=self.app.snapshot_provider
        def calendar_provider(user, start, end):
            snapshot=original_provider(user, start, end)
            snapshot["course_occurrences"]=[{
                "occurrence_id":"occ-1","course_id":"course-a",
                "starts_at":"2026-11-15T10:00:00+08:00",
                "ends_at":"2026-11-15T11:00:00+08:00","kind":"course"}]
            return snapshot
        self.app.snapshot_provider=calendar_provider
        legacy_calendar = {"api_version":"checkd.agent.v1", "request_id":"calendar-1",
            "timezone":"Asia/Shanghai", "input":{
                "date_range":{"start":"2026-11-15","end":"2026-11-15"}}}
        status,_,body=self.rpc("tools/call",{
            "name":"get_calendar_events",
            "arguments":legacy_calendar,
        },token)
        result=json.loads(body)["result"]["structuredContent"]["data"]
        self.assertEqual(status,200)
        self.assertEqual(result["events"][0]["occurrence_id"],"occ-1")
        self.assertEqual(result["events"][0]["starts_at"],
                         "2026-11-15T10:00:00+08:00")
        self.assertEqual(self.provider_calls[-1],("checkd-a","2026-11-15","2026-11-15"))

        status,_,body=self.rpc("tools/call",{
            "name":"get_calendar_events",
            "arguments": {**legacy_calendar, "input": {
                "date_range":{"start":"2026-11-15","end":"2026-11-15",
                               "user_id":"checkd-b"}}},
        },token)
        self.assertEqual(status,200)
        self.assertEqual(json.loads(body)["error"]["code"],-32602)
        self.assertEqual(self.provider_calls[-1],("checkd-a","2026-11-15","2026-11-15"))

    def test_recursive_schema_validation_accepts_declared_null_and_rejects_nested_extras(self):
        nullable = {"type":"object","properties":{"planned_at":{"type":["string","null"]}},
                    "required":["planned_at"],"additionalProperties":False}
        self.assertTrue(RemoteMcpApplication._valid_schema_value(nullable,{"planned_at":None}))
        calendar = next(tool for tool in self.app.tools if tool["name"]=="get_calendar_events")
        nested = calendar["inputSchema"]["properties"]["input"]["properties"]["date_range"]
        self.assertFalse(RemoteMcpApplication._valid_schema_value(nested,{
            "start":"2026-11-15","end":"2026-11-15","user_id":"other-user"}))

    def test_task_write_requires_verified_write_scope(self):
        with tempfile.TemporaryDirectory() as state_dir:
            app=RemoteMcpApplication(verifier=self.authority,audience=self.audience,
                snapshot_provider=lambda *_: {},resource_metadata_url=self.metadata_url,
                authorization_server_url=self.issuer_url,supabase_url="https://db.invalid",
                supabase_publishable_key="public-test-key",task_writes_enabled=True,
                task_agent_state_dir=state_dir)
            principal=type("Principal",(),{
                "access_token":"local-user-token","checkd_user_id":"user-a",
                "scopes":frozenset({"planning:read"})})()
            result=app._call_tool(principal,"prepare_task_creation",{
                "name":"test","expected_duration_minutes":30,
                "idempotency_key":"write-scope-test"})
        self.assertEqual(result["error"]["code"],"INSUFFICIENT_SCOPE")

    def test_shared_endpoint_keeps_user_snapshots_and_workbuddy_subjects_separate(self):
        ta=self.token("checkd-a",subject="workbuddy-101")
        tb=self.token("checkd-b",subject="workbuddy-202")
        status,_,body=self.rpc("tools/call",{"name":"get_planning_context","arguments":{"from":"2026-11-15","to":"2026-11-15"}},ta)
        a=json.loads(body)["result"]["structuredContent"]
        status2,_,body2=self.rpc("tools/call",{"name":"get_planning_context","arguments":{"from":"2026-11-15","to":"2026-11-15"}},tb)
        b=json.loads(body2)["result"]["structuredContent"]
        self.assertEqual((status,status2),(200,200))
        self.assertEqual(a["snapshot"]["subject_ref"],"checkd-a")
        self.assertEqual(b["snapshot"]["subject_ref"],"checkd-b")
        self.assertEqual(self.provider_calls,[
            ("checkd-a","2026-11-15","2026-11-15"),
            ("checkd-b","2026-11-15","2026-11-15"),
        ])

    def test_new_read_tools_are_user_scoped_and_adjustment_draft_is_non_persistent(self):
        token_a=self.token("checkd-a")
        token_b=self.token("checkd-b")
        for token, expected_user in ((token_a,"checkd-a"),(token_b,"checkd-b")):
            status,_,body=self.rpc("tools/call",{"name":"get_current_plan","arguments":{
                "from":"2026-11-15","to":"2026-11-15"}},token)
            plan=json.loads(body)["result"]["structuredContent"]
            self.assertEqual(plan["current_plan"]["status"],"confirmed")
            self.assertFalse(plan["execution_eligible"])

            status,_,body=self.rpc("tools/call",{"name":"check_schedule_feasibility","arguments":{
                "from":"2026-11-15","to":"2026-11-15"}},token)
            feasibility=json.loads(body)["result"]["structuredContent"]
            self.assertEqual(feasibility["operation"],"feasibility")
            self.assertFalse(feasibility["execution_eligible"])

            status,_,body=self.rpc("tools/call",{"name":"generate_adjustment_draft","arguments":{
                "from":"2026-11-15","to":"2026-11-15"}},token)
            draft=json.loads(body)["result"]["structuredContent"]
            self.assertEqual(draft["draft"],{"status":"preview_only","persistent":False,
                "approval_required_before_write":True})
            self.assertFalse(draft["execution_eligible"])
        self.assertEqual(self.provider_calls,[("checkd-a","2026-11-15","2026-11-15")]*3 +
                         [("checkd-b","2026-11-15","2026-11-15")]*3)

    def test_list_plan_risks_reads_only_the_authenticated_users_snapshot(self):
        for user in ("checkd-a", "checkd-b"):
            status,_,body=self.rpc("tools/call",{"name":"list_plan_risks","arguments":{
                "from":"2026-11-15","to":"2026-11-15"}},self.token(user))
            result=json.loads(body)["result"]["structuredContent"]
            self.assertEqual(status,200)
            self.assertTrue(result["ok"])
            self.assertIn("risks",result)
            self.assertTrue(result["risks"])
            self.assertTrue(all(
                task_id.startswith(f"task-{user}")
                for risk in result["risks"] for task_id in risk["affected_task_ids"]
            ))
            self.assertFalse(result["execution_eligible"])

    def test_proposal_status_tools_are_user_scoped_and_never_accept_user_id(self):
        from checkd_planning_engine.remote_mcp import RemoteIdentity
        principal_a=RemoteIdentity("checkd-a","wb-a",frozenset({"planning:read"}),
                                    2**31,"test-user-jwt-a")
        principal_b=RemoteIdentity("checkd-b","wb-b",frozenset({"planning:read"}),
                                    2**31,"test-user-jwt-b")
        listed=self.app._call_tool(principal_a,"list_plan_proposals",{})
        self.assertTrue(listed["ok"])
        self.assertEqual(listed["items"][0]["id"],"00000000-0000-4000-8000-000000000001")
        self.assertFalse(listed["execution_eligible"])

        foreign="00000000-0000-4000-8000-000000000002"
        hidden=self.app._call_tool(principal_a,"get_plan_proposal",{"proposal_id":foreign})
        self.assertFalse(hidden["ok"])
        self.assertEqual(hidden["error"]["code"],"NOT_FOUND")

        own=self.app._call_tool(principal_b,"get_plan_proposal",{"proposal_id":foreign})
        self.assertTrue(own["ok"])
        self.assertEqual(own["proposal"]["approval"]["status"],"consumed")

        rejected=self.app._call_tool(principal_a,"get_plan_proposal",{"proposal_id":foreign,
            "user_id":"checkd-b"})
        self.assertEqual(rejected["error"]["code"],"INVALID_INPUT")

    def test_misbound_snapshot_is_rejected_for_every_tool(self):
        def misbound(user_id, start, end):
            return {"subject_ref":"another-user","tasks":[]}
        app=RemoteMcpApplication(verifier=self.authority,audience=self.audience,
            snapshot_provider=misbound,resource_metadata_url=self.metadata_url,
            authorization_server_url=self.issuer_url)
        token=self.token("user-a")
        for name in ("get_current_plan","preview_schedule",
                     "check_schedule_feasibility","generate_adjustment_draft","list_plan_risks"):
            status,_,body=app.dispatch_http(method="POST",path="/mcp",headers={
                "accept":"application/json, text/event-stream","content-type":"application/json",
                "authorization":f"Bearer {token}"},body=json.dumps({"jsonrpc":"2.0","id":1,
                "method":"tools/call","params":{"name":name,"arguments":{
                    "from":"2026-11-15","to":"2026-11-15"}}}).encode())
            response=json.loads(body)["result"]["structuredContent"]
            self.assertEqual(status,200)
            self.assertEqual(response["error"]["code"],"NOT_FOUND")

    def test_user_id_argument_and_cross_user_task_are_rejected_without_leak(self):
        token=self.token("checkd-b")
        before=len(self.provider_calls)
        status,_,body=self.rpc("tools/call",{"name":"preview_schedule","arguments":{
            "from":"2026-11-15","to":"2026-11-15","user_id":"checkd-a"}},token)
        self.assertEqual(status,200)
        self.assertEqual(json.loads(body)["error"]["code"],-32602)
        self.assertEqual(len(self.provider_calls),before)
        status,_,body=self.rpc("tools/call",{"name":"simulate_task_delay","arguments":{
            "task_id":"task-checkd-a","until":"2026-11-15T13:00:00+08:00",
            "from":"2026-11-15","to":"2026-11-15"}},token)
        call=json.loads(body)["result"]["structuredContent"]
        self.assertEqual(status,200)
        self.assertEqual(call["error"]["code"],"NOT_FOUND")
        self.assertNotIn("task-checkd-a",json.dumps(call))

    def test_bad_dates_and_timezone_less_delay_are_rejected_before_planning(self):
        token=self.token("checkd-a")
        before=len(self.provider_calls)
        status,_,body=self.rpc("tools/call",{"name":"get_planning_context","arguments":{
            "from":"20261115","to":"2026-11-15"}},token)
        self.assertEqual(status,200)
        self.assertEqual(json.loads(body)["result"]["structuredContent"]["error"]["code"],"INVALID_INPUT")
        self.assertEqual(len(self.provider_calls),before)
        status,_,body=self.rpc("tools/call",{"name":"simulate_task_delay","arguments":{
            "task_id":"task-checkd-a","until":"2026-11-15T13:00:00",
            "from":"2026-11-15","to":"2026-11-15"}},token)
        self.assertEqual(status,200)
        self.assertEqual(json.loads(body)["result"]["structuredContent"]["error"]["code"],"INVALID_INPUT")
        self.assertEqual(len(self.provider_calls),before)

    def test_expired_revoked_wrong_audience_and_missing_scope_fail_closed(self):
        now=int(datetime.now(timezone.utc).timestamp())
        expired=self.token("user-a",expires=now)
        self.assertEqual(self.rpc("tools/list",token=expired)[0],401)
        revoked=self.token("user-a",token_id="revoke-me")
        self.authority.revoke("revoke-me")
        self.assertEqual(self.rpc("tools/list",token=revoked)[0],401)
        wrong_aud=self.token("user-a",audience="https://other.example.test/mcp")
        self.assertEqual(self.rpc("tools/list",token=wrong_aud)[0],401)
        no_scope=self.token("user-a",scopes=("profile:read",))
        status,headers,body=self.rpc("tools/list",token=no_scope)
        self.assertEqual(status,403)
        self.assertIn("insufficient_scope",headers["www-authenticate"])
        self.assertEqual(json.loads(body)["error"],"insufficient_scope")

    def test_invalid_signature_rejected_and_token_not_in_response(self):
        token=self.token("user-a")+"x"
        status,_,body=self.rpc("tools/list",token=token)
        self.assertEqual(status,401)
        self.assertNotIn(token.encode(),body)

    def test_introspection_adapter_requires_active_expiry_audience_and_binding(self):
        claims={"active":True,"iss":"https://workbuddy.example/tenant","sub":"workbuddy-user",
                "tid":"tenant-a","checkd_uid":"spoofed-claim-is-ignored",
                "aud":[self.audience],"exp":int(datetime.now(timezone.utc).timestamp())+100,
                "scope":"planning:read"}
        class BindingResolver:
            def resolve(self, *, issuer, subject, tenant_id):
                self.last=(issuer,subject,tenant_id)
                return "checkd-user" if (issuer,subject,tenant_id)==(
                    "https://workbuddy.example/tenant","workbuddy-user","tenant-a") else None
        bindings=BindingResolver()
        verifier=IntrospectionTokenVerifier(lambda token:claims if token=="opaque" else None,bindings)
        identity=verifier.verify("opaque",audience=self.audience,now=datetime.now(timezone.utc))
        self.assertEqual(identity.workbuddy_subject,"workbuddy-user")
        self.assertEqual(identity.checkd_user_id,"checkd-user")
        self.assertEqual(bindings.last,("https://workbuddy.example/tenant","workbuddy-user","tenant-a"))
        claims["exp"]=int(datetime.now(timezone.utc).timestamp())
        with self.assertRaises(PermissionError):
            verifier.verify("opaque",audience=self.audience,now=datetime.now(timezone.utc))
        claims["exp"]=int(datetime.now(timezone.utc).timestamp())+100
        claims["sub"]="unbound-workbuddy-user"
        with self.assertRaises(PermissionError):
            verifier.verify("opaque",audience=self.audience,now=datetime.now(timezone.utc))

    def _proposal_app(self, *, blocked=False):
        from checkd_planning_engine.remote_mcp import RemoteIdentity
        test_user_id="11111111-1111-4111-8111-111111111111"
        now = datetime.now(ZoneInfo("Asia/Shanghai")) + timedelta(minutes=1)
        today = now.date()
        snapshot = {
            "schema_version":"checkd.planning.snapshot.v1",
            "subject_ref":test_user_id,"source":"isolated_test_fixture",
            "captured_at":now.isoformat(),"version":"content-v1","sync_state":"current",
            "provisional":False,"timezone":"Asia/Shanghai","now":now.isoformat(),
            "horizon_end":(now+timedelta(hours=5)).isoformat(),
            "tasks":[{"task_id":"task-a","name":"E2E task","task_type":"one_time",
                "remaining_effort_state":"known","remaining_seconds":3600,
                "deadline_date":(today+timedelta(days=1)).isoformat(),
                "earliest_start":(now+timedelta(minutes=5)).isoformat(),
                "planned_at":None,"completion_status":"pending"}],
            "course_occurrences":[],"occupied_blocks":[],"unmodeled_recurring_occurrence_ids":[],
            "planning_ready":not blocked,"readiness_blockers":["device_checkpoint_conflict"] if blocked else [],
            "planning_blockers":[],"source_snapshot_version":"trusted-snapshot-v1",
            "course_occurrence_digest":"course-digest-v1",
        }

        class Provider:
            def __init__(self):
                self.snapshot=snapshot
                self.create_calls=[]
                self.request_calls=[]
                self.bound={}
                self.decisions=[]
                self.write_count=0
                self.approval_id="00000000-0000-4000-8000-000000000031"
                self.proposal_id="00000000-0000-4000-8000-000000000032"

            def fetch_authenticated(self, principal, start, end):
                return {**self.snapshot,"subject_ref":principal.checkd_user_id}

            def create_plan_proposal(self, identity, **kwargs):
                self.create_calls.append((identity.checkd_user_id,kwargs))
                return {"ok":True,"replayed":False,"proposal":{
                    "id":self.proposal_id,"user_id":identity.checkd_user_id,
                    "source_snapshot_version":kwargs["snapshot_version"],
                    "changes":kwargs["changes"],"status":"proposed"}}

            def request_plan_approval(self, identity, proposal_id, idempotency_key):
                self.request_calls.append((identity.checkd_user_id,proposal_id,idempotency_key))
                return {"ok":True,"approval_id":self.approval_id,"proposal_id":proposal_id,
                    "status":"pending","expires_at":(datetime.now(timezone.utc)+timedelta(minutes=5)).isoformat(),
                    "replayed":bool(len(self.request_calls)>1)}

            def bind_plan_approval_token(self, identity, approval_id, token_digest):
                self.bound[approval_id]=token_digest
                return {"ok":True}

            def get_plan_approval_preview(self, approval_id, token_digest):
                if self.bound.get(approval_id)!=token_digest:
                    return {"ok":False,"code":"APPROVAL_UNAVAILABLE"}
                return {"ok":True,"user_id":test_user_id,
                    "proposal_id":self.proposal_id,"changes":[{
                    "task_name":"E2E task","starts_at":"2026-11-18T10:00:00+08:00",
                    "ends_at":"2026-11-18T11:00:00+08:00","planned_seconds":3600}],
                    "risk_summary":[],"buffer_minutes":None}

            def decide_plan_proposal(self, approval_id, token_digest, decision):
                if self.bound.get(approval_id)!=token_digest:
                    return {"ok":False,"code":"APPROVAL_UNTRUSTED"}
                self.decisions.append(decision)
                if decision=="approve" and not self.write_count:
                    self.write_count=1
                result={"ok":True,"proposal_id":self.proposal_id,
                    "proposal_status":"applied" if decision=="approve" else "rejected",
                    "write_count":self.write_count if decision=="approve" else 0,
                    "readback_verified":decision=="approve"}
                return result

        provider=Provider()
        app=RemoteMcpApplication(verifier=self.authority,audience=self.audience,
            snapshot_provider=provider,resource_metadata_url=self.metadata_url,
            authorization_server_url=self.issuer_url,proposal_writes_enabled=True,
            approval_signing_key=b"isolated-test-signing-key-at-least-32-bytes",
            approval_base_url="https://isolated.example.test", legacy_module=legacy_m1)
        identity=RemoteIdentity(test_user_id,"test-subject",
            frozenset({"planning:read","planning:propose"}),2**31,"user-jwt")
        return app,provider,identity

    def test_proposal_tools_are_opt_in_and_do_not_duplicate_existing_tools(self):
        names=[tool["name"] for tool in self.app.tools]
        self.assertNotIn("create_plan_proposal",names)
        app,_,_=self._proposal_app()
        names=[tool["name"] for tool in app.tools]
        self.assertIn("create_plan_proposal",names)
        self.assertIn("request_plan_approval",names)
        self.assertEqual(len(names),len(set(names)))
        self.assertEqual(names.count("list_tasks"),1)

    def test_proposal_creation_uses_verified_identity_and_rejects_unready_snapshot(self):
        app,provider,identity=self._proposal_app(blocked=True)
        denied=app._call_tool(identity,"create_plan_proposal",{
            "from":date.today().isoformat(),"to":(date.today()+timedelta(days=1)).isoformat(),
            "idempotency_key":"proposal-request-0001"})
        self.assertFalse(denied["ok"])
        self.assertEqual(denied["error"]["code"],"PLANNING_NOT_READY")
        self.assertEqual(provider.create_calls,[])

        app,provider,identity=self._proposal_app()
        created=app._call_tool(identity,"create_plan_proposal",{
            "from":date.today().isoformat(),"to":(date.today()+timedelta(days=1)).isoformat(),
            "idempotency_key":"proposal-request-0002"})
        self.assertTrue(created["ok"],created)
        self.assertFalse(created["execution_eligible"])
        self.assertTrue(created["approval_required_before_write"])
        user_id,request=provider.create_calls[0]
        self.assertEqual(user_id,identity.checkd_user_id)
        self.assertEqual(request["snapshot_version"],"trusted-snapshot-v1")
        self.assertEqual(request["course_digest"],"course-digest-v1")
        self.assertEqual(len(request["changes"]),1)
        self.assertEqual(request["changes"][0]["task_id"],"task-a")

    def test_proposal_creation_requires_propose_scope_and_rejects_user_id(self):
        app,provider,identity=self._proposal_app()
        no_scope=type("Identity",(),{"checkd_user_id":identity.checkd_user_id,
            "workbuddy_subject":"x","scopes":frozenset({"planning:read"}),
            "expires_at":identity.expires_at,"access_token":"user-jwt"})()
        result=app._call_tool(no_scope,"create_plan_proposal",{
            "from":date.today().isoformat(),"to":(date.today()+timedelta(days=1)).isoformat(),
            "idempotency_key":"proposal-request-0003"})
        self.assertEqual(result["error"]["code"],"INSUFFICIENT_SCOPE")
        self.assertEqual(provider.create_calls,[])
        token=self.token("checkd-user-a",scopes=("planning:read","planning:propose"))
        status,_,body=self.rpc("tools/call",{"name":"create_plan_proposal","arguments":{
            "from":date.today().isoformat(),"to":(date.today()+timedelta(days=1)).isoformat(),
            "idempotency_key":"proposal-request-0004","user_id":"victim"}},token)
        self.assertEqual(status,200)
        self.assertEqual(json.loads(body)["error"]["code"],-32602)

    def test_one_time_approval_page_binds_proposal_and_decision_and_does_not_expose_token(self):
        app,provider,identity=self._proposal_app()
        created=app._call_tool(identity,"create_plan_proposal",{
            "from":date.today().isoformat(),"to":(date.today()+timedelta(days=1)).isoformat(),
            "idempotency_key":"proposal-request-0005"})
        approval=app._call_tool(identity,"request_plan_approval",{
            "proposal_id":created["proposal"]["id"],"idempotency_key":"approval-request-0005"})
        self.assertTrue(approval["ok"],approval)
        self.assertIn("#",approval["approval_url"])
        token=approval["approval_url"].split("#",1)[1]
        digest=sha256(token.encode("ascii")).hexdigest()
        self.assertEqual(provider.bound[approval["approval_id"]],digest)
        status,headers,page=app.dispatch_http(method="GET",
            path=f"/approval/{approval['approval_id']}",headers={},body=b"")
        self.assertEqual(status,200)
        self.assertEqual(headers["Cache-Control"],"no-store")
        self.assertEqual(headers["Referrer-Policy"],"no-referrer")
        self.assertNotIn(token.encode(),page)
        status,_,preview=app.dispatch_http(method="POST",
            path=f"/approval/{approval['approval_id']}/preview",
            headers={"content-type":"application/json"},
            body=json.dumps({"token":token}).encode())
        self.assertEqual(status,200)
        self.assertEqual(json.loads(preview)["proposal_id"],created["proposal"]["id"])
        status,_,applied=app.dispatch_http(method="POST",
            path=f"/approval/{approval['approval_id']}",
            headers={"content-type":"application/json"},
            body=json.dumps({"token":token,"decision":"approve"}).encode())
        self.assertEqual(status,200)
        self.assertTrue(json.loads(applied)["readback_verified"])
        self.assertEqual(provider.write_count,1)
        status,_,replayed=app.dispatch_http(method="POST",
            path=f"/approval/{approval['approval_id']}",
            headers={"content-type":"application/json"},
            body=json.dumps({"token":token,"decision":"approve"}).encode())
        self.assertEqual(status,200)
        self.assertEqual(provider.write_count,1)

    def test_reject_and_expired_or_wrong_proposal_capability_do_not_apply(self):
        app,provider,identity=self._proposal_app()
        created=app._call_tool(identity,"create_plan_proposal",{
            "from":date.today().isoformat(),"to":(date.today()+timedelta(days=1)).isoformat(),
            "idempotency_key":"proposal-request-0006"})
        approval=app._call_tool(identity,"request_plan_approval",{
            "proposal_id":created["proposal"]["id"],"idempotency_key":"approval-request-0006"})
        token=approval["approval_url"].split("#",1)[1]
        status,_,body=app.dispatch_http(method="POST",
            path=f"/approval/{approval['approval_id']}",
            headers={"content-type":"application/json"},
            body=json.dumps({"token":token,"decision":"reject"}).encode())
        self.assertEqual(status,200)
        self.assertEqual(json.loads(body)["write_count"],0)
        self.assertEqual(provider.write_count,0)
        self.assertEqual(provider.decisions,["reject"])

        wrong_app,_,_=self._proposal_app()
        wrong_app.approval_signing_key=b"a-different-isolated-key-at-least-32-bytes!"
        status,_,body=wrong_app.dispatch_http(method="POST",
            path=f"/approval/{approval['approval_id']}",
            headers={"content-type":"application/json"},
            body=json.dumps({"token":token,"decision":"approve"}).encode())
        self.assertEqual(status,410)
        status,_,body=app.dispatch_http(method="POST",
            path=f"/approval/{approval['approval_id']}",
            headers={"content-type":"application/json"},
            body=json.dumps({"token":token,"decision":"approve"}).encode(),
            now=datetime.now(timezone.utc)+timedelta(minutes=6))
        self.assertEqual(status,410)
        self.assertEqual(provider.write_count,0)
if __name__ == "__main__":
    unittest.main()
