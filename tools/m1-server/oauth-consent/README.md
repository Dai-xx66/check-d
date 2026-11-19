# CheckD Supabase OAuth consent UI

This is a minimal standalone Next.js app for Supabase's OAuth authorization
path. Repository inspection found no existing CheckD HTTPS web application or
deployment configuration to extend. This app is prepared for HTTPS deployment;
it has not been published or connected to Production.

## Local run and deployment

1. Copy `.env.example` into the local environment or deployment provider's
   secret settings. Set the CheckD Supabase project URL and publishable key.
   Do not use a service-role key.
2. Run `npm ci`, `npm run typecheck`, `npm run build`, and `npm run start`.
3. Deploy this directory to an HTTPS host. The smallest path is a dedicated
   Vercel project; alternatively, use a CheckD-owned domain/subdomain if its
   owner provides an existing host and DNS access.
4. In Supabase Authentication → URL Configuration, first inspect the existing
   Site URL and redirect allowlist. OAuth Server builds its consent URL from
   that Site URL plus Authorization Path. If the existing Site URL already hosts
   CheckD, mount `/oauth/consent` there. Changing the shared Production Site URL
   could affect existing login redirects and must be reviewed by its owner.
   Set OAuth Server Authorization Path to `/oauth/consent` only when that HTTPS
   route is reachable.
5. Next.js `proxy.ts` refreshes the SSR session. The browser login uses the
   normal CheckD email/password Supabase Auth flow, then returns to the exact
   consent URL with its original `authorization_id`.

## Consent safeguards

- The page reads the current Supabase cookie session and verifies it using
  `auth.getUser()`; it accepts no user ID or email as an identity selector.
- It calls `getAuthorizationDetails(authorization_id)` and displays the client
  name, callback URI, and exact requested scopes.
- The POST decision route checks same-origin, re-checks the signed-in user and
  that the authorization is still pending, then calls Supabase's official
  `approveAuthorization` or `denyAuthorization` method.
- Redirects use only Supabase's returned `redirect_url`. The route does not
  accept a redirect destination from the form.
- No email, token, password, or key is displayed or logged. Responses use
  `Cache-Control: private, no-store`.
- OAuth scopes are not database permissions. `/mcp/user` must validate the
  bearer and pass that same user's JWT to Supabase so RLS remains authoritative.

## Current readiness and blockers

- Read-only check-c probes: the specified OAuth authorization-server discovery
  URL and bare `/auth/v1/oauth/authorize` both returned HTTP 404. OIDC discovery
  returned HTTP 200 and advertised the issuer, authorization/token endpoints,
  PKCE S256, authorization-code/refresh grants, and
  `client_secret_basic`/`client_secret_post`. This does not prove OAuth Server
  is enabled; OAuth authorize is currently unavailable.
- No existing CheckD HTTPS site/deployment config, Supabase OAuth client, or
  WorkBuddy Connector metadata is available in this repository.
- WorkBuddy documentation says the callback is generated from the existing
  Connector `source` and must not be set manually in `oauth2_code`. The exact
  generated callback is not exposed by local files; the Connector owner must
  retrieve/confirm it from WorkBuddy before creating the confidential OAuth
  client. Preserve the existing `source`, tool list, and expert bindings.
- The OAuth token endpoint has not been exercised with Basic auth. Supabase's
  published flow documentation says confidential clients use HTTP Basic with
  `application/x-www-form-urlencoded`, and advertises this auth method in OIDC
  metadata. An actual exchange/refresh still requires an enabled OAuth Server,
  registered client, client secret, one-time code, and PKCE verifier; none are
  available, and no token was requested.
- The old M1 deployment runbook records that its WorkBuddy reverse proxy has
  previously injected or overwritten `Authorization`. The new `/mcp/user`
  route requires the user's `Authorization: Bearer` header. Before updating the
  Connector, the M1 deployment owner must verify that this exact route receives
  the WorkBuddy-issued bearer unmodified; do not fall back to the Demo token.

## Existing M1 service deployment gate

Deploy the current `tools/m1-server/app.py` on the existing M1 HTTPS service,
keeping `/mcp` configured as before. The read-only user route requires:

- `CHECKD_USER_MCP_ENABLED=1`
- `CHECKD_USER_MCP_ENV=production`
- `CHECKD_USER_MCP_PUBLIC_URL=<the actual HTTPS M1 base URL>`
- `CHECKD_USER_SUPABASE_URL=<the CheckD Supabase project URL>`
- `CHECKD_USER_SUPABASE_PUBLISHABLE_KEY=<the project's publishable key>`
- `CHECKD_USER_MCP_OAUTH_CLIENT_IDS=<the registered OAuth client ID>`

Keep the task and Proposal write switches disabled. Check public Protected
Resource Metadata at `/.well-known/oauth-protected-resource/mcp/user`, then
check that an unauthenticated `/mcp/user` request returns an MCP 401 challenge.
The previous anonymous request to the existing `app.workbuddy.host` address
returned 403 without identifying which layer produced it; the route is not yet
verified as deployed. A real bearer-forwarding test requires the WorkBuddy
Connector owner and an authorized test session. Record only HTTP status,
authenticated UID fingerprint, tool name and result count, never token values.

`connector-oauth2-code.patch.json` is an unpublished partial update containing
only `server_auth`. Applying it must merge that field into the current
Connector metadata; it intentionally omits `source`, tools, and expert data so
they remain untouched. Replace the placeholders only in WorkBuddy's managed
secret UI, never in source control.

The existing seven M1 tools remain the compatibility set:
`list_tasks`, `get_calendar_events`, `generate_schedule`, `validate_schedule`,
`apply_approved_changes`, `request_approval`, and `get_approval_status`.
The `/mcp/user` route additionally registers the current Personal Task Agent
and planning tools without duplicate names (22 total in the default local registry;
28 in isolated task-write mode). The original M1 `list_tasks` schema remains
unchanged; the Personal Task Agent pagination schema is available as
`list_one_time_tasks`.
This OAuth patch changes no tool definitions; the two existing experts stay
bound to the same Connector source when its owner applies a server-auth-only
update.
