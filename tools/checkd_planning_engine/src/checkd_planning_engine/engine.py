from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timedelta

from .models import Block, PlanningInput, Task, deadline_instant


@dataclass
class ScheduleResult:
    status: str
    feasible: bool
    blocks: list[dict]
    unplanned_tasks: list[dict]
    hard_constraints_satisfied: bool
    optimality_proven: bool = False
    limitation: str = "Deterministic EDF heuristic; failure to find a plan is not a proof of infeasibility."


def _overlap(a: Block, b: Block) -> bool:
    return a.starts_at < b.ends_at and b.starts_at < a.ends_at


def _busy_blocks(value: PlanningInput) -> list[Block]:
    result = []
    for block in (*value.fixed_blocks, *value.unavailable, *value.existing_blocks):
        if block.ends_at <= block.starts_at:
            raise ValueError("busy block end must be after start")
        result.append(block)
    ordered = sorted(result, key=lambda x: x.starts_at)
    for index, left in enumerate(ordered):
        for right in ordered[index + 1:]:
            if right.starts_at >= left.ends_at:
                break
            # Existing fixed overlaps are legal source data; both remain blocked.
    return ordered


def calculate_availability(value: PlanningInput, *, after: datetime | None = None) -> list[Block]:
    zone_now = after or value.now
    cursor = max(zone_now, value.now)
    quantum = timedelta(minutes=value.slot_minutes)
    if value.slot_minutes <= 0 or value.horizon_end <= cursor:
        return []
    busy = _busy_blocks(value)
    slots: list[Block] = []
    while cursor + quantum <= value.horizon_end:
        end = cursor + quantum
        candidate = Block(cursor, end)
        if not any(_overlap(candidate, item) for item in busy):
            slots.append(candidate)
        cursor = end
    return slots


def _serialize_block(task_id: str, start: datetime, end: datetime) -> dict:
    return {"task_id": task_id, "starts_at": start.isoformat(), "ends_at": end.isoformat(),
            "planned_seconds": int((end-start).total_seconds()), "status": "proposed", "source": "edf_heuristic"}


def generate_schedule(value: PlanningInput, *, delayed_task_id: str | None = None,
                      delayed_until: datetime | None = None) -> ScheduleResult:
    slots = calculate_availability(value)
    quantum = timedelta(minutes=value.slot_minutes)
    placed: list[dict] = []
    unplanned: list[dict] = []
    # EDF tie-breaks deterministically by task_id.
    tasks = sorted(value.tasks, key=lambda t: (deadline_instant(t.deadline, value.timezone), t.task_id))
    for task in tasks:
        if task.remaining_seconds <= 0 or task.minimum_block_minutes <= 0:
            unplanned.append({"task_id": task.task_id, "reason": "invalid_effort_or_minimum_block"})
            continue
        earliest = task.earliest_start
        if delayed_task_id == task.task_id and delayed_until:
            earliest = max(earliest, delayed_until)
        deadline = deadline_instant(task.deadline, value.timezone)
        eligible = [s for s in slots if s.starts_at >= earliest and s.ends_at <= deadline]
        need_slots = (task.remaining_seconds + int(quantum.total_seconds()) - 1) // int(quantum.total_seconds())
        min_slots = max(1, (task.minimum_block_minutes + value.slot_minutes - 1) // value.slot_minutes)
        chosen: list[Block] = []
        if not task.splittable:
            run: list[Block] = []
            for slot in eligible:
                if run and slot.starts_at != run[-1].ends_at:
                    run = []
                run.append(slot)
                if len(run) >= need_slots:
                    chosen = run[:need_slots]
                    break
        else:
            remaining = need_slots
            # Pack contiguous runs, preserving minimum block size except the final remainder.
            index = 0
            while index < len(eligible) and remaining:
                run = [eligible[index]]
                index += 1
                while index < len(eligible) and eligible[index].starts_at == run[-1].ends_at:
                    run.append(eligible[index]); index += 1
                take = min(remaining, len(run))
                if take >= min(min_slots, remaining):
                    chosen.extend(run[:take]); remaining -= take
            if remaining:
                chosen = []
        if not chosen:
            unplanned.append({"task_id": task.task_id, "reason": "no_slot_found_within_constraints"})
            continue
        for slot in chosen:
            placed.append(_serialize_block(task.task_id, slot.starts_at, slot.ends_at))
            slots.remove(slot)
    return ScheduleResult("feasible" if not unplanned else "partial", not unplanned, placed, unplanned, True)


def calculate_slack(value: PlanningInput, task: Task, *, earliest_start: datetime | None = None) -> dict:
    deadline = deadline_instant(task.deadline, value.timezone)
    earliest = max(task.earliest_start, earliest_start) if earliest_start else task.earliest_start
    available = sum(s.seconds for s in calculate_availability(value, after=earliest) if s.starts_at >= earliest and s.ends_at <= deadline)
    return {"task_id": task.task_id, "available_capacity_seconds": available,
            "required_effort_seconds": task.remaining_seconds, "slack_seconds": available-task.remaining_seconds}


def check_feasibility(value: PlanningInput) -> ScheduleResult:
    return generate_schedule(value)


def simulate_delay(value: PlanningInput, task_id: str, delayed_until: datetime) -> dict:
    before = generate_schedule(value)
    after = generate_schedule(value, delayed_task_id=task_id, delayed_until=delayed_until)
    target = next((t for t in value.tasks if t.task_id == task_id), None)
    if target is None:
        raise ValueError("unknown task_id")
    before_slack = calculate_slack(value, target)["slack_seconds"]
    delayed_input = PlanningInput(value.now, value.horizon_end, value.timezone,
        tuple(Task(t.task_id,t.remaining_seconds,t.deadline,
                   max(t.earliest_start, delayed_until) if t.task_id == task_id else t.earliest_start,
                   t.splittable,t.minimum_block_minutes,t.effort_confidence) for t in value.tasks),
        value.fixed_blocks,value.unavailable,value.existing_blocks,value.slot_minutes,value.preferences)
    after_slack = calculate_slack(delayed_input, target, earliest_start=delayed_until)["slack_seconds"]
    return {"task_id": task_id, "delayed_until": delayed_until.isoformat(), "before_feasible": before.feasible,
        "after_feasible": after.feasible, "before_slack_seconds": before_slack,
        "after_slack_seconds": after_slack, "slack_change_seconds": after_slack-before_slack,
        "affected_task_ids": sorted({b["task_id"] for b in before.blocks+after.blocks if b["task_id"] != task_id}),
        "before": asdict(before), "after": asdict(after), "optimality_proven": False}


def explain_infeasibility(result: ScheduleResult) -> list[dict]:
    return [{"task_id": item["task_id"], "reason_code": item["reason"],
             "message": "启发式排程未找到满足当前约束的时间块；这不构成数学无解证明。"}
            for item in result.unplanned_tasks]


def compare_proposals(left: ScheduleResult, right: ScheduleResult) -> dict:
    def mapping(result): return {(b["task_id"],b["starts_at"],b["ends_at"]) for b in result.blocks}
    a,b=mapping(left),mapping(right)
    return {"added": sorted(map(list,b-a)), "removed": sorted(map(list,a-b)), "change_count": len(a^b)}
