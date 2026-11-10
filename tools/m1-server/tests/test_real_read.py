#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""REAL-READ 适配层的隔离测试。

**这些测试不连接任何真实数据库，不使用任何真实凭证。**
全部靠注入假传输（`FakeTransport`）驱动，因此可以随时跑、反复跑、在干净的 clone 上跑。

这正好对应 M0 2026-11-09T14:08 第 2 条：
「提供可跑的隔离验证，不依赖 M0 的真实凭证也能先跑映射/权限拒绝/错误处理等测试」。

**这些测试通过 ≠ REAL-READ 通过。**
真实账号数据的读取只能由 M0 本人配置短期授权后单独验证，本文件给不出那个结论。
"""

import json
import os
import sys
import unittest
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))

import real_read as rr  # noqa: E402


# --------------------------------------------------------------------------
# 假传输
# --------------------------------------------------------------------------

class FakeTransport:
    """按表名分派响应，并记录每一次请求（url / headers），供断言检查。"""

    def __init__(self, routes):
        self.routes = routes          # {"tasks": (200, [...])} 或 {"tasks": (403, "denied")}
        self.calls = []               # [(table, url, headers)]

    @staticmethod
    def _table_of(url):
        # /rest/v1/tasks?select=…  →  tasks
        path = urllib.parse.urlparse(url).path
        return path.rsplit("/", 1)[-1]

    def __call__(self, url, headers, timeout):
        table = self._table_of(url)
        self.calls.append((table, url, headers))
        status, body = self.routes.get(table, (200, []))
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode("utf-8")
        elif isinstance(body, str):
            body = body.encode("utf-8")
        return status, body

    def tables_called(self):
        return [c[0] for c in self.calls]

    def table_url(self, table):
        for t, url, _ in self.calls:
            if t == table:
                return url
        raise AssertionError("没有请求过表 %s，实际请求：%s" % (table, self.tables_called()))


def reader(routes, jwt="fake-jwt"):
    t = FakeTransport(routes)
    return rr.SupabaseReader("https://example.supabase.co", "anon-key",
                             jwt, transport=t), t


TASK_ROW = {
    "id": "uuid-t1", "name": "完成实验报告", "type": "one_time",
    "status": "active", "updated_at": "2026-10-29T09:00:00+08:00",
}
COURSE_ROW = {
    "id": "uuid-c1", "name": "离散数学", "status": "active",
    "semester": "2026秋", "updated_at": "2026-10-29T09:00:00+08:00",
}


# --------------------------------------------------------------------------
# 一、安全边界：不允许调用方指定用户
# --------------------------------------------------------------------------

class TestNoCallerSuppliedIdentity(unittest.TestCase):
    """M0 2026-11-09T10:51：「必须在服务端实施访问控制，不得仅靠提示方/提示词」。

    实现方式是**根本不提供**这个入口：查询里没有 user_id 条件，靠 RLS 决定。
    如果哪天有人为了「方便调试」加了一个 user_id 参数，这些测试会红。
    """

    def test_query_never_filters_by_user_id(self):
        r, t = reader({"tasks": (200, [TASK_ROW])})
        rr.RealRead(r).list_tasks("2026-11-09", "2026-11-15")
        for table, url, _ in t.calls:
            self.assertNotIn("user_id", url,
                             "%s 的查询带上了 user_id 条件，隔离就变成调用方自觉了" % table)

    def test_public_api_takes_no_user_argument(self):
        import inspect
        sig = inspect.signature(rr.RealRead.list_tasks)
        self.assertNotIn("user_id", sig.parameters)
        self.assertNotIn("user", sig.parameters)
        sig2 = inspect.signature(rr.RealRead.get_calendar_events)
        self.assertNotIn("user_id", sig2.parameters)


# --------------------------------------------------------------------------
# 二、最小字段白名单
# --------------------------------------------------------------------------

class TestColumnWhitelist(unittest.TestCase):
    """M0 要求「最小字段白名单」。这里同时钉住「用了什么」和「没用什么」。"""

    def test_tasks_select_is_explicit_not_star(self):
        r, t = reader({"tasks": (200, [TASK_ROW])})
        rr.RealRead(r).list_tasks("2026-11-09", "2026-11-15")
        url = t.table_url("tasks")
        self.assertNotIn("select=*", url)
        self.assertNotIn("%2A", url, "select 里出现了通配符 *")
        self.assertIn("select=id", url)

    def test_sensitive_columns_never_requested(self):
        r, t = reader({"tasks": (200, [TASK_ROW]),
                       "courses": (200, [COURSE_ROW])})
        rr.RealRead(r).list_tasks("2026-11-09", "2026-11-15")
        rr.RealRead(r).get_calendar_events("2026-11-09", "2026-11-15")
        joined = " ".join(u for _, u, _ in t.calls)
        for col in ("notes", "teacher", "classroom", "color", "user_id"):
            self.assertNotIn(col, joined,
                             "白名单里不该出现 %s，它对本功能无用且属个人数据" % col)

    def test_deleted_rows_are_excluded(self):
        r, t = reader({"tasks": (200, [])})
        rr.RealRead(r).list_tasks("2026-11-09", "2026-11-15")
        self.assertIn("deleted_at", t.table_url("tasks"))
        self.assertIn("is.null", t.table_url("tasks"))


# --------------------------------------------------------------------------
# 三、凭证怎么用（用户级 JWT，不是 service_role）
# --------------------------------------------------------------------------

class TestCredentialUse(unittest.TestCase):
    def test_uses_anon_key_as_apikey_and_jwt_as_bearer(self):
        r, t = reader({"tasks": (200, [])}, jwt="user-jwt-abc")
        rr.RealRead(r).list_tasks("2026-11-09", "2026-11-15")
        _, _, headers = t.calls[0]
        self.assertEqual(headers["apikey"], "anon-key")
        self.assertEqual(headers["Authorization"], "Bearer user-jwt-abc")

    def test_missing_token_is_auth_required_not_503(self):
        """令牌过期是运行态常见事件，报 503 会被误判成服务挂了。"""
        with self.assertRaises(rr.RealReadError) as ctx:
            rr.SupabaseReader("https://example.supabase.co", "anon-key", "")
        self.assertEqual(ctx.exception.code, "AUTH_REQUIRED")


# --------------------------------------------------------------------------
# 四、错误映射（权限拒绝 / 上游故障 / 结构异常）
# --------------------------------------------------------------------------

class TestErrorMapping(unittest.TestCase):
    def test_401_is_auth_required(self):
        r, _ = reader({"tasks": (401, "expired")})
        with self.assertRaises(rr.RealReadError) as ctx:
            rr.RealRead(r).list_tasks("2026-11-09", "2026-11-15")
        self.assertEqual(ctx.exception.code, "AUTH_REQUIRED")

    def test_403_is_forbidden(self):
        r, _ = reader({"tasks": (403, "rls denied")})
        with self.assertRaises(rr.RealReadError) as ctx:
            rr.RealRead(r).list_tasks("2026-11-09", "2026-11-15")
        self.assertEqual(ctx.exception.code, "FORBIDDEN")

    def test_500_is_dependency_unavailable(self):
        r, _ = reader({"tasks": (500, "boom")})
        with self.assertRaises(rr.RealReadError) as ctx:
            rr.RealRead(r).list_tasks("2026-11-09", "2026-11-15")
        self.assertEqual(ctx.exception.code, "DEPENDENCY_UNAVAILABLE")

    def test_non_json_body_is_internal_error(self):
        r, _ = reader({"tasks": (200, "<html>gateway</html>")})
        with self.assertRaises(rr.RealReadError) as ctx:
            rr.RealRead(r).list_tasks("2026-11-09", "2026-11-15")
        self.assertEqual(ctx.exception.code, "INTERNAL_ERROR")

    def test_all_codes_stay_inside_contract_closure(self):
        """契约 §4.1 是 21 码闭集，本模块不得新增码。"""
        sys.path.insert(0, os.path.join(HERE, ".."))
        import errors
        allowed = set(errors.HTTP_BY_CODE)
        for code in ("AUTH_REQUIRED", "FORBIDDEN", "DEPENDENCY_UNAVAILABLE",
                     "INTERNAL_ERROR", "INVALID_ARGUMENT"):
            self.assertIn(code, allowed)


# --------------------------------------------------------------------------
# 五、空集不回落 MOCK（红线）
# --------------------------------------------------------------------------

class TestEmptyIsEmpty(unittest.TestCase):
    """M0 2026-11-09T14:08 第 3 条 / M3 红线建议第 4 条。

    这是最容易被「善意」破坏的一条：没数据就换一批假的顶上，看起来功能正常，
    而且验收方几乎不可能发现。所以单独一组，且断言得比其它组更死。
    """

    def test_zero_tasks_returns_zero_and_marks_real(self):
        r, _ = reader({"tasks": (200, [])})
        out = rr.RealRead(r).list_tasks("2026-11-09", "2026-11-15")
        self.assertEqual(out["tasks"], [])
        self.assertEqual(out["task_count"], 0)
        self.assertEqual(out["source"], "real")
        # 任何 MOCK 痕迹都不许出现
        blob = json.dumps(out, ensure_ascii=False)
        self.assertNotIn("t_1001", blob)
        self.assertNotIn("完成实验报告", blob)
        self.assertNotIn("mock", blob.lower())

    def test_zero_tasks_skips_child_queries(self):
        """空集时不再发三张子表请求：既是省往返，也是「空就是空」写死在最前面。"""
        r, t = reader({"tasks": (200, [])})
        rr.RealRead(r).list_tasks("2026-11-09", "2026-11-15")
        self.assertEqual(t.tables_called(), ["tasks"])

    def test_zero_courses_returns_zero(self):
        r, _ = reader({"courses": (200, [])})
        out = rr.RealRead(r).get_calendar_events("2026-11-09", "2026-11-15")
        self.assertEqual(out["courses"], [])
        self.assertEqual(out["source"], "real")
        self.assertNotIn("c_2001", json.dumps(out, ensure_ascii=False))


# --------------------------------------------------------------------------
# 六、字段映射（含最容易错的两处）
# --------------------------------------------------------------------------

class TestDeadlineMapping(unittest.TestCase):
    """`due_date` / `due_at` 在 `one_time_reminders` 上，不在 `tasks` 上。

    写错位置的表现是「截止时间永远为空」，不报错，所以单独钉。
    """

    def _tasks(self, reminder):
        r, _ = reader({
            "tasks": (200, [TASK_ROW]),
            "one_time_reminders": (200, [dict({"task_id": "uuid-t1"}, **reminder)]),
        })
        return rr.RealRead(r).list_tasks("2026-11-09", "2026-11-15")

    def test_due_at_becomes_exact(self):
        out = self._tasks({"due_at": "2026-10-31T18:00:00+08:00"})
        self.assertEqual(out["tasks"][0]["deadline"],
                         {"kind": "exact", "at": "2026-10-31T18:00:00+08:00"})

    def test_due_date_stays_date_only_without_synthetic_time(self):
        """migration 202609150001 原文：no synthetic end-of-day time。"""
        out = self._tasks({"due_date": "2026-11-02"})
        d = out["tasks"][0]["deadline"]
        self.assertEqual(d, {"kind": "date_only", "date": "2026-11-02"})
        self.assertNotIn("T", json.dumps(d), "不得补出 23:59:59 之类的时间")

    def test_no_deadline_is_none_not_absent(self):
        out = self._tasks({})
        self.assertEqual(out["tasks"][0]["deadline"], {"kind": "none"})

    def test_both_present_prefers_due_at_and_warns(self):
        """库约束是 not valid 加的，历史行仍可能两列都有；不静默择一。"""
        out = self._tasks({"due_date": "2026-11-02",
                           "due_at": "2026-11-03T09:00:00+08:00"})
        self.assertEqual(out["tasks"][0]["deadline"]["kind"], "exact")
        self.assertIn("warnings", out)
        self.assertIn("due_date", out["warnings"][0]["note"])

    def test_available_from_and_planned_date_carried(self):
        out = self._tasks({"available_from": "2026-10-29",
                           "planned_date": "2026-10-30"})
        task = out["tasks"][0]
        self.assertEqual(task["available_from"], "2026-10-29")
        self.assertEqual(task["planned_date"], "2026-10-30")


class TestKindAndDuration(unittest.TestCase):
    def test_long_term_maps_to_recurring(self):
        r, _ = reader({"tasks": (200, [dict(TASK_ROW, type="long_term")]),
                       "task_schedules": (200, [{
                           "task_id": "uuid-t1", "schedule_type": "daily",
                           "weekdays": [1, 2, 3], "starts_on": "2026-10-20",
                           "ends_on": None}])})
        out = rr.RealRead(r).list_tasks("2026-11-09", "2026-11-15")
        self.assertEqual(out["tasks"][0]["kind"], "recurring")
        self.assertEqual(out["tasks"][0]["recurrence"]["starts_on"], "2026-10-20")

    def test_missing_duration_is_null_and_untimed_not_invented(self):
        """真实 schema 没有「一次性任务预计耗时」字段。字段不存在就不假造。"""
        r, _ = reader({"tasks": (200, [TASK_ROW]), "long_term_tasks": (200, [])})
        out = rr.RealRead(r).list_tasks("2026-11-09", "2026-11-15")
        task = out["tasks"][0]
        self.assertIsNone(task["duration_target_seconds"])
        self.assertEqual(task["execution_mode"], "untimed")

    def test_kind_filter_applies(self):
        r, _ = reader({"tasks": (200, [TASK_ROW])})
        out = rr.RealRead(r).list_tasks("2026-11-09", "2026-11-15",
                                        kinds=["recurring"])
        self.assertEqual(out["tasks"], [])


class TestWeekRuleMapping(unittest.TestCase):
    """真实库是 camelCase（everyWeek），MOCK 是 snake_case（every_week）。"""

    def _rules(self, week_rule_type):
        r, _ = reader({
            "courses": (200, [COURSE_ROW]),
            "course_schedule_rules": (200, [{
                "id": "uuid-r1", "course_id": "uuid-c1", "weekday": 4,
                "week_rule_type": week_rule_type, "start_week": 1, "end_week": 16,
                "interval_weeks": None, "week_numbers": [],
                "starts_at_minute": 480, "ends_at_minute": 580}]),
        })
        return rr.RealRead(r).get_calendar_events("2026-11-09", "2026-11-15")

    def test_camel_to_snake(self):
        for db, expect in [("everyWeek", "every_week"), ("oddWeeks", "odd_weeks"),
                           ("evenWeeks", "even_weeks"),
                           ("everyNWeeks", "every_n_weeks"), ("custom", "custom")]:
            out = self._rules(db)
            self.assertEqual(out["courses"][0]["rules"][0]["week_rule_type"], expect)

    def test_unknown_week_rule_refuses_to_guess(self):
        with self.assertRaises(rr.RealReadError) as ctx:
            self._rules("biWeeklyFromNowOn")
        self.assertEqual(ctx.exception.code, "INTERNAL_ERROR")
        self.assertIn("week_rule_type", json.dumps(ctx.exception.details))

    def test_minute_fields_renamed_not_reinterpreted(self):
        out = self._rules("everyWeek")
        rule = out["courses"][0]["rules"][0]
        self.assertEqual(rule["start_minute"], 480)
        self.assertEqual(rule["end_minute"], 580)


# --------------------------------------------------------------------------
# 七、来源与新鲜度标注
# --------------------------------------------------------------------------

class TestProvenance(unittest.TestCase):
    def test_payload_carries_source_as_of_and_window(self):
        r, _ = reader({"tasks": (200, [TASK_ROW])})
        out = rr.RealRead(r).list_tasks("2026-11-09", "2026-11-15")
        self.assertEqual(out["source"], "real")
        self.assertIn("as_of", out)
        self.assertEqual(out["data_window"], {"start": "2026-11-09",
                                              "end": "2026-11-15"})
        self.assertTrue(out["as_of"].endswith("+00:00"),
                        "as_of 必须是带时区的时刻，否则无法判断证据是否过期")

    def test_events_not_fabricated(self):
        """周次展开不在本模块，events 必须空且给出原因，不能拿规则凑。"""
        r, _ = reader({"courses": (200, [COURSE_ROW]),
                       "course_schedule_rules": (200, [])})
        out = rr.RealRead(r).get_calendar_events("2026-11-09", "2026-11-15")
        self.assertEqual(out["events"], [])
        self.assertEqual(out["events_unavailable_reason"],
                         "week_expansion_not_implemented_here")



class TestDailyOverrides(unittest.TestCase):
    """单日例外（临时停课/调课）。

    真实表 `daily_item_overrides`，`item_type` 库里是 `oneTime`。
    早先 `get_calendar_events` 是「先查 courses，空了就 return」——
    一个没录课程、只给任务设了例外的用户，例外会被整片丢掉。
    """

    ROWS = [
        {"id": "ov-1", "item_type": "oneTime", "item_id": "uuid-t1",
         "local_date": "2026-11-10", "action": "skip",
         "planned_start_minute": None, "planned_end_minute": None},
        {"id": "ov-2", "item_type": "course", "item_id": "uuid-c1",
         "local_date": "2026-11-11", "action": "reschedule",
         "planned_start_minute": 600, "planned_end_minute": 700},
    ]

    def test_overrides_are_returned_and_renamed(self):
        r, _ = reader({"courses": (200, [COURSE_ROW]),
                       "daily_item_overrides": (200, self.ROWS)})
        out = rr.RealRead(r).get_calendar_events("2026-11-09", "2026-11-15")
        self.assertEqual(len(out["daily_overrides"]), 2)
        first = out["daily_overrides"][0]
        self.assertEqual(first["override_id"], "ov-1")
        # oneTime → one_time，与 week_rule_type 同一类转换
        self.assertEqual(first["item_type"], "one_time")
        self.assertEqual(first["action"], "skip")
        self.assertEqual(out["daily_overrides"][1]["item_type"], "course")

    def test_overrides_read_even_without_courses(self):
        """没有课程也必须读例外。这是之前会被短路漏掉的场景。"""
        r, t = reader({"courses": (200, []),
                       "daily_item_overrides": (200, self.ROWS)})
        out = rr.RealRead(r).get_calendar_events("2026-11-09", "2026-11-15")
        self.assertEqual(out["courses"], [])
        self.assertEqual(len(out["daily_overrides"]), 2)
        self.assertIn("daily_item_overrides", t.tables_called())

    def test_overrides_filtered_by_window(self):
        """按 local_date 过滤，不把整张历史拉下来。"""
        r, t = reader({"courses": (200, []),
                       "daily_item_overrides": (200, [])})
        rr.RealRead(r).get_calendar_events("2026-11-09", "2026-11-15")
        url = t.table_url("daily_item_overrides")
        self.assertIn("gte.2026-11-09", url)
        self.assertIn("lte.2026-11-15", url)
        self.assertIn("deleted_at", url)

    def test_unknown_item_type_refuses_to_guess(self):
        r, _ = reader({"courses": (200, []),
                       "daily_item_overrides": (200, [dict(
                           self.ROWS[0], item_type="someFutureType")])})
        with self.assertRaises(rr.RealReadError) as ctx:
            rr.RealRead(r).get_calendar_events("2026-11-09", "2026-11-15")
        self.assertEqual(ctx.exception.code, "INTERNAL_ERROR")
        self.assertIn("item_type", json.dumps(ctx.exception.details))

    def test_no_private_columns_requested(self):
        r, t = reader({"courses": (200, []),
                       "daily_item_overrides": (200, [])})
        rr.RealRead(r).get_calendar_events("2026-11-09", "2026-11-15")
        url = t.table_url("daily_item_overrides")
        for col in ("notes", "temporary_classroom", "reminder_minute_of_day",
                    "target_duration_seconds", "user_id"):
            self.assertNotIn(col, url, "单日例外查询里出现了非白名单列 %s" % col)


class TestSemesterAnchor(unittest.TestCase):
    """学期锚点：M2 的周次展开要「第一周是哪天」，由本层读出来送进去。

    M0 2026-11-10T02:04 的原话：学期首周日期在 App 里本来就有（大二上学期 /
    2026-08-31 / 18 周 / 已设为当前学期），所以「缺失」只能是读取链路没闭合。
    他的硬要求：不可写死、不可凭当前星期猜、缺记录或当前学期不确定时必须 fail-closed 上报。

    这三条测试就是「不许猜」的可执行版本。
    """

    SEM_OK = {"id": "uuid-s1", "name": "大二上学期",
              "first_week_start_date": "2026-08-31", "total_weeks": 18,
              "schedule_template_id": "uuid-tpl", "is_current": True,
              "updated_at": "2026-11-09T06:00:00+08:00"}

    def _cal(self, semesters):
        r, _ = reader({"courses": (200, []), "semesters": (200, semesters)})
        return rr.RealRead(r).get_calendar_events("2026-11-09", "2026-11-15")

    def test_current_semester_anchor_is_passed_through_verbatim(self):
        out = self._cal([self.SEM_OK])
        self.assertEqual(out["semester_blocked"], [])
        self.assertEqual(len(out["semesters"]), 1)
        sem = out["semesters"][0]
        # 原样透传：不补时间、不按当前日期推算、不换成「第几周」
        self.assertEqual(sem["first_week_start_date"], "2026-08-31")
        self.assertEqual(sem["total_weeks"], 18)
        self.assertTrue(sem["is_current"])
        self.assertEqual(sem["semester_id"], "uuid-s1")

    def test_no_semester_row_is_reported_not_guessed(self):
        out = self._cal([])
        self.assertEqual(out["semesters"], [])
        codes = [b["code"] for b in out["semester_blocked"]]
        self.assertEqual(codes, ["MISSING_SEMESTER_ANCHOR"])
        self.assertEqual(out["semester_blocked"][0]["basis"]["rows"], 0)

    def test_rows_but_no_current_is_reported(self):
        """有学期记录但没标当前：**不许**拿 updated_at 最新的那条顶上。

        猜错的后果是整学期课表错位，比不给更糟。
        """
        older = dict(self.SEM_OK, id="uuid-s2", is_current=False)
        newer = dict(self.SEM_OK, id="uuid-s1", is_current=False)
        out = self._cal([newer, older])
        self.assertEqual(len(out["semesters"]), 2, "全部学期都应该原样给出")
        self.assertEqual([b["code"] for b in out["semester_blocked"]],
                         ["MISSING_SEMESTER_ANCHOR"])
        self.assertEqual(out["semester_blocked"][0]["basis"]["current_rows"], 0)

    def test_multiple_current_is_reported(self):
        a = dict(self.SEM_OK, id="uuid-sa")
        b = dict(self.SEM_OK, id="uuid-sb")
        out = self._cal([a, b])
        self.assertEqual([x["code"] for x in out["semester_blocked"]],
                         ["MULTIPLE_CURRENT_SEMESTERS"])
        self.assertEqual(out["semester_blocked"][0]["basis"]["current_rows"], 2)

    def test_semester_query_uses_only_whitelisted_columns(self):
        r, t = reader({"courses": (200, []), "semesters": (200, [self.SEM_OK])})
        rr.RealRead(r).get_calendar_events("2026-11-09", "2026-11-15")
        url = t.table_url("semesters")
        self.assertIn("deleted_at=is.null", url)
        for col in ("notes", "user_id"):
            self.assertNotIn(col, url, "学期查询里出现了非白名单列 %s" % col)


if __name__ == "__main__":
    unittest.main()
