#!/usr/bin/env python3
"""CheckD agent tool mock server (MCP over stdio) for contract v1 CANDIDATE review.

Implements the five v1 tools plus one explicitly-marked extension
(`request_approval`) used to demonstrate the missing approval channel.
No third-party dependencies: JSON-RPC 2.0 over newline-delimited stdio.

Run:  python tool_server.py
"""
import hashlib
import json
import os
import sys
from datetime import date, datetime, timedelta, timezone

TZ = timezone(timedelta(hours=8))
API_VERSION = "checkd.agent.v1"
SERVER_NAME = "checkd-agent-mock"
SERVER_VERSION = "0.1.0"

# ---------------------------------------------------------------- mock data

TASKS = [
    {
        "task_id": "t_1001", "kind": "one_time", "name": "完成实验报告",
        "status": "active", "execution_mode": "timed",
        "available_from": "2026-10-29", "planned_date": None, "scheduled_at": None,
        "deadline": {"kind": "exact", "at": "2026-10-31T18:00:00+08:00"},
        "duration_target_seconds": 5400,
        "updated_at": "2026-10-29T09:00:00+08:00",
    },
    {
        "task_id": "t_1002", "kind": "one_time", "name": "英语六级听力复习",
        "status": "active", "execution_mode": "timed",
        "available_from": "2026-10-29", "planned_date": None, "scheduled_at": None,
        "deadline": {"kind": "date_only", "date": "2026-11-02"},
        "duration_target_seconds": 3600,
        "updated_at": "2026-10-29T09:00:00+08:00",
    },
    {
        "task_id": "t_1003", "kind": "recurring", "name": "背单词",
        "status": "active", "execution_mode": "timed",
        "duration_target_seconds": 1800,
        "updated_at": "2026-10-29T09:00:00+08:00",
        "recurrence": {
            "preset": "daily", "weekdays": [1, 2, 3, 4, 5, 6, 7],
            "starts_on": "2026-10-20", "ends_on": None, "scheduled_minute_of_day": None,
        },
    },
]

COURSES = [
    {
        "course_id": "c_2001", "name": "离散数学", "status": "active",
        "rules": [{
            "rule_id": "r_1", "weekday": 4, "week_rule_type": "every_week",
            "start_week": 1, "end_week": 16,
            "start_minute": 8 * 60, "end_minute": 9 * 60 + 40,
        }],
    },
]

STATE = {
    "tasks": {t["task_id"]: t for t in TASKS},
    "courses": {c["course_id"]: c for c in COURSES},
    "overrides": {},          # (item_id, local_date) -> override
    "proposals": {},          # proposal_id -> proposal
    "approvals": {},          # token -> approval record
    "idempotency": {},        # (user, tool, key) -> {"digest":..., "result":...}
    "applied_proposals": set(),
}

_clock = {"n": 0}


def _next_id(prefix):
    _clock["n"] += 1
    return f"{prefix}_{_clock['n']:04d}"


# ---------------------------------------------------------------- helpers

class ToolError(Exception):
    def __init__(self, code, message, details=None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.details = details or []


def parse_date(s, field):
    try:
        return date.fromisoformat(s)
    except Exception:
        raise ToolError("INVALID_ARGUMENT", f"{field} 不是合法的 YYYY-MM-DD。",
                        [{"field": field, "reason": "invalid_date"}])


def parse_instant(s, field):
    try:
        dt = datetime.fromisoformat(s)
    except Exception:
        raise ToolError("INVALID_ARGUMENT", f"{field} 不是合法的 ISO 8601 时间。",
                        [{"field": field, "reason": "invalid_instant"}])
    if dt.tzinfo is None:
        raise ToolError("INVALID_ARGUMENT", f"{field} 必须带明确偏移。",
                        [{"field": field, "reason": "missing_offset"}])
    return dt


def validate_envelope(args):
    if not isinstance(args, dict):
        raise ToolError("INVALID_ARGUMENT", "请求必须是对象。")
    if args.get("api_version") != API_VERSION:
        raise ToolError("INVALID_ARGUMENT", "api_version 必须是 checkd.agent.v1。",
                        [{"field": "api_version", "reason": "unsupported"}])
    if args.get("timezone") != "Asia/Shanghai":
        raise ToolError("INVALID_ARGUMENT", "v1 只接受 Asia/Shanghai。",
                        [{"field": "timezone", "reason": "unsupported"}])
    rid = args.get("request_id")
    if not isinstance(rid, str) or not 1 <= len(rid) <= 128:
        raise ToolError("INVALID_ARGUMENT", "request_id 必填且长度 1-128。",
                        [{"field": "request_id", "reason": "invalid"}])
    if "user_id" in args or ("input" in args and isinstance(args["input"], dict) and "user_id" in args["input"]):
        raise ToolError("INVALID_ARGUMENT", "请求体不得包含 user_id。",
                        [{"field": "user_id", "reason": "identity_from_body"}])
    inp = args.get("input")
    if not isinstance(inp, dict):
        raise ToolError("INVALID_ARGUMENT", "input 必须是对象。",
                        [{"field": "input", "reason": "not_object"}])
    return inp


def date_range(inp):
    r = inp.get("date_range")
    if not isinstance(r, dict) or "start" not in r or "end" not in r:
        raise ToolError("INVALID_ARGUMENT", "date_range 必填。",
                        [{"field": "input.date_range", "reason": "missing"}])
    start = parse_date(r["start"], "input.date_range.start")
    end = parse_date(r["end"], "input.date_range.end")
    if end < start:
        raise ToolError("INVALID_ARGUMENT", "date_range 的 start 必须不晚于 end。",
                        [{"field": "input.date_range", "reason": "reversed"}])
    if (end - start).days + 1 > 31:
        raise ToolError("INVALID_ARGUMENT", "v1 日期范围最多 31 天。",
                        [{"field": "input.date_range", "reason": "too_long"}])
    return start, end


def iter_dates(start, end):
    d = start
    while d <= end:
        yield d
        d += timedelta(days=1)


def canonical(obj):
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def digest(obj):
    return hashlib.sha256(canonical(obj).encode("utf-8")).hexdigest()


def user_from_token(token):
    # In production: verify signature/owner. Mock maps two demo users.
    if token == "demo-token-alice":
        return "u_alice"
    if token == "demo-token-bob":
        return "u_bob"
    raise ToolError("AUTH_REQUIRED", "缺少或无法验证的身份凭证。")


def snapshot_for(user, start, end, external_events):
    tasks = [t for t in STATE["tasks"].values() if t["status"] == "active"]
    courses = [c for c in STATE["courses"].values() if c["status"] == "active"]
    overrides = [o for (iid, d), o in STATE["overrides"].items()
                 if start <= parse_date(d, "local_date") <= end]
    payload = {
        "user": user,
        "range": [start.isoformat(), end.isoformat()],
        "tasks": tasks, "courses": courses, "overrides": overrides,
        "external_fixed_events": external_events,
    }
    return payload, digest(payload)


def calendar_events_for(payload):
    start = date.fromisoformat(payload["range"][0])
    end = date.fromisoformat(payload["range"][1])
    events = []
    for d in iter_dates(start, end):
        for c in payload["courses"]:
            for rule in c["rules"]:
                if rule["weekday"] != d.isoweekday():
                    continue
                events.append({
                    "event_id": f"ev_{c['course_id']}_{rule['rule_id']}_{d.isoformat()}",
                    "event_type": "course", "source_id": c["course_id"],
                    "date": d.isoformat(),
                    "start_at": f"{d.isoformat()}T{rule['start_minute']//60:02d}:{rule['start_minute']%60:02d}:00+08:00",
                    "end_at": f"{d.isoformat()}T{rule['end_minute']//60:02d}:{rule['end_minute']%60:02d}:00+08:00",
                    "fixed": True, "applied_override_id": None,
                })
        for t in payload["tasks"]:
            if t["kind"] == "one_time" and t.get("planned_date") == d.isoformat() and t.get("scheduled_at"):
                st = parse_instant(t["scheduled_at"], "scheduled_at")
                events.append({
                    "event_id": f"ev_{t['task_id']}_{d.isoformat()}",
                    "event_type": "one_time_task", "source_id": t["task_id"],
                    "date": d.isoformat(), "start_at": t["scheduled_at"],
                    "end_at": (st + timedelta(seconds=t.get("duration_target_seconds") or 1800)).isoformat(),
                    "fixed": False, "applied_override_id": None,
                })
        for ev in payload["external_fixed_events"]:
            if ev["start_at"][:10] == d.isoformat():
                events.append({
                    "event_id": ev["external_event_id"], "event_type": "external_fixed_event",
                    "source_id": ev["external_event_id"], "date": d.isoformat(),
                    "start_at": ev["start_at"], "end_at": ev["end_at"],
                    "fixed": True, "applied_override_id": None,
                })
    return events


def _hm(dt):
    return dt.hour * 60 + dt.minute


def _at_local(d, minute):
    return datetime(d.year, d.month, d.day, minute // 60, minute % 60, tzinfo=TZ)


def schedule(payload, prefs):
    start = date.fromisoformat(payload["range"][0])
    end = date.fromisoformat(payload["range"][1])
    day_start = int(prefs.get("day_start_minute", 8 * 60))
    day_end = int(prefs.get("day_end_minute", 22 * 60))
    min_block = int(prefs.get("minimum_block_minutes", 30))
    fixed = [e for e in calendar_events_for(payload) if e["fixed"]]
    blocks, changes, unplanned = [], [], []

    ones = [t for t in payload["tasks"] if t["kind"] == "one_time" and t["status"] == "active"]
    recurring = [t for t in payload["tasks"] if t["kind"] == "recurring" and t["status"] == "active"]

    def deadline_key(t):
        dl = t.get("deadline") or {}
        return (dl.get("at") or (dl.get("date", "") + "T23:59:59+08:00") or "9999", t["task_id"])

    for t in sorted(ones, key=deadline_key):
        need = int(t.get("duration_target_seconds") or 0)
        placed = False
        for d in iter_dates(start, end):
            busy = sorted((_hm(parse_instant(e["start_at"], "x")), _hm(parse_instant(e["end_at"], "x")))
                          for e in fixed if e["date"] == d.isoformat())
            cursor = day_start
            for bs, be in busy + [(day_end, day_end)]:
                while cursor + min_block <= bs:
                    free = bs - cursor
                    if free * 60 >= need:
                        b = {"block_id": _next_id("b"), "task_id": t["task_id"], "task_kind": "one_time",
                             "start_at": _at_local(d, cursor).isoformat(),
                             "end_at": _at_local(d, cursor + need // 60).isoformat(),
                             "source": "proposal", "persistable_as": "one_time_schedule",
                             "duration_source": "task_target", "duration_seconds": need}
                        blocks.append(b)
                        changes.append({"change_id": _next_id("ch"), "type": "schedule_one_time",
                                        "task_id": t["task_id"], "planned_date": d.isoformat(),
                                        "scheduled_at": b["start_at"]})
                        placed = True
                        break
                    cursor += 30
                if placed:
                    break
                cursor = max(cursor, be)
            if placed:
                break
        if not placed:
            unplanned.append({"task_id": t["task_id"], "reason": "no_free_slot"})

    for t in recurring:
        for d in iter_dates(start, end):
            busy = sorted((_hm(parse_instant(e["start_at"], "x")), _hm(parse_instant(e["end_at"], "x")))
                          for e in fixed if e["date"] == d.isoformat())
            cursor = day_start
            placed = False
            for bs, be in busy + [(day_end, day_end)]:
                if bs - cursor >= min_block and not placed:
                    blocks.append({"block_id": _next_id("b"), "task_id": t["task_id"], "task_kind": "recurring",
                                   "start_at": _at_local(d, cursor).isoformat(),
                                   "end_at": _at_local(d, cursor + min_block).isoformat(),
                                   "source": "proposal", "persistable_as": "daily_override",
                                   "duration_source": "scheduler_estimate",
                                   "duration_seconds": min_block * 60})
                    changes.append({"change_id": _next_id("ch"), "type": "upsert_daily_override",
                                    "item_type": "recurring", "item_id": t["task_id"],
                                    "local_date": d.isoformat(), "action": "reschedule",
                                    "planned_start_minute": cursor,
                                    "planned_end_minute": cursor + min_block})
                    placed = True
                cursor = max(cursor, be)
            if not placed:
                unplanned.append({"task_id": t["task_id"], "reason": "no_free_slot"})
    return blocks, changes, unplanned


def check_hard_constraints(proposal, events):
    violations = []
    for b in proposal["blocks"]:
        bs = parse_instant(b["start_at"], "block.start_at")
        be = parse_instant(b["end_at"], "block.end_at")
        if be <= bs:
            violations.append({"code": "BLOCK_TIME_INVALID", "block_id": b["block_id"]})
        for e in events:
            if not e["fixed"] or e["date"] != b["start_at"][:10]:
                continue
            es = parse_instant(e["start_at"], "event.start_at")
            ee = parse_instant(e["end_at"], "event.end_at")
            if bs < ee and es < be:
                violations.append({"code": "FIXED_EVENT_CONFLICT",
                                   "block_id": b["block_id"], "event_id": e["event_id"]})
    seen = {}
    for ch in proposal["changes"]:
        if ch["type"] == "schedule_one_time":
            seen[ch["task_id"]] = seen.get(ch["task_id"], 0) + 1
    for tid, n in seen.items():
        if n > 1:
            violations.append({"code": "MULTIPLE_CHANGES_FOR_ONE_TIME_TASK", "task_id": tid})
    return violations


# ---------------------------------------------------------------- tools

def tool_list_tasks(args, user):
    inp = validate_envelope(args)
    start, end = date_range(inp)
    kinds = inp.get("kinds") or ["recurring", "one_time"]
    statuses = inp.get("statuses") or ["active"]
    tasks = [t for t in STATE["tasks"].values()
             if t["kind"] in kinds and t["status"] in statuses]
    return {
        "query_version": digest({"user": user, "range": [start.isoformat(), end.isoformat()],
                                 "tasks": [t["task_id"] for t in tasks]}),
        "tasks": tasks,
        "date_range": {"start": start.isoformat(), "end": end.isoformat()},
    }


def tool_get_calendar_events(args, user):
    inp = validate_envelope(args)
    start, end = date_range(inp)
    ext = []
    for ev in inp.get("external_fixed_events") or []:
        for f in ("external_event_id", "title", "start_at", "end_at"):
            if f not in ev:
                raise ToolError("INVALID_ARGUMENT", f"external_fixed_events 缺少 {f}。")
        s, e = parse_instant(ev["start_at"], "start_at"), parse_instant(ev["end_at"], "end_at")
        if e <= s:
            raise ToolError("INVALID_ARGUMENT", "外部事件结束必须晚于开始。")
        if not (start.isoformat() <= s.date().isoformat() <= end.isoformat()):
            raise ToolError("INVALID_ARGUMENT", "外部事件必须落在查询范围内。")
        ext.append(ev)
    payload, _ = snapshot_for(user, start, end, ext)
    events = calendar_events_for(payload)
    return {
        "query_version": digest({"user": user, "events": [e["event_id"] for e in events]}),
        "courses": list(STATE["courses"].values()),
        "daily_overrides": list(STATE["overrides"].values()),
        "events": events,
    }


def tool_generate_schedule(args, user):
    inp = validate_envelope(args)
    start, end = date_range(inp)
    ext = inp.get("external_fixed_events") or []
    prefs = inp.get("preferences") or {}
    if any(k in inp for k in ("tasks", "courses", "base_version", "snapshot_ref")):
        raise ToolError("INVALID_ARGUMENT", "远程调用不得提交 tasks/courses/base_version/snapshot_ref。")
    payload, input_digest = snapshot_for(user, start, end, ext)
    base_version = digest({"snapshot": input_digest, "user": user})
    blocks, changes, unplanned = schedule(payload, prefs)
    stored_events = list(ext)
    # test seam: inject an event AFTER scheduling so the proposal violates it
    if isinstance(prefs.get("__test_conflict_event"), dict):
        stored_events.append(prefs["__test_conflict_event"])
    proposal = {
        "proposal_id": _next_id("prop"),
        "snapshot_ref": "snap_" + base_version[:16],
        "base_version": base_version,
        "input_digest": input_digest,
        "status": "draft",
        "expires_at": "2026-10-30T23:59:00+08:00",
        "blocks": blocks, "changes": changes, "unplanned_tasks": unplanned,
        "explanations": ["固定课程与外部会议不可移动。", "单次事项只持久化一个计划日期。"],
        "user": user, "_range": [start.isoformat(), end.isoformat()],
        "_external_events": stored_events,
    }
    STATE["proposals"][proposal["proposal_id"]] = proposal
    return proposal


def tool_validate_schedule(args, user):
    inp = validate_envelope(args)
    pid = inp.get("proposal_id")
    p = STATE["proposals"].get(pid)
    if not p or p["user"] != user:
        raise ToolError("NOT_FOUND", "找不到该提案。")
    start, end = map(date.fromisoformat, p["_range"])
    payload, _ = snapshot_for(user, start, end, p.get("_external_events", []))
    events = calendar_events_for(payload)
    violations = check_hard_constraints(p, events)
    now = datetime.now(TZ).isoformat(timespec="seconds")
    if violations:
        p["status"] = "draft"
        return {"proposal_id": pid, "snapshot_ref": p["snapshot_ref"], "base_version": p["base_version"],
                "input_digest": p["input_digest"], "proposal_status": "draft",
                "validation_status": "invalid", "approval_status": "not_approvable",
                "violations": violations, "validated_at": now, "expires_at": p["expires_at"]}
    p["status"] = "pending_approval"
    return {"proposal_id": pid, "snapshot_ref": p["snapshot_ref"], "base_version": p["base_version"],
            "input_digest": p["input_digest"], "proposal_status": "pending_approval",
            "validation_status": "valid", "approval_status": "pending_approval",
            "violations": [], "validated_at": now, "expires_at": p["expires_at"]}


def tool_request_approval(args, user):
    """Extension, NOT in v1. Demonstrates the missing trusted-confirmation channel."""
    inp = validate_envelope(args)
    pid = inp.get("proposal_id")
    p = STATE["proposals"].get(pid)
    if not p or p["user"] != user:
        raise ToolError("NOT_FOUND", "找不到该提案。")
    if p["status"] != "pending_approval":
        raise ToolError("APPROVAL_REQUIRED", "提案尚未通过校验。")
    token = _next_id("approval")
    STATE["approvals"][token] = {
        "user": user, "proposal_id": pid, "base_version": p["base_version"],
        "input_digest": p["input_digest"],
        "expires_at": "2026-10-30T23:59:00+08:00",
    }
    return {"approval_token": token, "expires_at": STATE["approvals"][token]["expires_at"],
            "note": "mock only: production token must be issued by a trusted approval service"}


def tool_apply(args, user):
    inp = validate_envelope(args)
    pid, base_version = inp.get("proposal_id"), inp.get("base_version")
    token, key = inp.get("approval_token"), inp.get("idempotency_key")
    if not all(isinstance(x, str) and x for x in (pid, base_version, token, key)):
        raise ToolError("INVALID_ARGUMENT", "proposal_id/base_version/approval_token/idempotency_key 必填。")
    appr = STATE["approvals"].get(token)
    if not appr or appr["user"] != user:
        raise ToolError("APPROVAL_UNTRUSTED", "审批凭据无效。")
    if appr["proposal_id"] != pid or appr["base_version"] != base_version:
        raise ToolError("APPROVAL_UNTRUSTED", "审批凭据与提案不匹配。")
    p = STATE["proposals"].get(pid)
    if not p or p["user"] != user:
        raise ToolError("NOT_FOUND", "找不到该提案。")
    if p["base_version"] != base_version:
        raise ToolError("SNAPSHOT_CONFLICT", "快照版本已变化。")
    req_digest = digest({"proposal": pid, "base_version": base_version, "approval": token})
    idem = (user, "apply_approved_changes", key)
    if idem in STATE["idempotency"]:
        rec = STATE["idempotency"][idem]
        if rec["digest"] != req_digest:
            raise ToolError("IDEMPOTENCY_CONFLICT", "幂等键被用于不同请求。")
        return rec["result"]
    if p["status"] != "pending_approval":
        raise ToolError("APPROVAL_REQUIRED", "提案当前不可应用。")
    if pid in STATE["applied_proposals"]:
        raise ToolError("WRITE_BLOCKED", "该提案已应用过，v1 需要固定错误码。")

    applied = []
    for ch in p["changes"]:
        if ch["type"] == "schedule_one_time":
            t = STATE["tasks"][ch["task_id"]]
            t["planned_date"] = ch["planned_date"]
            t["scheduled_at"] = ch.get("scheduled_at")
            applied.append({"change_id": ch["change_id"], "type": ch["type"],
                            "task_id": ch["task_id"], "planned_date": t["planned_date"],
                            "scheduled_at": t["scheduled_at"]})
        else:
            STATE["overrides"][(ch["item_id"], ch["local_date"])] = {
                "override_id": _next_id("ov"), "item_type": ch["item_type"],
                "item_id": ch["item_id"], "local_date": ch["local_date"],
                "action": "reschedule", "planned_start_minute": ch["planned_start_minute"],
                "planned_end_minute": ch["planned_end_minute"],
            }
            applied.append({"change_id": ch["change_id"], "type": ch["type"],
                            "override_id": STATE["overrides"][(ch["item_id"], ch["local_date"])]["override_id"]})

    # readback: only planned_date and scheduled_at for one-time changes
    for ch in p["changes"]:
        if ch["type"] == "schedule_one_time":
            t = STATE["tasks"][ch["task_id"]]
            if t["planned_date"] != ch["planned_date"] or t.get("scheduled_at") != ch.get("scheduled_at"):
                raise ToolError("READBACK_MISMATCH", "写后回读不一致。")
    STATE["applied_proposals"].add(pid)
    p["status"] = "applied"
    result = {"proposal_id": pid, "base_version": base_version, "result_version": _next_id("ver"),
              "idempotency_key": key, "applied_changes": applied,
              "readback_verified": True, "applied_at": datetime.now(TZ).isoformat(timespec="seconds")}
    STATE["idempotency"][idem] = {"digest": req_digest, "result": result}
    return result


TOOLS = {
    "list_tasks": tool_list_tasks,
    "get_calendar_events": tool_get_calendar_events,
    "generate_schedule": tool_generate_schedule,
    "validate_schedule": tool_validate_schedule,
    "apply_approved_changes": tool_apply,
    "request_approval": tool_request_approval,  # extension
}

DESCRIPTIONS = {
    "list_tasks": "读取当前用户的任务定义（不展开逐日 occurrence）。",
    "get_calendar_events": "读取日期范围内生效的课程、任务与单日例外，支持传入外部固定事件。",
    "generate_schedule": "基于服务端快照生成调度提案（只读，不写入）。",
    "validate_schedule": "按服务端快照重新校验提案，合法则进入 pending_approval。",
    "apply_approved_changes": "凭可信审批凭据原子应用变更并回读核验。",
    "request_approval": "[扩展，非 v1] 演示审批通道缺失：由受控审批服务签发一次性凭据。",
}

SCHEMAS = {
    "list_tasks": {"type": "object", "required": ["date_range"], "properties": {
        "date_range": {"$ref": "#/$defs/date_range"},
        "kinds": {"type": "array", "items": {"enum": ["recurring", "one_time"]}},
        "statuses": {"type": "array", "items": {"enum": ["active", "paused", "archived"]}},
        "include_completed": {"type": "boolean"}}},
    "get_calendar_events": {"type": "object", "required": ["date_range"], "properties": {
        "date_range": {"$ref": "#/$defs/date_range"},
        "external_fixed_events": {"type": "array", "items": {"type": "object",
            "required": ["external_event_id", "title", "start_at", "end_at"],
            "properties": {"external_event_id": {"type": "string"}, "title": {"type": "string"},
                           "start_at": {"type": "string"}, "end_at": {"type": "string"}}}}}},
    "generate_schedule": {"type": "object", "required": ["date_range"], "properties": {
        "date_range": {"$ref": "#/$defs/date_range"},
        "external_fixed_events": {"type": "array", "items": {"type": "object"}},
        "preferences": {"type": "object"}}},
    "validate_schedule": {"type": "object", "required": ["proposal_id"],
                          "properties": {"proposal_id": {"type": "string"}}},
    "apply_approved_changes": {"type": "object",
        "required": ["proposal_id", "base_version", "approval_token", "idempotency_key"],
        "properties": {"proposal_id": {"type": "string"}, "base_version": {"type": "string"},
                       "approval_token": {"type": "string"}, "idempotency_key": {"type": "string"}}},
    "request_approval": {"type": "object", "required": ["proposal_id"],
                         "properties": {"proposal_id": {"type": "string"}}},
}


def tool_defs():
    defs = []
    for name, schema in SCHEMAS.items():
        defs.append({
            "name": name,
            "description": DESCRIPTIONS[name],
            "inputSchema": {
                "type": "object",
                "properties": {
                    "api_version": {"type": "string", "const": API_VERSION},
                    "request_id": {"type": "string"},
                    "timezone": {"type": "string", "const": "Asia/Shanghai"},
                    "input": schema,
                },
                "required": ["api_version", "request_id", "timezone", "input"],
            },
        })
    return defs


# ---------------------------------------------------------------- MCP plumbing

def send(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def ok(rid, result):
    send({"jsonrpc": "2.0", "id": rid, "result": result})


def err(rid, code, message):
    send({"jsonrpc": "2.0", "id": rid, "error": {"code": code, "message": message}})


def call_tool(name, args, token):
    try:
        user = user_from_token(token)
        fn = TOOLS[name]
        data = fn(args, user)
        return {"content": [{"type": "text", "text": json.dumps(
            {"status": "success", "data": data}, ensure_ascii=False)}],
            "structuredContent": {"status": "success", "data": data}, "isError": False}
    except ToolError as e:
        body = {"status": "error", "error": {"code": e.code, "message": e.message,
                                            "retryable": e.code in ("DEPENDENCY_UNAVAILABLE",),
                                            "details": e.details}}
        return {"content": [{"type": "text", "text": json.dumps(body, ensure_ascii=False)}],
                "structuredContent": body, "isError": True}


def main():
    try:
        sys.stdin.reconfigure(encoding="utf-8")
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    token = os.environ.get("CHECKD_TOKEN", "demo-token-alice")
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except Exception:
            continue
        method, rid = msg.get("method"), msg.get("id")
        params = msg.get("params") or {}
        if method == "initialize":
            ok(rid, {"protocolVersion": params.get("protocolVersion", "2024-11-05"),
                     "capabilities": {"tools": {"listChanged": False}},
                     "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION}})
        elif method == "notifications/initialized":
            continue
        elif method == "ping":
            ok(rid, {})
        elif method == "tools/list":
            ok(rid, {"tools": tool_defs()})
        elif method == "tools/call":
            name = params.get("name")
            args = params.get("arguments") or {}
            hdr = params.get("_meta") or {}
            token = hdr.get("authorization", token)
            if token.startswith("Bearer "):
                token = token[7:]
            if name not in TOOLS:
                ok(rid, {"content": [{"type": "text", "text": "unknown tool"}], "isError": True})
            else:
                ok(rid, call_tool(name, args, token))
        else:
            err(rid, -32601, f"method not found: {method}")


if __name__ == "__main__":
    main()