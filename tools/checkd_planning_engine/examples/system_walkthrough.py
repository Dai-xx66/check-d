#!/usr/bin/env python3
"""Reproducible, local-only walkthrough of planning and private workflow cases."""
from __future__ import annotations

from datetime import date, datetime, timedelta
import json
from pathlib import Path
import sys
import tempfile
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from checkd_planning_engine import PlanningInput, Task, generate_schedule, simulate_delay
from checkd_planning_engine.risk import evaluate_risks
from checkd_planning_engine.workflow_store import (
    LocalTestHumanConfirmation, LocalTestPrincipal, PlanningWorkflowStore, ProposalExpired,
)


ZONE = ZoneInfo("Asia/Shanghai")
NOW = datetime(2026, 11, 14, 9, tzinfo=ZONE)
TODAY = date(2026, 11, 14)
SCOPES = frozenset({"workspace:read", "workspace:write", "proposal:read",
                    "proposal:write", "approval:write", "proposal:apply"})


def main() -> None:
    normal_input = PlanningInput(
        NOW, datetime(2026, 11, 14, 18, tzinfo=ZONE), tasks=(
            Task("report", 3600, TODAY, NOW),
        ),
    )
    normal = generate_schedule(normal_input)
    delay_ok = simulate_delay(normal_input, "report", NOW + timedelta(hours=2))
    delay_tight = simulate_delay(
        PlanningInput(NOW, datetime(2026, 11, 14, 18, tzinfo=ZONE), tasks=(
            Task("report", 5 * 3600, TODAY, NOW),
        )),
        "report", NOW + timedelta(hours=6),
    )

    missed_risks = evaluate_risks([{
        "task_id": "unfinished-report", "planned_at": NOW - timedelta(minutes=5),
        "deadline": TODAY, "completed": False, "remaining_seconds": 1800,
        "available_capacity_seconds": 3600, "slack_seconds": 1200,
    }], evaluated_at=NOW)

    with tempfile.TemporaryDirectory() as directory:
        store = PlanningWorkflowStore(Path(directory) / "walkthrough.db")
        try:
            user_a = LocalTestPrincipal("demo-user-a", SCOPES)
            user_b = LocalTestPrincipal("demo-user-b", SCOPES)
            store.put_private(user_a, kind="memory", key="preference",
                              value={"reminders": "gentle"}, now=NOW)
            isolated = store.get_private(user_b, kind="memory", key="preference") is None

            store.create_draft(
                user_a, proposal_id="demo-proposal", base_version="snapshot-v1",
                rules_version="rules-v1", changes=[{"task_id": "report"}],
                expires_at=NOW + timedelta(minutes=30), idempotency_key="proposal-k", now=NOW,
            )
            store.propose(user_a, "demo-proposal", current_version="snapshot-v1", now=NOW)
            proposal = store.get_proposal(user_a, "demo-proposal")
            confirmation = LocalTestHumanConfirmation(
                subject=user_a.subject, proposal_id="demo-proposal",
                changes_digest=proposal["changes_digest"], confirmation_id="demo-explicit-confirmation",
            )
            approval = store.approve(
                user_a, "demo-proposal", confirmation=confirmation,
                current_version="snapshot-v1", now=NOW,
                token_ttl=timedelta(minutes=1),
            )
            try:
                store.begin_apply(
                    user_a, "demo-proposal", approval_token=approval["approval_token"],
                    idempotency_key="apply-k", current_version="snapshot-v1",
                    now=NOW + timedelta(minutes=1),
                )
                expired_rejected = False
            except ProposalExpired:
                expired_rejected = store.get_proposal(user_a, "demo-proposal")["status"] == "superseded"
        finally:
            store.close()

    print(json.dumps({
        "normal_planning": {
            "status": normal.status, "feasible": normal.feasible,
            "block_count": len(normal.blocks), "optimality_proven": normal.optimality_proven,
        },
        "delay_today_still_feasible": {
            "before": delay_ok["before_feasible"], "after": delay_ok["after_feasible"],
            "outcome": "found_feasible" if delay_ok["after_feasible"] else "no_solution_found",
        },
        "delay_heuristic_found_no_plan": {
            "before": delay_tight["before_feasible"], "after": delay_tight["after_feasible"],
            "outcome": "found_feasible" if delay_tight["after_feasible"] else "no_solution_found",
            "optimality_proven": delay_tight["optimality_proven"],
        },
        "unfinished_task_risk_reevaluation": sorted({risk["risk_type"] for risk in missed_risks}),
        "user_a_user_b_private_state_isolated": isolated,
        "expired_approval_rejected_without_apply": expired_rejected,
        "environment": "temporary local SQLite and deterministic fixtures; no CheckD/Supabase access",
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
