#!/usr/bin/env python3
"""CheckD agent tool mock server (MCP over stdio) aligned to contract 2c48579.

Baseline: docs/contracts/agent-api-v1.md @ 2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6

Implements the five v1 tools plus the two approval extensions from the contract,
with a file-based external approval handoff. Platform behaviour (WorkBuddy) stays
unverified; token signing/TTL enforcement at rest stays BLOCKED.

Environment:
  CHECKD_TOKEN        bearer token for the demo user (default demo-token-alice)
  MOCK_APPROVAL_FILE  JSON file acting as the external approval store
  MOCK_TEST_FLAGS     test-only JSON flags; never a tool parameter
"""
import hashlib
import json
import os
import sys
import uuid
from datetime import date, datetime, time, timedelta, timezone

TZ = timezone(timedelta(hours=8))
API_VERSION = "checkd.agent.v1"
SERVER_NAME = "checkd-agent-mock"
SERVER_VERSION = "0.4.0"
HERE = os.path.dirname(os.path.abspath(__file__))
APPROVAL_FILE = os.environ.get("MOCK_APPROVAL_FILE", os.path.join(HERE, "mock_approvals.json"))
FLAGS_FILE = os.environ.get("MOCK_TEST_FLAGS")

PROPOSAL_TTL_MIN = 30
TOKEN_TTL_MIN = 5

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
    {
        "task_id": "t_1004", "kind": "recurring", "name": "线性代数复习",
        "status": "active", "execution_mode": "timed",
        "duration_target_seconds": 3600,
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
    "overrides": {},
    "proposals": {},     # public proposal view
    "internal": {},      # proposal_id -> {user, range, events}
    "approvals": {},     # approval_id -> record (in-memory index over the file)
    "tokens": {},        # token -> binding
    "idempotency": {},
    "applied_proposals": set(),
}

_clock = {"n": 0}


def _next_id(prefix):
    _clock["n"] += 1
    return f"{prefix}_{_clock['n']:04d}"


class ToolError(Exception):
    def __init__(self, code, message, details=None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.details = details or []


def read_flags():
    if not FLAGS_FILE or not os.path.exists(FLAGS_FILE):
        return {}
    try:
        return json.load(open(FLAGS_FILE, encoding="utf-8"))
    except Exception:
        return {}


def set_flags(data):
    if not FLAGS_FILE:
        return
    with open(FLAGS_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)


def take_flag(name):
    flags = read_flags()
    if name in flags:
        value = flags.pop(name)
        set_flags(flags)
        return value
    return None


def read_approvals():
    if not os.path.exists(APPROVAL_FILE):
        return {}
    try:
        return json.load(open(APPROVAL_FILE, encoding="utf-8"))
    except Exception:
        return {}


def write_approvals(data):
    with open(APPROVAL_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)


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
    if token == "demo-token-alice":
        return "u_alice"
    if token == "demo-token-bob":
        return "u_bob"
    raise ToolError("AUTH_REQUIRED", "缺少或无法验证的身份凭证。")


def now():
    return datetime.now(TZ)


def iso(dt):
    return dt.isoformat(timespec="seconds")


def cap(instant, limit):
    return min(instant, limit)


def proposal_expires_at():
    return now() + timedelta(minutes=PROPOSAL_TTL_MIN)


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


def snapshot_digest(user, start, end, external_events):
    return snapshot_for(user, start, end, external_events)[1]


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


def deadline_key(t):
    dl = t.get("deadline") or {}
    if dl.get("kind") == "exact":
        return (0, dl.get("at") or "", t["task_id"])
    if dl.get("kind") == "date_only":
        return (1, dl.get("date") or "", t["task_id"])
    return (2, "", t["task_id"])


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

    for t in sorted(ones, key=deadline_key):
        need = int(t.get("duration_target_seconds") or 0)
        placed = False
        for d in iter_dates(start, end):
            busy = sorted((_hm(parse_instant(e["start_at"], "x")), _hm(parse_instant(e["end_at"], "x")))
                          for e in fixed if e["date"] == d.isoformat())
            cursor = day_start
            for bs, be in busy + [(day_end, day_end)]:
                while cursor + min_block <= bs:
                    if (bs - cursor) * 60 >= need:
                        b = {"block_id": _next_id("b"), "task_id": t["task_id"], "task_kind": "one_time",
                             "start_at": iso(_at_local(d, cursor)),
                             "end_at": iso(_at_local(d, cursor + need // 60)),
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
            dl = t.get("deadline") or {}
            past = dl.get("kind") == "exact" and dl.get("at") and \
                parse_instant(dl["at"], "deadline") < now()
            reason = "PAST_DEADLINE" if past else ("OVERLAPS_FIXED" if fixed else "NO_AVAILABILITY")
            unplanned.append({"task_id": t["task_id"], "reason_code": reason,
                              "remaining_minutes": max(int(need // 60), 1),
                              "message": "未找到可容纳目标时长的空档。"})

    for t in recurring:
        target = t.get("duration_target_seconds")
        need = int(target) if target else min_block * 60
        minutes = max(int((need + 59) // 60), min_block)
        for d in iter_dates(start, end):
            busy = sorted((_hm(parse_instant(e["start_at"], "x")), _hm(parse_instant(e["end_at"], "x")))
                          for e in fixed if e["date"] == d.isoformat())
            cursor = day_start
            placed = False
            for bs, be in busy + [(day_end, day_end)]:
                if not placed and bs - cursor >= minutes:
                    blocks.append({"block_id": _next_id("b"), "task_id": t["task_id"], "task_kind": "recurring",
                                   "start_at": iso(_at_local(d, cursor)),
                                   "end_at": iso(_at_local(d, cursor + minutes)),
                                   "source": "proposal", "persistable_as": "daily_override",
                                   "duration_source": "task_target" if target else "scheduler_estimate",
                                   "duration_seconds": minutes * 60})
                    changes.append({"change_id": _next_id("ch"), "type": "upsert_daily_override",
                                    "item_type": "recurring", "item_id": t["task_id"],
                                    "local_date": d.isoformat(), "action": "reschedule",
                                    "planned_start_minute": cursor,
                                    "planned_end_minute": cursor + minutes})
                    placed = True
                cursor = max(cursor, be)
            if not placed:
                reason = "WINDOW_INSUFFICIENT" if (day_end - day_start) < minutes else "NO_AVAILABILITY"
                unplanned.append({"task_id": t["task_id"], "reason_code": reason,
                                  "remaining_minutes": minutes,
                                  "message": "当日可用窗口不足以容纳该周期任务。"})
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


def check_items_exist(proposal):
    for ch in proposal["changes"]:
        if ch["type"] == "schedule_one_time":
            if ch.get("task_id") not in STATE["tasks"]:
                raise ToolError("NOT_FOUND", f'任务不存在：{ch.get("task_id")}',
                                [{"field": "changes.task_id", "reason": "missing"}])
        elif ch["type"] == "upsert_daily_override":
            if ch.get("item_id") not in STATE["tasks"]:
                raise ToolError("NOT_FOUND", f'事项不存在：{ch.get("item_id")}',
                                [{"field": "changes.item_id", "reason": "missing"}])


def public_view(pid):
    return STATE["proposals"][pid]


def apply_approval_status(rec):
    """Compute the externally visible approval status from times and flags."""
    if rec.get("status") in ("rejected", "consumed", "expired"):
        return rec["status"]
    if parse_instant(rec["expires_at"], "expires_at") < now():
        return "expired"
    if rec.get("token_consumed"):
        return "consumed"
    if rec.get("token_issued"):
        token = rec.get("token")
        trec = STATE["tokens"].get(token) if token else None
        if trec and parse_instant(trec["expires_at"], "expires_at") < now():
            return "expired"
        return "token_issued"
    if rec.get("status") == "approved":
        return "approved"
    return "pending"


def refresh_approval(aid):
    """Merge the external approval page state into the in-memory record."""
    rec = STATE["approvals"].get(aid)
    if not rec:
        return None
    file_rec = read_approvals().get(aid)
    if file_rec:
        for k in ("status", "token_issued", "token_consumed", "expires_at"):
            if k in file_rec:
                rec[k] = file_rec[k]
    return rec


def find_approval_for_proposal(proposal_id, user):
    best = None
    for aid, rec in STATE["approvals"].items():
        if rec["proposal_id"] == proposal_id and rec["user"] == user:
            st = apply_approval_status(rec)
            if st in ("pending", "approved", "token_issued"):
                best = rec
    return best


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
    extra = take_flag("conflict_event")
    if isinstance(extra, dict):
        stored_events.append(extra)
        _, input_digest = snapshot_for(user, start, end, stored_events)
        base_version = digest({"snapshot": input_digest, "user": user})

    explanations = [{"code": "PRESERVED_FIXED_EVENTS",
                     "message": "固定课程与外部固定事件不可移动。"}]
    if any(b["duration_source"] == "scheduler_estimate" for b in blocks):
        explanations.append({"code": "ESTIMATED_DURATION",
                             "message": "存在按估算时长排布的块。"})

    pid = _next_id("proposal")
    created = now()
    proposal = {
        "proposal_id": pid,
        "snapshot_ref": "snap_" + base_version[:16],
        "base_version": base_version,
        "input_digest": input_digest,
        "status": "draft",
        "generated_at": iso(created),
        "expires_at": iso(created + timedelta(minutes=PROPOSAL_TTL_MIN)),
        "blocks": blocks, "changes": changes, "unplanned_tasks": unplanned,
        "explanations": explanations,
    }
    STATE["proposals"][pid] = proposal
    STATE["internal"][pid] = {"user": user, "range": [start.isoformat(), end.isoformat()],
                              "events": stored_events}
    return proposal


def tool_validate_schedule(args, user):
    inp = validate_envelope(args)
    pid = inp.get("proposal_id")
    p = STATE["proposals"].get(pid)
    internal = STATE["internal"].get(pid)
    if not p or not internal or internal["user"] != user:
        raise ToolError("NOT_FOUND", "找不到该提案。")
    start, end = map(date.fromisoformat, internal["range"])

    bump = take_flag("bump_task")
    if isinstance(bump, str) and bump in STATE["tasks"]:
        STATE["tasks"][bump]["updated_at"] = iso(now())

    current = snapshot_digest(user, start, end, internal["events"])
    if current != p["input_digest"] or digest({"snapshot": current, "user": user}) != p["base_version"]:
        raise ToolError("SNAPSHOT_CONFLICT", "快照已变化，需重新生成提案。")

    injected = take_flag("inject_missing_change")
    if isinstance(injected, dict):
        p["changes"].append(injected)

    check_items_exist(p)

    payload, _ = snapshot_for(user, start, end, internal["events"])
    events = calendar_events_for(payload)
    violations = check_hard_constraints(p, events)
    validated_at = iso(now())
    if violations:
        p["status"] = "draft"
        return {"proposal_id": pid, "snapshot_ref": p["snapshot_ref"], "base_version": p["base_version"],
                "input_digest": p["input_digest"], "proposal_status": "draft",
                "validation_status": "invalid", "approval_status": "not_approvable",
                "violations": violations, "validated_at": validated_at, "expires_at": p["expires_at"]}
    p["status"] = "pending_approval"
    return {"proposal_id": pid, "snapshot_ref": p["snapshot_ref"], "base_version": p["base_version"],
            "input_digest": p["input_digest"], "proposal_status": "pending_approval",
            "validation_status": "valid", "approval_status": "pending_approval",
            "violations": [], "validated_at": validated_at, "expires_at": p["expires_at"]}


def tool_request_approval(args, user):
    inp = validate_envelope(args)
    pid = inp.get("proposal_id")
    key = inp.get("idempotency_key")
    if not isinstance(key, str) or not key:
        raise ToolError("INVALID_ARGUMENT", "idempotency_key 必填。")
    p = STATE["proposals"].get(pid)
    internal = STATE["internal"].get(pid)
    if not p or not internal or internal["user"] != user:
        raise ToolError("NOT_FOUND", "找不到该提案。")
    if take_flag("expire_proposal"):
        p["expires_at"] = iso(now() - timedelta(minutes=1))
    if p["status"] in ("applied",) or pid in STATE["applied_proposals"]:
        raise ToolError("ALREADY_APPLIED", "提案已应用，不能再次审批。")
    if p["status"] != "pending_approval":
        raise ToolError("PROPOSAL_INVALID", "提案尚未通过校验。")
    if parse_instant(p["expires_at"], "expires_at") < now():
        raise ToolError("PROPOSAL_EXPIRED", "提案已过期。")

    idem = (user, "request_approval", key)
    cached = STATE["idempotency"].get(idem)
    req_digest = digest({"proposal": pid, "action": "request_approval"})
    if cached:
        if cached["digest"] != req_digest:
            raise ToolError("IDEMPOTENCY_CONFLICT", "幂等键被用于其他提案。")
        return cached["result"]

    existing = find_approval_for_proposal(pid, user)
    if existing:
        result = {"approval_id": existing["approval_id"], "proposal_id": pid,
                  "status": apply_approval_status(existing), "approval_url": existing["url"],
                  "expires_at": existing["expires_at"]}
        STATE["idempotency"][idem] = {"digest": req_digest, "result": result}
        return result

    aid = _next_id("appr")
    rec = {
        "approval_id": aid, "url": f"https://approval.mock.local/p/{aid}",
        "proposal_id": pid, "base_version": p["base_version"], "user": user,
        "status": "pending", "token_issued": False, "token_consumed": False,
        "created_at": iso(now()),
        "expires_at": iso(cap(now() + timedelta(minutes=PROPOSAL_TTL_MIN),
                              parse_instant(p["expires_at"], "expires_at"))),
        "idempotency_key": key,
    }
    STATE["approvals"][aid] = rec
    approvals = read_approvals()
    approvals[aid] = rec
    write_approvals(approvals)

    result = {"approval_id": aid, "proposal_id": pid, "status": "pending",
              "approval_url": rec["url"], "expires_at": rec["expires_at"]}
    STATE["idempotency"][idem] = {"digest": req_digest, "result": result}
    return result


def tool_get_approval_status(args, user):
    inp = validate_envelope(args)
    aid = inp.get("approval_id")
    rec = refresh_approval(aid)
    if not rec or rec["user"] != user:
        raise ToolError("NOT_FOUND", "找不到该审批请求。")
    status = apply_approval_status(rec)
    base = {"approval_id": aid, "proposal_id": rec["proposal_id"], "status": status,
            "expires_at": rec["expires_at"]}

    if status == "pending":
        return base
    if status == "expired":
        return base
    if status in ("rejected", "consumed"):
        return base
    if status == "approved":
        token = "tok_" + uuid.uuid4().hex
        issued = now()
        token_expires = cap(issued + timedelta(minutes=TOKEN_TTL_MIN),
                            parse_instant(rec["expires_at"], "expires_at"))
        STATE["tokens"][token] = {
            "approval_id": aid, "user": user, "proposal_id": rec["proposal_id"],
            "base_version": rec["base_version"], "consumed": False,
            "issued_at": iso(issued), "expires_at": iso(token_expires),
        }
        rec["token_issued"] = True
        rec["status"] = "token_issued"
        rec["token"] = token
        STATE["approvals"][aid] = rec
        approvals = read_approvals()
        approvals[aid] = rec
        write_approvals(approvals)
        base.update({"status": "approved", "approval_token": token,
                     "token_issued_at": iso(issued), "token_expires_at": iso(token_expires)})
        return base
    base.update({"status": "token_issued", "approval_token": None})
    return base


def verify_readback(p):
    for ch in p["changes"]:
        if ch["type"] == "schedule_one_time":
            t = STATE["tasks"].get(ch["task_id"])
            if not t or t["planned_date"] != ch["planned_date"] or t.get("scheduled_at") != ch.get("scheduled_at"):
                raise ToolError("READBACK_MISMATCH", "单次事项回读不一致。")
        else:
            o = STATE["overrides"].get((ch["item_id"], ch["local_date"]))
            if not o or o["item_type"] != ch["item_type"] or o["action"] != ch["action"] \
                    or o["planned_start_minute"] != ch["planned_start_minute"] \
                    or o["planned_end_minute"] != ch["planned_end_minute"]:
                raise ToolError("READBACK_MISMATCH", "单日例外回读不一致。")


def tool_apply(args, user):
    inp = validate_envelope(args)
    pid, base_version = inp.get("proposal_id"), inp.get("base_version")
    token, key = inp.get("approval_token"), inp.get("idempotency_key")
    if not isinstance(pid, str) or not pid or not isinstance(base_version, str) or not base_version:
        raise ToolError("INVALID_ARGUMENT", "proposal_id/base_version 必填。")
    if not isinstance(key, str) or not key:
        raise ToolError("INVALID_ARGUMENT", "idempotency_key 必填。")
    if not isinstance(token, str) or not token:
        rec = find_approval_for_proposal(pid, user) if isinstance(pid, str) else None
        if not rec:
            raise ToolError("APPROVAL_REQUIRED", "没有可用的审批记录。")
        st = apply_approval_status(rec)
        if st == "pending":
            raise ToolError("APPROVAL_PENDING", "外部审批尚未通过。")
        if st == "rejected":
            raise ToolError("APPROVAL_REJECTED", "用户已拒绝该提案。")
        if st == "expired":
            raise ToolError("APPROVAL_EXPIRED", "审批或 Token 已过期。")
        raise ToolError("APPROVAL_REQUIRED", "审批尚未签发 Token。")
    trec = STATE["tokens"].get(token)
    if not trec or trec["user"] != user:
        raise ToolError("APPROVAL_UNTRUSTED", "审批 Token 无效。")
    p = STATE["proposals"].get(pid)
    internal = STATE["internal"].get(pid)
    if not p or not internal or internal["user"] != user:
        raise ToolError("NOT_FOUND", "找不到该提案。")

    idem = (user, "apply_approved_changes", key)
    req_digest = digest({"proposal": pid, "base_version": base_version,
                         "approval_id": trec["approval_id"]})
    cached = STATE["idempotency"].get(idem)
    if cached:
        if cached["digest"] != req_digest:
            raise ToolError("IDEMPOTENCY_CONFLICT", "幂等键被用于不同请求。")
        if cached["state"] == "done":
            return cached["result"]
        verify_readback(p)
        cached["state"] = "done"
        return cached["result"]

    if p["status"] in ("applying", "readback_pending"):
        raise ToolError("READBACK_PENDING", "写入可能已发生，只能用同一幂等键继续回读。",
                        [{"field": "proposal.status", "reason": "readback_pending"},
                         {"field": "input.idempotency_key", "reason": "reuse_same_key_for_readback_only"}])

    if pid in STATE["applied_proposals"]:
        raise ToolError("ALREADY_APPLIED", "该提案已成功应用。")

    if parse_instant(p["expires_at"], "expires_at") < now():
        raise ToolError("PROPOSAL_EXPIRED", "提案已过期。")

    start, end = map(date.fromisoformat, internal["range"])
    current = snapshot_digest(user, start, end, internal["events"])
    if current != p["input_digest"] or p["base_version"] != base_version:
        raise ToolError("SNAPSHOT_CONFLICT", "快照或版本已变化。")

    if rec := refresh_approval(trec["approval_id"]):
        st = apply_approval_status(rec)
        if st == "pending":
            raise ToolError("APPROVAL_PENDING", "外部审批尚未通过。")
        if st == "rejected":
            raise ToolError("APPROVAL_REJECTED", "用户已拒绝该提案。")
        if st == "expired":
            raise ToolError("APPROVAL_EXPIRED", "审批或 Token 已过期。")

    if trec["consumed"]:
        raise ToolError("APPROVAL_CONSUMED", "Token 已消费。")
    if take_flag("expire_token"):
        trec["expires_at"] = iso(now() - timedelta(minutes=1))
    if parse_instant(trec["expires_at"], "expires_at") < now():
        raise ToolError("APPROVAL_EXPIRED", "审批 Token 已过期。")
    if trec["proposal_id"] != pid or trec["base_version"] != base_version:
        raise ToolError("APPROVAL_UNTRUSTED", "审批 Token 与提案不匹配。")
    if p["status"] != "pending_approval":
        raise ToolError("PROPOSAL_INVALID", "提案当前不可应用。")

    check_items_exist(p)
    p["status"] = "applying"

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
            oid = _next_id("ov")
            STATE["overrides"][(ch["item_id"], ch["local_date"])] = {
                "override_id": oid, "item_type": ch["item_type"],
                "item_id": ch["item_id"], "local_date": ch["local_date"],
                "action": ch["action"], "planned_start_minute": ch["planned_start_minute"],
                "planned_end_minute": ch["planned_end_minute"],
            }
            applied.append({"change_id": ch["change_id"], "type": ch["type"],
                            "item_type": ch["item_type"], "item_id": ch["item_id"],
                            "local_date": ch["local_date"], "action": ch["action"],
                            "planned_start_minute": ch["planned_start_minute"],
                            "planned_end_minute": ch["planned_end_minute"],
                            "override_id": oid})

    STATE["applied_proposals"].add(pid)
    trec["consumed"] = True
    rec = STATE["approvals"].get(trec["approval_id"])
    if rec:
        rec["token_consumed"] = True

    result = {"proposal_id": pid, "base_version": base_version,
              "result_version": _next_id("ver"), "idempotency_key": key,
              "applied_changes": applied, "readback_verified": True,
              "applied_at": iso(now())}

    if take_flag("readback_mismatch"):
        p["status"] = "readback_pending"
        STATE["idempotency"][idem] = {"digest": req_digest, "state": "readback_pending", "result": result}
        raise ToolError("READBACK_PENDING", "写入可能已提交但回读未完成。",
                        [{"field": "proposal.status", "reason": "readback_pending"}])

    p["status"] = "applied"
    verify_readback(p)
    STATE["idempotency"][idem] = {"digest": req_digest, "state": "done", "result": result}
    return result


TOOLS = {
    "list_tasks": tool_list_tasks,
    "get_calendar_events": tool_get_calendar_events,
    "generate_schedule": tool_generate_schedule,
    "validate_schedule": tool_validate_schedule,
    "apply_approved_changes": tool_apply,
    "request_approval": tool_request_approval,
    "get_approval_status": tool_get_approval_status,
}

DESCRIPTIONS = {
    "list_tasks": "读取当前用户的任务定义（不展开逐日 occurrence）。",
    "get_calendar_events": "读取日期范围内生效的课程、任务与单日例外，支持传入外部固定事件。",
    "generate_schedule": "基于服务端快照生成调度提案（只读，不写入）。",
    "validate_schedule": "按服务端快照重新校验提案，合法则进入 pending_approval。",
    "apply_approved_changes": "凭可信审批凭据原子应用变更并回读核验。",
    "request_approval": "[候选扩展] 创建 pending 审批请求（按提案与幂等键幂等），不批准、不签 Token。",
    "get_approval_status": "[候选扩展] 轮询外部审批页；仅在批准后首次交付一次性 Token。",
}


def obj(props, required=None):
    d = {"type": "object", "properties": props, "additionalProperties": False}
    if required:
        d["required"] = required
    return d


DATE_STR = {"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$"}
DATE_RANGE = obj({"start": DATE_STR, "end": DATE_STR}, ["start", "end"])

SCHEMAS = {
    "list_tasks": obj({
        "date_range": {"$ref": "#/$defs/date_range"},
        "kinds": {"type": "array", "items": {"enum": ["recurring", "one_time"]}},
        "statuses": {"type": "array", "items": {"enum": ["active", "paused", "archived"]}},
        "include_completed": {"type": "boolean"}}, ["date_range"]),
    "get_calendar_events": obj({
        "date_range": {"$ref": "#/$defs/date_range"},
        "external_fixed_events": {"type": "array", "items": obj({
            "external_event_id": {"type": "string"}, "title": {"type": "string"},
            "start_at": {"type": "string"}, "end_at": {"type": "string"}},
            ["external_event_id", "title", "start_at", "end_at"])}}, ["date_range"]),
    "generate_schedule": obj({
        "date_range": {"$ref": "#/$defs/date_range"},
        "external_fixed_events": {"type": "array", "items": obj({
            "external_event_id": {"type": "string"}, "title": {"type": "string"},
            "start_at": {"type": "string"}, "end_at": {"type": "string"}},
            ["external_event_id", "title", "start_at", "end_at"])},
        "preferences": obj({
            "day_start_minute": {"type": "integer"},
            "day_end_minute": {"type": "integer"},
            "minimum_block_minutes": {"type": "integer"}})}, ["date_range"]),
    "validate_schedule": obj({"proposal_id": {"type": "string"}}, ["proposal_id"]),
    "apply_approved_changes": obj({
        "proposal_id": {"type": "string"}, "base_version": {"type": "string"},
        "approval_token": {"type": "string"}, "idempotency_key": {"type": "string"}},
        ["proposal_id", "base_version", "approval_token", "idempotency_key"]),
    "request_approval": obj({
        "proposal_id": {"type": "string"}, "idempotency_key": {"type": "string"}},
        ["proposal_id", "idempotency_key"]),
    "get_approval_status": obj({"approval_id": {"type": "string"}}, ["approval_id"]),
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
                "additionalProperties": False,
                "$defs": {"date_range": DATE_RANGE},
            },
        })
    return defs


# ---------------------------------------------------------------- MCP plumbing

def send(o):
    sys.stdout.write(json.dumps(o, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def ok(rid, result):
    send({"jsonrpc": "2.0", "id": rid, "result": result})


def err(rid, code, message):
    send({"jsonrpc": "2.0", "id": rid, "error": {"code": code, "message": message}})


def envelope(request_id, status, payload):
    return {"api_version": API_VERSION, "request_id": request_id,
            "trace_id": "trace_" + uuid.uuid4().hex[:16], "status": status, **payload}


def call_tool(name, args, token):
    rid = args.get("request_id") if isinstance(args, dict) else None
    try:
        user = user_from_token(token)
        data = TOOLS[name](args, user)
        body = envelope(rid, "success", {"data": data})
        return {"content": [{"type": "text", "text": json.dumps(body, ensure_ascii=False)}],
                "structuredContent": body, "isError": False}
    except ToolError as e:
        body = envelope(rid, "error", {"error": {
            "code": e.code, "message": e.message, "retryable": False, "details": e.details}})
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
            tok = hdr.get("authorization", token)
            if tok.startswith("Bearer "):
                tok = tok[7:]
            if name not in TOOLS:
                ok(rid, {"content": [{"type": "text", "text": "unknown tool"}], "isError": True})
            else:
                ok(rid, call_tool(name, args, tok))
        else:
            err(rid, -32601, f"method not found: {method}")


if __name__ == "__main__":
    main()