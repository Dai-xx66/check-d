# CheckD Android Planning Sync and WorkBuddy Implementation Plan

> **For agentic workers:** This task is being executed by the current agent under the user's explicit continuous-development authorization.

**Goal:** Extend the verified Android local planning feature toward per-user cloud sync, MCP access, approval, and durable risk processing without touching Production.

**Architecture:** Keep Drift as the offline-first local store and do not create a second task authority. Add planning-data sync through the existing queue only after ownership, version, conflict, and tombstone behavior are covered; retain the already isolated Python planning/MCP/workflow prototypes for service-side integration tests. No cloud capability is considered production-ready until a non-production PostgreSQL environment and real WorkBuddy OAuth/HTTPS tenant are verified.

**Tech Stack:** Flutter/Dart, Drift, Supabase/PostgreSQL (isolated only), Python planning engine and SQLite prototypes, Android AVD.

**Spec:** Current user request in the conversation; existing local planning persistence in `docs/planning/android-local-planning-persistence.md`.

## Global Constraints

- No Production writes, migrations, RLS changes, public deployment, or WorkBuddy production-expert changes.
- Do not clear/overwrite device data or upload the Mac's 111 pending operations.
- Use current-user ownership from trusted auth context, never caller-provided `user_id`.
- Android only; no iOS/macOS-specific work.
- Keep local confirmed plans distinct from server-approved/applied plans.

## Review Focus

- Course conflicts must use Flutter's canonical occurrence builder and be evidenced with the exact AVD inputs and resulting time blocks.
- Sync retries/conflicts/tombstones must never let older cloud state replace newer local state.
- OAuth and any mock identity must remain visibly separate from real WorkBuddy/CheckD authorization.
- Approval writes must be transactional, version-bound, idempotent, and readback-verified in isolated PostgreSQL only.
- Risk events must be durable/recoverable and must not depend on Android background execution.

---

### Task 1: Isolated AVD course-avoidance acceptance

**Files:** No app-code changes unless an observed defect is reproduced. Evidence goes in the final report.

- [x] Verify the isolated `CheckD_Planning_Isolated` AVD and CheckD Debug package.
- [x] Save a synthetic course in the AVD; use the pre-existing synthetic `Planning_demo` task with preview-only deadline/effort inputs.
- [x] Candidate `2026-11-15 21:09–22:09` followed the course `20:30–21:00`; no overlap. Evidence is in `docs/audits/2026-11-15-android-course-avoidance-avd.md`.
- [x] Odd/even week parity, cancellation, reschedule, extra course, and Drift-to-planner avoidance covered by the targeted Flutter tests (11 passed).

### Task 2: Planning-data sync adapter

**Files:** Existing `lib/core/sync/`, planning records in `lib/core/database/`, targeted tests, and a proposed migration outside active production migrations.

- [x] Reused the existing authenticated-user queue; new planning rows use parent-before-child upload ordering and stable conflict keys.
- [x] Added local outbox writes for effort, plan versions, time blocks, and TimerSession links; downloads apply only owner-matched rows and skip entities with pending/failed local writes.
- [x] Added an additive migration with per-owner RLS, composite ownership foreign keys, no direct DELETE grants, and version metadata. It was applied only to a temporary local Supabase project on non-default ports and then stopped.
- [ ] Physical tombstones for individual blocks/effort are not represented by the current Drift model. Plan replacement is retained as `superseded`; cross-device revision/idempotency collisions fail closed and remain sync failures for user-visible recovery.

### Task 3: Unified read-only planning MCP

**Files:** Existing Python `remote_mcp.py`, service contracts, tests, and integration notes.

- [x] Expanded the candidate MCP contract to eight read-only tools: task listing, context, current plan, preview, feasibility, delay, adjustment draft, and risks.
- [x] Added per-request binding resolver interface; WorkBuddy subject is not assumed to be a CheckD user id, and an unbound/misbound identity is rejected.
- [x] Tests cover user spoofing, two-user scope, misbound snapshots, and non-persistent draft output.
- [ ] Real WorkBuddy Connector/OAuth, persisted CheckD consent binding, HTTPS endpoint, and tenant verification remain BLOCKED.

### Task 4: Approval, PostgreSQL, and risk event integration

**Files:** Existing Python trusted snapshot/workflow stores and isolated tests; proposed SQL only unless an isolated PostgreSQL service is available.

- [ ] Proposal approval/apply transactions have not been implemented or tested in PostgreSQL. Existing approval and risk lifecycle tests remain SQLite prototypes; the PostgreSQL test only validated the planning-sync schema/RLS/ownership boundary.
- [x] Existing SQLite event/risk tests passed in the full Python suite, covering event restart/retry, concurrent users, risk reevaluation, resolution, cooldown, and notification caps.
- [ ] Keep Production and Android background execution out of scope.

### Task 5: Verification and Git delivery

- [x] Full Flutter suite: 249 passed. Full Python unittest suite: 90 passed. Scoped Dart analysis: no issues. `git diff --check` and MCP contract JSON parse passed.
- [ ] Stage only files belonging to this task, commit on `codex/checkd-planning-delivery`, and push only that branch.
- [ ] Report each external blocker and required user-provided configuration precisely.
