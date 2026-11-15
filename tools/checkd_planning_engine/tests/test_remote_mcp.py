from datetime import datetime, timedelta, timezone
import http.client
import json
import threading
import unittest

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
                "tasks":[{"task_id":f"task-{user_id}","remaining_seconds":1800,
                    "deadline_date":"2026-11-15","earliest_start":"2026-11-15T10:00:00+08:00",
                    "completion_status":"pending"}],
                "course_occurrences":[],"occupied_blocks":[],
                "unmodeled_recurring_occurrence_ids":[],
            }
        self.app=RemoteMcpApplication(
            verifier=self.authority,audience=self.audience,snapshot_provider=provider,
            resource_metadata_url=self.metadata_url,authorization_server_url=self.issuer_url,
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
        status,_,body=self.request({},method="GET",path="/.well-known/oauth-protected-resource")
        self.assertEqual(status,200)
        metadata=json.loads(body)
        self.assertEqual(metadata["resource"],self.audience)
        self.assertEqual(metadata["authorization_servers"],[self.issuer_url])

    def test_streamable_http_initialize_and_tools_list_are_read_only(self):
        token=self.token("user-a")
        status,_,body=self.rpc("initialize",{"protocolVersion":"2025-11-25","capabilities":{},
            "clientInfo":{"name":"test-client","version":"1"}},token)
        self.assertEqual(status,200)
        self.assertEqual(json.loads(body)["result"]["protocolVersion"],"2025-11-25")
        status,_,body=self.rpc("tools/list",token=token)
        tools=json.loads(body)["result"]["tools"]
        self.assertEqual(status,200)
        self.assertEqual({x["name"] for x in tools},{"get_planning_context","preview_schedule","simulate_task_delay","list_plan_risks"})
        self.assertTrue(all(x["_meta"]["checkd/permission"]=="read:self" for x in tools))

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
        claims={"active":True,"sub":"workbuddy-user","checkd_uid":"checkd-user",
                "aud":[self.audience],"exp":int(datetime.now(timezone.utc).timestamp())+100,
                "scope":"planning:read"}
        verifier=IntrospectionTokenVerifier(lambda token:claims if token=="opaque" else None)
        identity=verifier.verify("opaque",audience=self.audience,now=datetime.now(timezone.utc))
        self.assertEqual(identity.workbuddy_subject,"workbuddy-user")
        self.assertEqual(identity.checkd_user_id,"checkd-user")
        claims["exp"]=int(datetime.now(timezone.utc).timestamp())
        with self.assertRaises(PermissionError):
            verifier.verify("opaque",audience=self.audience,now=datetime.now(timezone.utc))


if __name__ == "__main__":
    unittest.main()
