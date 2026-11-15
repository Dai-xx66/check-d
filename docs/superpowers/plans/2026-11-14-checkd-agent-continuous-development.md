# CheckD Agent Continuous Development Implementation Plan

> **For agentic workers:** Implement one testable slice at a time. Preserve unrelated worktree changes and never connect production services.

**Goal:** Strengthen the local planning prototype into a tested, user-isolated system foundation for risk scanning, durable events, and approval previews.

**Architecture:** Keep the Flutter Drift context and deterministic Python planner loosely coupled by a versioned JSON contract. Extend the existing SQLite event prototype with user-scoped risk and proposal state, and keep remote OAuth, authoritative server snapshots, and production writes explicitly outside this implementation.

**Tech Stack:** Flutter/Dart, Drift, Python 3, SQLite, unittest, JSON file/stdio test adapters.

**Spec:** User request “CheckD Agent 下一阶段连续开发任务书”, received 2026-11-14.

## Global Constraints

- Do not connect to or write production data, run migrations, change RLS, publish endpoints, or modify the WorkBuddy production expert.
- Never treat local `verified` test seams, queue emptiness, or FNV content versions as production authentication or cloud-current proof.
- Keep unknown remaining effort unknown and keep TimerSession facts separate from task completion semantics.
- All durable planning, event, risk, approval, retry, and idempotency state must be user-scoped.
- Preserve existing user work; stage only files whose ownership is unambiguous.

## Review Focus

- A heuristic miss can be mistaken for mathematical infeasibility: tests must assert `no_solution_found`/heuristic limits.
- Existing task plans and course blocks can overlap or be double-booked: verify normalized busy intervals and planner output constraints.
- Snapshot inputs may change during capture or after preview: reject reuse when versions/principals differ.
- A user-scoped test seam may be mistaken for OAuth: production authorization remains blocked without a verified CheckD principal.
- Worker retry, duplicate delivery, and approval replay can cause duplicate effects: enforce scoped idempotency and terminal state behavior.

---

### Task 1: Worktree ownership and secret scan

**Files:** No modifications. Inspect Git status, branch/upstream, diffs, untracked paths, and candidate secret files.

- [ ] Record the baseline and classify planning files vs unrelated historical changes.
- [ ] Scan only candidate delivery files for credentials, personal records, and local runtime state; do not print secret values.
- [ ] Decide whether exact-path staging is safe; otherwise leave all changes uncommitted.

### Task 2: Planner contract and algorithm reliability

**Files:** `tools/checkd_planning_engine/src/checkd_planning_engine/{models.py,engine.py,importer.py}`, `tools/checkd_planning_engine/tests/`.

- [ ] Add deterministic/property-style tests for busy interval normalization, overlap constraints, equal deadlines, buffers, dependencies, and chunk tails.
- [ ] Add small exhaustive-oracle cases and preserve the distinction between “no solution found” and proven infeasibility.
- [ ] Implement only contract-compatible, independently tested fixes.

### Task 3: Flutter context provider and snapshot consistency

**Files:** `lib/features/planning/data/`, planning tests, existing auth/provider composition files only if safe.

- [ ] Inspect the actual app auth principal and repository providers; bind the context reader to that principal without accepting caller-supplied ownership.
- [ ] Cover recurring occurrences through CheckD’s canonical occurrence builder, completion state, exact plans, overrides, and timer facts without inferring work remaining.
- [ ] Add before/after local version checks; keep local snapshots advisory and provisional without a server watermark.

### Task 4: Local planning service API

**Files:** `tools/checkd_planning_engine/src/checkd_planning_engine/service.py` (or focused service modules), tests, runner.

- [ ] Expose structured validate, feasibility, delay, compare, risk, and stale-snapshot results behind an injectable principal/context boundary.
- [ ] Add a repeatable JSON/stdio end-to-end test adapter; do not create a public endpoint.

### Task 5: Durable event and risk pipeline

**Files:** existing isolated store plus focused risk scanner and tests.

- [ ] Persist event leases, retry timing, attempts, completion results, and sanitized errors under user scope.
- [ ] Implement overdue planned task, insufficient deadline capacity, and falling-buffer scans with version-bound risk lifecycle and deduplicated notifications.
- [ ] Test crash recovery, lease expiry, duplicate events, concurrent users, same-user concurrency, stale scans, risk resolution, and notification caps.

### Task 6: Private workspace and approval state machine

**Files:** isolated local persistence modules/tests and contract docs.

- [ ] Add isolated preferences/memory/proposal/approval/idempotency records and principal-bound access checks.
- [ ] Implement draft → proposed → approved/rejected → applying → applied/failed/superseded with version binding, replay protection, audit entries, and readback gate; no CheckD writes.
- [ ] Test cross-user proposal, approval, key, revocation, restart, expiry, and partial failure cases.

### Task 7: Preference and critic policy

**Files:** existing preference/risk modules and tests.

- [ ] Preserve objective risk facts across Gentle/Balanced/Direct renderings.
- [ ] Add explicit preference provenance, rest cooldown, significant-change reminders, daily caps, channel-unavailable persistence, and non-judgmental leisure handling.

### Task 8: Remote MCP/OAuth and production gates

**Files:** architecture/decision docs; optional local-only auth interface and tests.

- [ ] Document verified platform capability separately from assumptions and list WorkBuddy validation items.
- [ ] Define the future CheckD Auth binding, scope, revoke, token lifecycle, and per-request principal propagation contract.
- [ ] Keep server snapshot, cloud worker, transactional approval, readback, notification delivery, and Flutter runtime entry explicitly staged.

### Task 9: Route map, full validation, and safe delivery

**Files:** current roadmap and implementation docs only after checking exact ownership.

- [ ] Update M0–M8 statuses as prototype / locally verified / Flutter-integrated / cloud-connected / production-verified.
- [ ] Run Flutter, Dart analysis, Python tests, end-to-end runner, and diff checks.
- [ ] Commit/push only if all candidate files are unambiguously this task’s and no historical changes are mixed; otherwise report the Git blocker without staging.
