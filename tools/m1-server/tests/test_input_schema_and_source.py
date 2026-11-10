"""M3 2026-11-09T12:56:42Z 报的三条缺陷：schema 声明了没执行 + 载荷无来源标注。

三件一起钉住：

  1. **P1-b** `input` 里塞 `engine:"real"` 被静默接受，返回一份看不出是 MOCK 的成功结果。
     `SCHEMAS` 里明写 `additionalProperties: false`，服务端却从未执行 ——
     声明与实现脱节比不写 schema 更糟：调用方会以为被校验过了。
  2. **P2** `get_approval_status` 传 `proposal_id`（schema 要 `approval_id`）报 `NOT_FOUND`，
     现场调试分不清「参数错」和「状态丢了」。根因同上：没校验就往下传。
  3. **来源标注** M0 2026-11-09T10:51 要求「必须清晰区分 REAL-READ / MOCK-SCHEDULE / REAL-WRITE」，
     而实测载荷里 `mock` 出现 0 次，唯一痕迹是 `approval_url` 的域名 —— 太脆。

真起 HTTP 进程，不 mock。这几条都是传输层行为，mock 掉 Handler 就只测了自己写的 if。

**已知边界（不掩盖）**：当前只校验 `input` 顶层，**不递归**校验嵌套对象
（例如 `date_range` 内部塞未知字段不会被拦）。M3 报的两条都在顶层，已覆盖；
嵌套递归留待后续，本文件末有一条用例把这个边界钉出来，避免以后被误认为"全递归都验了"。
"""

import json
import os
import socket
import subprocess
import sys
import time
import unittest
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.dirname(HERE)
APP = os.path.join(SRC_DIR, "app.py")
MOCK_DIR = os.path.abspath(os.path.join(SRC_DIR, "..", "m1-mock"))

TOKEN = "schema-probe-token-4a1d"

_RELEVANT_ENV = ("CHECKD_DEMO_TOKEN", "CHECKD_DEMO_TOKEN_SHA256",
                 "CHECKD_ADMIN_KEY", "CHECKD_HEALTH_MINIMAL")


def _free_port():
    s = socket.socket()
    try:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]
    finally:
        s.close()


class _Server:
    def __init__(self):
        self.port = _free_port()
        env = dict(os.environ)
        for k in _RELEVANT_ENV:
            env.pop(k, None)
        env.update({"CHECKD_DEMO_TOKEN": TOKEN, "PORT": str(self.port),
                    "BIND": "127.0.0.1", "CHECKD_SNAPSHOT_MODE": "off"})
        env["PYTHONPATH"] = os.pathsep.join(
            [MOCK_DIR] + ([env["PYTHONPATH"]] if env.get("PYTHONPATH") else []))
        self.proc = subprocess.Popen(
            [sys.executable, APP], env=env, cwd=SRC_DIR,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self._wait_ready()

    def _wait_ready(self):
        deadline = time.time() + 20
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError("app.py 启动即退出，exit=%s" % self.proc.returncode)
            try:
                with socket.create_connection(("127.0.0.1", self.port), timeout=0.5):
                    return
            except OSError:
                time.sleep(0.1)
        raise RuntimeError("20 秒内没起来")

    def post(self, tool, input_obj, path=None):
        payload = {"api_version": "checkd.agent.v1",
                   "request_id": "t-schema-1",
                   "timezone": "Asia/Shanghai",
                   "input": input_obj}
        return self.post_raw(payload, path or "/tools/%s" % tool)

    def post_raw(self, payload, path="/tools/list_tasks"):
        req = urllib.request.Request(
            "http://127.0.0.1:%d%s" % (self.port, path),
            data=json.dumps(payload).encode(), method="POST",
            headers={"Content-Type": "application/json", "X-Demo-Token": TOKEN})
        try:
            with urllib.request.urlopen(req, timeout=25) as r:
                return r.status, json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", "replace")
            try:
                return e.code, json.loads(raw)
            except Exception:
                return e.code, {"raw": raw}

    def stop(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.proc.kill()


# 注意：这是 input 的完整形状，不是 date_range 本身。
# SCHEMAS 描述的是 input 这一层（properties 里有 date_range），
# 直接传 {"start":..,"end":..} 会被判成未知字段 start/end —— 这正是校验生效的证据。
DATE_RANGE = {"date_range": {"start": "2026-11-09", "end": "2026-11-09"}}


def _code(body):
    return ((body or {}).get("error") or {}).get("code")


class TestUnknownFieldFailClosed(unittest.TestCase):
    """P1-b：schema 写了 additionalProperties:false，就必须真拦住。"""

    @classmethod
    def setUpClass(cls):
        cls.srv = _Server()

    @classmethod
    def tearDownClass(cls):
        cls.srv.stop()

    def test_engine_real_is_rejected_not_silently_accepted(self):
        """M3 原样复现：input 里塞 engine:"real"。

        改前：200 + success + 一份 MOCK 排程，调用方看不出是假的。
        改后：400 + INVALID_ARGUMENT，且**不产生任何提案**。
        """
        st, body = self.srv.post("generate_schedule",
                                 dict(DATE_RANGE, engine="real"))
        self.assertEqual(st, 400, body)
        self.assertEqual(_code(body), "INVALID_ARGUMENT")
        self.assertNotEqual((body or {}).get("status"), "success",
                            "绝不能把带未知字段的请求当成功返回")
        self.assertNotIn("data", body or {},
                         "被拒的请求不得带 data，否则调用方仍可能读走一份假结果")

    def test_rejection_names_the_offending_field(self):
        """错误要能直接告诉调用方哪个字段不对，不是只回一句 INVALID_ARGUMENT。"""
        _st, body = self.srv.post("generate_schedule",
                                  dict(DATE_RANGE, engine="real"))
        details = (body.get("error") or {}).get("details") or []
        fields = {d.get("field") for d in details if isinstance(d, dict)}
        self.assertIn("engine", fields, details)
        self.assertTrue(all(d.get("reason") == "unknown_field"
                            for d in details if isinstance(d, dict)), details)

    def test_p2_wrong_param_reports_invalid_argument_not_not_found(self):
        """P2：传 proposal_id 给 get_approval_status（schema 要 approval_id）。

        改前报 NOT_FOUND —— 现场看就是「状态丢了」，实际只是参数名写错。
        这条对调试的伤害比它本身严重：会把「我传错参」误诊成「服务丢数据」。
        """
        st, body = self.srv.post("get_approval_status",
                                 {"proposal_id": "prop-whatever"})
        self.assertEqual(st, 400, body)
        self.assertEqual(_code(body), "INVALID_ARGUMENT")
        self.assertNotEqual(_code(body), "NOT_FOUND",
                            "参数错不得伪装成资源不存在")

    def test_missing_required_field_is_invalid_argument(self):
        """缺必填字段也走 INVALID_ARGUMENT，不是 NOT_FOUND。"""
        st, body = self.srv.post("list_tasks", {})
        self.assertEqual(st, 400, body)
        self.assertEqual(_code(body), "INVALID_ARGUMENT")
        details = (body.get("error") or {}).get("details") or []
        self.assertTrue(any(d.get("field") == "date_range" for d in details
                            if isinstance(d, dict)), details)

    def test_valid_input_still_passes(self):
        """回归：合法参数不能被这次收紧误伤。"""
        st, body = self.srv.post("list_tasks", DATE_RANGE)
        self.assertEqual(st, 200, body)
        self.assertEqual(body.get("status"), "success")
        self.assertEqual(len((body.get("data") or {}).get("tasks") or []), 4)


class TestSourceLabel(unittest.TestCase):
    """来源标注：M0 要求三种状态可区分，不能靠猜。"""

    @classmethod
    def setUpClass(cls):
        cls.srv = _Server()

    @classmethod
    def tearDownClass(cls):
        cls.srv.stop()

    def test_success_carries_source_mock(self):
        _st, body = self.srv.post("list_tasks", DATE_RANGE)
        self.assertEqual(body.get("source"), "mock",
                         "顶层必须标出来源；M3 实测载荷里 mock 出现 0 次是缺陷")
        self.assertEqual(body.get("data_source"), "builtin")

    def test_all_seven_tools_carry_source(self):
        """七个工具全带，不是只给 generate_schedule 补。

        ctx：两个审批类工具需要真实 id 才能成功，所以这里允许非 200，
        只断言「只要给了 body 就带 source」——错误响应也要能看出层归属。
        """
        calls = [
            ("list_tasks", DATE_RANGE),
            ("get_calendar_events", DATE_RANGE),
            ("generate_schedule", DATE_RANGE),
            ("validate_schedule", {"proposal_id": "p-x"}),
            ("request_approval", {"proposal_id": "p-x", "idempotency_key": "k"}),
            ("get_approval_status", {"approval_id": "a-x"}),
            ("apply_approved_changes", {"proposal_id": "p-x", "base_version": "b"}),
        ]
        missing = []
        for tool, inp in calls:
            _st, body = self.srv.post(tool, inp)
            if body.get("source") != "mock":
                missing.append((tool, body.get("source")))
        self.assertEqual(missing, [],
                         "以下工具没有 source 标注：%s" % missing)

    def test_source_survives_error_path(self):
        """非法参数也得带 source —— 否则验收方无法判断这条错误来自哪一层。"""
        _st, body = self.srv.post("generate_schedule",
                                  dict(DATE_RANGE, engine="real"))
        self.assertEqual(body.get("source"), "mock")


class TestNestedValidationBoundary(unittest.TestCase):
    """把「只校验顶层、不递归」这个边界钉出来。

    不是想让它一直这样，而是防止以后有人以为"全递归都验了"而漏掉真正的洞。
    哪天补了递归校验，这条会红 —— 那时把它改成断言"嵌套也被拦"即可。
    """

    @classmethod
    def setUpClass(cls):
        cls.srv = _Server()

    @classmethod
    def tearDownClass(cls):
        cls.srv.stop()

    def test_nested_unknown_field_is_currently_not_rejected(self):
        st, body = self.srv.post(
            "list_tasks",
            {"date_range": {"start": "2026-11-09", "end": "2026-11-09",
                            "bogus_nested": 1}})
        # 当前行为：顶层 date_range 合法，嵌套层未知字段放行
        self.assertEqual(st, 200, body)
        self.assertEqual(body.get("status"), "success")


if __name__ == "__main__":
    unittest.main()
