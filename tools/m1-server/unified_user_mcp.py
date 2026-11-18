"""Opt-in account-scoped planning MCP mounted by the M1 HTTP service.

This path accepts a CheckD Supabase access token per request. Supabase Auth is
intended to be the OAuth authorization server for WorkBuddy server-side OAuth;
this module is the resource-server/token-validation adapter, not an OAuth AS.
It is separate from M1's legacy static demo-token path and remains opt-in.
"""
from __future__ import annotations

import os

from checkd_planning_engine.remote_mcp import RemoteMcpApplication
from checkd_planning_engine.supabase_remote import (
    SupabaseAccessTokenVerifier,
    SupabaseRestSnapshotProvider,
)


def build_from_env(*, legacy_module=None) -> RemoteMcpApplication:
    required = (
        "CHECKD_USER_SUPABASE_URL",
        "CHECKD_USER_SUPABASE_PUBLISHABLE_KEY",
        "CHECKD_USER_MCP_PUBLIC_URL",
    )
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise RuntimeError("Missing required environment variables: " + ", ".join(missing))

    base_url = os.environ["CHECKD_USER_MCP_PUBLIC_URL"].rstrip("/")
    supabase_url = os.environ["CHECKD_USER_SUPABASE_URL"].rstrip("/")
    issuer = os.environ.get(
        "CHECKD_USER_SUPABASE_ISSUER", supabase_url + "/auth/v1"
    )
    mode = os.environ.get("CHECKD_USER_MCP_ENV", "development").lower()
    task_writes_enabled = os.environ.get("CHECKD_USER_MCP_TASK_WRITES_ENABLED", "0") == "1"
    proposal_writes_enabled = os.environ.get(
        "CHECKD_USER_MCP_PROPOSAL_WRITES_ENABLED", "0"
    ) == "1"
    approval_signing_secret = os.environ.get("CHECKD_APPROVAL_SIGNING_KEY", "")
    approval_base_url = os.environ.get(
        "CHECKD_USER_MCP_APPROVAL_BASE_URL", base_url
    ).rstrip("/")
    task_agent_state_dir = os.environ.get("CHECKD_USER_AGENT_STATE_DIR")
    client_ids = frozenset(
        item.strip()
        for item in os.environ.get("CHECKD_USER_MCP_OAUTH_CLIENT_IDS", "").split(",")
        if item.strip()
    )
    if mode == "production":
        if not base_url.startswith("https://") or not supabase_url.startswith("https://"):
            raise RuntimeError("HTTPS is required in production")
        if issuer != supabase_url + "/auth/v1":
            raise RuntimeError("OAuth issuer must match this Supabase project's Auth issuer")
        if not client_ids:
            raise RuntimeError("registered OAuth client IDs are required in production")
        if task_writes_enabled:
            raise RuntimeError(
                "task writes require verified WorkBuddy per-user OAuth grants; "
                "the direct Supabase JWT adapter is not sufficient"
            )
        if proposal_writes_enabled:
            raise RuntimeError(
                "proposal writes require verified WorkBuddy OAuth identity and approval delivery; "
                "the isolated direct CheckD JWT approval-link adapter is not production auth"
            )
    if proposal_writes_enabled:
        if mode not in {"isolated", "test"}:
            raise RuntimeError("proposal writes are available only in isolated environments")
        if len(approval_signing_secret.encode("utf-8")) < 32:
            raise RuntimeError("CHECKD_APPROVAL_SIGNING_KEY must contain at least 32 bytes")
        if not approval_base_url.startswith(("http://", "https://")):
            raise RuntimeError("CHECKD_USER_MCP_APPROVAL_BASE_URL must be an absolute URL")
    if task_writes_enabled and not task_agent_state_dir:
        raise RuntimeError("CHECKD_USER_AGENT_STATE_DIR is required when task writes are enabled")

    try:
        timeout = float(os.environ.get("CHECKD_USER_MCP_UPSTREAM_TIMEOUT_SECONDS", "8"))
    except ValueError as exc:
        raise RuntimeError("upstream timeout must be numeric") from exc
    if timeout <= 0 or timeout > 30:
        raise RuntimeError("upstream timeout is out of range")

    key = os.environ["CHECKD_USER_SUPABASE_PUBLISHABLE_KEY"]
    verifier = SupabaseAccessTokenVerifier(
        supabase_url=supabase_url,
        publishable_key=key,
        allowed_oauth_client_ids=client_ids,
        expected_issuer=issuer,
        timeout_seconds=timeout,
        task_writes_enabled=task_writes_enabled,
        proposal_writes_enabled=proposal_writes_enabled,
    )
    provider = SupabaseRestSnapshotProvider(
        supabase_url=supabase_url,
        publishable_key=key,
        timeout_seconds=timeout,
    )
    return RemoteMcpApplication(
        verifier=verifier,
        audience=base_url + "/mcp/user",
        snapshot_provider=provider,
        resource_metadata_url=(base_url
            + "/.well-known/oauth-protected-resource/mcp/user"),
        authorization_server_url=issuer,
        supabase_url=supabase_url,
        supabase_publishable_key=key,
        task_writes_enabled=task_writes_enabled,
        task_agent_state_dir=task_agent_state_dir,
        proposal_writes_enabled=proposal_writes_enabled,
        legacy_module=legacy_module,
        approval_signing_key=(approval_signing_secret.encode("utf-8")
                              if proposal_writes_enabled else None),
        approval_base_url=(approval_base_url if proposal_writes_enabled else None),
    )
