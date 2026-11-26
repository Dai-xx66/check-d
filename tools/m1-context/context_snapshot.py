#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ContextSnapshot 参考实现（与 supabase/migrations/202611260002 同算法）。

为什么有这份 Python：

  1. M1 侧**没有数据库连接**（本机无 psql / 无容器 / TLS 到 Supabase 不通），
     SQL 无法在真实库执行。这份实现用 fixture 证明「算法」正确，SQL 的语法与
     执行仍需 M0 在有权环境跑一次。
  2. M0 要用固定 fixture 提前开发（任务书 §5 G1），需要能离线生成样例 JSON。
  3. 将来 Dart 实现要与它逐条对拍：同一 fixture 必须得到同一结果。

严格同构的三处，改动时必须同步（改一边不改另一边 = 造第二套口径）：
  · 周次计算：week_no = (day - first_week_start_date).days // 7 + 1
  · 规则匹配：week_numbers 非空时优先；否则按 everyWeek / oddWeeks / evenWeeks / everyNWeeks
  · 空闲计算：每天 [day_start, day_end) 按分钟求差集，再合并连续段，丢弃 < 5 分钟碎片

不做的事（与 SQL 一致）：
  · 不展开长周期任务实例。只在 occurrences_available 为真时读取客户端已发布实例。
  · 不用 0 或默认值冒充缺失字段，一律返回 unknown。
"""

from __future__ import annotations

import json
from datetime import date, datetime, timedelta, timezone as dt_timezone
from typing import Any, Iterable

SLOT_MIN_MINUTES = 5
MAX_WINDOW_DAYS = 31


def _iso_utc(dt: datetime | None = None) -> str:
    dt = dt or datetime.now(dt_timezone.utc)
    return dt.astimezone(dt_timezone.utc).isoformat().replace("+00:00", "Z")


def _parse_date(value: Any) -> date | None:
    if value is None or value == "":
        return None
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    return date.fromisoformat(str(value)[:10])


def _week_no(day: date, first_week_start: date) -> int:
    """第几教学周。与 SQL 的 ((d - fw) / 7) + 1 同义（整数除法）。"""
    return (day - first_week_start).days // 7 + 1


def _rule_matches(rule: dict[str, Any], week_no: int, total_weeks: int) -> bool:
    """某条排课规则在第 week_no 周是否成立。顺序与 SQL 的 CASE 完全一致。"""
    if not (1 <= week_no <= total_weeks):
        return False
    start_week = rule.get("start_week")
    end_week = rule.get("end_week")
    if start_week is not None and week_no < start_week:
        return False
    if end_week is not None and week_no > end_week:
        return False

    week_numbers = rule.get("week_numbers") or []
    if week_numbers:
        return week_no in week_numbers

    kind = rule.get("week_rule_type")
    if kind == "everyWeek":
        return True
    if kind == "oddWeeks":
        return week_no % 2 == 1
    if kind == "evenWeeks":
        return week_no % 2 == 0
    if kind == "everyNWeeks":
        base = start_week if start_week is not None else 1
        interval = rule.get("interval_weeks") or 1
        if interval <= 0 or week_no < base:
            return False
        return (week_no - base) % interval == 0
    return False


def _iter_days(start: date, end: date) -> Iterable[date]:
    cursor = start
    while cursor <= end:
        yield cursor
        cursor += timedelta(days=1)


def _merge_free(days: list[date], busy: dict[date, list[tuple[int, int]]],
                day_start: int, day_end: int) -> list[dict[str, Any]]:
    """每分钟打点求差集，再合并连续区间。与 SQL 的 islands 同算法。"""
    out: list[dict[str, Any]] = []
    for day in days:
        occupied: set[int] = set()
        for start, end in busy.get(day, []):
            if end > start:
                occupied.update(range(start, end))
        minutes = [m for m in range(day_start, day_end) if m not in occupied]
        if not minutes:
            continue
        run_start = minutes[0]
        prev = minutes[0]
        for m in minutes[1:]:
            if m == prev + 1:
                prev = m
                continue
            if prev + 1 - run_start >= SLOT_MIN_MINUTES:
                out.append({"date": day.isoformat(), "start_minute": run_start,
                            "end_minute": prev + 1, "minutes": prev + 1 - run_start})
            run_start = m
            prev = m
        if prev + 1 - run_start >= SLOT_MIN_MINUTES:
            out.append({"date": day.isoformat(), "start_minute": run_start,
                        "end_minute": prev + 1, "minutes": prev + 1 - run_start})
    return out


def _long_term_scheduled_in_window(task_id: str,
                                   schedules: list[dict[str, Any]],
                                   days: list[date]) -> bool:
    """长期任务在本窗口内是否有「该做」的天。

    与 0002 migration 同语义：
      - 没有任何排期行 → True（老数据兼容；否则长期任务会整批消失）
      - 有排期行 → 窗口内至少一天命中 weekdays_mask（bit0 = 周一）
      - mask 缺失时回退到 weekdays 数组；两者都没有 → False（fail closed）
    """
    rows = [s for s in schedules
            if s.get("task_id") == task_id and not s.get("deleted_at")]
    if not rows:
        return True
    for row in rows:
        starts_on = _parse_date(row.get("starts_on"))
        ends_on = _parse_date(row.get("ends_on"))
        mask = row.get("weekdays_mask")
        weekdays = row.get("weekdays") or []
        for day in days:
            if starts_on and day < starts_on:
                continue
            if ends_on and day > ends_on:
                continue
            if isinstance(mask, int):
                if mask & (1 << (day.isoweekday() - 1)):
                    return True
            elif weekdays:
                if day.isoweekday() in weekdays:
                    return True
            else:
                return False
    return False


def build_snapshot(
    *,
    window_from: date | str,
    window_through: date | str,
    semesters: list[dict[str, Any]],
    courses: list[dict[str, Any]],
    rules: list[dict[str, Any]],
    tasks: list[dict[str, Any]],
    one_time_reminders: list[dict[str, Any]] | None = None,
    long_term_tasks: list[dict[str, Any]] | None = None,
    completions: list[dict[str, Any]] | None = None,
    task_schedules: list[dict[str, Any]] | None = None,
    occurrences_available: bool = False,
    occurrences_cover_window: bool = False,
    timezone: str = "Asia/Shanghai",
    energy_self_report: int | None = None,
    day_start_minute: int = 480,
    day_end_minute: int = 1380,
    now: datetime | None = None,
) -> dict[str, Any]:
    """产出一份 ContextSnapshot。字段名与任务书 §6 一致。"""
    start = _parse_date(window_from)
    through = _parse_date(window_through)
    if start is None or through is None or through < start:
        raise ValueError("INVALID_RANGE")
    if (through - start).days > MAX_WINDOW_DAYS:
        raise ValueError("RANGE_TOO_LARGE")
    if not (0 <= day_start_minute < day_end_minute <= 1440):
        raise ValueError("INVALID_DAY_WINDOW")
    if energy_self_report is not None and not (1 <= energy_self_report <= 5):
        raise ValueError("INVALID_ENERGY")

    one_time_reminders = one_time_reminders or []
    long_term_tasks = long_term_tasks or []
    completions = completions or []
    task_schedules = task_schedules or []

    blocking: list[dict[str, str]] = []

    # ---------- 学期锚点 ----------
    # 与 SQL 一致：多条 is_current 时取 updated_at 最新的一条（数据异常下的确定性）。
    current_candidates = [s for s in semesters
                          if s.get("is_current") and not s.get("deleted_at")]
    current_candidates.sort(key=lambda s: str(s.get("updated_at") or ""), reverse=True)
    current = current_candidates[0] if current_candidates else None
    if current is None:
        semester_status = "missing"
        semester_block = {"status": "missing"}
        blocking.append({"code": "SEMESTER_MISSING",
                         "message": "No current semester; course weekly expansion is impossible."})
    else:
        semester_status = "ok"
        first_week = _parse_date(current["first_week_start_date"])
        total_weeks = int(current["total_weeks"])
        semester_block = {"status": "ok",
                          "first_week_start_date": first_week.isoformat(),
                          "total_weeks": total_weeks}

    # ---------- 固定事件：课程展开 ----------
    # 只展开属于当前学期的课程。semester_id 为 null 的历史课程（semesters 表出现前
    # 创建的）继续纳入，否则老用户整张课表会消失。
    # 判据是「属于任意一个 is_current 学期」而非某一个 id：数据异常下若有多条
    # is_current，按单 id 过滤会把挂在另一条上的课整批丢掉。
    current_sids = {s.get("id") for s in current_candidates if s.get("id")}
    course_by_id = {
        c["id"]: c for c in courses
        if not c.get("deleted_at")
        and c.get("status", "active") == "active"
        and (c.get("semester_id") is None or c.get("semester_id") in current_sids)
    }
    days = list(_iter_days(start, through))
    fixed_events: list[dict[str, Any]] = []
    if current is not None:
        for day in days:
            iso_dow = day.isoweekday()          # 1=周一 … 7=周日，与 SQL isodow 一致
            for rule in rules:
                if rule.get("deleted_at") or rule.get("weekday") != iso_dow:
                    continue
                course = course_by_id.get(rule.get("course_id"))
                if course is None:
                    continue
                week_no = _week_no(day, first_week)
                if not _rule_matches(rule, week_no, total_weeks):
                    continue
                fixed_events.append({
                    "kind": "course",
                    "ref_id": course["id"],
                    "title": course["name"],
                    "date": day.isoformat(),
                    "start_minute": int(rule["starts_at_minute"]),
                    "end_minute": int(rule["ends_at_minute"]),
                    "week_no": week_no,
                    "source": "courses+course_schedule_rules",
                })
    fixed_events.sort(key=lambda e: (e["date"], e["start_minute"]))

    # ---------- 空闲时段 ----------
    busy: dict[date, list[tuple[int, int]]] = {}
    for event in fixed_events:
        busy.setdefault(date.fromisoformat(event["date"]), []).append(
            (event["start_minute"], event["end_minute"]))
    free_slots = _merge_free(days, busy, day_start_minute, day_end_minute)

    # ---------- 任务与负荷 ----------
    reminder_by_task = {r["task_id"]: r for r in one_time_reminders if not r.get("deleted_at")}
    long_by_task = {t["task_id"]: t for t in long_term_tasks if not t.get("deleted_at")}
    completed_ids = {c["task_id"] for c in completions
                     if c.get("is_success") and not c.get("deleted_at")}

    task_rows: list[dict[str, Any]] = []
    known = unknown_n = open_n = 0
    for task in tasks:
        if task.get("deleted_at") or task.get("status", "active") != "active":
            continue
        if task.get("type") not in ("one_time", "long_term"):
            continue
        reminder = reminder_by_task.get(task["id"])
        long_row = long_by_task.get(task["id"])

        if task["type"] == "one_time":
            if reminder is None:
                in_window = True      # 提醒行缺失：保留可见，标 unknown
            else:
                due_date = _parse_date(reminder.get("due_date"))
                planned = _parse_date(reminder.get("planned_date"))
                due_at = reminder.get("due_at")
                in_window = bool(
                    (due_date and start <= due_date <= through)
                    or (planned and start <= planned <= through)
                    or (due_at and str(due_at)[:19] >= f"{start.isoformat()}T00:00:00"
                        and str(due_at)[:19] <= f"{through.isoformat()}T23:59:59")
                )
            if not in_window:
                continue
        else:
            reminder = reminder or {}
            long_row = long_row or {}
            # 长期任务只有在排期覆盖本窗口时才算「本窗口该做」。
            # 没有排期行 = 老数据/未设排期 → 保留，否则长期任务会整批消失。
            if not _long_term_scheduled_in_window(task["id"], task_schedules, days):
                continue

        seconds = (long_row or {}).get("target_duration_seconds")
        estimated = None if seconds is None else (int(seconds) + 59) // 60
        done = task["id"] in completed_ids

        task_rows.append({
            "task_id": task["id"],
            "name": task.get("name"),
            "type": task["type"],
            "due_date": (reminder or {}).get("due_date"),
            "due_at": (reminder or {}).get("due_at"),
            "planned_date": (reminder or {}).get("planned_date"),
            "available_from": (reminder or {}).get("available_from"),
            "completed": done,
            "estimated_minutes": estimated,
            "estimated_status": "known" if estimated is not None else "unknown",
        })
        if not done:
            open_n += 1
            if estimated is None:
                unknown_n += 1
            else:
                known += estimated

    order_key = lambda t: (t["due_date"] or t["planned_date"] or through.isoformat(), t["name"] or "")
    task_rows.sort(key=order_key)

    # ---------- occurrence 快照可用性 ----------
    if not occurrences_available:
        occ_status = "missing"
        blocking.append({"code": "TASK_OCCURRENCES_UNAVAILABLE",
                         "message": "Occurrence snapshot table is absent; "
                                    "long-term instances are not expanded here."})
    elif not occurrences_cover_window:
        occ_status = "missing"
        blocking.append({"code": "TASK_OCCURRENCES_MISSING",
                         "message": "No published occurrence snapshot covers this window."})
    else:
        occ_status = "published"

    overall = ("blocked" if semester_status != "ok"
               else "partial" if occ_status != "published" or unknown_n > 0
               else "ok")

    return {
        "as_of": _iso_utc(now),
        "timezone": timezone,
        "window": {"from": start.isoformat(), "through": through.isoformat()},
        "semester": semester_block,
        "fixed_events": fixed_events,
        "free_slots": free_slots,
        "tasks": task_rows,
        "workload": {
            "known_minutes": known,
            "unknown_estimate_count": unknown_n,
            "open_task_count": open_n,
            "status": "known" if unknown_n == 0 else "partial",
        },
        "energy_self_report": energy_self_report,
        "day_window": {"start_minute": day_start_minute, "end_minute": day_end_minute},
        "freshness": {
            "semester": semester_status,
            "task_occurrences": occ_status,
            "completions": "ok",
            "overall": overall,
        },
        "status": overall,
        "blocking": blocking,
    }


def main() -> int:
    """命令行：python context_snapshot.py <fixture.json> [--from ...] [--through ...]"""
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("fixture")
    ap.add_argument("--from", dest="w_from", required=True)
    ap.add_argument("--through", dest="w_through", required=True)
    ap.add_argument("--energy", type=int, default=None)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    with open(args.fixture, encoding="utf-8") as fh:
        seed = json.load(fh)

    snapshot = build_snapshot(
        window_from=args.w_from, window_through=args.w_through,
        semesters=seed.get("semesters", []),
        courses=seed.get("courses", []),
        rules=seed.get("course_schedule_rules", []),
        tasks=seed.get("tasks", []),
        one_time_reminders=seed.get("one_time_reminders", []),
        long_term_tasks=seed.get("long_term_tasks", []),
        completions=seed.get("task_completions", []),
        task_schedules=seed.get("task_schedules", []),
        occurrences_available=seed.get("occurrences_available", False),
        occurrences_cover_window=seed.get("occurrences_cover_window", False),
        energy_self_report=args.energy,
    )
    text = json.dumps(snapshot, ensure_ascii=False, indent=2)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
        print("wrote", args.out)
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
