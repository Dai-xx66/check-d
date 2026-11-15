# M2 Drift → Planning read-only integration

## Implemented path

`PlanningContextRepository.load(from, through, now)` is exposed by the Riverpod `planningSnapshotProvider`, using the same `currentDataOwnerProvider` and user-scoped repositories as the app screens. It gathers task details through `TaskRepository`, courses/templates through `CourseRepository`, semester dates through `SemesterRepository`, date-specific exceptions through `DayScheduleRepository`, and timer facts plus pending/failed queue state from Drift. Reads execute in a Drift transaction. For each date it calls `TaskRepository.watchTasksForDate` and CheckD's canonical `buildCalendarOccurrencesForDate`; resolved course events enter the snapshot, and recurring occurrences become occupied blocks only when an explicit target duration and scheduled minute exist. The DTO is serialized to JSON and `tools/checkd_planning_engine/examples/run_snapshot.py` passes it to the Python importer and deterministic scheduler.

Only active, pending one-time tasks with a supported deadline and known effort are emitted as schedulable demand. The committed `TaskDetails` model at the delivery base exposes the current `scheduledAt`, but does not expose date-only/exact deadline or `availableFrom` fields; those DTO values remain null and such tasks appear in `missing_deadline_task_ids` rather than receiving invented deadlines. A task with `planned_at` and known effort becomes an existing occupied block so it is not scheduled twice; if effort is unknown, it is surfaced in `existing_plan_needing_effort_task_ids` and no duration is guessed. Due recurring occurrences are resolved through the existing Task Repository and calendar builder; untimed occurrences remain visible in `unmodeled_recurring_occurrence_ids`. Timer facts are evidence, not an automatic estimate of remaining effort or completion. Completed sessions do not occupy future availability. Overrides with explicit start/end ranges are emitted as existing occupied blocks.

## Version and synchronization meaning

The local version is a stable FNV-1a 64-bit digest over normalized planning DTO content, excluding capture time and the version field. It changes when the serialized planning inputs change; it is a local cache/version hint, not a security digest or server base version. The local queue can show pending/failed operations, but an empty queue does not prove the server has received every device change. Therefore the context reports `sync_state=unknown` when no pending entries are found, `provisional=true` always, and `execution_eligible=false` always.

Python `assert_snapshot_current` rejects a changed local version, principal mismatch, pending state, or previously provisional snapshot. It prevents stale-preview reuse within the local prototype, but cannot certify cloud freshness.

## Not yet complete

- Paused tasks are read for context but omitted from schedulable one-time demand; archived task history is excluded.
- A recurring task's target duration is a planned target, not measured remaining effort. Occurrence blocks are advisory reservations; the snapshot never derives recurring remaining effort from TimerSession.
- Exact existing plans without explicit known remaining effort cannot reserve a duration and are surfaced for clarification.
- No authoritative server snapshot version, download watermark, or synced-outbox acknowledgement is available. Real CheckD live account access and safe server-current claims are blocked.
- In-flight timers and task completion histories are not yet included as demand-adjustment inputs; only finished TimerSession facts are exported.

## Production integration gates

Flutter should expose a user-scoped, transaction-consistent snapshot DTO plus per-user outbox watermark and dirty-range state. Supabase should issue a server-generated base version over tasks, reminders, course rules, templates, semesters, overrides, completions, sessions, and existing plan blocks. MCP must verify the CheckD OAuth principal on every request and ignore any client-supplied user ID. WorkBuddy platform identity must be explicitly bound to CheckD Auth identity through a supported OAuth authorization flow; the mapping and revoke path require platform verification.

Preview responses remain advisory while local sync is pending/unknown. Before approval, the server re-reads the full basis snapshot and verifies its version/digest. Applying changes later requires an atomic version compare, user/proposal-bound one-time approval, scoped idempotency, a narrow write allowlist, and authoritative readback; any mismatch returns failure. This M2 code has no schedule write operation.

## Minimum dependency for deadline and availability fields

The `codex/checkd-planning-delivery` base (`70d76cb`) does not contain the Stage 14A deadline model. In that committed revision, `TaskDetails` exposes `scheduledAt` but not `deadline`, `availableFrom`, or `plannedDate`; `OneTimeReminderRecords` likewise contains `scheduledAt` and `hasScheduledDate` only. The planning adapter therefore preserves the missing values as JSON `null`, and the importer reports tasks with no usable deadline as missing-data/unknown. This is intentional: no date or remaining work is inferred.

A separate, uncommitted project workspace currently contains a candidate dependency: `supabase/migrations/202609150001_stage_14a_task_deadline_foundation.sql` adds `available_from`, `planned_date`, `due_date`, and `due_at` to `one_time_reminders`, while the corresponding local Drift table, generated database schema, task draft/model, and `TaskRepository` mapping expose and persist those values. None of those files is included from that workspace in this delivery branch. Before the planner may consume non-null deadlines and availability, merge the reviewed minimum dependency set together: (1) the Stage 14A schema migration and its migration verification, (2) Drift table/schema version and generated code, and (3) `TaskDeadline`/`TaskDetails` plus `TaskRepository` read/write mapping. Verify date-only and exact-instant deadline semantics independently. Until that dependency is reviewed and merged, planning snapshots must keep deadline and availability unknown/null and must not become execution-eligible.

## WorkBuddy test-tenant two-account acceptance runbook

Current tenant readiness is **BLOCKED**: this repository has no WorkBuddy test tenant/Connector registration, no externally reachable HTTPS MCP endpoint, no CheckD OAuth authorization server, and no two disposable CheckD test accounts. The included `remote_mcp.py` is loopback-only and its test token issuer is not an identity provider. Do not connect the hosted WorkBuddy service to it or treat local protocol tests as tenant acceptance.

When those prerequisites are provided, use one test Connector and one shared test Expert (never a second copy of the production Expert):

1. Deploy the read-only MCP skeleton to a private test HTTPS host; configure WorkBuddy Connector OAuth (`auth_mode: server-side`) and complete the required WorkBuddy Connector review/allowlisting. Do not enable write tools.
2. Configure a CheckD test OAuth authorization service that binds the OAuth subject to the validated CheckD Auth user ID. Ensure access tokens have audience, `planning:read` scope, expiry, and per-user revocation/introspection. The WorkBuddy platform account ID must not be assumed to equal the CheckD user ID.
3. Create disposable CheckD users A and B with distinct non-sensitive task fixtures. Connect both WorkBuddy test sessions to the same Expert, authorizing each CheckD account independently.
4. From session A call `get_planning_context`, then call it from B. Verify each response contains only that account's fixture. Record only HTTP result, anonymized fixture labels, and opaque test run IDs.
5. From A submit B's task ID to `simulate_task_delay`; expect a non-enumerating denial (`NOT_FOUND` or the service's uniform inaccessible-resource result) and no change to either fixture. Repeat with A's proposal/approval identifiers supplied to B if proposal tools are later enabled.
6. Revoke A's CheckD grant at the authorization service. Replay A's previously issued bearer token: expect HTTP 401/authorization failure. Confirm B's existing session still succeeds.
7. Restart the MCP process and repeat the scoped reads and A-token rejection. Verify no process-global identity/session cache causes one account to inherit another's principal.

Acceptance evidence: both users authorize separately; each sees only their own fixture; cross-user identifiers disclose no resource existence and cause no mutation; A's revoked token fails after revocation propagation; B remains authorized; restart preserves these outcomes. Required inputs before this test can run: WorkBuddy test tenant/workspace and Connector review path, test HTTPS hosting, a CheckD test OAuth/Auth binding and revocation mechanism, and two disposable CheckD accounts. WorkBuddy's current Connector documentation describes remote MCP over HTTP/Streamable HTTP and recommends cloud-hosted OAuth via `auth_mode: "server-side"`; platform-specific Connector approval and tenant behavior still require hands-on verification.
