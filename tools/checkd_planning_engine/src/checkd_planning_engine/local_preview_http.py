"""Loopback-only HTTP bridge for a developer Flutter app and Python planner.

The bridge computes only from a snapshot submitted by Flutter, stores nothing,
and exposes no write operation. Its bearer token is a local test guard, not a
CheckD credential or user authentication mechanism.
"""
from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import argparse
import hmac
import json
import os
from typing import Any

from .service import PlanningService


MAX_REQUEST_BYTES = 2 * 1024 * 1024


def make_local_preview_server(*, token: str, host: str = "127.0.0.1", port: int = 8765):
    if not token or len(token) < 24:
        raise ValueError("local preview token must contain at least 24 characters")
    if host != "127.0.0.1":
        raise ValueError("local preview bridge must bind only to 127.0.0.1")

    class Handler(BaseHTTPRequestHandler):
        server_version = "CheckDLocalPlanningPreview/0.1"

        def log_message(self, _format: str, *_args: object) -> None:
            # Requests contain private task and course data; never log them.
            return

        def do_POST(self) -> None:
            if self.path not in {"/v0/preview", "/v0/delay", "/v0/risks"}:
                self._reply(404, {"ok": False, "error": {"code": "NOT_FOUND"}})
                return
            scheme, _, presented = self.headers.get("Authorization", "").partition(" ")
            if (scheme.lower() != "bearer" or not presented or
                    not hmac.compare_digest(presented, token)):
                self._reply(401, {"ok": False, "error": {"code": "AUTH_REQUIRED"}})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if length <= 0 or length > MAX_REQUEST_BYTES:
                    raise ValueError("request size is invalid")
                payload = json.loads(self.rfile.read(length))
                if not isinstance(payload, dict) or "user_id" in payload:
                    raise ValueError("request envelope is invalid")
                snapshot = payload.get("snapshot")
                if not isinstance(snapshot, dict):
                    raise ValueError("snapshot is required")
                # This subject value scopes only an in-memory computation over
                # the submitted snapshot. The bridge has no database access.
                subject = snapshot.get("subject_ref")
                if not isinstance(subject, str) or not subject:
                    raise ValueError("snapshot subject is required")
                request: dict[str, Any] = {"snapshot": snapshot}
                if self.path == "/v0/preview":
                    request["operation"] = "preview"
                    if "expected_version" in payload:
                        request["expected_version"] = payload["expected_version"]
                elif self.path == "/v0/delay":
                    request["operation"] = "delay"
                    request["delay"] = {
                        "task_id": payload.get("task_id"),
                        "until": payload.get("until"),
                    }
                else:
                    request["operation"] = "risk"
                result = PlanningService(lambda context: context).handle(request, subject)
                code = result.get("error", {}).get("code")
                status = 409 if code == "SNAPSHOT_STALE" else 400 if code else 200
                self._reply(status, result)
            except (ValueError, TypeError, json.JSONDecodeError):
                self._reply(400, {"ok": False, "error": {"code": "INVALID_INPUT"}})
            except Exception:
                # Avoid propagating task contents, auth material, or tracebacks.
                self._reply(500, {"ok": False, "error": {"code": "PLANNING_FAILED"}})

        def _reply(self, status: int, payload: dict[str, Any]) -> None:
            body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    class LoopbackServer(ThreadingHTTPServer):
        allow_reuse_address = True

    return LoopbackServer((host, port), Handler)


def main() -> None:
    parser = argparse.ArgumentParser(description="Local Flutter planning preview bridge")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    token = os.environ.get("CHECKD_PLANNING_PREVIEW_TOKEN", "")
    server = make_local_preview_server(token=token, port=args.port)
    print(json.dumps({"ready": True, "host": "127.0.0.1", "port": server.server_port}), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
