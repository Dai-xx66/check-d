"""Runnable stateless Streamable HTTP MCP host for non-production deployment."""
from __future__ import annotations

import os

from .remote_mcp import make_http_server
from .supabase_remote import build_remote_application_from_env


def main() -> None:
    host = os.environ.get("CHECKD_MCP_BIND_HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", os.environ.get("CHECKD_MCP_PORT", "8080")))
    public_url = os.environ.get("CHECKD_MCP_PUBLIC_URL", "")
    environment = os.environ.get("CHECKD_MCP_ENV", "development").lower()
    if environment == "production" and not public_url.startswith("https://"):
        raise SystemExit("CHECKD_MCP_PUBLIC_URL must use HTTPS in production")
    if not public_url.startswith(("https://", "http://localhost", "http://127.0.0.1")):
        raise SystemExit("CHECKD_MCP_PUBLIC_URL must be HTTPS, or local HTTP for development")
    application = build_remote_application_from_env()
    server = make_http_server(application, host=host, port=port)
    print(f"CheckD remote MCP listening on {host}:{server.server_address[1]}", flush=True)
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
