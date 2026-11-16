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
    result: list[Block] = []
    for block in (*value.fixed_blocks, *value.unavailable, *value.existing_blocks):
        _require_aware(block.starts_at, "busy block start")
        _require_aware(block.ends_at, "busy block end")
        if block.ends_at <= block.starts_at:
            raise ValueError("busy block end must be after start")
        result.append(block)
    ordered = sorted(result, key=lambda x: x.starts_at)
    merged: list[Block] = []
    for block in ordered:
        if merged and block.starts_at <= merged[-1].ends_at:
            prior = merged[-1]
            merged[-1] = Block(prior.starts_at, max(prior.ends_at,block.ends_at),kind="merged_busy")
        else:
            merged.append(Block(block.starts_at,block.ends_at,block.task_id,block.kind))
    return merged


def _require_aware(value: datetime, label: str) -> None:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError(f"{label} must include timezone")


def calculate_availability(value: PlanningInput, *, after: datetime | None = None) -> list[Block]:
    _require_aware(value.now,"now")
    _require_aware(value.horizon_end,"horizon_end")
    if after is not None: _require_aware(after,"after")
    if value.slot_minutes <= 0:
        raise ValueError("slot_minutes must be positive")
    zone_now = after or value.now
    cursor = max(zone_now, value.now)
    quantum = timedelta(minutes=value.slot_minutes)
    if value.horizon_end <= cursor:
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
    _require_aware(value.now,"now")
    _require_aware(value.horizon_end,"horizon_end")
    if value.horizon_end < value.now:
        raise ValueError("horizon_end must not precede now")
    if value.slot_minutes <= 0:
        raise ValueError("slot_minutes must be positive")
    for task in value.tasks:
        _require_aware(task.earliest_start,"task earliest_start")
        if task.priority < 0 or task.priority > 10:
            raise ValueError("task priority must be between 0 and 10")
        if task.minimum_rest_minutes < 0:
            raise ValueError("minimum_rest_minutes must not be negative")
        if task.maximum_continuous_minutes is not None:
            if task.maximum_continuous_minutes <= 0:
                raise ValueError("maximum_continuous_minutes must be positive")
            if task.maximum_continuous_minutes < task.minimum_block_minutes:
                raise ValueError("maximum continuous time is shorter than minimum block")
    ids = [task.task_id for task in value.tasks]
    if len(ids) != len(set(ids)):
        raise ValueError("task IDs must be unique")
    slots = calculate_availability(value)
    quantum = timedelta(minutes=value.slot_minutes)
    placed: list[dict] = []
    unplanned: list[dict] = []
    task_map = {task.task_id:task for task in value.tasks}
    pending = set(task_map)
    completed: dict[str,datetime] = {}
    failed: set[str] = set()
    for task in value.tasks:
        if any(dep not in task_map for dep in task.depends_on):
            unplanned.append({"task_id":task.task_id,"reason":"unknown_dependency"})
            pending.discard(task.task_id)
            failed.add(task.task_id)
    while pending:
        ready = [task_map[key] for key in pending
                 if set(task_map[key].depends_on) <= (set(completed)|failed)]
        if not ready:
            for key in sorted(pending):
                unplanned.append({"task_id":key,"reason":"dependency_cycle_or_missing_dependency"})
            break
        # An explicit scheduling priority is a top-level preference; EDF orders
        # tasks within that priority, followed by task ID for deterministic ties.
        task = min(ready,key=lambda t:(-t.priority,deadline_instant(t.deadline,value.timezone),t.task_id))
        pending.remove(task.task_id)
        if any(dep in failed for dep in task.depends_on):
            unplanned.append({"task_id":task.task_id,"reason":"dependency_unplanned"})
            failed.add(task.task_id)
            continue
        if task.remaining_seconds <= 0 or task.minimum_block_minutes <= 0:
            unplanned.append({"task_id": task.task_id, "reason": "invalid_effort_or_minimum_block"})
            failed.add(task.task_id)
            continue
        earliest = task.earliest_start
        if task.depends_on:
            earliest = max(earliest,*(completed[dep] for dep in task.depends_on))
        if delayed_task_id == task.task_id and delayed_until:
            _require_aware(delayed_until,"delayed_until")
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
                if len(run) >= need_slots and (task.maximum_continuous_minutes is None or need_slots <= (task.maximum_continuous_minutes+value.slot_minutes-1)//value.slot_minutes):
                    chosen = run[:need_slots]
                    break
        else:
            remaining = need_slots
            max_slots = (task.maximum_continuous_minutes + value.slot_minutes - 1) // value.slot_minutes if task.maximum_continuous_minutes else None
            index = 0
            while index < len(eligible) and remaining:
                run = [eligible[index]]
                index += 1
                while index < len(eligible) and eligible[index].starts_at == run[-1].ends_at:
                    run.append(eligible[index]); index += 1
                offset = 0
                while offset < len(run) and remaining:
                    capacity = min(len(run)-offset,max_slots or len(run))
                    take = min(remaining,capacity)
                    if take < min(min_slots,remaining):
                        break
                    chosen.extend(run[offset:offset+take])
                    remaining -= take
                    offset += take
                    if remaining and max_slots is not None and take == max_slots:
                        rest_slots = (task.minimum_rest_minutes + value.slot_minutes - 1)//value.slot_minutes
                        if rest_slots == 0:
                            break
                        offset += rest_slots
            if remaining:
                chosen = []
        if not chosen:
            unplanned.append({"task_id": task.task_id, "reason": "no_slot_found_within_constraints"})
            failed.add(task.task_id)
            continue
        left = task.remaining_seconds
        groups: list[list[Block]] = []
        for slot in chosen:
            if groups and groups[-1][-1].ends_at == slot.starts_at:
                groups[-1].append(slot)
            else:
                groups.append([slot])
        for group in groups:
            capacity = sum(slot.seconds for slot in group)
            duration = min(capacity,left)
            end = group[0].starts_at + timedelta(seconds=duration)
            placed.append(_serialize_block(task.task_id,group[0].starts_at,end))
            left -= duration
            for slot in group:
                slots.remove(slot)
        completed[task.task_id] = max(datetime.fromisoformat(block["ends_at"]) for block in placed if block["task_id"] == task.task_id)
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
                   t.splittable,t.minimum_block_minutes,t.effort_confidence,t.priority,
                   t.maximum_continuous_minutes,t.minimum_rest_minutes,t.depends_on) for t in value.tasks),
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
