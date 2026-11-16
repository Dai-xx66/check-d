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
- Task create/edit tools remain unregistered on this route until per-user
  confirmation state can be stored in a durable multi-instance server store and
  the authenticated OAuth grant has an explicit write scope. The existing local
  stdio creation/edit flow is not silently promoted to remote production use.
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
