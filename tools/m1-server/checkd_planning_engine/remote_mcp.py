"""Local Streamable HTTP MCP skeleton with a per-request bearer auth boundary.

Only safe read-only planning tools are registered. TestJwtAuthority is a local
test issuer, not WorkBuddy OAuth, Supabase Auth, or a production token source.
The production verifier must validate a real CheckD authorization and its
explicit WorkBuddy-subject -> CheckD-user binding on every request.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from datetime import date
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import socketserver
from typing import Any, Callable, Protocol
from urllib.parse import urlparse
from uuid import UUID

from checkd_task_agent.mcp_server import McpApplication as PersonalMcpApplication
from checkd_task_agent.mcp_server import TOOLS as PERSONAL_AGENT_TOOLS
from checkd_task_agent.query_service import TaskQueryService
from checkd_task_agent.supabase import SupabaseTaskRepository
from checkd_task_agent.timeparse import resolve_deadline

from .service import PlanningService


PROTOCOL_VERSION = "2025-11-25"
RESOURCE_METADATA_PATH = "/.well-known/oauth-protected-resource"


def _load_registered_tools() -> tuple[dict[str, Any], ...]:
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
    return tuple(tools)


TOOLS = _load_registered_tools()
PERSONAL_READ_TOOL_NAMES = frozenset({
    "resolve_deadline", "list_tasks", "search_tasks", "get_tasks_by_date",
    "list_overdue_tasks", "get_task_detail",
})
PERSONAL_WRITE_TOOL_NAMES = frozenset({
    "prepare_task_creation", "create_task", "cancel_task_creation",
    "prepare_task_update", "update_task", "cancel_task_update",
})
PERSONAL_TOOL_NAMES = PERSONAL_READ_TOOL_NAMES | PERSONAL_WRITE_TOOL_NAMES
_PERSONAL_READ_TOOLS = tuple(
    tool for tool in PERSONAL_AGENT_TOOLS if tool.get("name") in PERSONAL_READ_TOOL_NAMES
)
_PLANNING_TOOLS = tuple(tool for tool in TOOLS if tool.get("name") != "list_tasks")


@dataclass(frozen=True)
class RemoteIdentity:
    checkd_user_id: str
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
                 task_agent_state_dir: str | None = None):
        self.verifier=verifier
        self.audience=audience
        self.snapshot_provider=snapshot_provider
        self.resource_metadata_url=resource_metadata_url
        self.authorization_server_url=authorization_server_url
        self.supabase_url=supabase_url
        self.supabase_publishable_key=supabase_publishable_key
        self.task_writes_enabled = bool(task_writes_enabled)
        self.task_agent_state_dir = task_agent_state_dir
        if self.task_writes_enabled and not self.task_agent_state_dir:
            raise ValueError("persistent per-user task agent state directory is required")
        personal_tools = tuple(
            tool for tool in PERSONAL_AGENT_TOOLS
            if tool.get("name") in (PERSONAL_TOOL_NAMES if self.task_writes_enabled
                                    else PERSONAL_READ_TOOL_NAMES)
        )
        self.tools=tuple((*personal_tools,*_PLANNING_TOOLS))
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
        if method == "GET" and path == RESOURCE_METADATA_PATH:
            return self._json_response(200,self.metadata())
        if method == "GET" and path == "/healthz":
            return self._json_response(200,{"status":"ok","service":"checkd-planning-mcp"})
        if path != "/mcp":
            return self._json_response(404,{"error":"not_found"})
        if method != "POST":
            return self._json_response(405,{"error":"method_not_allowed"},{"Allow":"POST"})
        accept=headers.get("accept","")
        content_type=headers.get("content-type","").split(";",1)[0].strip().lower()
        if content_type != "application/json" or not {
            "application/json","text/event-stream"
        }.issubset({part.strip().split(";",1)[0] for part in accept.split(",")}):
            return self._json_response(406,{"error":"not_acceptable"})
        authorization=headers.get("authorization","")
        scheme,_,token=authorization.partition(" ")
        try:
            if scheme.lower() != "bearer" or not token:
                raise PermissionError("missing bearer token")
            principal=self.verifier.verify(token,audience=self.audience,now=now)
        except Exception:
            challenge=f'Bearer resource_metadata="{self.resource_metadata_url}", error="invalid_token"'
            return self._json_response(401,{"error":"invalid_token"},{"WWW-Authenticate":challenge})
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
        if name in PERSONAL_TOOL_NAMES:
            return self._call_personal_task_tool(principal,name,arguments)
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

    @staticmethod
    def _valid_schema_value(spec: dict[str, Any], value: Any) -> bool:
        expected=spec.get("type")
        if isinstance(expected, list):
            return any(RemoteMcpApplication._valid_schema_value(
                {**spec, "type": option}, value) for option in expected)
        if expected == "string":
            return isinstance(value,str) and (not spec.get("minLength") or len(value)>=spec["minLength"])
        if expected == "integer":
            return type(value) is int and ("minimum" not in spec or value>=spec["minimum"])
        if expected == "boolean":
            return isinstance(value,bool)
        if expected == "object":
            return isinstance(value,dict)
        if expected == "array":
            return isinstance(value,list)
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

        def do_GET(self):
            status,headers,body=app.dispatch_http(method="GET",path=urlparse(self.path).path,
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
            status,headers,response=app.dispatch_http(method="POST",path=urlparse(self.path).path,
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
