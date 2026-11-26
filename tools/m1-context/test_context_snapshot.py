#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ContextSnapshot 参考实现的验收测试。

对应 STAGE 04 M1「最低验收清单」里能在一台无数据库的机器上验证的部分：

  ✔ 固定课程改变后 free_slots / workload 随之变化
  ✔ 过期、不完整、未展开的数据被标记，且不生成虚假可用时段
  ✔ 真实任务/完成记录可读取；缺字段返回 unknown
  ✔ 时区、跨日、空数据、无可用窗口

  以下两条属于数据库层，**本文件覆盖不到**，由 migration + RLS 承担：
  ✘ 同一 event_id 重试不重复计数（behavior_events 主键约束）
  ✘ 账号 A 不能读/改账号 B 的数据（RLS）

跑法：
    python -m unittest discover -s tools/m1-context -p "test_*.py"
或：
    cd tools/m1-context && python -m unittest test_context_snapshot -v
"""

from __future__ import annotations

import json
import os
import unittest
from datetime import date

from context_snapshot import build_snapshot

HERE = os.path.dirname(os.path.abspath(__file__))
WINDOW = ("2026-11-26", "2026-11-28")   # 周四 ~ 周六，第 13 教学周


def load_seed() -> dict:
    with open(os.path.join(HERE, "fixtures", "seed.json"), encoding="utf-8") as fh:
        return json.load(fh)


def snap(seed=None, **overrides):
    seed = load_seed() if seed is None else seed
    kwargs = dict(
        window_from=WINDOW[0], window_through=WINDOW[1],
        semesters=seed.get("semesters", []),
        courses=seed.get("courses", []),
        rules=seed.get("course_schedule_rules", []),
        tasks=seed.get("tasks", []),
        one_time_reminders=seed.get("one_time_reminders", []),
        long_term_tasks=seed.get("long_term_tasks", []),
        completions=seed.get("task_completions", []),
        occurrences_available=seed.get("occurrences_available", False),
        occurrences_cover_window=seed.get("occurrences_cover_window", False),
    )
    kwargs.update(overrides)
    return build_snapshot(**kwargs)


class TestFixedEvents(unittest.TestCase):
    def test_thursday_course_expanded_once(self):
        out = snap()
        courses = [e for e in out["fixed_events"] if e["kind"] == "course"]
        self.assertEqual(len(courses), 1, "窗口内只有周四数据结构一门课")
        e = courses[0]
        self.assertEqual(e["date"], "2026-11-26")
        self.assertEqual((e["start_minute"], e["end_minute"]), (490, 710))
        self.assertEqual(e["week_no"], 13)
        self.assertEqual(e["title"], "数据结构")

    def test_archived_course_excluded(self):
        out = snap()
        titles = {e["title"] for e in out["fixed_events"]}
        self.assertNotIn("已归档课程", titles)

    def test_week_numbers_take_priority(self):
        """大学物理用 week_numbers 1..18，第 13 周必须上课。"""
        out = snap(window_from="2026-11-24", window_through="2026-11-24")  # 周二
        titles = [e["title"] for e in out["fixed_events"]]
        self.assertIn("大学物理", titles)

    def test_even_weeks_rule(self):
        """IELTS写作 evenWeeks：第 13 周(奇)不上，第 14 周(偶)上。"""
        odd = snap(window_from="2026-11-24", window_through="2026-11-24")   # 第13周周二
        self.assertNotIn("IELTS写作", [e["title"] for e in odd["fixed_events"]])

        even = snap(window_from="2026-12-01", window_through="2026-12-01")  # 第14周周二
        self.assertIn("IELTS写作", [e["title"] for e in even["fixed_events"]])

    def test_outside_semester_weeks_ignored(self):
        """第 19 周已超 total_weeks=18，课不应出现。"""
        out = snap(window_from="2027-01-05", window_through="2027-01-05")  # 第19周周二
        self.assertEqual(out["fixed_events"], [])


class TestFreeSlots(unittest.TestCase):
    def test_three_days_two_segments_on_course_day(self):
        out = snap()
        slots = out["free_slots"]
        thu = [s for s in slots if s["date"] == "2026-11-26"]
        self.assertEqual(len(thu), 2, "周四被课程切成两段")
        self.assertEqual((thu[0]["start_minute"], thu[0]["end_minute"]), (480, 490))
        self.assertEqual(thu[0]["minutes"], 10)
        self.assertEqual((thu[1]["start_minute"], thu[1]["end_minute"]), (710, 1380))

    def test_free_slots_change_when_course_changes(self):
        """验收清单第 3 条：固定课程改变，free_slots 必须随之变化。"""
        seed = load_seed()
        before = snap(seed)
        # 把周四那门课挪到周五 08:10-11:50
        moved = json.loads(json.dumps(seed))
        for rule in moved["course_schedule_rules"]:
            if rule["id"] == "r-ds-thu":
                rule["weekday"] = 5
        after = snap(moved)
        self.assertNotEqual(before["free_slots"], after["free_slots"])
        thu_before = [s for s in before["free_slots"] if s["date"] == "2026-11-26"]
        thu_after = [s for s in after["free_slots"] if s["date"] == "2026-11-26"]
        self.assertEqual(len(thu_before), 2)
        self.assertEqual(len(thu_after), 1, "课程搬走后周四应变成整段空闲")

    def test_no_free_slot_when_day_fully_booked(self):
        """验收清单：无可用窗口时不编造时段。"""
        seed = load_seed()
        busy = json.loads(json.dumps(seed))
        for rule in busy["course_schedule_rules"]:
            if rule["id"] == "r-ds-thu":
                rule["starts_at_minute"] = 0
                rule["ends_at_minute"] = 1440
        out = snap(busy, day_start_minute=0, day_end_minute=1440)
        thu = [s for s in out["free_slots"] if s["date"] == "2026-11-26"]
        self.assertEqual(thu, [])

    def test_tiny_gap_dropped(self):
        """小于 5 分钟的碎片不算可用窗口。"""
        seed = load_seed()
        tight = json.loads(json.dumps(seed))
        for rule in tight["course_schedule_rules"]:
            if rule["id"] == "r-ds-thu":
                rule["starts_at_minute"] = 483   # 距 480 只剩 3 分钟
        out = snap(tight)
        thu = [s for s in out["free_slots"] if s["date"] == "2026-11-26"]
        self.assertEqual(len(thu), 1)
        self.assertEqual(thu[0]["start_minute"], 710)


class TestTasksAndWorkload(unittest.TestCase):
    def test_workload_splits_known_and_unknown(self):
        out = snap()
        w = out["workload"]
        self.assertEqual(w["known_minutes"], 60, "背单词 3600 秒 = 60 分钟")
        self.assertEqual(w["unknown_estimate_count"], 1, "单次任务没有预计时长字段")
        self.assertEqual(w["open_task_count"], 2, "已完成的不计入未完成")
        self.assertEqual(w["status"], "partial")

    def test_completed_task_not_counted(self):
        out = snap()
        done = next(t for t in out["tasks"] if t["task_id"] == "t-done")
        self.assertTrue(done["completed"])

        # 把完成记录去掉，未完成数应 +1
        seed = load_seed()
        seed = json.loads(json.dumps(seed))
        seed["task_completions"] = []
        out2 = snap(seed)
        self.assertEqual(out2["workload"]["open_task_count"], 3)

    def test_missing_estimate_is_unknown_not_zero(self):
        out = snap()
        lab = next(t for t in out["tasks"] if t["task_id"] == "t-lab-report")
        self.assertIsNone(lab["estimated_minutes"])
        self.assertEqual(lab["estimated_status"], "unknown")

    def test_archived_task_excluded(self):
        out = snap()
        ids = {t["task_id"] for t in out["tasks"]}
        self.assertNotIn("t-archived", ids)

    def test_task_outside_window_excluded(self):
        seed = load_seed()
        far = json.loads(json.dumps(seed))
        for r in far["one_time_reminders"]:
            if r["task_id"] == "t-lab-report":
                r["due_date"] = "2026-12-20"
                r["planned_date"] = "2026-12-19"
        out = snap(far)
        self.assertNotIn("t-lab-report", {t["task_id"] for t in out["tasks"]})


class TestFreshnessAndBlocking(unittest.TestCase):
    def test_missing_semester_blocks_courses(self):
        seed = load_seed()
        seed = json.loads(json.dumps(seed))
        seed["semesters"] = []
        out = snap(seed)
        self.assertEqual(out["semester"]["status"], "missing")
        self.assertEqual(out["fixed_events"], [])
        self.assertEqual(out["status"], "blocked")
        codes = [b["code"] for b in out["blocking"]]
        self.assertIn("SEMESTER_MISSING", codes)

    def test_occurrences_missing_marks_partial(self):
        out = snap()
        self.assertEqual(out["freshness"]["task_occurrences"], "missing")
        self.assertEqual(out["status"], "partial")
        self.assertIn("TASK_OCCURRENCES_UNAVAILABLE",
                      [b["code"] for b in out["blocking"]])

    def test_occurrences_published_and_known_workload_is_ok(self):
        """occurrence 有 + 无未知时长 => 整体 ok。"""
        seed = load_seed()
        seed = json.loads(json.dumps(seed))
        seed["occurrences_available"] = True
        seed["occurrences_cover_window"] = True
        seed["one_time_reminders"] = [r for r in seed["one_time_reminders"]
                                      if r["task_id"] != "t-lab-report"]
        seed["tasks"] = [t for t in seed["tasks"] if t["id"] != "t-lab-report"]
        out = snap(seed)
        self.assertEqual(out["freshness"]["task_occurrences"], "published")
        self.assertEqual(out["status"], "ok")
        self.assertEqual(out["blocking"], [])


class TestBoundaries(unittest.TestCase):
    def test_empty_data_does_not_crash(self):
        out = build_snapshot(window_from="2026-11-26", window_through="2026-11-26",
                             semesters=[], courses=[], rules=[], tasks=[])
        self.assertEqual(out["tasks"], [])
        self.assertEqual(out["fixed_events"], [])
        self.assertEqual(out["status"], "blocked")

    def test_window_over_31_days_rejected(self):
        with self.assertRaises(ValueError) as ctx:
            build_snapshot(window_from="2026-11-01", window_through="2026-12-31",
                           semesters=[], courses=[], rules=[], tasks=[])
        self.assertEqual(str(ctx.exception), "RANGE_TOO_LARGE")

    def test_reversed_window_rejected(self):
        with self.assertRaises(ValueError):
            build_snapshot(window_from="2026-11-28", window_through="2026-11-26",
                           semesters=[], courses=[], rules=[], tasks=[])

    def test_invalid_energy_rejected(self):
        with self.assertRaises(ValueError):
            build_snapshot(window_from="2026-11-26", window_through="2026-11-26",
                           semesters=[], courses=[], rules=[], tasks=[],
                           energy_self_report=9)

    def test_cross_day_window_covers_each_day(self):
        out = snap(window_from="2026-11-27", window_through="2026-11-29")
        dates = {s["date"] for s in out["free_slots"]}
        self.assertEqual(dates, {"2026-11-27", "2026-11-28", "2026-11-29"})

    def test_timezone_is_echoed_not_used_for_date_math(self):
        """日期按用户本地日历日解释；timezone 只回显，不参与运算。"""
        a = snap(timezone="Asia/Shanghai")
        b = snap(timezone="UTC")
        self.assertEqual(a["free_slots"], b["free_slots"])
        self.assertEqual(a["timezone"], "Asia/Shanghai")
        self.assertEqual(b["timezone"], "UTC")

    def test_energy_self_report_echoed(self):
        out = snap(energy_self_report=3)
        self.assertEqual(out["energy_self_report"], 3)
        self.assertIsNone(snap()["energy_self_report"])

    def test_output_shape_matches_contract(self):
        out = snap()
        for key in ("as_of", "timezone", "window", "semester", "fixed_events",
                    "free_slots", "tasks", "workload", "energy_self_report",
                    "freshness", "status", "blocking"):
            self.assertIn(key, out, "契约字段缺失: %s" % key)
        self.assertIn("known_minutes", out["workload"])
        self.assertIn("unknown_estimate_count", out["workload"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
