"""REAL-READ 端到端隔离验证：起一个**本地假 PostgREST**，验证整条链路。

## 这个文件证明什么、不证明什么

**证明**：`app.py` → `real_read.py` → HTTP → 行数据 → 信封 → 调用方
这条链路是通的，字段映射、白名单、信封形状、`source` 标注在真实 HTTP 往返中都成立。

**不证明**：读过 M0 账号的真实数据。真实读取只能由 M0 本人配置短期授权后单独验证
（M0 2026-11-09T14:08 第 2 条原文：「真实账号数据读取只有 M0 本人安全配置短期授权后才能标 PASS」）。
本文件里所有行数据都是**手写构造**的，不是从任何数据库导出的。

## 为什么要端到端而不止单元测试

`test_real_read.py` 用手工注入的假传输，能钉住映射规则，但证明不了
「HTTP 层真的把 `X-Real-Token` 与 JWT 送出去了」「信封真的被包成 `data.tasks`」。
这两处出错的表现都是「接口 200 但字段读不到」，单测抓不到。
"""

import json
import os
import socket
import subprocess
import sys
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.dirname(HERE)
APP = os.path.join(SRC_DIR, "app.py")
MOCK_DIR = os.path.abspath(os.path.join(SRC_DIR, "..", "m1-mock"))

_RELEVANT_ENV = (
    "CHECKD_DEMO_TOKEN", "CHECKD_DEMO_TOKEN_SHA256", "CHECKD_ADMIN_KEY",
    "CHECKD_HEALTH_MINIMAL", "CHECKD_REAL_ENABLED", "CHECKD_REAL_TOKEN",
    "CHECKD_REAL_SUPABASE_URL", "CHECKD_REAL_ANON_KEY", "CHECKD_REAL_JWT",
    "CHECKD_REAL_WINDOW",
)

# --------------------------------------------------------------------------
# 手写构造的行数据（模拟「已同步到 Supabase」的任务，不是真实账号数据）
# --------------------------------------------------------------------------
FIXTURE_TASKS = [
    # 一次性任务：截止是精确时刻，来自 one_time_reminders.due_at
    {"id": "fixture-task-exact", "name": "提交课程设计报告", "type": "one_time",
     "status": "active", "updated_at": "2026-11-09T08:00:00+08:00"},
    # 一次性任务：截止是纯日期，来自 one_time_reminders.due_date
    {"id": "fixture-task-date", "name": "英语六级听力复习", "type": "one_time",
     "status": "active", "updated_at": "2026-11-09T07:00:00+08:00"},
    # 长期任务：→ recurring，时长来自 long_term_tasks
    {"id": "fixture-task-recurring", "name": "线性代数复习", "type": "long_term",
     "status": "active", "updated_at": "2026-11-09T06:00:00+08:00"},
]

FIXTURE_REMINDERS = [
    {"task_id": "fixture-task-exact", "available_from": "2026-11-01",
     "planned_date": None, "due_date": None,
     "due_at": "2026-11-12T18:00:00+08:00"},
    {"task_id": "fixture-task-date", "available_from": "2026-11-01",
     "planned_date": "2026-11-10", "due_date": "2026-11-14", "due_at": None},
]

FIXTURE_LONG_TERM = [
    {"task_id": "fixture-task-recurring", "check_mode": "timer",
     "target_duration_seconds": 3600},
]

FIXTURE_SCHEDULES = [
    {"task_id": "fixture-task-recurring", "schedule_type": "daily",
     "weekdays": [1, 2, 3, 4, 5], "starts_on": "2026-10-20", "ends_on": None},
]

FIXTURE_COURSES = [
    {"id": "fixture-course-1", "name": "离散数学", "status": "active",
     "semester": "2026秋", "updated_at": "2026-11-09T06:00:00+08:00"},
]

FIXTURE_OVERRIDES = [
    {"id": "fixture-override-1", "item_type": "oneTime",
     "item_id": "fixture-task-exact", "local_date": "2026-11-10",
     "action": "skip", "planned_start_minute": None, "planned_end_minute": None},
]

FIXTURE_RULES = [
    {"id": "fixture-rule-1", "course_id": "fixture-course-1", "weekday": 4,
     "week_rule_type": "everyWeek", "start_week": 1, "end_week": 16,
     "interval_weeks": None, "week_numbers": [],
     "starts_at_minute": 480, "ends_at_minute": 580},
]

# 学期锚点。M0 2026-11-10T02:04 在 App「编辑学期」页核到的真实值是
# 大二上学期 / 首周 2026-08-31 / 18 周 / 当前学期 —— 但这里是**构造行**，
# 用的是真实列名，不是他的真实记录。
FIXTURE_SEMESTERS = [
    {"id": "fixture-semester-1", "name": "大二上学期",
     "first_week_start_date": "2026-08-31", "total_weeks": 18,
     "schedule_template_id": "fixture-template-1", "is_current": True,
     "updated_at": "2026-11-09T06:00:00+08:00"},
]

_ROUTE = {
    "tasks": FIXTURE_TASKS,
    "one_time_reminders": FIXTURE_REMINDERS,
    "long_term_tasks": FIXTURE_LONG_TERM,
    "task_schedules": FIXTURE_SCHEDULES,
    "courses": FIXTURE_COURSES,
    "course_schedule_rules": FIXTURE_RULES,
    "daily_item_overrides": FIXTURE_OVERRIDES,
    "semesters": FIXTURE_SEMESTERS,
}


class _FakePostgrest(BaseHTTPRequestHandler):
    """只实现 GET /rest/v1/<table>，按表名返回构造好的行。

    不做真正的过滤（那是 PostgREST 的职责，不是被测代码的职责），
    但把收到的请求记下来，供断言检查「发出去的条件对不对」。
    """
    received = []

    def log_message(self, *a):
        pass

    def do_GET(self):
        path = self.path.split("?")[0]
        table = path.rsplit("/", 1)[-1]
        type(self).received.append({
            "table": table,
            "query": self.path.split("?", 1)[1] if "?" in self.path else "",
            "apikey": self.headers.get("apikey"),
            "authorization": self.headers.get("Authorization"),
        })
        body = json.dumps(_ROUTE.get(table, [])).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def _free_port():
    s = socket.socket()
    try:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]
    finally:
        s.close()


def _wait(port, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return
        except OSError:
            time.sleep(0.1)
    raise RuntimeError("端口 %d 20 秒内没起来" % port)


class _Stack:
    """假 PostgREST + 真 app.py 子进程。"""

    REAL_TOKEN = "e2e-real-token"
    DEMO_TOKEN = "e2e-demo-token"
    JWT = "e2e-user-jwt"
    ANON = "e2e-anon-key"

    def __init__(self):
        self.pg_port = _free_port()
        _FakePostgrest.received = []
        self.pg = ThreadingHTTPServer(("127.0.0.1", self.pg_port), _FakePostgrest)
        self.pg_thread = threading.Thread(target=self.pg.serve_forever, daemon=True)
        self.pg_thread.start()

        self.port = _free_port()
        env = dict(os.environ)
        for k in _RELEVANT_ENV:
            env.pop(k, None)
        env.update({
            "PORT": str(self.port), "BIND": "127.0.0.1",
            "CHECKD_SNAPSHOT_MODE": "off",
            "CHECKD_DEMO_TOKEN": self.DEMO_TOKEN,
            "CHECKD_REAL_ENABLED": "1",
            "CHECKD_REAL_TOKEN": self.REAL_TOKEN,
            "CHECKD_REAL_SUPABASE_URL": "http://127.0.0.1:%d" % self.pg_port,
            "CHECKD_REAL_ANON_KEY": self.ANON,
            "CHECKD_REAL_JWT": self.JWT,
        })
        env["PYTHONPATH"] = os.pathsep.join(
            [MOCK_DIR] + ([env["PYTHONPATH"]] if env.get("PYTHONPATH") else []))
        self.proc = subprocess.Popen(
            [sys.executable, APP], env=env, cwd=SRC_DIR,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        _wait(self.port)

    def call(self, tool, inp=None):
        payload = {
            "api_version": "checkd.agent.v1", "request_id": "e2e-1",
            "timezone": "Asia/Shanghai",
            "input": inp if inp is not None else {
                "date_range": {"start": "2026-11-09", "end": "2026-11-15"}},
        }
        req = urllib.request.Request(
            "http://127.0.0.1:%d/real/tools/%s" % (self.port, tool),
            data=json.dumps(payload).encode(), method="POST",
            headers={"Content-Type": "application/json",
                     "X-Real-Token": self.REAL_TOKEN})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.status, json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read().decode())

    def stop(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        self.pg.shutdown()


class TestEndToEndRead(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.stack = _Stack()

    @classmethod
    def tearDownClass(cls):
        cls.stack.stop()

    def test_list_tasks_returns_constructed_rows_with_real_source(self):
        code, body = self.stack.call("list_tasks")
        self.assertEqual(code, 200, body)
        self.assertEqual(body.get("status"), "success")
        self.assertEqual(body.get("source"), "real")
        self.assertEqual(body.get("data_source"), "supabase")

        data = body["data"]
        self.assertEqual(data["source"], "real")
        self.assertEqual(data["task_count"], 3)
        names = [t["name"] for t in data["tasks"]]
        self.assertIn("提交课程设计报告", names)
        self.assertIn("线性代数复习", names)

    def test_deadline_shape_travels_through_real_http(self):
        """截止时间的两种形态必须一路传到调用方，中途不被抹平。"""
        code, body = self.stack.call("list_tasks")
        by_id = {t["task_id"]: t for t in body["data"]["tasks"]}

        exact = by_id["fixture-task-exact"]["deadline"]
        self.assertEqual(exact, {"kind": "exact", "at": "2026-11-12T18:00:00+08:00"})

        date_only = by_id["fixture-task-date"]["deadline"]
        self.assertEqual(date_only, {"kind": "date_only", "date": "2026-11-14"})
        self.assertNotIn("T", date_only["date"], "纯日期截止不得被补出时刻")

    def test_recurring_kind_and_duration(self):
        code, body = self.stack.call("list_tasks")
        by_id = {t["task_id"]: t for t in body["data"]["tasks"]}
        rec = by_id["fixture-task-recurring"]
        self.assertEqual(rec["kind"], "recurring")
        self.assertEqual(rec["duration_target_seconds"], 3600)
        self.assertEqual(rec["execution_mode"], "timed")
        self.assertEqual(rec["recurrence"]["starts_on"], "2026-10-20")

        # 一次性任务没有时长字段 → null + untimed，不编一个值
        one = by_id["fixture-task-exact"]
        self.assertIsNone(one["duration_target_seconds"])
        self.assertEqual(one["execution_mode"], "untimed")

    def test_upstream_received_user_jwt_and_anon_key(self):
        """真实 HTTP 往返里，凭证必须真的是「anon key + 用户 JWT」。"""
        self.stack.call("list_tasks")
        got = _FakePostgrest.received
        self.assertTrue(got, "上游一次都没被调用，链路断了")
        first = got[0]
        self.assertEqual(first["apikey"], self.stack.ANON)
        self.assertEqual(first["authorization"], "Bearer " + self.stack.JWT)

    def test_no_user_id_condition_sent(self):
        self.stack.call("list_tasks")
        for req in _FakePostgrest.received:
            self.assertNotIn("user_id", req["query"],
                             "%s 的查询带了 user_id 条件，隔离就落到调用方身上了" % req["table"])

    def test_deleted_filter_only_on_tables_that_have_the_column(self):
        """软删除过滤只许加在**真有** `deleted_at` 列的表上。

        `task_schedules` 建表时（migration 202609020001）就没有 `deleted_at`，
        后续 202609100001 只加了 weekdays_mask；这张表的删除靠外键 `on delete cascade` 硬删。
        带 `deleted_at=is.null` 会被 PostgREST 判 400（column does not exist），
        表现是整个 list_tasks 失败。假 PostgREST 不校验列名，所以只有这条断言能守住。
        """
        self.stack.call("list_tasks")
        self.stack.call("get_calendar_events")
        tables_with_soft_delete = {"tasks", "courses", "course_schedule_rules",
                                   "daily_item_overrides", "semesters"}
        seen = {r["table"]: r["query"] for r in _FakePostgrest.received}
        for t, q in seen.items():
            if t in tables_with_soft_delete:
                self.assertIn("deleted_at", q, "%s 没带软删除过滤" % t)
            else:
                self.assertNotIn("deleted_at", q,
                                 "%s 没有 deleted_at 列，不能带这个过滤" % t)

    def test_calendar_events_maps_week_rule_but_does_not_expand(self):
        code, body = self.stack.call("get_calendar_events")
        self.assertEqual(code, 200, body)
        data = body["data"]
        self.assertEqual(len(data["courses"]), 1)
        rule = data["courses"][0]["rules"][0]
        # camelCase → snake_case 的转换必须在真实往返里也成立
        self.assertEqual(rule["week_rule_type"], "every_week")
        self.assertEqual(rule["start_minute"], 480)
        # 周次展开归 M2，本模块不越界
        self.assertEqual(data["events"], [])
        self.assertEqual(data["events_unavailable_reason"],
                         "week_expansion_not_implemented_here")

    def test_daily_overrides_travel_through(self):
        """单日例外必须真的读出来并改名，不能在端到端里丢。"""
        code, body = self.stack.call("get_calendar_events")
        self.assertEqual(code, 200, body)
        ovs = body["data"]["daily_overrides"]
        self.assertEqual(len(ovs), 1)
        self.assertEqual(ovs[0]["item_type"], "one_time")   # oneTime → one_time
        self.assertEqual(ovs[0]["action"], "skip")
        self.assertEqual(ovs[0]["local_date"], "2026-11-10")

    def test_override_query_carries_window_and_soft_delete(self):
        seen = {r["table"]: r["query"] for r in _FakePostgrest.received}
        self.assertIn("daily_item_overrides", seen)
        q = seen["daily_item_overrides"]
        self.assertIn("gte.", q)
        self.assertIn("lte.", q)
        self.assertIn("deleted_at", q)


    def test_payload_has_no_internal_columns(self):
        """白名单在真实往返里也不能漏。"""
        code, body = self.stack.call("list_tasks")
        blob = json.dumps(body, ensure_ascii=False)
        for col in ("user_id", "notes", "color", "teacher", "classroom", "sync_version"):
            self.assertNotIn(col, blob, "响应里出现了非白名单列 %s" % col)


if __name__ == "__main__":
    unittest.main()
