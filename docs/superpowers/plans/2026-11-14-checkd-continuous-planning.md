# CheckD Continuous Planning Prototype Implementation Plan

> **For agentic workers:** Native execution; no Git operations.

**Goal:** Deliver an isolated offline deterministic planning and multi-user workspace prototype with contracts, tests, and a production integration roadmap.

**Architecture:** Keep a pure Python planning core independent from Flutter, Supabase, and the existing Personal Task Agent. Accept resolved course occurrences and verified principal context at adapter boundaries; persist prototype events and workspace state in per-user-scoped SQLite tables.

**Tech Stack:** Python 3.11 standard library, `datetime`, `zoneinfo`, `sqlite3`, `unittest`, JSON Schema.

**Spec:** User attachment `已粘贴的文本.txt` and multi-user additions in this chat.

## Global Constraints

- No Production writes, migrations, RLS changes, public deployment, or Git writes.
- Do not modify Flutter business logic, Personal Task Agent, or WorkBuddy runtime configuration.
- Course occurrences must be supplied by the existing Flutter occurrence builder adapter; the Python prototype does not claim parity for semester rules.
- Unknown identity is denied; never fall back to the project owner.

## Review Focus

- Date-only deadlines must not be converted into persisted instants; planning uses an exclusive local next-day boundary.
- Heuristic failure means “no plan found,” not proven mathematical infeasibility.
- User scope must be derived from verified principal, never request `user_id`.
- Event retries and idempotency must be scoped by user and dedupe key.
- Preference inference must not silently become a hard constraint.

---

## Planned deliverables

- `tools/checkd_planning_engine/`: independent package, deterministic scheduler, delay simulation, risks, preferences, scoped workspace/event store, contracts, examples and tests.
- `docs/architecture/2026-11-14-checkd-continuous-planning.md`: architecture, consistency and multi-user threat model.
- `docs/contracts/agent-planning-v0.json`: candidate read/write tool contracts; not registered in WorkBuddy.
- `docs/plans/2026-11-14-checkd-planning-roadmap.md`: M0–M8 implementation plan.

## Execution checklist

- [x] Inspect attachment, repository constraints, existing schema and Flutter course builder.
- [ ] Implement offline scheduler and delay analysis.
- [ ] Implement risk and preference policy modules.
- [ ] Implement scoped SQLite event/workspace prototype and isolation tests.
- [ ] Add contracts, architecture, examples, and roadmap.
- [ ] Run all isolated tests and verify the existing 12-tool MCP registry is unchanged.
