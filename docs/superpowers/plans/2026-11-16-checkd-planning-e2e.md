# CheckD Planning E2E Integration Implementation Plan

> **For agentic workers:** Execute this plan in the existing `codex/checkd-planning-delivery` worktree. Keep all Supabase execution local and synthetic; do not touch Production or production RLS.

**Goal:** Carry one synthetic user dataset from Drift through local Supabase sync, server snapshot validation, planning, approval, atomic apply, and Drift readback.

**Architecture:** Keep CheckD task/course tables authoritative and add a server-owned snapshot RPC that derives a canonical digest/version from synchronized source rows. Exercise it with a dedicated local Supabase project and isolated Android AVD; approval fixtures remain explicitly synthetic. Resolve local sync conflicts only through an owner-scoped explicit choice that preserves the unselected payload for audit.

**Tech Stack:** Flutter/Dart + Drift, local Supabase/PostgreSQL, existing Dart planning engine, Python test/worker tools.

**Spec:** User request in the active conversation; current planning/sync migrations and `docs/superpowers/plans/2026-11-15-checkd-cloud-planning-closure.md`.

## Global Constraints

- No Production writes, migrations, RLS changes, public service deployment, or WorkBuddy production expert changes.
- Never clear the existing phone database or upload the Mac's pending operations.
- Never treat test identities or synthetic approvals as real WorkBuddy consent.
- Keep unknown work estimates unknown and fail closed on stale snapshots.

## Review Focus

- Server snapshot must be based on rows committed in Supabase, not caller-supplied DTOs; verify owner binding and digest changes.
- Course exceptions and semester rules must not silently diverge from Flutter occurrence semantics; add parity fixtures for supported rules and return unsupported data as incomplete.
- An Android outbox write must be acknowledged before server proposal creation; test pending local writes and cloud version drift.
- Conflict resolution must preserve both variants and require explicit owner selection; test cross-user rejection and restart persistence.
- Risk rescans must be idempotent, resumable, and readable only by the owning user; test retry, dismissal cooldown, and resolution.

---

### Task 1: Server-owned snapshot and stale-proposal invalidation

**Files:** new local-only migration; SQL workflow tests; snapshot RPC adapter/tests.

- [x] Build a user-bound canonical snapshot from synced tasks, course rules/overrides, effort, and plan rows in one transaction. The RPC derives `auth.uid()` and limits the date range.
- [x] Persist canonical JSONB SHA-256 digest and monotonic revision; source-row triggers dirty the version and supersede un-applied proposals / expire approvals.
- [x] Test owner binding, stable version for identical content, course occurrence normalization, unknown deadlines/effort, source mutation invalidation, zero-write stale apply, and same-data snapshot-to-approval-RPC-to-readback in the local Supabase project.
- [ ] Still blocked from execution eligibility: no device sync watermark proves the server has the newest local-first state; current branch cloud schema lacks the four Stage 14A date/deadline columns; course occurrence parity needs more fixtures (单双周、停课、调课、补课) before removing the blocker.

### Task 2: One-dataset Android-to-PostgreSQL round trip

**Files:** isolated integration harness, Android integration test, local Supabase fixture script.

- [ ] Android AVD → actual app `SyncQueue` → isolated Supabase was not completed. AVD is present, but this branch has no automated authenticated Android-to-local-Supabase harness or common proposal-creation service.
- [x] A local SQL integration fixture now uses the same synthetic user/task/course/effort to build a server snapshot, mutate source data to reject an old proposal, then create an explicitly synthetic approved proposal against the refreshed snapshot, atomically apply and read back the block.
- [ ] No Android download/display in the same run. The SQL test inserts the synthetic Proposal/Approval as the isolated DB test principal; this is not real human or WorkBuddy consent and is not the full requested product E2E.

### Task 3: Conflict recovery

**Files:** planning repository, sync/download service, focused Flutter tests.

- [x] Add owner-scoped `keep_local` / `keep_remote` resolution that records the choice and preserves both payloads.
- [x] Test both resolutions and cross-user rejection in Drift. Existing tests also cover tombstone writes and superseded-plan reads.
- [ ] Remote conflict synchronization/retry across actual devices, restart recovery, and paired tombstones remain unverified.

### Task 4: Durable risk scan/read path

**Files:** local worker/SQL tests and owner-scoped read adapter.

- [ ] A scheduled cloud risk scanner is not implemented. Existing PostgreSQL lease/retry and risk persistence RPCs are exercised by SQL tests, and Python local prototypes test event/risk lifecycle.
- [ ] Owner-scoped database reads exist through RLS, while MCP `list_plan_risks` computes risks for a supplied server-scoped snapshot. It does not yet read persisted PostgreSQL risk states; no cloud worker or App risk inbox is wired.

### Task 5: WorkBuddy non-production handoff

**Files:** deployment/configuration guide and unified MCP composition only if source modules are present.

- [x] Verify source: the planning remote MCP exists; the personal task MCP is not integrated with its authentication boundary.
- [x] Document WorkBuddy tenant/Connector, OAuth, HTTPS, CheckD identity binding and two-account revoke/isolation steps; live checks remain blocked until permissions and test tenant exist.

### Task 6: End-to-end verification and delivery

- [x] Run full Flutter (255 tests), Python (90 tests), local PostgreSQL migration + cloud workflow + concurrent apply tests, Dart analysis, targeted analysis, and `git diff --check`.
- [ ] Android-to-Supabase integration was not run; Git commit/push remains pending final scope review.

## Execution notes — 2026-11-16

- The isolated Supabase project is `/tmp/checkd-planning-sync-validation`; no linked or remote project was used.
- All fixture SQL runs inside a transaction and rolls back. A local DB reset recreated only that temporary container.
- `dart analyze` reports 59 existing lint/info issues; none is in the Dart files changed in this task. Targeted analysis for changed Dart files is clean.
- The server snapshot is trusted as a view of **committed cloud rows only**. It deliberately remains non-executable when device freshness, full deadline schema/history, or course parity is unverified.
- Full Android → Supabase → approval → Android readback remains the next integration blocker, not a passed test.
