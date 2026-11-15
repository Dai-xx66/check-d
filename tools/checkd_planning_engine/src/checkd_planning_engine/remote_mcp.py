"""Local Streamable HTTP MCP skeleton with a per-request bearer auth boundary.

Only safe read-only planning tools are registered. TestJwtAuthority is a local
test issuer, not WorkBuddy OAuth, Supabase Auth, or a production token source.
The production verifier must validate a real CheckD authorization and its
explicit WorkBuddy-subject -> CheckD-user binding on every request.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from datetime import date
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import base64
import hashlib
import hmac
import json
from pathlib import Path
import secrets
import socketserver
from typing import Any, Callable, Protocol
from urllib.parse import urlparse

from .service import PlanningService


PROTOCOL_VERSION = "2025-11-25"
RESOURCE_METADATA_PATH = "/.well-known/oauth-protected-resource"


def _load_registered_tools() -> tuple[dict[str, Any], ...]:
    """Load tool schemas from the repository's canonical candidate contract."""
    repository_root = Path(__file__).resolve().parents[4]
    contract_path = repository_root / "docs/contracts/agent-planning-v0.json"
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


@dataclass(frozen=True)
class RemoteIdentity:
    checkd_user_id: str
    workbuddy_subject: str
    scopes: frozenset[str]
    expires_at: int


class AccessTokenVerifier(Protocol):
    def verify(self, token: str, *, audience: str, now: datetime) -> RemoteIdentity: ...


class IntrospectionTokenVerifier:
    """Production-facing adapter contract; the injected introspector must be trusted."""
    def __init__(self, introspect: Callable[[str], dict[str, Any] | None]):
        self._introspect = introspect

    def verify(self, token: str, *, audience: str, now: datetime) -> RemoteIdentity:
        claims = self._introspect(token)
        if not isinstance(claims, dict) or claims.get("active") is not True:
            raise PermissionError("inactive access token")
        expiry = claims.get("exp")
        audiences = claims.get("aud")
        if isinstance(audiences, str):
            audiences = [audiences]
        workbuddy_subject = claims.get("sub")
        checkd_user_id = claims.get("checkd_uid")
        raw_scopes = claims.get("scope", "")
        scopes = frozenset(raw_scopes.split()) if isinstance(raw_scopes, str) else frozenset(raw_scopes or [])
        if (not isinstance(expiry, int) or int(now.timestamp()) >= expiry
                or not isinstance(audiences, list) or audience not in audiences
                or not isinstance(workbuddy_subject, str) or not workbuddy_subject
                or not isinstance(checkd_user_id, str) or not checkd_user_id):
            raise PermissionError("token claims invalid")
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
                 resource_metadata_url: str, authorization_server_url: str):
        self.verifier=verifier
        self.audience=audience
        self.snapshot_provider=snapshot_provider
        self.resource_metadata_url=resource_metadata_url
        self.authorization_server_url=authorization_server_url
        self.service=PlanningService(lambda context: context.checkd_user_id)

    def metadata(self) -> dict[str, Any]:
        return {
            "resource":self.audience,
            "authorization_servers":[self.authorization_server_url],
            "scopes_supported":["planning:read"],
            "bearer_methods_supported":["header"],
        }

    def dispatch_http(self, *, method: str, path: str, headers: dict[str,str],
                      body: bytes, now: datetime | None = None) -> tuple[int,dict[str,str],bytes]:
        now=now or datetime.now(timezone.utc)
        if method == "GET" and path == RESOURCE_METADATA_PATH:
            return self._json_response(200,self.metadata())
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
                return self._json_response(200,{"jsonrpc":"2.0","id":request_id,"result":{"tools":list(TOOLS)}})
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
        schemas={tool["name"]:tool["inputSchema"] for tool in TOOLS}
        if name not in schemas:
            return {"ok":False,"error":{"code":"NOT_FOUND","message":"Tool unavailable."}}
        schema=schemas[name]
        if set(arguments)-set(schema["properties"]):
            return {"ok":False,"error":{"code":"INVALID_INPUT","message":"Tool arguments invalid."}}
        if any(key not in arguments for key in schema.get("required",[])):
            return {"ok":False,"error":{"code":"INVALID_INPUT","message":"Required argument missing."}}
        for key, value in arguments.items():
            if not isinstance(value, str) or not value:
                return {"ok":False,"error":{"code":"INVALID_INPUT","message":"Tool arguments invalid."}}
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
            snapshot=self.snapshot_provider(principal.checkd_user_id,from_date,to_date)
        except Exception:
            return {"ok":False,"error":{"code":"SNAPSHOT_UNAVAILABLE","message":"Planning data unavailable."}}
        if name == "get_planning_context":
            if snapshot.get("subject_ref") != principal.checkd_user_id:
                return {"ok":False,"error":{"code":"NOT_FOUND","message":"Planning data unavailable."}}
            return {"ok":True,"snapshot":snapshot,"provisional":bool(snapshot.get("provisional",True)),
                    "execution_eligible":False}
        if name == "preview_schedule":
            return self.service.handle({"snapshot":snapshot,"operation":"preview",
                "expected_version":arguments.get("expected_version")},principal)
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
            length=int(self.headers.get("Content-Length","0"))
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
