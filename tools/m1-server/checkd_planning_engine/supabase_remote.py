"""Supabase Auth and user-JWT PostgREST adapters for remote read-only MCP.

This adapter deliberately uses the caller's verified JWT for every database
request. It has no service-role code path. A successful auth user lookup proves
the CheckD Auth principal; it does not prove device sync freshness or make a
planning preview eligible for execution.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from hashlib import sha256
import json
import os
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

from .remote_mcp import RemoteIdentity


class SupabaseReadError(RuntimeError):
    """Sanitized upstream failure; never retains response bodies or tokens."""
    def __init__(self, stage: str, status: int | None = None):
        self.stage = stage
        self.status = status
        super().__init__(f"Supabase read failed at {stage}" + (f" (HTTP {status})" if status else ""))


def _jwt_payload(token: str) -> dict[str, Any]:
    """Decode already Auth-verified claims for consistency checks, not signature trust."""
    import base64
    try:
        _, payload, _ = token.split(".")
        data = base64.urlsafe_b64decode(payload + "=" * ((4-len(payload)%4)%4))
        value = json.loads(data)
        return value if isinstance(value, dict) else {}
    except (ValueError, json.JSONDecodeError):
        return {}


class SupabaseAccessTokenVerifier:
    """Validate a CheckD JWT through Auth, then use Auth's returned user ID."""
    def __init__(self, *, supabase_url: str, publishable_key: str,
                 allowed_oauth_client_ids: frozenset[str] = frozenset(),
                 expected_issuer: str | None = None,
                 timeout_seconds: float = 8.0, opener=urlopen,
                 task_writes_enabled: bool = False):
        self.base_url = supabase_url.rstrip("/")
        self.publishable_key = publishable_key
        self.allowed_oauth_client_ids = allowed_oauth_client_ids
        self.expected_issuer = expected_issuer
        self.timeout_seconds = timeout_seconds
        self.opener = opener
        self.task_writes_enabled = bool(task_writes_enabled)

    def verify(self, token: str, *, audience: str, now: datetime) -> RemoteIdentity:
        if not token or len(token) > 16_384:
            raise PermissionError("invalid access token")
        request = Request(f"{self.base_url}/auth/v1/user", headers={
            "apikey": self.publishable_key,
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
        }, method="GET")
        try:
            with self.opener(request, timeout=self.timeout_seconds) as response:
                if response.status != 200:
                    raise PermissionError("invalid access token")
                raw = response.read(64_001)
            if len(raw) > 64_000:
                raise PermissionError("invalid access token")
            user = json.loads(raw)
            user_id = user.get("id") if isinstance(user, dict) else None
            claims = _jwt_payload(token)
            expiry = claims.get("exp")
            # Auth validates signature/session. These checks prevent accepting an
            # unexpected token class/audience or a claim subject mismatch.
            if (not isinstance(user_id, str) or not user_id
                    or claims.get("sub") != user_id
                    or claims.get("aud") != "authenticated"
                    or claims.get("role") != "authenticated"
                    or not isinstance(expiry, int) or int(now.timestamp()) >= expiry):
                raise PermissionError("invalid access token")
            if self.expected_issuer and claims.get("iss") != self.expected_issuer:
                raise PermissionError("invalid access token")
            if (self.allowed_oauth_client_ids
                    and claims.get("client_id") not in self.allowed_oauth_client_ids):
                raise PermissionError("OAuth client is not enabled")
            # Planning reads are the default. The isolated-test task-write switch
            # adds a local capability only; production startup refuses that mode
            # until an actual WorkBuddy OAuth grant verifier is available.
            scopes = {"planning:read"}
            if self.task_writes_enabled:
                # This deployment gate is for isolated testing only. Production
                # WorkBuddy OAuth must supply a separately verified write grant.
                scopes.add("task:write")
            return RemoteIdentity(user_id, f"supabase-auth:{user_id}",
                                  frozenset(scopes), expiry, token)
        except PermissionError:
            raise
        except HTTPError:
            raise PermissionError("invalid access token") from None
        except (URLError, TimeoutError, OSError, ValueError, json.JSONDecodeError):
            raise PermissionError("authentication service unavailable") from None


class SupabaseRestSnapshotProvider:
    """Fetch an owner-scoped, non-executable planning read model via PostgREST."""
    def __init__(self, *, supabase_url: str, publishable_key: str,
                 timeout_seconds: float = 8.0, opener=urlopen):
        self.rest_url = supabase_url.rstrip("/") + "/rest/v1"
        self.publishable_key = publishable_key
        self.timeout_seconds = timeout_seconds
        self.opener = opener

    def _get(self, table: str, params: dict[str, str], token: str,
             *, required: bool = False) -> list[dict[str, Any]]:
        url = f"{self.rest_url}/{table}?{urlencode(params)}"
        request = Request(url, headers={
            "apikey": self.publishable_key,
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
        }, method="GET")
        try:
            with self.opener(request, timeout=self.timeout_seconds) as response:
                raw = response.read(1_000_001)
                if response.status != 200 or len(raw) > 1_000_000:
                    raise SupabaseReadError(table, response.status)
            rows = json.loads(raw)
            if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
                raise SupabaseReadError(table)
            return rows
        except HTTPError as exc:
            if not required and exc.code in {400, 404}:
                return []
            raise SupabaseReadError(table, exc.code) from None
        except SupabaseReadError:
            raise
        except (URLError, TimeoutError, OSError, ValueError, json.JSONDecodeError):
            raise SupabaseReadError(table) from None

    def _post_rpc(self, function: str, body: dict[str, Any], token: str) -> dict[str, Any]:
        request = Request(f"{self.rest_url}/rpc/{function}",
            data=json.dumps(body, separators=(",", ":")).encode(),
            headers={"apikey": self.publishable_key,
                     "Authorization": f"Bearer {token}",
                     "Content-Type": "application/json",
                     "Accept": "application/json"}, method="POST")
        try:
            with self.opener(request, timeout=self.timeout_seconds) as response:
                raw = response.read(1_000_001)
                if response.status != 200 or len(raw) > 1_000_000:
                    raise SupabaseReadError(function, response.status)
            result = json.loads(raw)
            if not isinstance(result, dict):
                raise SupabaseReadError(function)
            return result
        except HTTPError as exc:
            raise SupabaseReadError(function, exc.code) from None
        except SupabaseReadError:
            raise
        except (URLError, TimeoutError, OSError, ValueError, json.JSONDecodeError):
            raise SupabaseReadError(function) from None

    @staticmethod
    def _normalize_course_occurrences(rows: list[dict[str, Any]], start: str,
                                     end: str) -> list[dict[str, Any]]:
        zone = ZoneInfo("Asia/Shanghai")
        normalized: list[dict[str, Any]] = []
        for row in rows:
            for occurrence in row.get("occurrences", []):
                local_day = date.fromisoformat(occurrence["local_date"])
                begin = int(occurrence["start_minute"])
                finish = int(occurrence["end_minute"])
                if (not start <= local_day.isoformat() <= end or begin < 0
                        or begin >= 1440 or finish <= begin or finish > 1440
                        or occurrence.get("timezone") != "Asia/Shanghai"):
                    raise SupabaseReadError("course_occurrence_validation")
                midnight = datetime.combine(local_day, datetime.min.time(), zone)
                normalized.append({
                    "starts_at": (midnight + timedelta(minutes=begin)).isoformat(),
                    "ends_at": (midnight + timedelta(minutes=finish)).isoformat(),
                    "course_id": occurrence["course_id"],
                    "schedule_rule_id": occurrence.get("schedule_rule_id"),
                    "occurrence_id": occurrence["occurrence_id"],
                    "kind": "course",
                })
        normalized.sort(key=lambda item: (item["starts_at"], item["ends_at"],
                                          item["occurrence_id"]))
        return normalized

    def fetch_authenticated(self, identity: RemoteIdentity, start: str,
                            end: str) -> dict[str, Any]:
        token = identity.access_token
        if not token:
            raise SupabaseReadError("missing_user_token")
        owner = identity.checkd_user_id
        base = {"user_id": f"eq.{owner}", "limit": "1000"}
        task_rows = self._get("tasks", {**base,
            "select": "id,name,type,status,updated_at,sync_version,deleted_at",
            "status": "eq.active", "deleted_at": "is.null", "order": "updated_at.desc"},
            token, required=True)

        # Stage 14A fields are optional across deployed schemas. A missing field
        # produces a safe fallback to legacy columns and is surfaced as a blocker.
        reminder_select = "task_id,scheduled_at,remind_before_minutes,completed_at,updated_at,available_from,planned_date,due_date,due_at"
        deadline_fields_available = True
        try:
            reminders = self._get("one_time_reminders", {**base,
                "select": reminder_select}, token, required=True)
        except SupabaseReadError as exc:
            if exc.status not in {400, 404}:
                raise
            deadline_fields_available = False
            reminders = self._get("one_time_reminders", {**base,
                "select": "task_id,scheduled_at,remind_before_minutes,completed_at,updated_at"},
                token, required=True)

        courses = self._get("courses", {**base,
            "select": "id,name,semester,status,updated_at,sync_version,deleted_at",
            "status": "eq.active", "deleted_at": "is.null"}, token)
        rules = self._get("course_schedule_rules", {**base,
            "select": "id,course_id,weekday,week_rule_type,start_week,end_week,interval_weeks,week_numbers,schedule_template_id,section_ids,starts_at_minute,ends_at_minute,updated_at,sync_version,deleted_at",
            "deleted_at": "is.null"}, token)
        semesters = self._get("semesters", {**base,
            "select": "id,name,first_week_start_date,total_weeks,schedule_template_id,is_current,sync_version,updated_at,deleted_at",
            "deleted_at": "is.null"}, token)
        templates = self._get("schedule_templates", {**base,
            "select": "id,name,timezone,is_default,sync_version,updated_at,deleted_at",
            "deleted_at": "is.null"}, token)
        segments = self._get("schedule_template_segments", {**base,
            "select": "id,template_id,name,starts_at_minute,ends_at_minute,segment_type,sort_order,sync_version,deleted_at",
            "deleted_at": "is.null"}, token)
        overrides = self._get("daily_item_overrides", {**base,
            "select": "id,item_type,item_id,local_date,action,planned_start_minute,planned_end_minute,sync_version,deleted_at",
            "local_date": f"gte.{start}", "and": f"(local_date.lte.{end},deleted_at.is.null)"}, token)
        effort = self._get("task_effort_estimates", {**base,
            "select": "task_id,estimated_seconds,remaining_seconds,source,updated_at,sync_version"}, token)
        plan_versions = self._get("task_plan_versions", {**base,
            "select": "id,revision,source_snapshot_version,starts_on,ends_on,status,updated_at,sync_version",
            "status": "in.(confirmed,applied)", "order": "revision.desc", "limit": "100"}, token)
        end_exclusive = (date.fromisoformat(end) + timedelta(days=1)).isoformat()
        blocks = self._get("task_time_blocks", {**base,
            "select": "id,plan_version_id,task_id,starts_at,ends_at,planned_seconds,sync_version,deleted_at",
            "deleted_at": "is.null", "starts_at": f"lt.{end_exclusive}T00:00:00+08:00",
            "ends_at": f"gt.{start}T00:00:00+08:00"}, token)
        completions = self._get("task_completions", {**base,
            "select": "task_id,local_date,completed_at,is_success,updated_at,sync_version",
            "local_date": f"gte.{start}", "and": f"(local_date.lte.{end},deleted_at.is.null)"}, token)

        try:
            checkpoint_status = self._post_rpc(
                "get_agent_planning_checkpoint_status",
                {"p_from_date": start, "p_through_date": end}, token)
        except SupabaseReadError:
            # Missing migration or an unavailable checkpoint RPC only removes
            # trusted execution readiness. A task-only preview may still be
            # shown as provisional; course rules without Flutter occurrences
            # remain a hard planning blocker.
            checkpoint_status = {"planning_ready": False,
                                 "device_checkpoints_current": False,
                                 "course_occurrences_cover_window": False,
                                 "known_device_count": 0,
                                 "server_data_version": None}
        checkpoints_current = (
            checkpoint_status.get("planning_ready") is True
            and checkpoint_status.get("device_checkpoints_current") is True
            and checkpoint_status.get("course_occurrences_cover_window") is True
        )
        course_snapshot_rows: list[dict[str, Any]] = []
        course_occurrences: list[dict[str, Any]] = []
        course_snapshot_valid = not rules
        if checkpoints_current:
            version = checkpoint_status.get("server_data_version")
            cutoff = (datetime.now(timezone.utc) - timedelta(minutes=15)).isoformat()
            try:
                course_snapshot_rows = self._get("agent_course_occurrence_snapshots", {
                    **base,
                    "select": "device_id,from_date,through_date,timezone,builder_version,course_data_version,generated_at,server_data_version,occurrence_digest,occurrences,local_generation",
                    "server_data_version": f"eq.{version}",
                    "from_date": f"lte.{start}", "through_date": f"gte.{end}",
                    "timezone": "eq.Asia/Shanghai",
                    "builder_version": "eq.checkd_flutter_course_occurrence_v1",
                    "generated_at": f"gte.{cutoff}",
                    "order": "generated_at.desc", "limit": "100",
                }, token, required=True)
            except SupabaseReadError:
                course_snapshot_rows = []
            device_count = checkpoint_status.get("known_device_count")
            digests = {row.get("occurrence_digest") for row in course_snapshot_rows}
            course_snapshot_valid = (
                type(device_count) is int and device_count > 0
                and len(course_snapshot_rows) == device_count
                and len(digests) == 1 and None not in digests
            )
            if course_snapshot_valid:
                course_occurrences = self._normalize_course_occurrences(
                    course_snapshot_rows, start, end)

        by_task = {str(row.get("task_id")): row for row in reminders}
        effort_by_task = {str(row.get("task_id")): row for row in effort}
        task_dtos: list[dict[str, Any]] = []
        for row in task_rows:
            reminder = by_task.get(str(row.get("id")), {})
            estimate = effort_by_task.get(str(row.get("id")), {})
            task_type = row.get("type")
            task_dtos.append({
                "task_id": row.get("id"), "name": row.get("name"),
                "task_type": task_type, "completion_status": (
                    "completed" if reminder.get("completed_at") else
                    "unknown" if task_type != "one_time" else "pending"),
                "deadline_date": reminder.get("due_date"),
                "deadline_at": reminder.get("due_at"),
                "planned_at": reminder.get("scheduled_at"),
                "earliest_start": self._earliest_start(reminder.get("available_from"), start),
                "remaining_seconds": estimate.get("remaining_seconds"),
                "remaining_effort_state": "known" if estimate.get("remaining_seconds") else "unknown",
                "source_updated_at": row.get("updated_at"),
            })

        plan_by_id = {row.get("id"): row for row in plan_versions}
        visible_blocks = [{key: row.get(key) for key in (
            "id", "plan_version_id", "task_id", "starts_at", "ends_at", "planned_seconds")}
            for row in blocks if row.get("plan_version_id") in plan_by_id]
        captured_at = datetime.now(timezone.utc).isoformat()
        source_data = {
            "tasks": task_dtos, "reminders": reminders, "courses": courses,
            "course_rules": rules, "semesters": semesters, "templates": templates,
            "template_segments": segments, "overrides": overrides,
            "effort": effort, "plan_versions": plan_versions,
            "time_blocks": visible_blocks, "completions": completions,
            "course_snapshot": course_snapshot_rows,
        }
        digest = sha256(json.dumps(source_data, sort_keys=True, separators=(",", ":"),
                                  ensure_ascii=False, default=str).encode()).hexdigest()
        execution_blockers = [] if checkpoints_current else [
            "device_sync_watermark_unavailable", "local_unsynced_changes_unknown"]
        if not checkpoints_current:
            execution_blockers.append("server_course_snapshot_unverified")
        if not deadline_fields_available:
            execution_blockers.append("stage14a_deadline_fields_unavailable")
        planning_blockers = (["flutter_course_occurrences_unavailable_or_stale"]
                             if rules and not course_snapshot_valid else [])
        if any(row.get("type") != "one_time" for row in task_rows):
            planning_blockers.append("recurring_occurrences_not_resolved")
        return {
            "schema_version": "checkd.planning.snapshot.v1",
            "subject_ref": owner, "source": "supabase_postgrest_user_jwt",
            "captured_at": captured_at, "version": f"read:{digest}",
            "sync_state": "current" if checkpoints_current and course_snapshot_valid else "unknown",
            "provisional": not (checkpoints_current and course_snapshot_valid),
            "timezone": "Asia/Shanghai", "now": datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(),
            "horizon_end": datetime.combine(date.fromisoformat(end), datetime.max.time(),
                                               ZoneInfo("Asia/Shanghai")).isoformat(),
            "tasks": task_dtos, "courses": courses, "course_rules": rules,
            "semesters": semesters, "schedule_templates": templates,
            "schedule_template_segments": segments, "daily_item_overrides": overrides,
            "course_occurrences": course_occurrences, "occupied_blocks": visible_blocks,
            "effort_records": effort, "plan_versions": plan_versions,
            "completion_facts": completions,
            "current_plan": {"status": "read_only", "revision": plan_versions[0].get("revision")
                             if plan_versions else None, "blocks": visible_blocks},
            "readiness_blockers": execution_blockers,
            "planning_blockers": planning_blockers,
            "execution_eligible": False,
            "planning_ready": checkpoints_current and course_snapshot_valid,
            "course_snapshot": {
                "validated": course_snapshot_valid,
                "server_data_version": checkpoint_status.get("server_data_version"),
                "builder_version": "checkd_flutter_course_occurrence_v1",
                "device_count": checkpoint_status.get("known_device_count", 0),
                "course_data_version": course_snapshot_rows[0].get("course_data_version")
                    if course_snapshot_rows and course_snapshot_valid else None,
            },
            "limitation_codes": execution_blockers + planning_blockers,
        }

    def fetch_plan_proposals(self, identity: RemoteIdentity, *,
                             proposal_id: str | None = None,
                             limit: int = 20) -> list[dict[str, Any]]:
        """Read proposal summaries using the current user's JWT and RLS.

        Approval credentials are intentionally never selected. A proposal id
        owned by another account is indistinguishable from an absent id because
        both owner filtering and the database RLS policy apply.
        """
        token = identity.access_token
        if not token:
            raise SupabaseReadError("missing_user_token")
        if not 1 <= limit <= 50:
            raise ValueError("proposal limit out of range")
        owner = identity.checkd_user_id
        params = {
            "user_id": f"eq.{owner}",
            "select": "id,base_version,changes,change_digest,rules_version,starts_on,ends_on,status,expires_at,created_at,applied_at",
            "order": "created_at.desc",
            "limit": str(limit),
        }
        if proposal_id is not None:
            params["id"] = f"eq.{proposal_id}"
            params["limit"] = "1"
        proposals = self._get("agent_plan_proposals", params, token, required=True)
        if proposal_id is None or not proposals:
            return proposals
        proposal = proposals[0]
        approval_rows = self._get("agent_plan_approvals", {
            "user_id": f"eq.{owner}",
            "proposal_id": f"eq.{proposal_id}",
            "select": "id,status,expires_at,created_at,decided_at",
            "order": "created_at.desc",
            "limit": "1",
        }, token, required=True)
        proposal["approval"] = approval_rows[0] if approval_rows else None
        return proposals

    @staticmethod
    def _earliest_start(available_from: Any, range_start: str) -> str:
        value = available_from if isinstance(available_from, str) else range_start
        return datetime.combine(date.fromisoformat(value), datetime.min.time(),
                                ZoneInfo("Asia/Shanghai")).isoformat()


def build_remote_application_from_env():
    required = ("SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "CHECKD_MCP_PUBLIC_URL")
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise RuntimeError("Missing required environment variables: " + ", ".join(missing))
    public_url = os.environ["CHECKD_MCP_PUBLIC_URL"].rstrip("/")
    supabase_url = os.environ["SUPABASE_URL"].rstrip("/")
    auth_url = os.environ.get("CHECKD_MCP_OAUTH_ISSUER_URL", supabase_url + "/auth/v1")
    environment = os.environ.get("CHECKD_MCP_ENV", "development").lower()
    oauth_client_ids = frozenset(value.strip() for value in
        os.environ.get("CHECKD_MCP_OAUTH_CLIENT_IDS", "").split(",") if value.strip())
    if environment == "production" and not oauth_client_ids:
        raise RuntimeError("CHECKD_MCP_OAUTH_CLIENT_IDS must allow registered WorkBuddy clients")
    if environment == "production" and not supabase_url.startswith("https://"):
        raise RuntimeError("SUPABASE_URL must use HTTPS in production")
    verifier = SupabaseAccessTokenVerifier(supabase_url=supabase_url,
        publishable_key=os.environ["SUPABASE_PUBLISHABLE_KEY"],
        allowed_oauth_client_ids=oauth_client_ids,
        expected_issuer=auth_url,
        timeout_seconds=float(os.environ.get("CHECKD_MCP_UPSTREAM_TIMEOUT_SECONDS", "8")))
    provider = SupabaseRestSnapshotProvider(supabase_url=supabase_url,
        publishable_key=os.environ["SUPABASE_PUBLISHABLE_KEY"],
        timeout_seconds=float(os.environ.get("CHECKD_MCP_UPSTREAM_TIMEOUT_SECONDS", "8")))
    from .remote_mcp import RemoteMcpApplication
    return RemoteMcpApplication(verifier=verifier,
        audience=public_url + "/mcp", snapshot_provider=provider,
        resource_metadata_url=public_url + "/.well-known/oauth-protected-resource",
        authorization_server_url=auth_url)
