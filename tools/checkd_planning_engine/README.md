# CheckD offline planning prototype

Python 3.11+, standard library only. This isolated prototype never connects to CheckD, Supabase, or WorkBuddy.

Run tests:

```sh
PYTHONPATH=src python3 -m unittest discover -s tests -v
```

Run the deterministic examples:

```sh
PYTHONPATH=src python3 examples/demo.py
PYTHONPATH=src python3 examples/system_walkthrough.py
PYTHONPATH=src python3 examples/trusted_snapshot_walkthrough.py
```

Run the Drift snapshot JSON runner from the Flutter repository root:

```sh
python3 tools/checkd_planning_engine/examples/run_snapshot.py < snapshot.json
```

`PlanningService` is a transport-neutral read-only service boundary for preview, feasibility, delay, comparison, and risk. Its authenticator is injected; tests use a fake principal only. Responses always set `execution_eligible=false`. It is not an HTTP/MCP server and the test authenticator is not production authentication.

`TrustedSnapshotStore` is an isolated SQLite model for a server-owned cloud snapshot revision, per-device local/upload/download watermarks, provisional-vs-current results, TTL-bound proposals, one-time approval, idempotent apply, and readback-only recovery. The apply transaction is atomic inside this local test database; it does not call CheckD or Supabase. A pending local edit or a cloud revision not acknowledged by the device permits display of a provisional suggestion but blocks proposal creation. A concurrent server version change supersedes the proposal before any business write.

`remote_mcp.py` implements the stateless Streamable HTTP MCP protocol surface and remains testable with `TestJwtAuthority` (local tests only). `remote_server.py` is the runnable deployment host. It validates each bearer through CheckD Supabase Auth `/auth/v1/user`, then uses that same user's JWT and the publishable key for PostgREST `GET` requests; it does not contain a service-role path. The request body cannot select a `user_id`. The service intentionally marks every fetched snapshot provisional because it cannot prove that all device-local changes reached the server. It also refuses schedule calculations when course rules exist but canonical Flutter course occurrences have not been resolved. This is a deployable non-production service skeleton, not a WorkBuddy OAuth/Connector integration: no external HTTPS host, CheckD OAuth consent setup, platform allowlist, Connector, or two-account WorkBuddy run has been completed.

### Remote MCP local run / container

The service uses only Python standard-library modules. Set configuration in a local secret manager or untracked environment file; do not put credentials in command arguments, source, connector files, or logs. `SUPABASE_PUBLISHABLE_KEY` must be a publishable/anon key, never a service-role key. Production startup also requires an allowlist of registered WorkBuddy OAuth client IDs, so an ordinary authenticated CheckD App session is not accepted as a WorkBuddy connection.

```sh
export SUPABASE_URL='https://<non-production-project>.supabase.co'
export SUPABASE_PUBLISHABLE_KEY='<non-production-publishable-key>'
export CHECKD_MCP_PUBLIC_URL='https://<temporary-public-host>'
export CHECKD_MCP_OAUTH_ISSUER_URL="$SUPABASE_URL/auth/v1"
export CHECKD_MCP_ENV=development
export PORT=8080
PYTHONPATH=tools/checkd_planning_engine/src python3 -m checkd_planning_engine.remote_server
```

`GET /healthz` returns process health only and is unauthenticated. MCP is `POST /mcp`; OAuth protected-resource metadata is `GET /.well-known/oauth-protected-resource`. For a local-only smoke test, use `CHECKD_MCP_PUBLIC_URL=http://127.0.0.1:8080`; real WorkBuddy cannot call loopback. The Docker image is built from the repository root:

```sh
docker build -f tools/checkd_planning_engine/Dockerfile -t checkd-planning-mcp:dev .
docker run --rm -p 8080:8080 \
  -e SUPABASE_URL -e SUPABASE_PUBLISHABLE_KEY \
  -e CHECKD_MCP_PUBLIC_URL -e CHECKD_MCP_OAUTH_ISSUER_URL \
  -e CHECKD_MCP_OAUTH_CLIENT_IDS \
  checkd-planning-mcp:dev
```

For a short-lived non-production tunnel only, start the service bound to a local port and run `cloudflared tunnel --url http://localhost:8080` in another terminal. Copy its temporary HTTPS hostname into `CHECKD_MCP_PUBLIC_URL`, restart the service, and probe `https://<hostname>/healthz`. Do not use this for stable Connector publication; temporary tunnel URLs change and expose the service publicly. Restrict the Supabase project to disposable test users and disable the tunnel after testing.

Configuration variables:

| Variable | Required | Meaning |
| --- | --- | --- |
| `SUPABASE_URL` | yes | Non-production Supabase project URL |
| `SUPABASE_PUBLISHABLE_KEY` | yes | Publishable/anon key, not service role |
| `CHECKD_MCP_PUBLIC_URL` | yes | Externally visible base URL; HTTPS required for production |
| `CHECKD_MCP_OAUTH_ISSUER_URL` | no | Defaults to `${SUPABASE_URL}/auth/v1` |
| `CHECKD_MCP_OAUTH_CLIENT_IDS` | production required | Comma-separated allowlist of registered WorkBuddy OAuth `client_id` values |
| `CHECKD_MCP_BIND_HOST` | no | Defaults to `0.0.0.0` |
| `PORT` / `CHECKD_MCP_PORT` | no | Defaults to `8080` |
| `CHECKD_MCP_UPSTREAM_TIMEOUT_SECONDS` | no | Defaults to `8` |
| `CHECKD_MCP_ENV` | no | `production` enforces an HTTPS public URL |

The eight contract tools remain registered. `get_planning_context` returns owner-scoped task, course, rule, plan, and effort records with private notes omitted. Task and course reads use PostgREST `GET` plus the verified user's bearer, so existing owner RLS applies. Existing course rules are included, but the Python service does not reproduce Flutter's odd/even week, cancellation, reschedule, or makeup occurrence semantics. Until a pure, permission-reviewed server occurrence read model is available, affected scheduling previews fail closed with `PLANNING_BLOCKED`. Ordinary preview results are provisional and never write data. The present migrations' public snapshot-building RPC has side effects on snapshot/proposal metadata, so this MCP does not call it as a read workaround.

Supabase OAuth scopes are not database read-only grants. Supabase documents its OAuth scopes as controlling OIDC identity data, while table access continues to follow JWT role/grants and RLS. Therefore the MCP tool allowlist and GET-only adapter constrain this service, but do not make a Supabase authenticated JWT intrinsically read-only if it is copied elsewhere. Production use requires a reviewed client-specific read-only RLS/grant design or a dedicated read-only data layer, plus a non-production test first. No Production RLS or schema change is included here.

The Flutter app's **Smart Planning Preview** page can call a separate developer-only bridge, `local_preview_http.py`. It runs on the developer machine, binds to `127.0.0.1`, requires a temporary local bearer guard, accepts only a submitted read-only Drift snapshot, and offers preview/delay/risk computation without persistence or writes. Start it from the repository root:

```sh
cd tools/checkd_planning_engine
export CHECKD_PLANNING_PREVIEW_TOKEN='<generate a random local-only value of at least 24 characters>'
PYTHONPATH=src python3 -m checkd_planning_engine.local_preview_http --port 8765
```

In another terminal at the repository root, export the same token and run the desktop development app with local build defines (do not commit them):

```sh
cd <repository-root>
flutter run -d macos \
  --dart-define=CHECKD_PLANNING_PREVIEW_URL=http://127.0.0.1:8765 \
  --dart-define=CHECKD_PLANNING_PREVIEW_TOKEN="$CHECKD_PLANNING_PREVIEW_TOKEN"
```

The bridge is intentionally not configured in ordinary builds. Mobile devices cannot reach the developer's loopback by default; use a separately reviewed TLS/tunnel setup before attempting a device run. Temporary work estimates/deadlines entered in the preview page affect only that computation and are never persisted. This bridge is a local integration test path, not a production planning service or identity boundary.

Course input must be occurrences already resolved by Flutter's `buildCalendarOccurrencesForDate`; this package does not reproduce semester, odd/even week, cancellation, makeup, or rescheduling rules. Date-only deadlines are inclusive local dates, represented internally as the following local midnight boundary only for calculation; no data is persisted. The EDF slot allocator is deterministic but heuristic: `no_solution_found` means the heuristic did not find a plan, not that infeasibility is mathematically proven. Property-style seeded tests and a small exhaustive EDF oracle are included, but do not establish global optimality.

`IsolatedStore` is an earlier local prototype. Its `verified=True` flag is only a test seam and is not authentication. `PlanningWorkflowStore` adds local SQLite leases/retries, user-scoped workspaces/idempotency, risk lifecycle and pending notification records, and a one-time approval state machine. `LocalTestPrincipal` is also only a local test seam; neither module is a production multi-user service or cross-device event database. Production must inject a principal derived from validated/revocable CheckD authorization, never from tool arguments. No user data is stored in shared global memory.

The local approval prototype never performs CheckD business writes. Its `begin_apply` consumes the local approval and enters `applying`; `finish_apply` models an authoritative readback result and transitions to `applied`, `readback_pending`, or terminal `failed`. `reconcile_readback` only performs readback/state convergence and never re-applies business changes. Any future cloud implementation still needs an atomic server-side version compare, durable one-time approval, real allowlisted writes, and authoritative readback.
