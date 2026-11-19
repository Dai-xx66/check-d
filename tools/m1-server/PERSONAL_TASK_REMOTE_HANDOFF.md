# Personal Task Agent remote MCP handoff (candidate)

This handoff describes the source tree only. It does not claim the public M1
host, WorkBuddy OAuth, or the shared expert has been updated. Keep the existing
`/mcp` Demo route and its seven input schemas unchanged. Do not replace either
entry in `~/.workbuddy/mcp.json`; the existing entries are
`checkd-agent-tools` (HTTP) and `checkd-personal-task-agent` (stdio).

## The twelve personal tools

The original input schemas and business implementations are in
`checkd_task_agent/mcp_server.py`. The account route is `/mcp/user`. It validates
the bearer for every request through Supabase Auth, derives the CheckD UID from
Auth's user response, and uses that same bearer with PostgREST/RLS. No tool
argument may select `user_id`. These are account-route mappings:

| Original tool | Account-route name | Input schema (required; optional) | Implementation | Permission and state |
| --- | --- | --- | --- | --- |
| `resolve_deadline` | unchanged | `text`; `timezone` | original `timeparse.resolve_deadline` | local read, no ledger |
| `prepare_task_creation` | unchanged | `name`, `expected_duration_minutes`, `idempotency_key`; `deadline_date`, `deadline_at`, `planned_at`, `notes`, `timezone` | original `TaskCreationService` | isolated `task:write`; pending draft in per-user SQLite ledger, no cloud write |
| `create_task` | unchanged | `confirmation_id`, `user_confirmation_text` | original `TaskCreationService` | isolated `task:write`; consumes original phrase, idempotent cloud write and readback |
| `cancel_task_creation` | unchanged | `confirmation_id` | original `TaskCreationService` | isolated `task:write`; cancels pending draft |
| `list_tasks` | **`list_one_time_tasks`** | none; `include_completed`, `limit`, `offset` | original `TaskQueryService.list_tasks` | `planning:read`; one-time tasks, pagination |
| `search_tasks` | unchanged | `query`; `include_completed`, `limit`, `offset` | original `TaskQueryService` | `planning:read` |
| `get_tasks_by_date` | unchanged | `date`; `include_completed`, `limit`, `offset`, `timezone` | original `TaskQueryService` | `planning:read` |
| `list_overdue_tasks` | unchanged | none; `limit`, `offset`, `timezone` | original `TaskQueryService` | `planning:read` |
| `get_task_detail` | unchanged | `task_id` | original `TaskQueryService` | `planning:read` |
| `prepare_task_update` | unchanged | `task_id`, `changes`, `idempotency_key` | original `TaskUpdateService` | isolated `task:write`; pending change and original snapshot in per-user ledger |
| `update_task` | unchanged | `update_confirmation_id`, `user_confirmation_text` | original `TaskUpdateService` | isolated `task:write`; original phrase, concurrency check, idempotent update and readback |
| `cancel_task_update` | unchanged | `update_confirmation_id` | original `TaskUpdateService` | isolated `task:write`; cancels pending change |

The original M1 `list_tasks` stays at its existing name and envelope schema on
both routes. It cannot also expose the Personal pagination schema under that
same name. The alias preserves the Personal schema without duplicate
registration. The six Personal write tools are absent from the default
production registry. They are available only when the isolated task-write
switch and a persistent state directory are configured. The default registry
has 22 unique tools; isolated task-write mode has 28. `resolve_deadline` needs
no database, but the route still requires a valid bearer before exposing it.

The confirmation phrase and per-user ledger are copied from the existing
Personal Task Agent business layer, not reimplemented. The SQLite path is the
hash of the verified CheckD UID under `CHECKD_USER_AGENT_STATE_DIR`. This
protects records from another user in the isolated deployment and survives a
process restart when the volume is retained. It is not a distributed durable
ledger. A model can submit a phrase it has seen; the phrase alone does not
prove a human confirmed in WorkBuddy. Therefore production task writes remain
fail-closed until a verifiable per-user WorkBuddy authorization and human
confirmation signal are implemented and tested. Do not set production mode to
`isolated` to bypass this gate.

## M1 deployment and OAuth read-only checklist

1. Keep the existing M1 host and `/mcp` route. Deploy this source to that same
   host only after its owner approves deployment; preserve the old service
   release for rollback. Set the read-only variables listed in
   `oauth-consent/README.md` through the host's secret manager. Keep task and
   Proposal write switches at `0`.
2. Host the Consent UI at an approved HTTPS CheckD origin. In Supabase Auth,
   enable OAuth Server and configure its consent URL. Create a confidential
   OAuth app using the **exact** callback that WorkBuddy displays for the
   existing Connector. Neither the callback nor the Connector source is in
   this repository; do not infer either.
3. In the existing WorkBuddy Connector, update only the server-side OAuth
   configuration using `oauth-consent/connector-oauth2-code.patch.json` as a
   candidate. Enter the client secret only in the managed secret UI. Preserve
   Connector source, old seven tool schemas and both expert definitions.
4. Before changing any expert binding, verify that WorkBuddy forwards each
   user's bearer unchanged to `/mcp/user`, and run `initialize`, `tools/list`,
   `list_one_time_tasks`, `get_calendar_events`, and `get_task_detail` with an
   authorized test account. Record only UID fingerprints and result counts.
5. The owner of the existing Personal Task Agent expert can then update its
   tool binding to the verified remote route while retaining its expert ID,
   name, persona and sharing entry. Check the old QR/link with another account
   after saving; whether WorkBuddy preserves it is a platform acceptance item.
   Leave the MOCK scheduling expert bound to the original `/mcp` route.
6. Test two separate WorkBuddy accounts: each authorizes its own CheckD
   account, each sees only its own task and course IDs, cross-user task lookup
   is denied, expired/revoked tokens are rejected, and one user's revocation
   does not affect the other. This is **not yet verified in WorkBuddy**.

Before any local `mcp.json` change, save a permission-restricted backup outside
the repository and show a redacted diff that contains only entry names, type,
URL host/path and header *names*. Never print header values. This handoff does
not require or perform a local config change; server-side OAuth should use the
managed Connector rather than storing credentials in `mcp.json`.

## Local checks and rollback

Run the targeted Python tests from `tools/m1-server` with
`PYTHONPATH=. python3 -m unittest tests.planning_runtime.test_remote_mcp
tests.planning_runtime.test_supabase_remote
tests.planning_runtime.test_unified_user_mcp tests.test_user_mcp_route
tests.personal_agent.test_mcp_server -q`. Also run the OAuth Consent UI
`npm run typecheck` and a build with non-secret placeholder public config.
The route tests verify that `/mcp` still has its original seven tools and that
an unconfigured `/mcp/user` fails closed.

If remote authorization or bearer forwarding fails, restore the prior M1
release and the previous Connector server-auth field. Keep the original
Personal expert bound to its working stdio configuration until remote reads
are accepted; keep the MOCK expert and share links untouched. Rollback does
not require a database migration or deletion of user data.
