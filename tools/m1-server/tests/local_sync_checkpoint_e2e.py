"""Exercise sync checkpoint RPCs against a loopback Supabase only.

Required environment is supplied by `supabase status` for a disposable local
project. Credentials are consumed in memory, never printed or persisted.
"""
from __future__ import annotations

import json
import os
import secrets
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse


def request(base: str, path: str, *, key: str, token: str | None = None,
            method: str = "GET", body=None, prefer: str | None = None):
    headers = {"apikey": key, "Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if body is not None:
        headers["Content-Type"] = "application/json"
    if prefer:
        headers["Prefer"] = prefer
    req = urllib.request.Request(
        base.rstrip("/") + path,
        data=None if body is None else json.dumps(body).encode(),
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            raw = response.read(1_000_000)
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        # Do not print or preserve server bodies: they may include account data.
        try:
            body = json.loads(exc.read(4096))
            code = body.get("code") if isinstance(body, dict) else None
            message = body.get("message") if isinstance(body, dict) else None
        except Exception:
            code = None
            message = None
        return exc.code, {"_error_code": code, "_error_message": message}


def require(ok: bool, name: str):
    if not ok:
        raise AssertionError(name)
    print(f"PASS {name}")


def main():
    base = os.environ["CHECKD_LOCAL_SUPABASE_URL"]
    anon = os.environ["CHECKD_LOCAL_SUPABASE_ANON_KEY"]
    service = os.environ["CHECKD_LOCAL_SUPABASE_SERVICE_ROLE_KEY"]
    parsed = urlparse(base)
    require(parsed.scheme == "http" and parsed.hostname in {"127.0.0.1", "localhost", "::1"},
            "endpoint is loopback HTTP")
    users = []
    try:
        created = []
        for _ in range(2):
            email = f"checkd-watermark-{uuid.uuid4()}@example.invalid"
            password = secrets.token_urlsafe(32)
            status, user = request(
                base, "/auth/v1/admin/users", key=service, token=service,
                method="POST", body={"email": email, "password": password,
                                     "email_confirm": True},
            )
            require(status in {200, 201} and isinstance(user, dict) and user.get("id"),
                    "create isolated local auth user")
            user_id = user["id"]
            users.append(user_id)
            status, session = request(
                base, "/auth/v1/token?grant_type=password", key=anon,
                method="POST", body={"email": email, "password": password},
            )
            require(status == 200 and isinstance(session, dict)
                    and session.get("access_token"), "authenticate isolated user")
            created.append((user_id, session["access_token"]))

        user_a, token_a = created[0]
        user_b, token_b = created[1]
        course_id = str(uuid.uuid4())
        foreign_course_id = str(uuid.uuid4())
        status, _ = request(
            base, "/rest/v1/courses", key=anon, token=token_a, method="POST",
            prefer="return=minimal",
            body={"id": course_id, "user_id": user_a, "name": "Synthetic course",
                  "color": 1, "status": "active"},
        )
        require(status in {201, 204}, "authenticated user writes own synthetic course")
        status, _ = request(
            base, "/rest/v1/courses", key=anon, token=token_b, method="POST",
            prefer="return=minimal",
            body={"id": foreign_course_id, "user_id": user_b,
                  "name": "Synthetic foreign course", "color": 2,
                  "status": "active"},
        )
        require(status in {201, 204}, "second user writes isolated synthetic course")
        version_path = "/rest/v1/agent_user_data_versions?select=data_version"
        status, version_rows = request(
            base, version_path, key=anon, token=token_a,
        )
        require(status == 200 and version_rows and version_rows[0]["data_version"] > 0,
                "course trigger advances user data version")
        server_version = version_rows[0]["data_version"]
        device_id = str(uuid.uuid4())
        from_date = datetime.now(timezone(timedelta(hours=8))).date()
        through_date = from_date + timedelta(days=6)
        snapshot = {
            "from_date": from_date.isoformat(),
            "through_date": through_date.isoformat(),
            "timezone": "Asia/Shanghai",
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "builder_version": "checkd_flutter_course_occurrence_v1",
            "course_data_version": "sha256:synthetic-test-digest",
            "device_id": device_id,
            "local_generation": 0,
            "occurrences": [{
                "occurrence_id": "synthetic-occurrence-1", "course_id": course_id,
                "local_date": from_date.isoformat(), "start_minute": 540,
                "end_minute": 630, "timezone": "Asia/Shanghai",
            }],
        }
        status, published = request(
            base, "/rest/v1/rpc/publish_agent_course_occurrence_snapshot",
            key=anon, token=token_a, method="POST",
            body={"p_device_id": device_id, "p_snapshot": snapshot},
        )
        if status != 200:
            details = published if isinstance(published, dict) else {}
            print(f"INFO publish_rpc_http_status={status} error_code={details.get('_error_code')} message={details.get('_error_message')}")
        require(status == 200 and published["server_data_version"] == server_version,
                "publish Flutter-versioned occurrence snapshot")
        status, ack = request(
            base, "/rest/v1/rpc/acknowledge_agent_device_sync_checkpoint",
            key=anon, token=token_a, method="POST",
            body={"p_device_id": device_id, "p_local_generation": 0},
        )
        require(status == 200 and ack["local_generation"] == 0,
                "acknowledge device generation after occurrence publication")
        query = urllib.parse.urlencode({
            "p_from_date": from_date.isoformat(),
            "p_through_date": through_date.isoformat(),
        })
        status, readiness = request(
            base, "/rest/v1/rpc/get_agent_planning_checkpoint_status", key=anon,
            token=token_a, method="POST", body={
                "p_from_date": from_date.isoformat(),
                "p_through_date": through_date.isoformat(),
            },
        )
        require(status == 200 and readiness["planning_ready"] is True
                and readiness["execution_eligible"] is False,
                "readiness requires current checkpoint and course coverage")
        foreign_snapshot = dict(snapshot)
        foreign_snapshot["occurrences"] = [
            {**row, "course_id": foreign_course_id}
            for row in snapshot["occurrences"]
        ]
        status, rejected = request(
            base, "/rest/v1/rpc/publish_agent_course_occurrence_snapshot",
            key=anon, token=token_a, method="POST", body={
                "p_device_id": device_id, "p_snapshot": foreign_snapshot,
            },
        )
        require(status >= 400 and rejected.get("_error_code") == "42501",
                f"server rejects foreign course occurrence (http={status}, code={rejected.get('_error_code')})")
        status, foreign_rows = request(
            base, "/rest/v1/agent_course_occurrence_snapshots?select=user_id",
            key=anon, token=token_b,
        )
        require(status == 200 and foreign_rows == [], "RLS hides user A snapshot from user B")
        status, _ = request(
            base, "/rest/v1/courses?id=eq." + course_id, key=anon,
            token=token_a, method="PATCH", prefer="return=minimal",
            body={"name": "Synthetic course changed"},
        )
        require(status in {204, 200}, "synthetic course update accepted")
        status, stale = request(
            base, "/rest/v1/rpc/get_agent_planning_checkpoint_status", key=anon,
            token=token_a, method="POST", body={
                "p_from_date": from_date.isoformat(),
                "p_through_date": through_date.isoformat(),
            },
        )
        require(status == 200 and stale["planning_ready"] is False
                and stale["execution_eligible"] is False,
                "course mutation invalidates checkpoint and occurrence snapshot")
    finally:
        for user_id in users:
            request(base, "/auth/v1/admin/users/" + user_id, key=service,
                    token=service, method="DELETE")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"FAIL {type(exc).__name__}: {exc}")
        raise SystemExit(1)
