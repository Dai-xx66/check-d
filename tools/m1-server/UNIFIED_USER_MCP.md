# M1 unified CheckD user MCP integration (candidate)

This M1 server contains an **opt-in**, per-request CheckD-authenticated route at
`POST /mcp/user`. Its Protected Resource Metadata is served at
`/.well-known/oauth-protected-resource/mcp/user` (the root metadata path is a
compatibility alias). The old `/mcp` route and its static Demo-token behavior are
not changed by this candidate.

The user route registers 22 unique tools by default. It includes the **original seven M1
tool names and exact input schemas**, sourced from `tools/m1-mock/tool_server.py`,
then adds the five non-duplicate Personal Task Agent read tools, the personal
pagination query as `list_one_time_tasks`, and nine non-duplicate planning read
tools. `list_tasks` is registered only once, using
the original M1 envelope (`api_version`, `request_id`, `timezone`, `input`).
Read and preview calls use the verified CheckD UID and the caller's own JWT for
PostgREST/RLS. Legacy `validate_schedule`, `request_approval`, and
`apply_approved_changes` are preserved as callable names/schema but fail closed
with a compatibility error until connected to the durable trusted Proposal flow;
legacy Demo approval tokens are never accepted. `generate_schedule` is preview
only (`execution_eligible=false`); caller-supplied external events/preferences
remain accepted by the schema but return an explicit unsupported-input error
until the shared planner can apply them correctly. The route never falls back to
Demo data.

The six Personal Task Agent prepare/confirm/cancel tools for task create and edit
can be enabled only in an isolated test deployment with
`CHECKD_USER_MCP_TASK_WRITES_ENABLED=1` and a persistent state directory. They
are omitted by default. Each CheckD user receives a separate SQLite confirmation
ledger file whose name is a hash of the verified Auth user ID; the directory is
restricted to the service account. The adapter maps the explicit local test
switch to `task:write`, but the production builder rejects this mode until a
real WorkBuddy OAuth grant verifier exists. A user JWT still drives PostgREST
and RLS; no service-role credential is used.

## Account route configuration

Enable only in a non-production test deployment until OAuth and data coverage
have been verified:

| Variable | Purpose |
| --- | --- |
| `CHECKD_USER_MCP_ENABLED=1` | Explicitly enable the route; default is off. |
| `CHECKD_USER_SUPABASE_URL` | CheckD Auth/PostgREST project URL. |
| `CHECKD_USER_SUPABASE_PUBLISHABLE_KEY` | Publishable key; never a service-role key. |
| `CHECKD_USER_MCP_PUBLIC_URL` | HTTPS base URL of this deployed service. |
| `CHECKD_USER_SUPABASE_ISSUER` | Optional issuer expected in the CheckD access token; defaults to `<Supabase URL>/auth/v1`. |
| `CHECKD_USER_MCP_OAUTH_CLIENT_IDS` | Comma-separated allowed client IDs; required in production mode. |
| `CHECKD_USER_MCP_ENV` | `development` by default; production requires HTTPS and a client allowlist. |
| `CHECKD_USER_MCP_TASK_WRITES_ENABLED` | Isolated development/test only; enables Personal Task Agent create/edit confirmation tools. Production startup rejects this setting until verified WorkBuddy OAuth grants are implemented. |
| `CHECKD_USER_AGENT_STATE_DIR` | Persistent, access-restricted directory for user-separated confirmation ledgers; required when isolated task writes are enabled. |

The tool server validates each Bearer access token against Supabase Auth `/user`,
binds the authenticated response ID to the token subject, and uses that same
request token for PostgREST so RLS remains active. The Personal Task Agent
query repository independently rechecks the authenticated user ID before each
query. The token is not cached or logged. No request may provide `user_id`.

## WorkBuddy server-side OAuth preparation

The selected mode is WorkBuddy server-side OAuth with a pre-registered Supabase
Confidential OAuth client (`oauth2_code`). Do not use DCR or `mcp_oauth` for
this integration. Update only the existing Connector's `server_auth`; preserve
its source, original seven tools, remaining tool registry, and both expert
bindings. No Connector metadata is present locally, so the unpublished patch
`oauth-consent/connector-oauth2-code.patch.json` deliberately contains only the
`server_auth` object.

The `/mcp/user` route has 22 unique tools by default and preserves the original seven
names/schema. Its Protected Resource Metadata is served at
`/.well-known/oauth-protected-resource/mcp/user`; requests require a user Bearer
and use that same JWT for Supabase Auth validation and PostgREST/RLS. The old
`/mcp` static Demo route was not changed. No request body selects `user_id`.
Production startup requires HTTPS, the CheckD Auth issuer and an OAuth client ID
allowlist; task/proposal writes remain disabled in production.

Candidate WorkBuddy settings (`connector-oauth2-code.patch.json`):

- Authorization URL: `https://cjnrmgxaxkjzvezrurcc.supabase.co/auth/v1/oauth/authorize`
- Token/refresh URL: `https://cjnrmgxaxkjzvezrurcc.supabase.co/auth/v1/oauth/token`
- Scopes: `openid offline_access`
- `pkce_enabled=true`
- `token_auth_method=basic_auth`
- `token_content_type=application/x-www-form-urlencoded`
- `refresh_enabled=true`; `refresh_auth_method=basic_auth`

The check-c OIDC discovery response was HTTP 200 and advertised PKCE S256,
`authorization_code` / `refresh_token`, and confidential-client auth methods
`client_secret_basic` / `client_secret_post`. Supabase's documented confidential
code exchange uses HTTP Basic plus form-urlencoded. This is a documented
protocol match only; actual token exchange and refresh are unverified. The
Supabase OAuth authorization-server discovery URL and a bare authorize endpoint
request both returned HTTP 404, so the OAuth Server must first be enabled and
configured in Dashboard. No token endpoint POST, OAuth client creation, or
Production setting change was made.

WorkBuddy documentation states its callback is generated from the Connector
`source`, rather than entered in `oauth2_code`. Supabase OAuth Apps requires a
redirect URI when creating the Confidential Client. The exact generated URI and
actual Connector `source` are absent from this repository; the Connector owner
must retrieve the callback from the existing Connector/admin preview and provide
it before client creation. Do not change the source or create a second Connector.

The Consent UI is a standalone Next.js app in `oauth-consent/`. It type-checks,
builds and serves local routes, but no existing CheckD HTTPS website or hosting
configuration is present in this repository. It is not deployed. The minimum
hosting/configuration steps are documented in `oauth-consent/README.md`.

A read-only request to the existing `checkd-agent-tools.app.workbuddy.host`
Protected Resource Metadata and `/mcp/user` returned HTTP 403. The response
does not identify which gateway/application layer produced it, so it does not
verify application-level metadata, OAuth, or tool calls.

## Current limitations

- This is direct CheckD JWT authentication, **not** a completed WorkBuddy OAuth
  authorization-code flow or persisted WorkBuddy-subject-to-CheckD binding.
- Supabase Authentication → OAuth Server must be enabled and configured with
  the deployed Consent UI path before this flow can run. DCR is intentionally
  not part of the selected integration.
- The OIDC endpoint does advertise PKCE S256, token exchange, and refresh
  grant metadata. No authorization-code exchange, refresh, callback, or
  revocation was executed. WorkBuddy will need its generated callback URL
  allowlisted by the authorization server; exact Dashboard support remains
  unverified.
- WorkBuddy pre-registration, token delivery, current user task/course reads,
  refresh, and expired-token behavior have not been tested with a real Connector.
  The legacy `X-Demo-Token` route is not user OAuth and does not establish
  individual CheckD identities.
- Task create/edit tools remain disabled by default. An isolated test deployment
  can opt in to exercise the existing confirmation flow against synthetic data;
  this is not production authorization. A durable shared ledger for multiple
  server instances and a verified WorkBuddy per-user OAuth write grant are still
  required before production enablement.
- Planning snapshots are provisional. Device sync watermarks are unavailable;
  course rules are not converted through Flutter's occurrence builder, so
  schedule tools fail closed when unresolved course rules exist. No result is
  executable or writable.
- The original seven tools are now registered on `/mcp/user` with their exact
  original input schemas. Approval/apply calls deliberately fail closed there;
  this is schema/name compatibility, not a claim that trusted Proposal approval
  or real plan writes are available through WorkBuddy.

An isolated local Supabase run has verified two synthetic users can each read
their own task list/search/detail and run a provisional planning preview through
this route; cross-user task-detail lookup is concealed by RLS. This is a local
integration test, not WorkBuddy OAuth evidence. The existing online service and
Connector have not been changed by this branch.
