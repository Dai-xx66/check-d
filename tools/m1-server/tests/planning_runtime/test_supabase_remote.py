import base64
from datetime import datetime, timezone
import json
import os
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlparse

from checkd_planning_engine.remote_mcp import RemoteIdentity
from checkd_planning_engine.supabase_remote import (
    SupabaseAccessTokenVerifier, SupabaseRestSnapshotProvider,
    build_remote_application_from_env,
)


class Response:
    def __init__(self, status, value):
        self.status = status
        self.raw = json.dumps(value).encode()
    def __enter__(self): return self
    def __exit__(self, *args): return None
    def read(self, size=-1): return self.raw[:size]


def test_token(user_id="user-a", now=None, **extra):
    now = now or int(datetime.now(timezone.utc).timestamp())
    encode = lambda obj: base64.urlsafe_b64encode(
        json.dumps(obj, separators=(",", ":")).encode()).decode().rstrip("=")
    claims = {'sub':user_id,'aud':'authenticated','role':'authenticated','exp':now+300,**extra}
    return f"{encode({'alg':'RS256','typ':'JWT'})}.{encode(claims)}.signature"


class SupabaseRemoteTests(unittest.TestCase):
    def test_auth_user_endpoint_is_authoritative_and_token_not_in_identity_repr(self):
        token = test_token()
        seen = {}
        def opener(request, timeout):
            seen["url"] = request.full_url
            seen["authorization"] = request.get_header("Authorization")
            seen["apikey"] = request.get_header("Apikey")
            return Response(200, {"id":"user-a"})
        verifier = SupabaseAccessTokenVerifier(supabase_url="https://supabase.test",
            publishable_key="public-test-key", opener=opener)
        identity = verifier.verify(token, audience="https://mcp.test/mcp",
            now=datetime.now(timezone.utc))
        self.assertEqual(identity.checkd_user_id, "user-a")
        self.assertEqual(identity.access_token, token)
        self.assertNotIn(token, repr(identity))
        self.assertEqual(seen["url"], "https://supabase.test/auth/v1/user")
        self.assertEqual(seen["authorization"], f"Bearer {token}")
        self.assertEqual(seen["apikey"], "public-test-key")

    def test_auth_subject_mismatch_fails_closed(self):
        verifier = SupabaseAccessTokenVerifier(supabase_url="https://supabase.test",
            publishable_key="public-test-key", opener=lambda *_args, **_kwargs:
                Response(200, {"id":"user-b"}))
        with self.assertRaises(PermissionError):
            verifier.verify(test_token("user-a"), audience="https://mcp.test/mcp",
                            now=datetime.now(timezone.utc))

    def test_oauth_client_and_issuer_are_allowlisted(self):
        verifier = SupabaseAccessTokenVerifier(supabase_url="https://supabase.test",
            publishable_key="public-test-key", expected_issuer="https://supabase.test/auth/v1",
            allowed_oauth_client_ids=frozenset({"workbuddy-client"}),
            opener=lambda *_args, **_kwargs: Response(200, {"id":"user-a"}))
        token = test_token(iss="https://supabase.test/auth/v1",client_id="workbuddy-client")
        verified = verifier.verify(token, audience="https://mcp.test/mcp",
                                   now=datetime.now(timezone.utc))
        self.assertEqual(verified.checkd_user_id, "user-a")
        with self.assertRaises(PermissionError):
            verifier.verify(test_token(iss="https://supabase.test/auth/v1",client_id="other"),
                            audience="https://mcp.test/mcp",now=datetime.now(timezone.utc))

    def test_production_configuration_requires_workbuddy_oauth_client_allowlist(self):
        config = {
            "SUPABASE_URL":"https://supabase.test",
            "SUPABASE_PUBLISHABLE_KEY":"publishable-test-only",
            "CHECKD_MCP_PUBLIC_URL":"https://mcp.test",
            "CHECKD_MCP_ENV":"production",
        }
        with patch.dict(os.environ, config, clear=True):
            with self.assertRaisesRegex(RuntimeError, "OAUTH_CLIENT_IDS"):
                build_remote_application_from_env()
        with patch.dict(os.environ, {**config,"CHECKD_MCP_OAUTH_CLIENT_IDS":"wb-client-a"}, clear=True):
            app = build_remote_application_from_env()
        self.assertEqual(app.verifier.allowed_oauth_client_ids, frozenset({"wb-client-a"}))

    def test_user_jwt_reads_only_filtered_tables_and_marks_planning_provisional(self):
        calls = []
        rows = {
            "tasks": [{"id":"task-a","name":"Fixture task","type":"one_time",
                "status":"active","updated_at":"2026-11-15T10:00:00+08:00","sync_version":2}],
            "one_time_reminders": [{"task_id":"task-a","scheduled_at":None,
                "completed_at":None,"due_date":"2026-11-18","due_at":None,
                "available_from":"2026-11-15"}],
            "courses": [{"id":"course-a","name":"Fixture course","semester":"Autumn",
                "status":"active"}],
            "course_schedule_rules": [{"id":"rule-a","course_id":"course-a",
                "weekday":1,"week_rule_type":"oddWeeks","starts_at_minute":540,
                "ends_at_minute":590}],
            "task_effort_estimates": [{"task_id":"task-a","remaining_seconds":1800}],
        }
        def opener(request, timeout):
            calls.append(request)
            table = urlparse(request.full_url).path.rsplit("/", 1)[-1]
            if table == "get_agent_planning_checkpoint_status":
                return Response(200, {"planning_ready":False,
                    "device_checkpoints_current":False,
                    "course_occurrences_cover_window":False,
                    "known_device_count":0,"server_data_version":0})
            return Response(200, rows.get(table, []))
        provider = SupabaseRestSnapshotProvider(supabase_url="https://supabase.test",
            publishable_key="public-test-key", opener=opener)
        identity = RemoteIdentity("user-a", "test", frozenset({"planning:read"}),
                                  2**31, "per-user-jwt")
        snapshot = provider.fetch_authenticated(identity, "2026-11-15", "2026-11-30")
        self.assertEqual(snapshot["subject_ref"], "user-a")
        self.assertEqual(snapshot["tasks"][0]["deadline_date"], "2026-11-18")
        self.assertEqual(snapshot["courses"][0]["name"], "Fixture course")
        self.assertEqual(snapshot["course_rules"][0]["week_rule_type"], "oddWeeks")
        self.assertTrue(snapshot["provisional"])
        self.assertFalse(snapshot["execution_eligible"])
        self.assertIn("flutter_course_occurrences_unavailable_or_stale",
                      snapshot["planning_blockers"])
        for request in calls:
            self.assertEqual(request.get_header("Authorization"), "Bearer per-user-jwt")
            if request.get_method() == "GET":
                query = parse_qs(urlparse(request.full_url).query)
                self.assertEqual(query["user_id"], ["eq.user-a"])
            else:
                self.assertTrue(urlparse(request.full_url).path.endswith(
                    "/rpc/get_agent_planning_checkpoint_status"))
                self.assertNotIn("user_id", request.data.decode())

    def test_fresh_flutter_occurrence_snapshot_becomes_schedule_blocks(self):
        calls=[]
        rows={
            "tasks":[{"id":"task-a","name":"考试复习","type":"one_time",
                "status":"active","updated_at":"2026-11-15T08:00:00+08:00"}],
            "one_time_reminders":[{"task_id":"task-a","due_date":"2026-11-20",
                "available_from":"2026-11-15","completed_at":None}],
            "courses":[{"id":"course-a","name":"高数","status":"active"}],
            "course_schedule_rules":[{"id":"rule-a","course_id":"course-a"}],
            "task_effort_estimates":[{"task_id":"task-a","remaining_seconds":1800}],
            "agent_course_occurrence_snapshots":[{
                "device_id":"device-a","from_date":"2026-11-15",
                "through_date":"2026-11-30","timezone":"Asia/Shanghai",
                "builder_version":"checkd_flutter_course_occurrence_v1",
                "course_data_version":"sha256:fixture",
                "generated_at":datetime.now(timezone.utc).isoformat(),
                "server_data_version":7,"occurrence_digest":"digest-a",
                "local_generation":4,"occurrences":[{
                    "occurrence_id":"course:rule-a:2026-11-16",
                    "course_id":"course-a","schedule_rule_id":"rule-a",
                    "local_date":"2026-11-16","start_minute":540,
                    "end_minute":600,"timezone":"Asia/Shanghai"}]}],
        }
        def opener(request, timeout):
            calls.append(request)
            name=urlparse(request.full_url).path.rsplit("/",1)[-1]
            if name == "get_agent_planning_checkpoint_status":
                return Response(200,{"planning_ready":True,
                    "device_checkpoints_current":True,
                    "course_occurrences_cover_window":True,
                    "known_device_count":1,"server_data_version":7})
            return Response(200,rows.get(name,[]))
        provider=SupabaseRestSnapshotProvider(supabase_url="https://supabase.test",
            publishable_key="publishable-test",opener=opener)
        identity=RemoteIdentity("user-a","test",frozenset({"planning:read"}),
                                2**31,"jwt-user-a")
        snapshot=provider.fetch_authenticated(identity,"2026-11-15","2026-11-20")
        self.assertFalse(snapshot["provisional"])
        self.assertTrue(snapshot["planning_ready"])
        self.assertFalse(snapshot["execution_eligible"])
        self.assertEqual(snapshot["course_occurrences"],[{
            "starts_at":"2026-11-16T09:00:00+08:00",
            "ends_at":"2026-11-16T10:00:00+08:00",
            "course_id":"course-a","schedule_rule_id":"rule-a",
            "occurrence_id":"course:rule-a:2026-11-16","kind":"course"}])
        self.assertNotIn("flutter_course_occurrences_unavailable_or_stale",
                         snapshot["planning_blockers"])
        gets=[request for request in calls if request.get_method()=="GET"]
        self.assertTrue(all(parse_qs(urlparse(request.full_url).query)["user_id"]
                            == ["eq.user-a"] for request in gets))
        rpc=next(request for request in calls if request.get_method()=="POST")
        self.assertEqual(json.loads(rpc.data)["p_from_date"],"2026-11-15")
        self.assertNotIn("user_id",rpc.data.decode())

    def test_proposal_reads_use_user_jwt_owner_filters_and_never_select_credentials(self):
        calls = []
        def opener(request, timeout):
            calls.append(request)
            table = urlparse(request.full_url).path.rsplit("/", 1)[-1]
            if table == "agent_plan_proposals":
                return Response(200, [{"id":"00000000-0000-4000-8000-000000000001",
                    "status":"proposed","changes":[{"task_id":"synthetic"}]}])
            return Response(200, [{"id":"approval-id","status":"pending"}])

        provider = SupabaseRestSnapshotProvider(supabase_url="https://supabase.test",
            publishable_key="public-test-key", opener=opener)
        identity = RemoteIdentity("user-a", "test", frozenset({"planning:read"}),
                                  2**31, "user-jwt-a")
        rows = provider.fetch_plan_proposals(identity,
            proposal_id="00000000-0000-4000-8000-000000000001")
        self.assertEqual(rows[0]["approval"]["status"], "pending")
        self.assertNotIn("approval_token", rows[0]["approval"])
        self.assertEqual(len(calls), 2)
        for request in calls:
            self.assertEqual(request.get_method(), "GET")
            self.assertEqual(request.get_header("Authorization"), "Bearer user-jwt-a")
            query = parse_qs(urlparse(request.full_url).query)
            self.assertEqual(query["user_id"], ["eq.user-a"])
            self.assertNotIn("token", query.get("select", [""])[0].lower())


if __name__ == "__main__":
    unittest.main()
