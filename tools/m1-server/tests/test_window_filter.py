#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""窗口筛选（口径乙：严格筛选 + 逾期单列）的测试。

**背景**：2026-11-10 M3 独立复核发现 `list_tasks` 的 `start`/`end` 只被写进
`data_window` 回显、从未参与筛选（原实现过滤条件只有 `deleted_at` 与 `status`），
属契约 §6.1「date_range：实际查询范围」的违反。M0 同日裁定采用口径乙：

- `date_range` 必须实际参与筛选；
- 「范围内待调度」与「逾期未完成」要有明确分类与原因；
- 逾期任务可供用户了解，但**不得**被引擎排进未来日期；
- 未设日期的 active 任务必须明确归类，不许无依据丢弃；
- 「账号全量基线核对」与「窗口查询输出」是两个不同概念，
  窄窗口筛出的条数少于全量基线**不算读取失败**。

本文件钉住上面每一条。全部靠注入假传输，不连任何真实数据库。

**这些测试通过不等于 REAL-READ 通过**，只证明筛选语义与契约一致。
"""

import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, HERE)

import real_read as rr  # noqa: E402
from test_real_read import FakeTransport, TASK_ROW  # noqa: E402

# 固定的「今天」，让逾期判定可复现。真实调用不传，走系统日期。
TODAY = "2026-11-10"
WIDE = ("2026-11-01", "2026-11-30")
FUTURE = ("2027-06-01", "2027-06-30")


def reader(routes, jwt="fake-jwt"):
    t = FakeTransport(routes)
    return rr.SupabaseReader("https://example.supabase.co", "anon-key",
                             jwt, transport=t), t


def task(tid="uuid-t1", name="任务", ttype="one_time"):
    return {"id": tid, "name": name, "type": ttype, "status": "active",
            "updated_at": "2026-10-29T09:00:00+08:00"}


def run(tasks, window=WIDE, reminders=None, schedules=None, today=TODAY):
    """跑一次 list_tasks，返回 (payload, 最近一次响应)。"""
    routes = {"tasks": (200, tasks)}
    if reminders is not None:
        routes["one_time_reminders"] = (200, reminders)
    if schedules is not None:
        routes["task_schedules"] = (200, schedules)
    r, _ = reader(routes)
    return rr.RealRead(r).list_tasks(window[0], window[1], today=today)


def by_name(payload):
    return {t["name"]: t for t in payload["tasks"]}


# --------------------------------------------------------------------------
# 一、四类归属
# --------------------------------------------------------------------------

class TestClassification(unittest.TestCase):

    def test_overdue_kept_and_labeled(self):
        """截止日已过、且早于窗口起点 ⇒ overdue，必须保留。"""
        out = run([task(name="机器人作业")],
                  reminders=[{"task_id": "uuid-t1", "due_date": "2026-10-11"}])
        got = by_name(out)["机器人作业"]
        self.assertEqual(got["window_status"], rr.WINDOW_OVERDUE)
        self.assertIn("2026-10-11", got["window_reason"])
        self.assertEqual(out["window_counts"]["overdue"], 1)
        self.assertEqual(out["window_counts"]["in_window"], 0)

    def test_in_window_task(self):
        out = run([task(name="交报告")],
                  reminders=[{"task_id": "uuid-t1", "due_date": "2026-11-15"}])
        self.assertEqual(by_name(out)["交报告"]["window_status"], rr.WINDOW_IN)
        self.assertEqual(out["window_counts"]["in_window"], 1)

    def test_undated_task_kept_not_dropped(self):
        """无任何日期 ⇒ undated，保留。丢弃它等于静默漏排。"""
        out = run([task(name="随手记")], reminders=[{"task_id": "uuid-t1"}])
        got = by_name(out)["随手记"]
        self.assertEqual(got["window_status"], rr.WINDOW_UNDATED)
        self.assertIn("未设置", got["window_reason"])

    def test_future_task_excluded(self):
        """未来才到期、且不在窗口 ⇒ 不返回。这是「窗口真生效」的唯一体现。"""
        out = run([task(name="将来的事")],
                  reminders=[{"task_id": "uuid-t1", "due_date": "2027-06-15"}])
        self.assertEqual(out["tasks"], [])
        self.assertEqual(out["window_counts"]["excluded_out_of_window"], 1)

    def test_recurring_covers_window(self):
        out = run([task(name="英语单词", ttype="long_term")],
                  schedules=[{"task_id": "uuid-t1", "schedule_type": "daily",
                              "weekdays": [1, 2, 3, 4, 5, 6, 7],
                              "starts_on": "2026-10-08", "ends_on": None}])
        self.assertEqual(by_name(out)["英语单词"]["window_status"], rr.WINDOW_IN)

    def test_recurring_starts_after_window(self):
        out = run([task(name="下学期的课", ttype="long_term")],
                  schedules=[{"task_id": "uuid-t1", "schedule_type": "daily",
                              "weekdays": [1], "starts_on": "2027-07-01",
                              "ends_on": None}])
        self.assertEqual(out["tasks"], [])


# --------------------------------------------------------------------------
# 二、负向：真的能构造出空集（M0 裁定要求，M3 复核此项）
# --------------------------------------------------------------------------

class TestEmptySet(unittest.TestCase):

    def test_window_filters_everything_out_still_source_real(self):
        """全部任务都不符合窗口条件 ⇒ 空数组，但 source 仍是 real。

        **这是 L4「空集不回落 MOCK」真正的测试。** 2026-11-10 之前这条
        从未被验证过：窗口不生效，所以永远造不出空集。
        """
        tasks = [task(tid="uuid-t1", name="将来的A"),
                 task(tid="uuid-t2", name="将来的B")]
        reminders = [{"task_id": "uuid-t1", "due_date": "2027-06-15"},
                     {"task_id": "uuid-t2", "due_date": "2027-07-20"}]
        out = run(tasks, reminders=reminders, window=("2026-11-01", "2026-11-05"))
        self.assertEqual(out["tasks"], [])
        self.assertEqual(out["source"], "real", "空集也必须 source=real，绝不回落 MOCK")
        self.assertEqual(out["task_count"], 0)
        self.assertEqual(out["window_counts"]["excluded_out_of_window"], 2)
        self.assertNotIn("m_", json.dumps(out["tasks"]), "不得混入 MOCK 夹具")

    def test_overdue_exception_does_not_block_empty_set(self):
        """即使存在逾期例外，也要能构造出真空集。

        逾期任务是「保留」的，所以构造空集必须**不包含任何逾期任务** ——
        这条测试证明「逾期保留」并没有把空集这条路堵死。
        """
        # 一条逾期（保留）+ 一条未来（排除）⇒ 结果只有逾期那条，不是空集
        tasks = [task(tid="uuid-t1", name="已过期"),
                 task(tid="uuid-t2", name="将来的")]
        reminders = [{"task_id": "uuid-t1", "due_date": "2026-10-11"},
                     {"task_id": "uuid-t2", "due_date": "2027-06-15"}]
        out = run(tasks, reminders=reminders, window=("2026-11-01", "2026-11-05"))
        self.assertEqual([t["name"] for t in out["tasks"]], ["已过期"])

        # 去掉逾期那条，只剩未来的 ⇒ 空集，且仍 source=real
        out2 = run([tasks[1]], reminders=[reminders[1]],
                   window=("2026-11-01", "2026-11-05"))
        self.assertEqual(out2["tasks"], [])
        self.assertEqual(out2["source"], "real")

    def test_empty_table_path(self):
        """库里一条 active 任务都没有 ⇒ 空集早退路径，同样 source=real。"""
        out = run([])
        self.assertEqual(out["tasks"], [])
        self.assertEqual(out["source"], "real")
        self.assertTrue(out["window_applied"])

    def test_empty_set_is_not_an_error(self):
        """空集是正常结果，不是错误：不得出现 error 字段。"""
        out = run([task(name="将来的")],
                  reminders=[{"task_id": "uuid-t1", "due_date": "2027-06-15"}])
        self.assertNotIn("error", out)
        self.assertNotIn("code", out)


# --------------------------------------------------------------------------
# 三、结构：分类可读、数量守恒、窗口标记
# --------------------------------------------------------------------------

class TestPayloadShape(unittest.TestCase):

    def test_window_applied_flag_present(self):
        out = run([task(name="x")], reminders=[{"task_id": "uuid-t1"}])
        self.assertIs(out["window_applied"], True)

    def test_every_task_has_status_and_reason(self):
        out = run([task(tid="uuid-t1", name="A"), task(tid="uuid-t2", name="B")],
                  reminders=[{"task_id": "uuid-t1", "due_date": "2026-10-11"},
                             {"task_id": "uuid-t2", "due_date": "2026-11-15"}])
        for t in out["tasks"]:
            self.assertIn(t["window_status"],
                          (rr.WINDOW_IN, rr.WINDOW_OVERDUE, rr.WINDOW_UNDATED))
            self.assertTrue(t["window_reason"], "每个任务都要有可展示的原因")

    def test_counts_are_conserved(self):
        """三条任务：一条窗口内、一条逾期、一条未来 ⇒ 返回 2 条，排除 1 条。"""
        tasks = [task(tid="uuid-t1", name="A"), task(tid="uuid-t2", name="B"),
                 task(tid="uuid-t3", name="C")]
        reminders = [{"task_id": "uuid-t1", "due_date": "2026-11-15"},
                     {"task_id": "uuid-t2", "due_date": "2026-10-11"},
                     {"task_id": "uuid-t3", "due_date": "2027-06-15"}]
        out = run(tasks, reminders=reminders)
        c = out["window_counts"]
        self.assertEqual(out["task_count"], 2)
        self.assertEqual(c["in_window"], 1)
        self.assertEqual(c["overdue"], 1)
        self.assertEqual(c["excluded_out_of_window"], 1)
        self.assertEqual(out["task_count"] + c["excluded_out_of_window"], len(tasks))


# --------------------------------------------------------------------------
# 四、两个概念不能混：全量基线 vs 窗口输出
# --------------------------------------------------------------------------

class TestBaselineVersusWindow(unittest.TestCase):
    """M0 裁定原文：「保持过去的 5 条任务『账号全量基线核对』与『窗口查询输出』
    两个不同测试概念；2026-11 时间窗口筛完少于 5 条不应被误判为读取失败。」"""

    def test_narrower_window_returns_fewer_but_both_succeed(self):
        tasks = [task(tid="uuid-t1", name="A"), task(tid="uuid-t2", name="B"),
                 task(tid="uuid-t3", name="C")]
        reminders = [{"task_id": "uuid-t1", "due_date": "2026-11-15"},
                     {"task_id": "uuid-t2", "due_date": "2026-11-20"},
                     {"task_id": "uuid-t3", "due_date": "2027-06-15"}]

        wide = run(tasks, reminders=reminders, window=("2026-11-01", "2026-11-30"))
        narrow = run(tasks, reminders=reminders, window=("2026-11-01", "2026-11-16"))

        # 两条都成功，都不是失败
        for out in (wide, narrow):
            self.assertEqual(out["source"], "real")
            self.assertNotIn("error", out)

        # 宽窗口两条、窄窗口一条 —— 差额来自筛选，不是读失败
        self.assertEqual(wide["window_counts"]["in_window"], 2)
        self.assertEqual(narrow["window_counts"]["in_window"], 1)
        self.assertLess(narrow["task_count"], wide["task_count"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
