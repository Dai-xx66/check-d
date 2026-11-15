# CheckD Cloud Planning Closure Implementation Plan

> **For agentic workers:** Execute the scoped tasks in order in the existing `codex/checkd-planning-delivery` worktree. The owner explicitly authorized autonomous implementation and isolated testing; do not use subagents.

**Goal:** Strengthen planning sync, validate server-side approval and risk persistence in isolated PostgreSQL, and extend the authenticated read-only MCP boundary without claiming production OAuth readiness.

**Architecture:** Drift remains the offline-first client authority. Cloud planning rows are user-owned replicas with conflict/tombstone semantics. PostgreSQL approval and risk records are tested only in a temporary local Supabase stack. The shared remote MCP derives CheckD identity from a server-side binding resolver, never request-supplied user IDs.

**Tech Stack:** Flutter/Dart, Drift, Supabase/PostgreSQL local stack, Python planning/MCP code, SQLite prototype comparisons.

**Spec:** User request in the active conversation; previous delivery plan at `docs/superpowers/plans/2026-11-15-checkd-planning-sync-workbuddy.md`.

## Global Constraints

- Never connect to or write Production, run Production migrations, modify Production RLS, publicly deploy, or alter the WorkBuddy production expert.
- Do not clear device data or upload the Mac's 111 pending operations.
- Keep task ownership in the existing task authority; no second task table.
- A mock principal or approval is test-only, not real OAuth or WorkBuddy user approval.
- Do not claim release readiness from local-stack tests.

## Review Focus

- Local pending outbox rows must win over stale cloud copies; test both upload retries and download ordering.
- A deleted planning block must not resurrect on another device; test tombstone replay and conflict.
- Approval identity, proposal version, and exact change digest must be checked before mutation.
- An interrupted/unknown apply must recover by readback without a second business write.
- A risk event repeated or retried must persist once per user and remain independently readable.

---

### Task 1: Planning sync conflict and tombstone contract

**Files:** `lib/core/database/app_database.dart`, generated Drift file only if schema changes; `lib/features/planning/data/planning_plan_repository.dart`; `lib/core/sync/sync_upload_service.dart`; `lib/core/sync/sync_download_service.dart`; `supabase/migrations/`; focused sync tests.

- [x] Added Drift v21 tombstone columns for effort and time blocks (with repository tombstone operation for blocks), PlanVersion supersession lineage, and owner-scoped local conflict records with local/remote payloads.
- [x] Added idempotent tombstone upload, tombstone download convergence, pending-local conflict retention and owner-scoped conflict reads.
- [x] Tested v19/v20 Drift upgrades, replacement history, repeated tombstone, stale cloud suppression and user A/B isolation with focused Flutter tests.
- [ ] Conflict selection UI and a complete policy for concurrent PlanVersion revision collisions remain incomplete; revisions fail closed at unique constraints.
- [x] Applied all migrations in the dedicated local Supabase project and exercised approval, RLS, event lease/retry and risk snapshot SQL tests. No Production database was connected.

### Task 2: PostgreSQL approval transaction

**Files:** planning service Python package, isolated migration, PostgreSQL integration tests, SQLite behavior comparison tests.

- [x] Added owner-bound Proposal/Approval tables, exact change digest, base snapshot version, expiration and apply-idempotency records.
- [x] Added an authenticated-user PostgreSQL RPC that locks proposal/snapshot, checks approval and digest, atomically creates a plan/version/blocks, and verifies readback.
- [ ] Snapshot rotation after apply is currently an opaque concurrency fence. A trusted builder that recomputes task/course/plan source digests is still required before any proposal can be considered production-safe.
- [x] SQL integration test covers successful readback, same-key replay, new-key denial, cross-user NOT_FOUND, expiry, snapshot conflict and FK failure rollback.
- [x] A separate-session concurrent same-key apply test proves two callers receive the same stored result and only one business block is written; competing proposals are rejected after the first apply rotates the version fence.
- [ ] Full response-loss-after-commit transport simulation remains untested; same-key retry is verified directly against the stored PostgreSQL result.
- [ ] WorkBuddy human authorization remains BLOCKED. SQL fixtures set approval rows directly and are not real user approval.

### Task 3: Unified MCP and revocable identity binding

**Files:** `tools/checkd_planning_engine/src/checkd_planning_engine/remote_mcp.py`, service composition/configuration, tests, tool contract JSON.

- [ ] The current delivery branch contains the planning MCP only; personal task creator/query/editor tool sources are absent from this worktree, so the combined tool set and write regressions cannot be integrated here without the owning source module.
- [x] Existing planning service requires per-request token verification and a server-side WorkBuddy-subject-to-CheckD binding resolver; unbound and misbound identities fail closed in tests.
- [ ] WorkBuddy remote Connector/OAuth registration and live multi-account revoke/expiry test remain blocked on tenant, app registration and HTTPS host.

### Task 4: Persistent risk processing in isolated PostgreSQL

**Files:** risk/event service package, isolated migration, scanner/worker tests, MCP read path.

- [x] Added isolated PostgreSQL risk-event, risk-state and notification tables; event claims use expiring leases and fencing tokens; retry/dead/done transitions are persisted.
- [x] Added isolated SQL risk snapshot persistence, resolution on disappearance, owner-scoped reads, user dismissal cooldown, critical escalation and notification dedupe.
- [x] Verified the same risk can notify again after its dismissal cooldown expires, while a critical escalation bypasses an active cooldown.
- [ ] A scheduled server scanner still needs a trusted snapshot source and deployment scheduler; Android is not treated as a permanent worker.
- [ ] MCP currently reads planning risks from its scoped snapshot provider, not these PostgreSQL tables; database-backed risk read integration remains incomplete.

### Task 5: End-to-end isolated acceptance and delivery

- [ ] Flutter outbox/download is verified with deterministic remote fakes, and PostgreSQL apply with isolated SQL fixtures; one automated test does not yet carry the same Drift data over real local Supabase REST into apply and back down.
- [x] Full Flutter suite and Python suite pass; local Supabase migrations and SQL workflow script pass; focused Dart analysis, contract JSON parse and diff check pass.
- [x] Committed and pushed only the 14 verified in-scope paths on `codex/checkd-planning-delivery`; no merge or force push.
