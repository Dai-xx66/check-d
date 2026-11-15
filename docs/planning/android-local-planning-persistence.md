# Android local planning persistence

Status: local Android/Flutter persistence prototype; not cloud approval and not
an execution authorization.

## Local model

- `TaskEffortRecords` stores user-scoped planning estimates and remaining effort.
  Unknown stays `NULL`; TimerSession totals are not converted into remaining work.
- `TaskPlanVersionRecords` stores a local plan revision, its source snapshot
  version, proposal digest, rules version and local state.
- `PlannedTimeBlockRecords` stores one or more proposed time blocks per task and
  plan. A same-owner composite foreign key binds each block to its plan version.
- `PlannedBlockTimerLinks` optionally links an actual TimerSession to a planned
  block. It does not change the timer fact.
- All four tables are local only and do not enqueue Supabase sync operations.

The preview is an in-memory draft. Only the explicit confirmation action writes
a plan, and it writes it as `confirmed` in the local database. `applied` is
reserved for a future server-authorized operation. There is no cloud apply path.

## Save boundary

The repository runs in a Drift transaction. It checks the owner-scoped
idempotency record, reads the live snapshot version, validates current task
ownership, rejects past or overlapping blocks, persists explicitly supplied
remaining effort, supersedes overlapping confirmed local plans, and inserts the
version and all blocks atomically. A version mismatch or any insert failure
rolls back the transaction. Exact retries return the already-saved local plan.

Snapshot versions hash planning content. Collection time and generated
`earliest_start` are excluded because they are clock-derived, while task/course
content, occurrences, existing overrides, timers and effort remain included.
The UI includes a 15-minute review lead for new suggestions. This local version
does not prove Supabase has acknowledged those changes.

## Upgrade and cloud sync

Drift schema v20 adds the tables without rewriting existing task, course or
TimerSession rows. The migration test models a v19 database and verifies that
existing task rows survive. The candidate SQL under
`supabase/proposed_migrations/` is intentionally outside the active migration
directory. It is read-only for authenticated clients until a server-side
snapshot, ownership constraints, version comparison, approval transaction,
idempotency and authoritative readback are designed and reviewed.

Future local-first sync should upload planning estimates and local plan
versions as user-owned records, preserving source snapshot and local status.
The server must issue its own snapshot version and mark a proposal eligible for
approval only after checking its watermark against synchronized task/course
state. Client `confirmed` must never map directly to server `applied`.
