"""Local Streamable HTTP MCP skeleton with a per-request bearer auth boundary.

Only safe read-only tools are registered by default. TestJwtAuthority is a
local test issuer, not WorkBuddy OAuth, Supabase Auth, or a production token
source. With Supabase OAuth, the authorized CheckD Auth UID is the data
principal; never infer it from a WorkBuddy platform ID or request argument.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from datetime import date
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import base64
import copy
import hashlib
import hmac
import re
import json
import os
from pathlib import Path
import secrets
import socketserver
import sys
from typing import Any, Callable, Protocol
from urllib.parse import parse_qs, urlencode, urlparse, urlsplit
from uuid import UUID

from checkd_task_agent.mcp_server import McpApplication as PersonalMcpApplication
from checkd_task_agent.mcp_server import TOOLS as PERSONAL_AGENT_TOOLS
from checkd_task_agent.query_service import TaskQueryService
from checkd_task_agent.supabase import SupabaseTaskRepository
from checkd_task_agent.timeparse import resolve_deadline

from .service import PlanningService


PROTOCOL_VERSION = "2025-11-25"
RESOURCE_METADATA_PATH = "/.well-known/oauth-protected-resource"
RESOURCE_METADATA_PATH_MCP_USER = RESOURCE_METADATA_PATH + "/mcp/user"


def _load_registered_tools() -> tuple[tuple[dict[str, Any], ...], tuple[dict[str, Any], ...]]:
    """Load tool schemas from the repository's canonical candidate contract."""
    # The M1 deployment bundle is assembled from several source directories, so
    # keep the contract next to this vendored runtime instead of relying on the
    # original monorepo's directory depth.
    contract_path = Path(__file__).with_name("agent-planning-v0.json")
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    tools = contract.get("registered_read_only_tools")
    if not isinstance(tools, list) or not tools:
        raise RuntimeError("planning MCP contract has no registered read-only tools")
    names = [tool.get("name") for tool in tools if isinstance(tool, dict)]
    if len(names) != len(tools) or len(set(names)) != len(names):
        raise RuntimeError("planning MCP contract contains invalid tool definitions")
    if any(tool.get("_meta", {}).get("checkd/permission") != "read:self"
           for tool in tools):
        raise RuntimeError("planning MCP prototype only registers read:self tools")
    proposals = contract.get("registered_proposal_tools", [])
    if not isinstance(proposals, list):
        raise RuntimeError("planning MCP proposal tools must be an array")
    proposal_names = [tool.get("name") for tool in proposals if isinstance(tool, dict)]
    if (len(proposal_names) != len(proposals) or len(set(proposal_names)) != len(proposal_names)
            or set(names) & set(proposal_names)):
        raise RuntimeError("planning MCP proposal tools contain invalid or duplicate definitions")
    if any(tool.get("_meta", {}).get("checkd/permission") != "propose:self"
           for tool in proposals):
        raise RuntimeError("proposal tools must be marked propose:self")
    return tuple(tools), tuple(proposals)


TOOLS, PROPOSAL_TOOLS = _load_registered_tools()
PERSONAL_READ_TOOL_NAMES = frozenset({
    "resolve_deadline", "list_tasks", "search_tasks", "get_tasks_by_date",
    "list_overdue_tasks", "get_task_detail",
})
PERSONAL_WRITE_TOOL_NAMES = frozenset({
    "prepare_task_creation", "create_task", "cancel_task_creation",
    "prepare_task_update", "update_task", "cancel_task_update",
})
PERSONAL_TOOL_NAMES = PERSONAL_READ_TOOL_NAMES | PERSONAL_WRITE_TOOL_NAMES
PERSONAL_LIST_ALIAS = "list_one_time_tasks"
_PERSONAL_LIST_TOOL = copy.deepcopy(next(
    tool for tool in PERSONAL_AGENT_TOOLS if tool["name"] == "list_tasks"
))
_PERSONAL_LIST_TOOL["name"] = PERSONAL_LIST_ALIAS
_PERSONAL_LIST_TOOL["description"] = (
    "分页查询当前用户未完成的单次事项；保留个人任务助手的 list_tasks 参数，"
    "与原 M1 list_tasks 请求信封区分。"
)
_PERSONAL_READ_TOOLS = tuple(
    tool for tool in PERSONAL_AGENT_TOOLS if tool.get("name") in PERSONAL_READ_TOOL_NAMES
)
_PLANNING_TOOLS = tuple(tool for tool in TOOLS if tool.get("name") != "list_tasks")
LEGACY_M1_TOOL_NAMES = frozenset({
    "list_tasks", "get_calendar_events", "generate_schedule", "validate_schedule",
    "apply_approved_changes", "request_approval", "get_approval_status",
})
_LEGACY_DATE_RANGE = {
    "type": "object",
    "properties": {
        "start": {"type": "string", "format": "date"},
        "end": {"type": "string", "format": "date"},
    },
    "required": ["start", "end"],
    "additionalProperties": False,
}
_CALENDAR_EVENTS_TOOL = {
    "name": "get_calendar_events",
    "description": "读取授权用户日期范围内的课程、课程 occurrence、单日例外及课程快照状态。",
    "inputSchema": {
        "type": "object",
        "properties": {
            "date_range": _LEGACY_DATE_RANGE,
            "external_fixed_events": {"type": "array", "items": {
                "type": "object", "properties": {
                    "external_event_id": {"type": "string"},
                    "title": {"type": "string"},
                    "start_at": {"type": "string"},
                    "end_at": {"type": "string"},
                }, "required": ["external_event_id", "title", "start_at", "end_at"],
                "additionalProperties": False,
            }},
        },
        "required": ["date_range"],
        "additionalProperties": False,
    },
    "annotations": {"readOnlyHint": True, "destructiveHint": False},
    "_meta": {"checkd/permission": "read:self"},
}


@dataclass(frozen=True)
class RemoteIdentity:
    checkd_user_id: str
    # For Supabase OAuth this is a non-authoritative label derived from the
    # Auth UID. It is not assumed to equal a WorkBuddy platform subject.
    workbuddy_subject: str
    scopes: frozenset[str]
    expires_at: int
    # Held only for the lifetime of this request so an upstream Supabase read
    # can use the same user's RLS context. Never serialize or log this value.
    access_token: str | None = field(default=None, repr=False, compare=False)


class AccessTokenVerifier(Protocol):
    def verify(self, token: str, *, audience: str, now: datetime) -> RemoteIdentity: ...


class CheckDIdentityBindingResolver(Protocol):
    """Server-side WorkBuddy identity -> CheckD account binding lookup.

    A WorkBuddy subject is not a CheckD user id. Production implementations
    must resolve a persisted, consented, revocable binding; request arguments
    and arbitrary token claims are not a substitute.
    """
    def resolve(self, *, issuer: str, subject: str, tenant_id: str | None) -> str | None: ...


class IntrospectionTokenVerifier:
    """Adapter contract for trusted WorkBuddy introspection plus server binding."""
    def __init__(self, introspect: Callable[[str], dict[str, Any] | None],
                 resolve_checkd_user: CheckDIdentityBindingResolver):
        self._introspect = introspect
        self._resolve_checkd_user = resolve_checkd_user

    def verify(self, token: str, *, audience: str, now: datetime) -> RemoteIdentity:
        claims = self._introspect(token)
        if not isinstance(claims, dict) or claims.get("active") is not True:
            raise PermissionError("inactive access token")
        expiry = claims.get("exp")
        audiences = claims.get("aud")
        if isinstance(audiences, str):
            audiences = [audiences]
        workbuddy_subject = claims.get("sub")
        workbuddy_issuer = claims.get("iss")
        tenant_id = claims.get("tid")
        raw_scopes = claims.get("scope", "")
        scopes = frozenset(raw_scopes.split()) if isinstance(raw_scopes, str) else frozenset(raw_scopes or [])
        if (not isinstance(expiry, int) or int(now.timestamp()) >= expiry
                or not isinstance(audiences, list) or audience not in audiences
                or not isinstance(workbuddy_subject, str) or not workbuddy_subject
                or not isinstance(workbuddy_issuer, str) or not workbuddy_issuer
                or (tenant_id is not None and not isinstance(tenant_id, str))):
            raise PermissionError("token claims invalid")
        checkd_user_id = self._resolve_checkd_user.resolve(
            issuer=workbuddy_issuer,
            subject=workbuddy_subject,
            tenant_id=tenant_id,
        )
        if not isinstance(checkd_user_id, str) or not checkd_user_id.strip():
            raise PermissionError("CheckD account is not bound")
        return RemoteIdentity(checkd_user_id, workbuddy_subject, scopes, expiry)


class TestJwtAuthority:
    """HMAC test tokens for local HTTP tests only; never configure in a deployment."""
    def __init__(self, secret: bytes | None = None, *, issuer: str = "checkd-local-test-issuer"):
        self._secret = secret or secrets.token_bytes(32)
        self.issuer = issuer
        self._revoked: set[str] = set()

    @staticmethod
    def _b64(data: bytes) -> str:
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")

    def issue(self, *, workbuddy_subject: str, checkd_user_id: str,
              audience: str, scopes: tuple[str, ...], expires_at: int,
              token_id: str | None = None) -> str:
        header = self._b64(json.dumps({"alg":"HS256","typ":"JWT"},separators=(",",":")).encode())
        claims = self._b64(json.dumps({
            "iss":self.issuer,"sub":workbuddy_subject,"checkd_uid":checkd_user_id,
            "aud":audience,"scope":" ".join(scopes),"exp":expires_at,
            "jti":token_id or secrets.token_hex(12),
        },separators=(",",":"),sort_keys=True).encode())
        body=f"{header}.{claims}"
        signature=self._b64(hmac.new(self._secret,body.encode(),hashlib.sha256).digest())
        return f"{body}.{signature}"

    def revoke(self, token_id: str) -> None:
        self._revoked.add(token_id)

    def verify(self, token: str, *, audience: str, now: datetime) -> RemoteIdentity:
        try:
            header,claims,signature=token.split(".")
            body=f"{header}.{claims}"
            expected=self._b64(hmac.new(self._secret,body.encode(),hashlib.sha256).digest())
            if not hmac.compare_digest(signature,expected):
                raise PermissionError("invalid access token")
            decoded_header=json.loads(base64.urlsafe_b64decode(header+"="*((4-len(header)%4)%4)))
            decoded=json.loads(base64.urlsafe_b64decode(claims+"="*((4-len(claims)%4)%4)))
            exp=decoded.get("exp")
            if (decoded_header.get("alg") != "HS256" or decoded.get("iss") != self.issuer
                    or decoded.get("aud") != audience or not isinstance(exp,int)
                    or int(now.timestamp()) >= exp or decoded.get("jti") in self._revoked
                    or not decoded.get("sub") or not decoded.get("checkd_uid")):
                raise PermissionError("invalid access token")
            scopes=frozenset(decoded.get("scope","").split())
            return RemoteIdentity(decoded["checkd_uid"],decoded["sub"],scopes,exp)
        except (ValueError, TypeError, KeyError, json.JSONDecodeError):
            raise PermissionError("invalid access token") from None


class RemoteMcpApplication:
    def __init__(self, *, verifier: AccessTokenVerifier, audience: str,
                 snapshot_provider: Callable[[str, str, str], dict[str, Any]],
                 resource_metadata_url: str, authorization_server_url: str,
                 supabase_url: str = "", supabase_publishable_key: str = "",
                 task_writes_enabled: bool = False,
                 task_agent_state_dir: str | None = None,
                 proposal_writes_enabled: bool = False,
                 approval_signing_key: bytes | None = None,
                 approval_base_url: str | None = None,
                 legacy_module: Any | None = None):
        self.verifier=verifier
        self.audience=audience
        self.snapshot_provider=snapshot_provider
        self.resource_metadata_url=resource_metadata_url
        self.authorization_server_url=authorization_server_url
        self.supabase_url=supabase_url
        self.supabase_publishable_key=supabase_publishable_key
        self.task_writes_enabled = bool(task_writes_enabled)
        self.task_agent_state_dir = task_agent_state_dir
        self.proposal_writes_enabled = bool(proposal_writes_enabled)
        self.approval_signing_key = approval_signing_key
        self.approval_base_url = (approval_base_url or "").rstrip("/")
        if self.proposal_writes_enabled and (
                not self.approval_signing_key or len(self.approval_signing_key) < 32
                or not self.approval_base_url):
            raise ValueError("proposal capability signing and public URL are required")
        if self.task_writes_enabled and not self.task_agent_state_dir:
            raise ValueError("persistent per-user task agent state directory is required")
        self.legacy_module = legacy_module
        legacy_tools = tuple(legacy_module.tool_defs()) if legacy_module is not None else ()
        if legacy_tools and ({tool.get("name") for tool in legacy_tools}
                             != LEGACY_M1_TOOL_NAMES):
            raise RuntimeError("legacy M1 tool contract must contain its original seven tools")
        if not legacy_tools:
            legacy_tools = (_CALENDAR_EVENTS_TOOL,)
        legacy_names = {tool["name"] for tool in legacy_tools}
        personal_names = (PERSONAL_TOOL_NAMES if self.task_writes_enabled
                          else PERSONAL_READ_TOOL_NAMES) - {"list_tasks"}
        personal_tools = tuple(tool for tool in PERSONAL_AGENT_TOOLS
                               if tool.get("name") in personal_names)
        planning_tools = tuple(tool for tool in _PLANNING_TOOLS
                               if tool.get("name") not in legacy_names
                               and tool.get("name") not in personal_names)
        self.tools=tuple((*legacy_tools,_PERSONAL_LIST_TOOL,*personal_tools,*planning_tools,
                          *(PROPOSAL_TOOLS if self.proposal_writes_enabled else ())))
        names=[tool.get("name") for tool in self.tools]
        if len(names) != len(set(names)):
            raise RuntimeError("unified MCP tool registry contains duplicate names")
        self.service=PlanningService(lambda context: context.checkd_user_id)

    def metadata(self) -> dict[str, Any]:
        return {
            "resource":self.audience,
            "authorization_servers":[self.authorization_server_url],
            "bearer_methods_supported":["header"],
        }

    def dispatch_http(self, *, method: str, path: str, headers: dict[str,str],
                      body: bytes, now: datetime | None = None) -> tuple[int,dict[str,str],bytes]:
        now=now or datetime.now(timezone.utc)
        route = urlsplit(path).path
        if method == "GET" and route in {
                RESOURCE_METADATA_PATH, RESOURCE_METADATA_PATH_MCP_USER}:
            return self._json_response(200,self.metadata())
        if method == "GET" and route == "/healthz":
            return self._json_response(200,{"status":"ok","service":"checkd-planning-mcp"})
        if method == "GET" and route.startswith("/approval/"):
            approval_id = route.removeprefix("/approval/")
            if not self.proposal_writes_enabled or not self._valid_uuid(approval_id):
                return self._json_response(404,{"error":"not_found"})
            return self._approval_page(approval_id)
        if route.startswith("/approval/") and method == "POST":
            if not self.proposal_writes_enabled or len(body) > 16_384:
                return self._json_response(404,{"error":"not_found"})
            if headers.get("content-type","").split(";",1)[0].strip().lower() != "application/json":
                return self._json_response(415,{"error":"unsupported_media_type"})
            return self._handle_approval_post(route, body, now)
        if route not in {"/mcp", "/mcp/user"}:
            return self._json_response(404,{"error":"not_found"})
        authorization=headers.get("authorization","")
        scheme,_,token=authorization.partition(" ")
        try:
            if scheme.lower() != "bearer" or not token:
                raise PermissionError("missing bearer token")
            principal=self.verifier.verify(token,audience=self.audience,now=now)
        except Exception:
            metadata_url = self.resource_metadata_url
            query = parse_qs(urlsplit(path).query, keep_blank_values=True)
            sharecodes = query.get("sharecode", [])
            if (len(sharecodes) == 1 and 1 <= len(sharecodes[0]) <= 128
                    and re.fullmatch(r"[A-Za-z0-9_-]+", sharecodes[0])):
                metadata_url += "?" + urlencode({"sharecode": sharecodes[0]})
            challenge=f'Bearer resource_metadata="{metadata_url}", error="invalid_token"'
            return self._json_response(401,{"error":"invalid_token"},{"WWW-Authenticate":challenge})
        if method != "POST":
            return self._json_response(405,{"error":"method_not_allowed"},{"Allow":"POST"})
        accept=headers.get("accept","")
        content_type=headers.get("content-type","").split(";",1)[0].strip().lower()
        if content_type != "application/json" or not {
            "application/json","text/event-stream"
        }.issubset({part.strip().split(";",1)[0] for part in accept.split(",")}):
            return self._json_response(406,{"error":"not_acceptable"})
        try:
            request=None
            request=json.loads(body)
            if not isinstance(request,dict) or request.get("jsonrpc") != "2.0":
                raise ValueError("invalid JSON-RPC request")
            method_name=request.get("method")
            request_id=request.get("id")
            if method_name == "notifications/initialized":
                return 202,{"Content-Length":"0"},b""
            if method_name == "initialize":
                result={"protocolVersion":PROTOCOL_VERSION,"capabilities":{"tools":{"listChanged":False}},
                        "serverInfo":{"name":"checkd-planning-remote-test","version":"0.1.0"}}
                return self._json_response(200,{"jsonrpc":"2.0","id":request_id,"result":result})
            if "planning:read" not in principal.scopes:
                return self._json_response(403,{"error":"insufficient_scope"},{
                    "WWW-Authenticate":f'Bearer error="insufficient_scope", scope="planning:read"'})
            if method_name == "tools/list":
                return self._json_response(200,{"jsonrpc":"2.0","id":request_id,"result":{"tools":list(self.tools)}})
            if method_name == "tools/call":
                params=request.get("params")
                if not isinstance(params,dict) or not isinstance(params.get("name"),str):
                    raise ValueError("invalid tool call")
                name=params["name"]
                arguments=params.get("arguments",{})
                if not isinstance(arguments,dict) or self._contains_user_id(arguments):
                    raise ValueError("invalid tool arguments")
                data=self._call_tool(principal,name,arguments)
                response={"content":[{"type":"text","text":json.dumps(data,ensure_ascii=False)}],
                          "structuredContent":data,"isError":not data.get("ok",True)}
                return self._json_response(200,{"jsonrpc":"2.0","id":request_id,"result":response})
            if method_name == "server/discover":
                return self._json_response(200,{"jsonrpc":"2.0","id":request_id,
                    "result":{"serverInfo":{"name":"checkd-planning-remote-test","version":"0.1.0"},
                              "capabilities":{"tools":True},"protocolVersion":PROTOCOL_VERSION}})
            return self._json_response(200,{"jsonrpc":"2.0","id":request_id,
                "error":{"code":-32601,"message":"Method not found"}})
        except (ValueError, TypeError, KeyError):
            return self._json_response(200,{"jsonrpc":"2.0","id":request.get("id") if isinstance(request,dict) else None,
                "error":{"code":-32602,"message":"Invalid params"}})

    def _call_tool(self, principal: RemoteIdentity, name: str,
                   arguments: dict[str, Any]) -> dict[str, Any]:
        schemas={tool["name"]:tool["inputSchema"] for tool in self.tools}
        if name not in schemas:
            return {"ok":False,"error":{"code":"NOT_FOUND","message":"Tool unavailable."}}
        schema=schemas[name]
        if name in LEGACY_M1_TOOL_NAMES:
            if self.legacy_module is None:
                return self._tool_error("LEGACY_COMPATIBILITY_UNAVAILABLE",
                                        "Legacy tool compatibility is unavailable.")
            if not self._valid_schema_value(schema, arguments, root=schema):
                return self._tool_error("INVALID_INPUT", "Tool arguments invalid.")
            return self._call_legacy_tool(principal, name, arguments)
        extra=set(arguments)-set(schema["properties"])
        if extra:
            return {"ok":False,"error":{"code":"INVALID_INPUT","message":"Tool arguments invalid.",
                "details":{"unknown_fields":sorted(extra)}}}
        if any(key not in arguments for key in schema.get("required",[])):
            return {"ok":False,"error":{"code":"INVALID_INPUT","message":"Required argument missing."}}
        for key, value in arguments.items():
            if not self._valid_schema_value(schema["properties"].get(key, {}), value):
                return {"ok":False,"error":{"code":"INVALID_INPUT","message":"Tool arguments invalid.",
                    "details":{"invalid_field":key}}}
        if name == "get_calendar_events":
            return self._get_calendar_events(principal, arguments)
        if name == PERSONAL_LIST_ALIAS:
            return self._call_personal_task_tool(principal,"list_tasks",arguments)
        if name in PERSONAL_TOOL_NAMES:
            return self._call_personal_task_tool(principal,name,arguments)
        if name in {tool["name"] for tool in PROPOSAL_TOOLS}:
            if not self.proposal_writes_enabled:
                return {"ok":False,"error":{"code":"WRITE_BLOCKED",
                    "message":"Proposal creation is not enabled in this environment."}}
            if "planning:propose" not in principal.scopes:
                return {"ok":False,"error":{"code":"INSUFFICIENT_SCOPE",
                    "message":"Current authorization does not allow proposal creation."}}
            if name == "create_plan_proposal":
                return self._create_plan_proposal(principal, arguments)
            if name == "request_plan_approval":
                return self._request_plan_approval(principal, arguments)
        if name in {"list_plan_proposals", "get_plan_proposal"}:
            fetch_proposals = getattr(self.snapshot_provider, "fetch_plan_proposals", None)
            if fetch_proposals is None or not principal.access_token:
                return {"ok":False,"error":{"code":"PROPOSAL_READ_UNAVAILABLE",
                    "message":"Proposal status is unavailable."}}
            limit = arguments.get("limit", 20)
            if type(limit) is not int or not 1 <= limit <= 50:
                return {"ok":False,"error":{"code":"INVALID_INPUT",
                    "message":"Proposal page size must be between 1 and 50."}}
            proposal_id = arguments.get("proposal_id")
            if proposal_id is not None:
                try:
                    if str(UUID(proposal_id)) != proposal_id.lower():
                        raise ValueError
                except (ValueError, AttributeError):
                    return {"ok":False,"error":{"code":"INVALID_INPUT",
                        "message":"Proposal identifier is invalid."}}
            try:
                rows = fetch_proposals(principal, proposal_id=proposal_id, limit=limit)
            except Exception:
                return {"ok":False,"error":{"code":"PROPOSAL_READ_UNAVAILABLE",
                    "message":"Proposal status is unavailable."}}
            if proposal_id is not None:
                if not rows:
                    return {"ok":False,"error":{"code":"NOT_FOUND",
                        "message":"Proposal is unavailable."}}
                return {"ok":True,"proposal":rows[0],"execution_eligible":False}
            return {"ok":True,"items":rows,"limit":limit,"execution_eligible":False}
        from_date=arguments.get("from")
        to_date=arguments.get("to")
        try:
            from_day=date.fromisoformat(from_date)
            to_day=date.fromisoformat(to_date)
            if (from_day.isoformat() != from_date or to_day.isoformat() != to_date
                    or to_day < from_day or (to_day-from_day).days > 90):
                raise ValueError("invalid planning date range")
        except (TypeError, ValueError):
            return {"ok":False,"error":{"code":"INVALID_INPUT","message":"Planning date range invalid."}}
        delay_until = None
        if name == "simulate_task_delay":
            try:
                delay_until=datetime.fromisoformat(arguments["until"].replace("Z","+00:00"))
                if delay_until.tzinfo is None or delay_until.utcoffset() is None:
                    raise ValueError("UTC offset required")
            except ValueError:
                return {"ok":False,"error":{"code":"INVALID_INPUT","message":"Delay timestamp invalid."}}
        try:
            fetch_authenticated = getattr(self.snapshot_provider, "fetch_authenticated", None)
            if fetch_authenticated is not None:
                snapshot=fetch_authenticated(principal,from_date,to_date)
            else:
                snapshot=self.snapshot_provider(principal.checkd_user_id,from_date,to_date)
        except Exception:
            return {"ok":False,"error":{"code":"SNAPSHOT_UNAVAILABLE","message":"Planning data unavailable."}}
        if not isinstance(snapshot, dict) or snapshot.get("subject_ref") != principal.checkd_user_id:
            return {"ok":False,"error":{"code":"NOT_FOUND","message":"Planning data unavailable."}}
        if name == "get_planning_context":
            return {"ok":True,"snapshot":snapshot,"provisional":bool(snapshot.get("provisional",True)),
                    "execution_eligible":False}
        if name == "get_current_plan":
            current_plan = snapshot.get("current_plan")
            if current_plan is None:
                current_plan = {"status":"not_available_in_snapshot","blocks":[]}
            return {"ok":True,"current_plan":current_plan,
                    "snapshot_version":snapshot.get("version"),
                    "provisional":bool(snapshot.get("provisional",True)),
                    "execution_eligible":False}
        if name in {"preview_schedule", "check_schedule_feasibility",
                    "generate_adjustment_draft", "simulate_task_delay"}:
            blockers=snapshot.get("planning_blockers", [])
            if blockers:
                return {"ok":False,"error":{"code":"PLANNING_BLOCKED",
                    "message":"Planning preview is unavailable until required source data is resolved.",
                    "details":{"blockers":blockers}},"provisional":True,
                    "execution_eligible":False}
        if name == "preview_schedule":
            return self.service.handle({"snapshot":snapshot,"operation":"preview",
                "expected_version":arguments.get("expected_version")},principal)
        if name == "check_schedule_feasibility":
            return self.service.handle({"snapshot":snapshot,"operation":"feasibility",
                "expected_version":arguments.get("expected_version")},principal)
        if name == "generate_adjustment_draft":
            result = self.service.handle({"snapshot":snapshot,"operation":"preview",
                "expected_version":arguments.get("expected_version")},principal)
            # This is a calculation result only: no durable proposal, approval,
            # task write, or time-block write is created by this prototype.
            if result.get("ok"):
                result["draft"] = {"status":"preview_only","persistent":False,
                                   "approval_required_before_write":True}
            return result
        if name == "list_plan_risks":
            return self.service.handle({"snapshot":snapshot,"operation":"risk"},principal)
        if name == "simulate_task_delay":
            task_id=arguments["task_id"]
            if task_id not in {task.get("task_id") for task in snapshot.get("tasks",[])}:
                return {"ok":False,"error":{"code":"NOT_FOUND","message":"Task unavailable."}}
            return self.service.handle({"snapshot":snapshot,"operation":"delay",
                "delay":{"task_id":task_id,"until":delay_until.isoformat()}},principal)
        return {"ok":False,"error":{"code":"NOT_FOUND","message":"Tool unavailable."}}

    def _get_calendar_events(self, principal: RemoteIdentity,
                             arguments: dict[str, Any]) -> dict[str, Any]:
        date_range = arguments.get("date_range")
        if (not isinstance(date_range, dict)
                or set(date_range) != {"start", "end"}
                or not isinstance(date_range.get("start"), str)
                or not isinstance(date_range.get("end"), str)):
            return self._tool_error("INVALID_INPUT", "Date range is invalid.")
        start, end = date_range["start"], date_range["end"]
        try:
            first, last = date.fromisoformat(start), date.fromisoformat(end)
            if (first.isoformat() != start or last.isoformat() != end
                    or last < first or (last - first).days > 90):
                raise ValueError
        except (TypeError, ValueError):
            return self._tool_error("INVALID_INPUT", "Date range is invalid.")
        try:
            fetch = getattr(self.snapshot_provider, "fetch_authenticated", None)
            snapshot = (fetch(principal, start, end) if fetch is not None else
                        self.snapshot_provider(principal.checkd_user_id, start, end))
        except Exception:
            return self._tool_error("CALENDAR_UNAVAILABLE", "Calendar data is unavailable.")
        if not isinstance(snapshot, dict) or snapshot.get("subject_ref") != principal.checkd_user_id:
            return self._tool_error("NOT_FOUND", "Calendar data is unavailable.")
        external = arguments.get("external_fixed_events", [])
        if not isinstance(external, list):
            return self._tool_error("INVALID_INPUT", "External events are invalid.")
        # Match the legacy input contract while ensuring external data is only
        # returned as caller-provided context and never persisted or trusted as
        # a CheckD course occurrence.
        return {"ok": True, "source": snapshot.get("source", "unknown"),
            "as_of": snapshot.get("captured_at"),
            "data_window": {"start": start, "end": end},
            "courses": snapshot.get("courses", []),
            "course_rules": snapshot.get("course_rules", []),
            "semesters": snapshot.get("semesters", []),
            "daily_overrides": snapshot.get("daily_item_overrides", []),
            "events": snapshot.get("course_occurrences", []),
            "course_snapshot": snapshot.get("course_snapshot", {}),
            "provisional": bool(snapshot.get("provisional", True)),
            "planning_ready": bool(snapshot.get("planning_ready", False)),
            "execution_eligible": False,
            "external_fixed_events": external}

    def _call_legacy_tool(self, principal: RemoteIdentity, name: str,
                          arguments: dict[str, Any]) -> dict[str, Any]:
        """Compatibility adapter for the original seven argument envelopes.

        Read/preview calls are translated to the authenticated user snapshot.
        Legacy approval tokens and demo apply state are deliberately not reused.
        """
        try:
            inputs = self.legacy_module.validate_envelope(arguments)
            request_id = arguments["request_id"]
            if name in {"list_tasks", "get_calendar_events", "generate_schedule"}:
                start, end = self.legacy_module.date_range(inputs)
                start_text, end_text = start.isoformat(), end.isoformat()
            else:
                start_text = end_text = None
        except Exception as exc:
            return self._legacy_error(arguments.get("request_id"),
                getattr(exc, "code", "INVALID_INPUT"),
                getattr(exc, "message", "Legacy tool arguments are invalid."))

        if name == "list_tasks":
            fetch = getattr(self.snapshot_provider, "fetch_legacy_tasks", None)
            if fetch is None:
                return self._legacy_error(request_id, "TASK_READ_UNAVAILABLE",
                                          "Task list is unavailable.")
            try:
                rows = fetch(principal, statuses=inputs.get("statuses") or ["active"])
            except Exception:
                return self._legacy_error(request_id, "TASK_READ_UNAVAILABLE",
                                          "Task list is unavailable.")
            kinds = set(inputs.get("kinds") or ["recurring", "one_time"])
            tasks = []
            for row in rows:
                kind = row.get("kind")
                if kind not in kinds:
                    continue
                tasks.append(row)
            query_version = hashlib.sha256(json.dumps({
                "user": principal.checkd_user_id, "range": [start_text, end_text],
                "ids": [task.get("task_id") for task in tasks],
            }, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
            return self._legacy_success(request_id, {"query_version": query_version,
                "tasks": tasks, "date_range": {"start": start_text, "end": end_text}})

        if name == "get_calendar_events":
            # Preserve M1's validation for caller-provided external fixed events;
            # they are request context only and never become trusted CheckD data.
            try:
                for event in inputs.get("external_fixed_events") or []:
                    start_at = self.legacy_module.parse_instant(
                        event["start_at"], "start_at")
                    end_at = self.legacy_module.parse_instant(
                        event["end_at"], "end_at")
                    if end_at <= start_at or not (
                            start <= start_at.astimezone(
                                self.legacy_module.TZ).date() <= end):
                        raise ValueError("external event outside query window")
            except Exception:
                return self._legacy_error(request_id, "INVALID_ARGUMENT",
                                          "External fixed event is invalid.")
            result = self._get_calendar_events(principal, {
                "date_range": {"start": start_text, "end": end_text},
                **({"external_fixed_events": inputs["external_fixed_events"]}
                   if "external_fixed_events" in inputs else {}),
            })
            if not result.get("ok"):
                error = result.get("error", {})
                return self._legacy_error(request_id, error.get("code", "CALENDAR_UNAVAILABLE"),
                                          error.get("message", "Calendar data is unavailable."))
            data = {key: result.get(key) for key in (
                "source", "as_of", "data_window", "courses", "course_rules", "semesters",
                "daily_overrides", "events", "course_snapshot", "provisional",
                "planning_ready", "execution_eligible", "external_fixed_events")}
            data["query_version"] = hashlib.sha256(json.dumps({
                "user": principal.checkd_user_id,
                "events": [event.get("occurrence_id") for event in data["events"]],
            }, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
            return self._legacy_success(request_id, data)

        if name == "generate_schedule":
            try:
                for event in inputs.get("external_fixed_events") or []:
                    start_at = self.legacy_module.parse_instant(
                        event["start_at"], "start_at")
                    end_at = self.legacy_module.parse_instant(
                        event["end_at"], "end_at")
                    if end_at <= start_at or not (
                            start <= start_at.astimezone(
                                self.legacy_module.TZ).date() <= end):
                        raise ValueError("external event outside query window")
            except Exception:
                return self._legacy_error(request_id, "INVALID_ARGUMENT",
                                          "External fixed event is invalid.")
            preferences = inputs.get("preferences") or {}
            allowed_preferences = {
                "day_start_minute", "day_end_minute", "minimum_block_minutes"
            }
            if set(preferences) - allowed_preferences:
                return self._legacy_error(request_id, "INVALID_ARGUMENT",
                                          "Planning preferences are invalid.")
            # The shared engine currently reads user-owned preferences from its
            # snapshot. Do not silently claim to apply caller values it cannot
            # yet model. Keep the old schema/name callable and fail closed for
            # non-empty values until the planner accepts these parameters.
            if preferences or inputs.get("external_fixed_events"):
                return self._legacy_error(request_id, "PLANNING_INPUT_UNSUPPORTED",
                    "This preview cannot apply external events or caller preferences yet.")
            result = self._call_tool(principal, "preview_schedule", {
                "from": start_text, "to": end_text,
            })
            if not result.get("ok"):
                return self._legacy_error(request_id,
                    result.get("error", {}).get("code", "PLANNING_UNAVAILABLE"),
                    result.get("error", {}).get("message", "Planning preview is unavailable."))
            result["proposal_status"] = "preview_only"
            result["persistent"] = False
            result["execution_eligible"] = False
            return self._legacy_success(request_id, result)

        if name == "get_approval_status":
            fetch = getattr(self.snapshot_provider, "fetch_plan_proposals", None)
            if fetch is None or not principal.access_token:
                return self._legacy_error(request_id, "APPROVAL_READ_UNAVAILABLE",
                                          "Approval status is unavailable.")
            try:
                proposals = fetch(principal, limit=50)
            except Exception:
                return self._legacy_error(request_id, "APPROVAL_READ_UNAVAILABLE",
                                          "Approval status is unavailable.")
            approval_id = inputs.get("approval_id")
            for proposal in proposals:
                approval = proposal.get("approval")
                if isinstance(approval, dict) and approval.get("id") == approval_id:
                    return self._legacy_success(request_id, {
                        "approval_id": approval_id, "proposal_id": proposal.get("id"),
                        "status": approval.get("status"), "expires_at": approval.get("expires_at"),
                        "approval_token": None,
                    })
            return self._legacy_error(request_id, "NOT_FOUND", "Approval is unavailable.")

        if name == "validate_schedule":
            return self._legacy_error(request_id, "PROPOSAL_REVALIDATION_REQUIRED",
                "Legacy proposals are not executable here; read the current proposal and regenerate if needed.")
        if name in {"request_approval", "apply_approved_changes"}:
            return self._legacy_error(request_id, "WRITE_BLOCKED",
                "Legacy demo approval credentials are not accepted by the user OAuth route.")
        return self._legacy_error(request_id, "NOT_FOUND", "Tool unavailable.")

    @staticmethod
    def _legacy_success(request_id: str, data: dict[str, Any]) -> dict[str, Any]:
        return {"api_version": "checkd.agent.v1", "request_id": request_id,
                "status": "success", "source": "supabase_user_jwt", "data": data,
                "execution_eligible": False}

    @staticmethod
    def _legacy_error(request_id: str | None, code: str, message: str) -> dict[str, Any]:
        return {"api_version": "checkd.agent.v1", "request_id": request_id,
                "status": "error", "source": "supabase_user_jwt",
                "error": {"code": code, "message": message, "retryable": False},
                "execution_eligible": False}

    def _create_plan_proposal(self, principal: RemoteIdentity,
                              arguments: dict[str, Any]) -> dict[str, Any]:
        if not principal.access_token:
            return self._tool_error("AUTH_REQUIRED", "A verified CheckD session is required.")
        start, end = arguments.get("from"), arguments.get("to")
        try:
            start_day, end_day = date.fromisoformat(start), date.fromisoformat(end)
            if start_day.isoformat() != start or end_day.isoformat() != end or end_day < start_day:
                raise ValueError
            if (end_day - start_day).days > 30:
                raise ValueError
        except (TypeError, ValueError):
            return self._tool_error("INVALID_INPUT", "Planning date range is invalid.")
        fetch = getattr(self.snapshot_provider, "fetch_authenticated", None)
        create = getattr(self.snapshot_provider, "create_plan_proposal", None)
        if fetch is None or create is None:
            return self._tool_error("PROPOSAL_UNAVAILABLE", "Proposal service is unavailable.")
        try:
            snapshot = fetch(principal, start, end)
        except Exception:
            return self._tool_error("SNAPSHOT_UNAVAILABLE", "Planning data is unavailable.")
        if not isinstance(snapshot, dict) or snapshot.get("subject_ref") != principal.checkd_user_id:
            return self._tool_error("NOT_FOUND", "Planning data is unavailable.")
        blockers = []
        for key in ("readiness_blockers", "planning_blockers"):
            value = snapshot.get(key, [])
            if not isinstance(value, list):
                blockers.append("snapshot_readiness_invalid")
            else:
                blockers.extend(value)
        if snapshot.get("planning_ready") is not True:
            blockers.append("trusted_snapshot_not_ready")
        source_version = snapshot.get("source_snapshot_version")
        course_digest = snapshot.get("course_occurrence_digest")
        if not isinstance(source_version, str) or not source_version:
            blockers.append("server_snapshot_version_unavailable")
        if not isinstance(course_digest, str) or not course_digest:
            blockers.append("course_occurrence_digest_unavailable")
        if snapshot.get("provisional") is True:
            blockers.append("snapshot_is_provisional")
        if blockers:
            return {"ok":False,"provisional":True,"execution_eligible":False,
                "error":{"code":"PLANNING_NOT_READY",
                    "message":"The trusted planning snapshot is not ready for a proposal.",
                    "details":{"blockers":sorted(set(blockers))}}}
        preview = self.service.handle({"snapshot":snapshot,"operation":"preview",
            "expected_version":snapshot.get("version")}, principal)
        if not preview.get("ok"):
            return {"ok":False,"provisional":True,"execution_eligible":False,
                "error":preview.get("error",{"code":"PLANNING_FAILED",
                    "message":"Planning preview failed."})}
        missing = preview.get("missing_data", {})
        if any(missing.get(key) for key in (
                "unknown_effort_task_ids", "missing_deadline_task_ids",
                "existing_plan_needing_effort_task_ids", "unmodeled_recurring_occurrence_ids")):
            return {"ok":False,"provisional":True,"execution_eligible":False,
                "error":{"code":"PLANNING_DATA_INCOMPLETE",
                    "message":"Unknown work or unresolved task data prevents executable proposals.",
                    "details":{"missing_data":missing}}}
        schedule = preview.get("schedule")
        if (preview.get("outcome") != "found_feasible" or not isinstance(schedule, dict)
                or schedule.get("feasible") is not True
                or schedule.get("hard_constraints_satisfied") is not True
                or schedule.get("unplanned_tasks")):
            return {"ok":False,"provisional":False,"execution_eligible":False,
                "error":{"code":"NO_EXECUTABLE_PLAN",
                    "message":"The planner did not produce a complete feasible plan.",
                    "details":{"outcome":preview.get("outcome")}}}
        raw_blocks = schedule.get("blocks")
        if not isinstance(raw_blocks, list) or not raw_blocks:
            return self._tool_error("NO_CHANGES", "No candidate plan blocks were produced.")
        changes = []
        for block in raw_blocks:
            if not isinstance(block, dict):
                return self._tool_error("PLANNING_FAILED", "Planner output is invalid.")
            changes.append({key:block.get(key) for key in (
                "task_id", "starts_at", "ends_at", "planned_seconds")})
        risk_result = self.service.handle({"snapshot":snapshot,"operation":"risk",
            "expected_version":snapshot.get("version")}, principal)
        risk_summary = risk_result.get("risks", []) if risk_result.get("ok") else []
        request_digest_key = arguments["idempotency_key"]
        try:
            result = create(principal, start=start, end=end,
                snapshot_version=source_version, course_digest=course_digest,
                rules_version="checkd-edf-v1", idempotency_key=request_digest_key,
                changes=changes, risk_summary=risk_summary, buffer_minutes=None)
        except Exception:
            return self._tool_error("PROPOSAL_CREATE_FAILED", "Proposal could not be created.")
        if not result.get("ok"):
            return {"ok":False,"provisional":False,"execution_eligible":False,
                "error":{"code":result.get("code","PROPOSAL_CREATE_FAILED"),
                    "message":"The server rejected the proposal.",
                    "details":{"blockers":result.get("blockers",[])}}}
        return {"ok":True,"proposal":result.get("proposal"),
            "replayed":bool(result.get("replayed")),"preview":preview,
            "provisional":False,"execution_eligible":False,
            "approval_required_before_write":True}

    def _request_plan_approval(self, principal: RemoteIdentity,
                               arguments: dict[str, Any]) -> dict[str, Any]:
        if not principal.access_token:
            return self._tool_error("AUTH_REQUIRED", "A verified CheckD session is required.")
        request = getattr(self.snapshot_provider, "request_plan_approval", None)
        bind = getattr(self.snapshot_provider, "bind_plan_approval_token", None)
        if request is None or bind is None:
            return self._tool_error("APPROVAL_UNAVAILABLE", "Approval service is unavailable.")
        try:
            result = request(principal, arguments["proposal_id"], arguments["idempotency_key"])
            if not result.get("ok"):
                return {"ok":False,"error":{"code":result.get("code","APPROVAL_UNAVAILABLE"),
                    "message":"Approval request was rejected."}}
            approval_id = result.get("approval_id")
            proposal_id = result.get("proposal_id")
            expires_at = datetime.fromisoformat(result["expires_at"].replace("Z", "+00:00"))
            if (not self._valid_uuid(approval_id) or not self._valid_uuid(proposal_id)
                    or expires_at.tzinfo is None or expires_at.utcoffset() is None):
                raise ValueError("invalid approval response")
            token = self._approval_capability(principal.checkd_user_id, approval_id,
                                              proposal_id, int(expires_at.timestamp()))
            token_digest = hashlib.sha256(token.encode("ascii")).hexdigest()
            bound = bind(principal, approval_id, token_digest)
            if not bound.get("ok"):
                return {"ok":False,"error":{"code":bound.get("code","APPROVAL_UNAVAILABLE"),
                    "message":"Approval link could not be issued."}}
            return {"ok":True,"approval_id":approval_id,"proposal_id":proposal_id,
                "status":result.get("status"),"expires_at":result["expires_at"],
                "approval_url":f"{self.approval_base_url}/approval/{approval_id}#{token}",
                "replayed":bool(result.get("replayed")),
                "note":"Opening this one-time link displays the exact proposal and requires an explicit approve or reject click."}
        except Exception:
            return self._tool_error("APPROVAL_UNAVAILABLE", "Approval link could not be issued.")

    def _approval_capability(self, user_id: str, approval_id: str,
                             proposal_id: str, expires_at: int) -> str:
        payload = json.dumps({"user_id":user_id,"approval_id":approval_id,"proposal_id":proposal_id,
                              "expires_at":expires_at},separators=(",",":"),sort_keys=True).encode()
        signature = hmac.new(self.approval_signing_key, payload, hashlib.sha256).digest()
        return self._b64url(payload) + "." + self._b64url(signature)

    def _verify_approval_capability(self, approval_id: str, token: Any,
                                    now: datetime) -> tuple[dict[str, Any], str] | None:
        if not isinstance(token, str) or len(token) > 2048:
            return None
        try:
            encoded, signature = token.split(".", 1)
            payload = self._b64url_decode(encoded)
            expected = hmac.new(self.approval_signing_key, payload, hashlib.sha256).digest()
            if not hmac.compare_digest(signature, self._b64url(expected)):
                return None
            claims = json.loads(payload)
            if (not self._valid_uuid(claims.get("user_id"))
                    or claims.get("approval_id") != approval_id
                    or not self._valid_uuid(claims.get("proposal_id"))
                    or type(claims.get("expires_at")) is not int
                    or int(now.timestamp()) >= claims["expires_at"]):
                return None
            return claims, hashlib.sha256(token.encode("ascii")).hexdigest()
        except (ValueError, TypeError, json.JSONDecodeError, UnicodeEncodeError):
            return None

    def _handle_approval_post(self, route: str, body: bytes,
                              now: datetime) -> tuple[int,dict[str,str],bytes]:
        parts = route.strip("/").split("/")
        if len(parts) not in (2, 3) or parts[0] != "approval" or not self._valid_uuid(parts[1]):
            return self._json_response(404,{"error":"not_found"})
        try:
            value = json.loads(body)
        except (ValueError, UnicodeDecodeError):
            return self._json_response(400,{"error":"invalid_request"})
        if not isinstance(value, dict) or "user_id" in value or set(value) - {"token", "decision"}:
            return self._json_response(400,{"error":"invalid_request"})
        verified = self._verify_approval_capability(parts[1], value.get("token"), now)
        if verified is None:
            return self._json_response(410,{"error":"approval_unavailable"})
        claims, digest = verified
        if len(parts) == 3 and parts[2] == "preview":
            if set(value) != {"token"}:
                return self._json_response(400,{"error":"invalid_request"})
            preview = self.snapshot_provider.get_plan_approval_preview(parts[1], digest)
            if (not preview.get("ok") or preview.get("proposal_id") != claims["proposal_id"]
                    or preview.get("user_id") != claims["user_id"]):
                return self._json_response(410,{"error":"approval_unavailable"})
            public_preview = {key:value for key,value in preview.items() if key != "user_id"}
            return self._json_response(200,public_preview,{
                "Cache-Control":"no-store","Referrer-Policy":"no-referrer"})
        if len(parts) != 2 or parts[2:] or value.get("decision") not in {"approve", "reject"}:
            return self._json_response(400,{"error":"invalid_request"})
        if set(value) != {"token", "decision"}:
            return self._json_response(400,{"error":"invalid_request"})
        result = self.snapshot_provider.decide_plan_proposal(parts[1], digest, value["decision"])
        status = 200 if result.get("ok") else 409
        return self._json_response(status,result,{
            "Cache-Control":"no-store","Referrer-Policy":"no-referrer"})

    def _approval_page(self, approval_id: str) -> tuple[int,dict[str,str],bytes]:
        nonce = self._b64url(secrets.token_bytes(18))
        approval_path = f"/approval/{approval_id}"
        script = """const approvalId = %s;
const approvalPath = '/approval/' + approvalId;
const token = location.hash.slice(1);
history.replaceState(null, '', location.pathname);
const status = document.getElementById('status');
const details = document.getElementById('details');
function showError(message){ status.textContent = message; }
function request(path, data){ return fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},
  cache:'no-store',credentials:'omit',body:JSON.stringify(data)}).then(async r=>({ok:r.ok,data:await r.json()})); }
function render(data){
  status.textContent = '请检查以下方案；选择批准或拒绝。';
  const title=document.createElement('h2'); title.textContent='Proposal '+data.proposal_id; details.appendChild(title);
  for(const change of data.changes||[]){
    const row=document.createElement('p');
    row.textContent=(change.task_name||'任务')+' · '+change.starts_at+' – '+change.ends_at;
    details.appendChild(row);
  }
  const risks=document.createElement('pre'); risks.textContent=JSON.stringify(data.risk_summary||[],null,2); details.appendChild(risks);
  for(const decision of ['approve','reject']){
    const button=document.createElement('button'); button.textContent=decision==='approve'?'批准并应用':'拒绝方案';
    button.onclick=async()=>{ button.disabled=true; const result=await request(approvalPath,{token,decision});
      status.textContent=result.ok ? (decision==='approve'?'方案已批准并执行。':'方案已拒绝，未写入计划。')
        : ('操作未完成：'+(result.data.error||result.data.code||'请重新生成方案。'));
      details.replaceChildren(); };
    details.appendChild(button);
  }
}
if(!token){ showError('审批链接缺少有效凭据。'); }
else { request(approvalPath+'/preview',{token}).then(r=>{
  if(!r.ok){showError('方案已过期或不可用，请回到 WorkBuddy 重新生成。');return;} render(r.data);
}).catch(()=>showError('暂时无法读取方案，请稍后重试。')); }
""" % json.dumps(approval_id)
        html = ("<!doctype html><html lang='zh-CN'><meta charset='utf-8'>"
                "<meta name='viewport' content='width=device-width,initial-scale=1'>"
                "<title>CheckD 方案确认</title><body><main><h1>CheckD 方案确认</h1>"
                "<p id='status'>正在安全读取方案…</p><section id='details'></section></main>"
                f"<script nonce='{nonce}'>{script}</script></body></html>").encode()
        return 200,{"Content-Type":"text/html; charset=utf-8",
                    "Content-Length":str(len(html)),"Cache-Control":"no-store",
                    "Referrer-Policy":"no-referrer",
                    "Content-Security-Policy":f"default-src 'none'; script-src 'nonce-{nonce}'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'"},html

    @staticmethod
    def _b64url(value: bytes) -> str:
        return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")

    @staticmethod
    def _b64url_decode(value: str) -> bytes:
        return base64.urlsafe_b64decode(value + "=" * ((4 - len(value) % 4) % 4))

    @staticmethod
    def _valid_uuid(value: Any) -> bool:
        try:
            return isinstance(value, str) and str(UUID(value)) == value.lower()
        except (ValueError, AttributeError):
            return False

    @staticmethod
    def _tool_error(code: str, message: str) -> dict[str, Any]:
        return {"ok":False,"error":{"code":code,"message":message}}

    @staticmethod
    def _valid_schema_value(spec: dict[str, Any], value: Any,
                            root: dict[str, Any] | None = None) -> bool:
        root = root or spec
        reference = spec.get("$ref")
        if isinstance(reference, str) and reference.startswith("#/$defs/"):
            target = root.get("$defs", {}).get(reference.rsplit("/", 1)[-1])
            return isinstance(target, dict) and RemoteMcpApplication._valid_schema_value(
                target, value, root=root)
        if "const" in spec and value != spec["const"]:
            return False
        if "enum" in spec and value not in spec["enum"]:
            return False
        expected=spec.get("type")
        # JSON Schema permits enum/const-only schemas (used by the original M1
        # contract for array items). Once those constraints pass, absence of a
        # type is valid and must not make the legacy schema stricter.
        if expected is None:
            return True
        if isinstance(expected, list):
            return any(RemoteMcpApplication._valid_schema_value(
                {**spec, "type": option}, value, root=root) for option in expected)
        if expected == "string":
            if not isinstance(value, str):
                return False
            if spec.get("minLength") and len(value) < spec["minLength"]:
                return False
            if spec.get("maxLength") and len(value) > spec["maxLength"]:
                return False
            if spec.get("pattern") and not re.fullmatch(spec["pattern"], value):
                return False
            if spec.get("format") == "date":
                try:
                    return date.fromisoformat(value).isoformat() == value
                except ValueError:
                    return False
            return True
        if expected == "integer":
            return type(value) is int and ("minimum" not in spec or value>=spec["minimum"])
        if expected == "boolean":
            return isinstance(value,bool)
        if expected == "object":
            if not isinstance(value, dict):
                return False
            properties = spec.get("properties", {})
            if spec.get("additionalProperties") is False and set(value) - set(properties):
                return False
            if any(key not in value for key in spec.get("required", [])):
                return False
            return all(RemoteMcpApplication._valid_schema_value(properties[key], item, root=root)
                       for key, item in value.items() if key in properties)
        if expected == "array":
            return (isinstance(value, list) and
                    all(RemoteMcpApplication._valid_schema_value(spec.get("items", {}), item,
                                                                  root=root)
                        for item in value))
        if expected == "null":
            return value is None
        return False

    def _call_personal_task_tool(self, principal: RemoteIdentity, name: str,
                                 arguments: dict[str, Any]) -> dict[str, Any]:
        if name == "resolve_deadline":
            try:
                from datetime import timezone as _timezone
                return {"ok":True,**resolve_deadline(arguments.get("text",""),
                    now=datetime.now(_timezone.utc),
                    timezone=arguments.get("timezone","Asia/Shanghai"))}
            except Exception as exc:
                return {"ok":False,"error":{"code":getattr(exc,"code","INVALID_INPUT"),
                    "message":getattr(exc,"message","无法解析截止时间。")}}
        if not principal.access_token or not self.supabase_url or not self.supabase_publishable_key:
            return {"ok":False,"error":{"code":"AUTH_REQUIRED","message":"当前请求缺少可验证的 CheckD 会话。"}}
        if name in PERSONAL_WRITE_TOOL_NAMES:
            if not self.task_writes_enabled:
                return {"ok":False,"error":{"code":"WRITE_BLOCKED","message":"当前环境未启用任务写入。"}}
            if "task:write" not in principal.scopes:
                return {"ok":False,"error":{"code":"INSUFFICIENT_SCOPE","message":"当前授权不允许任务写入。"}}
        try:
            repository=SupabaseTaskRepository(url=self.supabase_url,
                publishable_key=self.supabase_publishable_key,
                user_access_token=principal.access_token)
            if repository.authenticated_user_id() != principal.checkd_user_id:
                return {"ok":False,"error":{"code":"NOT_FOUND","message":"任务不可用。"}}
            query_service=TaskQueryService(repository)
            if name in PERSONAL_WRITE_TOOL_NAMES:
                from checkd_task_agent.ledger import ConfirmationLedger
                from checkd_task_agent.service import TaskCreationService
                from checkd_task_agent.update_service import TaskUpdateService

                user_ref = hashlib.sha256(principal.checkd_user_id.encode("utf-8")).hexdigest()
                state_root = Path(self.task_agent_state_dir).expanduser().resolve()
                state_root.mkdir(mode=0o700, parents=True, exist_ok=True)
                try:
                    os.chmod(state_root, 0o700)
                except OSError:
                    pass
                ledger = ConfirmationLedger(state_root / f"{user_ref}.sqlite3")
                personal = PersonalMcpApplication(
                    TaskCreationService(ledger, repository), query_service=query_service,
                    update_service=TaskUpdateService(ledger, repository))
            else:
                personal=PersonalMcpApplication(None,query_service=query_service)
            result = personal.call_tool(name, arguments)
            return result if isinstance(result,dict) else {
                "ok":False,"error":{"code":"INTERNAL_ERROR","message":"任务操作失败。"}}
        except Exception as exc:
            code=getattr(exc,"code",None)
            message=getattr(exc,"message",None)
            if code and message:
                return {"ok":False,"error":{"code":code,"message":message,
                    "retryable":bool(getattr(exc,"retryable",False)),
                    "details":getattr(exc,"details",{})}}
            return {"ok":False,"error":{"code":"TASK_READ_FAILED","message":"任务读取失败。"}}

    @staticmethod
    def _contains_user_id(value: Any) -> bool:
        if isinstance(value,dict):
            return any(key.lower() == "user_id" or RemoteMcpApplication._contains_user_id(item)
                       for key,item in value.items())
        if isinstance(value,list):
            return any(RemoteMcpApplication._contains_user_id(item) for item in value)
        return False

    @staticmethod
    def _json_response(status: int, value: dict[str,Any], extra: dict[str,str] | None = None):
        body=json.dumps(value,ensure_ascii=False,separators=(",",":")).encode()
        headers={"Content-Type":"application/json","Content-Length":str(len(body)),**(extra or {})}
        return status,headers,body


def make_http_server(app: RemoteMcpApplication, host: str = "127.0.0.1", port: int = 0) -> ThreadingHTTPServer:
    class Handler(BaseHTTPRequestHandler):
        server_version="CheckDPlanningMCP/0.1"

        def log_message(self, fmt, *args):
            parts = self.requestline.split()
            if len(parts) == 3:
                safe_line = f"{parts[0]} {urlsplit(parts[1]).path} {parts[2]}"
            else:
                safe_line = "request"
            sys.stderr.write(f"{self.address_string()} {safe_line}\n")

        def do_GET(self):
            status,headers,body=app.dispatch_http(method="GET",path=self.path,
                headers={key.lower():value for key,value in self.headers.items()},body=b"")
            self.send_response(status)
            for name,value in headers.items(): self.send_header(name,value)
            self.end_headers()
            if body: self.wfile.write(body)

        def do_POST(self):
            try:
                length=int(self.headers.get("Content-Length","0"))
            except ValueError:
                self.send_error(400)
                return
            if length < 0:
                self.send_error(400)
                return
            if length > 1_048_576:
                self.send_error(413)
                return
            body=self.rfile.read(length)
            status,headers,response=app.dispatch_http(method="POST",path=self.path,
                headers={key.lower():value for key,value in self.headers.items()},body=body)
            self.send_response(status)
            for name,value in headers.items(): self.send_header(name,value)
            self.end_headers()
            if response: self.wfile.write(response)

        def log_message(self, format: str, *args: Any) -> None:
            # HTTP request lines can contain query secrets; deliberately emit no access logs.
            return

    class LocalMcpHTTPServer(ThreadingHTTPServer):
        def server_bind(self):
            # Avoid a reverse DNS lookup during local startup; the bound address is
            # only used for the test server's metadata and does not affect routing.
            socketserver.TCPServer.server_bind(self)
            self.server_name = self.server_address[0]
            self.server_port = self.server_address[1]

    return LocalMcpHTTPServer((host,port),Handler)
