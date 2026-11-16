"""Normalize a privacy-minimized, read-only CheckD snapshot export.

This intentionally accepts exported JSON rather than authenticating to Supabase.
The future adapter must obtain principal and consistency metadata server-side.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, timedelta
from hashlib import sha256
import json
from typing import Any

from .models import Block, PlanningInput, Task


@dataclass(frozen=True)
class Snapshot:
    user_ref: str
    source: str
    captured_at: datetime
    version: str
    sync_state: str
    effort_known: bool
    planning_input: PlanningInput
    digest: str
    provisional: bool
    unknown_effort_task_ids: tuple[str, ...] = ()
    missing_deadline_task_ids: tuple[str, ...] = ()
    existing_plan_task_ids: tuple[str, ...] = ()
    existing_plan_needing_effort_task_ids: tuple[str, ...] = ()


def assert_snapshot_current(snapshot: Snapshot, *, subject_ref: str, version: str, sync_state: str) -> None:
    """Reject cached preview reuse when principal, source version, or sync state changed."""
    if subject_ref != snapshot.user_ref:
        raise PermissionError("snapshot principal mismatch")
    if version != snapshot.version or sync_state != "current" or snapshot.provisional:
        raise RuntimeError("snapshot is stale or not server-current; regenerate preview")


def import_snapshot(payload: dict[str, Any]) -> Snapshot:
    required={"subject_ref","source","captured_at","version","sync_state","timezone","now","horizon_end","tasks","course_occurrences","occupied_blocks"}
    missing=required-set(payload)
    if missing: raise ValueError(f"missing fields: {sorted(missing)}")
    if "user_id" in payload: raise ValueError("caller-supplied user_id is forbidden")
    if payload["sync_state"] not in {"current","pending_local_changes","unknown"}: raise ValueError("invalid sync_state")
    def instant(v):
        out=datetime.fromisoformat(v.replace("Z","+00:00"))
        if out.tzinfo is None: raise ValueError("timestamps must have UTC offset")
        return out
    tasks=[]; unknown_effort=[]; missing_deadline=[]
    existing_plan=[]; existing_plan_needs_effort=[]; busy=[]
    for row in payload["tasks"]:
        remaining=row.get("remaining_seconds")
        deadline = (
            date.fromisoformat(row["deadline_date"])
            if row.get("deadline_date")
            else instant(row["deadline_at"])
            if row.get("deadline_at")
            else None
        )
        planned_at = instant(row["planned_at"]) if row.get("planned_at") else None
        if deadline is None and planned_at is None:
            missing_deadline.append(row["task_id"])
        if remaining is None:
            unknown_effort.append(row["task_id"])
            if planned_at is not None:
                existing_plan_needs_effort.append(row["task_id"])
            continue
        if planned_at is not None:
            busy.append(Block(
                planned_at,
                planned_at + timedelta(seconds=remaining),
                row["task_id"],
                "existing_task_plan",
            ))
            existing_plan.append(row["task_id"])
            continue
        if deadline is None:
            continue
        tasks.append(Task(row["task_id"], remaining, deadline,
            instant(row["earliest_start"]), bool(row.get("splittable",True)),
            int(row.get("minimum_block_minutes",30)),row.get("effort_confidence"),
            int(row.get("priority",0)),row.get("maximum_continuous_minutes"),
            int(row.get("minimum_rest_minutes",0)),tuple(row.get("depends_on",()))))
    for row in [*payload["course_occurrences"],*payload["occupied_blocks"]]:
        busy.append(Block(instant(row["starts_at"]),instant(row["ends_at"]),row.get("task_id"),row.get("kind","course")))
    normalized={k:v for k,v in payload.items() if k!="display_names"}
    digest=sha256(json.dumps(normalized,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest()
    planning=PlanningInput(instant(payload["now"]),instant(payload["horizon_end"]),payload["timezone"],tuple(tasks),tuple(busy))
    captured=instant(payload["captured_at"])
    return Snapshot(payload["subject_ref"],payload["source"],captured,payload["version"],payload["sync_state"],not unknown_effort,planning,digest,payload["sync_state"]!="current",tuple(unknown_effort),tuple(missing_deadline),tuple(existing_plan),tuple(existing_plan_needs_effort))
