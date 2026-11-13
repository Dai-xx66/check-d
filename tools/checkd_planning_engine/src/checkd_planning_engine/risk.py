from __future__ import annotations

from datetime import datetime
from hashlib import sha256
import json


def evaluate_risks(tasks: list[dict], *, evaluated_at: datetime, buffer_threshold_seconds: int = 3600,
                   consecutive_misses: dict[str, int] | None = None) -> list[dict]:
    risks=[]
    for task in tasks:
        due=task.get("deadline")
        due_at=due if isinstance(due,datetime) else None
        reasons=[]
        if task.get("available_capacity_seconds",0) < task.get("remaining_seconds",0):
            reasons.append(("capacity_insufficient","high"))
        if task.get("planned_at") and task.get("planned_at") < evaluated_at and not task.get("completed",False):
            reasons.append(("plan_missed","medium"))
        if due_at and due_at <= evaluated_at:
            reasons.append(("deadline_passed","critical"))
        if task.get("slack_seconds") is not None and task["slack_seconds"] < buffer_threshold_seconds:
            reasons.append(("buffer_below_threshold","medium"))
        if task.get("continuous_required_seconds",0) > task.get("largest_slot_seconds",0):
            reasons.append(("continuous_slot_insufficient","high"))
        if (consecutive_misses or {}).get(task["task_id"],0) >= 3:
            reasons.append(("repeated_plan_miss","medium"))
        for kind,severity in reasons:
            key=sha256(f"{task['task_id']}:{kind}".encode()).hexdigest()
            risks.append({"risk_key":key,"risk_type":kind,"severity":severity,
                "affected_task_ids":[task["task_id"]],"evidence":{"evaluated_at":evaluated_at.isoformat()},
                "recommendation":"重新评估剩余时间与可行安排。","evaluated_at":evaluated_at.isoformat()})
    return risks
