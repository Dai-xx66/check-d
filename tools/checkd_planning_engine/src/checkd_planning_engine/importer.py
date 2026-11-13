"""Normalize a privacy-minimized, read-only CheckD snapshot export.

This intentionally accepts exported JSON rather than authenticating to Supabase.
The future adapter must obtain principal and consistency metadata server-side.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
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
    tasks=[]; effort_known=True
    for row in payload["tasks"]:
        remaining=row.get("remaining_seconds")
        if remaining is None: effort_known=False
        tasks.append(Task(row["task_id"], remaining if remaining is not None else 0,
            date.fromisoformat(row["deadline_date"]) if row.get("deadline_date") else instant(row["deadline_at"]),
            instant(row["earliest_start"]), bool(row.get("splittable",True)),int(row.get("minimum_block_minutes",30)),row.get("effort_confidence")))
    busy=[]
    for row in [*payload["course_occurrences"],*payload["occupied_blocks"]]:
        busy.append(Block(instant(row["starts_at"]),instant(row["ends_at"]),row.get("task_id"),row.get("kind","course")))
    normalized={k:v for k,v in payload.items() if k!="display_names"}
    digest=sha256(json.dumps(normalized,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest()
    planning=PlanningInput(instant(payload["now"]),instant(payload["horizon_end"]),payload["timezone"],tuple(tasks),tuple(busy))
    captured=instant(payload["captured_at"])
    return Snapshot(payload["subject_ref"],payload["source"],captured,payload["version"],payload["sync_state"],effort_known,planning,digest,payload["sync_state"]!="current")
