"""跨学期课程过滤 + 长期任务排期的测试。

背景（2026-11-26 盘点 Flutter Drift 时发现的两个真缺口）：
  1. `courses.semester_id` 一直没被用到 —— 服务端所有 active 课程都按「当前学期」
     算周次，上过学期但仍 active 的课会凭空出现在本周课表里。
  2. `task_schedules` 一直没被读到 —— 长期任务只有「全纳入」一种处理，
     用户设的「只在工作日」「下月才开始」全部失效，负荷会虚高。

这两个缺口都不需要数据库就能修，属于「能做的」，所以补上并钉测试。

跑法：python -m unittest test_semester_and_schedule -v
"""

import json
import os
import unittest

from context_snapshot import build_snapshot

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURE = os.path.join(HERE, "fixtures", "seed_semester_schedule.json")
THURSDAY = ("2026-11-26", "2026-11-26")   # 第 13 周周四
SATURDAY = ("2026-11-28", "2026-11-28")   # 第 13 周周六


def load() -> dict:
    with open(FIXTURE, encoding="utf-8") as fh:
        return json.load(fh)


def snap(window=THURSDAY, **overrides):
    seed = load()
    kwargs = dict(
        window_from=window[0], window_through=window[1],
        semesters=seed["semesters"],
        courses=seed["courses"],
        rules=seed["course_schedule_rules"],
        tasks=seed["tasks"],
        one_time_reminders=seed["one_time_reminders"],
        long_term_tasks=seed["long_term_tasks"],
        completions=seed["task_completions"],
        task_schedules=seed["task_schedules"],
        occurrences_available=False,
        occurrences_cover_window=False,
    )
    kwargs.update(overrides)
    return build_snapshot(**kwargs)


def course_titles(out) -> list[str]:
    return [e["title"] for e in out["fixed_events"]]


def task_names(out) -> list[str]:
    return [t["name"] for t in out["tasks"]]


class TestSemesterScopedCourses(unittest.TestCase):
    def test_current_semester_course_appears(self):
        self.assertIn("本学期课", course_titles(snap()))

    def test_previous_semester_course_excluded(self):
        """上过学期但仍 active 的课不能混进当前周。"""
        self.assertNotIn("上学期课", course_titles(snap()))

    def test_legacy_course_without_semester_still_appears(self):
        """semester_id 为 null 的历史课程继续纳入，否则老用户整张课表会消失。"""
        self.assertIn("无学期课程", course_titles(snap()))

    def test_exactly_two_courses_on_thursday(self):
        self.assertEqual(sorted(course_titles(snap())), ["无学期课程", "本学期课"])

    def test_multiple_current_semesters_keep_all_their_courses(self):
        """多条 is_current（数据异常）时，挂在任一条上的课都要保留。

        如果按「某一个 id」过滤，第二条上的课会被整批丢掉——这是刻意避免的行为。
        """
        seed = load()
        semesters = seed["semesters"] + [{
            "id": "sem-dup", "name": "重复当前学期",
            "first_week_start_date": "2026-08-31", "total_weeks": 18,
            "is_current": True, "updated_at": "2026-11-01T00:00:00Z",
            "deleted_at": None,
        }]
        courses = seed["courses"] + [{
            "id": "c-dup", "name": "重复学期课", "status": "active",
            "semester_id": "sem-dup", "deleted_at": None,
        }]
        rules = seed["course_schedule_rules"] + [{
            "id": "r-dup", "course_id": "c-dup", "weekday": 4,
            "starts_at_minute": 900, "ends_at_minute": 960,
            "week_rule_type": "everyWeek", "start_week": None, "end_week": None,
            "interval_weeks": None, "week_numbers": [], "deleted_at": None,
        }]
        out = snap(semesters=semesters, courses=courses, rules=rules)
        self.assertEqual(sorted(course_titles(out)),
                         sorted(["无学期课程", "本学期课", "重复学期课"]))


class TestLongTermSchedule(unittest.TestCase):
    def test_daily_schedule_included(self):
        self.assertIn("每天背单词", task_names(snap()))

    def test_weekday_only_included_on_thursday(self):
        self.assertIn("只在工作日", task_names(snap()))

    def test_weekend_only_excluded_on_thursday(self):
        self.assertNotIn("只在周末", task_names(snap()))

    def test_weekend_only_included_on_saturday(self):
        self.assertIn("只在周末", task_names(snap(window=SATURDAY)))

    def test_schedule_starting_after_window_excluded(self):
        """starts_on 在窗口之后 → 本窗口不该做。"""
        self.assertNotIn("下月才开始", task_names(snap()))

    def test_task_without_schedule_row_kept(self):
        """没有排期行的长期任务是老数据，保留；否则整批长期任务会消失。"""
        self.assertIn("老数据无排期", task_names(snap()))

    def test_paused_task_excluded(self):
        self.assertNotIn("暂停任务", task_names(snap()))

    def test_workload_counts_only_scheduled(self):
        """负荷只算纳入的任务：30 + 60 = 90 分钟已知识别，1 条未知，共 3 条未完成。"""
        wl = snap()["workload"]
        self.assertEqual(wl["known_minutes"], 90)
        self.assertEqual(wl["unknown_estimate_count"], 1)
        self.assertEqual(wl["open_task_count"], 3)

    def test_mask_falls_back_to_weekdays_array(self):
        seed = dict(load())
        seed["task_schedules"] = [
            {**s, "weekdays_mask": None} for s in seed["task_schedules"]
        ]
        self.assertIn("只在工作日", task_names(snap(task_schedules=seed["task_schedules"])))
        self.assertNotIn("只在周末", task_names(snap(task_schedules=seed["task_schedules"])))

    def test_empty_mask_and_no_weekdays_means_never(self):
        """mask=0 且没有 weekdays 数组 → 明确不做（fail closed），不当成每天。"""
        seed = load()
        idx = next(i for i, s in enumerate(seed["task_schedules"]) if s["task_id"] == "t-daily")
        schedules = [dict(s) for s in seed["task_schedules"]]
        schedules[idx]["weekdays_mask"] = 0
        schedules[idx]["weekdays"] = []
        self.assertNotIn("每天背单词", task_names(snap(task_schedules=schedules)))

    def test_any_of_multiple_schedules_hit_is_enough(self):
        """同一任务多条排期，任一命中即算要做。"""
        seed = load()
        schedules = list(seed["task_schedules"]) + [{
            "id": "s-extra", "task_id": "t-weekend", "schedule_type": "custom",
            "weekdays_mask": 8, "weekdays": [4],   # 周四
            "starts_on": "2026-08-31", "ends_on": None, "deleted_at": None,
        }]
        self.assertIn("只在周末", task_names(snap(task_schedules=schedules)))

    def test_ended_schedule_excluded(self):
        """ends_on 早于窗口 → 排期已结束，不该做。"""
        seed = load()
        schedules = [dict(s) for s in seed["task_schedules"]]
        idx = next(i for i, s in enumerate(schedules) if s["task_id"] == "t-weekday")
        schedules[idx]["ends_on"] = "2026-10-01"
        self.assertNotIn("只在工作日", task_names(snap(task_schedules=schedules)))


if __name__ == "__main__":
    unittest.main()
