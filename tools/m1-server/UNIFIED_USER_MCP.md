# M1 unified CheckD user MCP integration (candidate)

This M1 server now contains an **opt-in**, per-request CheckD-authenticated
account route at `POST /mcp/user`. The existing `POST /mcp` route and its seven
static demo tools remain unchanged for compatibility. The new route merges the
Personal Task Agent's six read-only tools with the seven non-duplicate planning
tools, for 13 uniquely named tools. Its `list_tasks` is the Personal Task Agent
query implementation; the planner's duplicate `list_tasks` schema is not
registered. The route never falls back to demo data.

The original seven legacy tools remain available unchanged at `/mcp`. On the
account route the duplicate `list_tasks` name is registered once, with the
Personal Task Agent schema and real user-JWT query implementation. The account
route also includes `get_planning_context`, `get_current_plan`,
`preview_schedule`, `check_schedule_feasibility`, `generate_adjustment_draft`,
`simulate_task_delay`, `list_plan_risks`, `resolve_deadline`,
`search_tasks`, `get_tasks_by_date`, `list_overdue_tasks`, and
`get_task_detail`. Full WorkBuddy Connector/OAuth integration remains blocked
on platform user-token forwarding and registration details.

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

## Current limitations

- This is direct CheckD JWT authentication, **not** a completed WorkBuddy OAuth
  authorization-code flow or persisted WorkBuddy-subject-to-CheckD binding.
- WorkBuddy ability to forward each user's CheckD token to the route is not
  verified. Do not replace the existing connector configuration yet.
- Task create/edit tools remain disabled by default. An isolated test deployment
  can opt in to exercise the existing confirmation flow against synthetic data;
  this is not production authorization. A durable shared ledger for multiple
  server instances and a verified WorkBuddy per-user OAuth write grant are still
  required before production enablement.
- Planning snapshots are provisional. Device sync watermarks are unavailable;
  course rules are not converted through Flutter's occurrence builder, so
  schedule tools fail closed when unresolved course rules exist. No result is
  executable or writable.
- Proposal/approval/apply remain absent from the account route. The legacy
  approval tools are demo-only and are not called by the account route. No task
  create/edit/delete or plan apply is permitted there.

An isolated local Supabase run has verified two synthetic users can each read
their own task list/search/detail and run a provisional planning preview through
this route; cross-user task-detail lookup is concealed by RLS. This is a local
integration test, not WorkBuddy OAuth or production evidence. Before a WorkBuddy
test, deploy only to an isolated HTTPS service with a non-production Supabase
project and verify the platform's per-user OAuth behavior. The existing online
service and Connector have not been changed by this branch.
