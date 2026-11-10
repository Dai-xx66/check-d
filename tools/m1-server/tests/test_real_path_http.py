"""REAL-READ 路径的传输层测试（真起 HTTP 进程，不 mock）。

**不连接真实 Supabase，不使用任何真实凭证。** 七个用例组：

  1. **未启用 / 未配置口令 → 503 fail-closed**，不回落到 MOCK
  2. **反向隔离**：`X-Demo-Token` 开不了 REAL，`X-Real-Token` 也开不了 MOCK
  3. **REAL 只暴露两个只读工具**，其余工具不出现在 tools/list
  4. **真实数据源不可达时 503 且响应里没有任何 MOCK 痕迹**（红线：不回落）
  5. **现网 `/mcp` 与 `/tools/*` 行为零变化**（回归，M0 要求不改已部署 MOCK）
  6. **serverInfo 能区分两条路径**
  7. **演示窗口配置非法时拒绝，而不是放行**

第 4 组是这份文件存在的主要理由：把「没数据/连不上就换假数据顶上」
这类好意变成一条会红的测试。
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

_RELEVANT_ENV = (
    "CHECKD_DEMO_TOKEN", "CHECKD_DEMO_TOKEN_SHA256", "CHECKD_ADMIN_KEY",
    "CHECKD_HEALTH_MINIMAL", "CHECKD_REAL_ENABLED", "CHECKD_REAL_TOKEN",
    "CHECKD_REAL_SUPABASE_URL", "CHECKD_REAL_ANON_KEY", "CHECKD_REAL_JWT",
    "CHECKD_REAL_WINDOW",
)

_OMITTED = object()

# 故意指向一个必然连不上的地址，用来验证「真实源不可用时不回落 MOCK」。
# 127.0.0.1:1 是保留端口，正常环境不会有服务在听。
DEAD_URL = "http://127.0.0.1:1"


def _free_port():
    s = socket.socket()
    try:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]
    finally:
        s.close()


class _Server:
    def __init__(self, **env_extra):
        self.port = _free_port()
        env = dict(os.environ)
        for k in _RELEVANT_ENV:
            env.pop(k, None)
        env.update({"PORT": str(self.port), "BIND": "127.0.0.1",
                    "CHECKD_SNAPSHOT_MODE": "off"})
        env["PYTHONPATH"] = os.pathsep.join(
            [MOCK_DIR] + ([env["PYTHONPATH"]] if env.get("PYTHONPATH") else []))
        env.update(env_extra)
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
        raise RuntimeError("20 秒内没起来（port=%d）" % self.port)

    def _post(self, path, payload, headers):
        req = urllib.request.Request(
            "http://127.0.0.1:%d%s" % (self.port, path),
            data=json.dumps(payload).encode(), method="POST", headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=25) as r:
                return r.status, json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", "replace")
            try:
                return e.code, json.loads(raw)
            except Exception:
                return e.code, {"raw": raw}

    def real(self, path="/real/tools/list_tasks", real_token=_OMITTED,
             demo_token=_OMITTED, inp=None):
        payload = {
            "api_version": "checkd.agent.v1", "request_id": "t-real-1",
            "timezone": "Asia/Shanghai",
            "input": inp if inp is not None else {
                "date_range": {"start": "2026-11-09", "end": "2026-11-09"}},
        }
        headers = {"Content-Type": "application/json"}
        if real_token is not _OMITTED:
            headers["X-Real-Token"] = real_token
        if demo_token is not _OMITTED:
            headers["X-Demo-Token"] = demo_token
        return self._post(path, payload, headers)

    def mock(self, path="/tools/list_tasks", demo_token=_OMITTED,
             real_token=_OMITTED):
        payload = {
            "api_version": "checkd.agent.v1", "request_id": "t-mock-1",
            "timezone": "Asia/Shanghai",
            "input": {"date_range": {"start": "2026-11-09", "end": "2026-11-09"}},
        }
        headers = {"Content-Type": "application/json"}
        if demo_token is not _OMITTED:
            headers["X-Demo-Token"] = demo_token
        if real_token is not _OMITTED:
            headers["X-Real-Token"] = real_token
        return self._post(path, payload, headers)

    def mcp(self, path, rpc, headers=None):
        return self._post(path, rpc,
                          dict({"Content-Type": "application/json"}, **(headers or {})))

    def stop(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.proc.kill()


def _err(resp):
    body = resp[1] if isinstance(resp, tuple) else resp
    return (body.get("error") or {}).get("code")


class TestRealDisabled(unittest.TestCase):
    """默认关。没开就不给任何入口，且**不能悄悄改走 MOCK**。"""

    @classmethod
    def setUpClass(cls):
        # 故意把 MOCK 侧配置齐：这样若 REAL 悄悄回落到 MOCK，请求会 200 成功，
        # 测试才会红。只配 REAL_TOKEN 而 MOCK 也空的话，503 可能来自别的原因。
        cls.s = _Server(CHECKD_DEMO_TOKEN="demo-tok",
                        CHECKD_REAL_TOKEN="real-tok")

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()

    def test_mcp_path_503(self):
        code, body = self.s.real("/real/mcp", real_token="real-tok")
        self.assertEqual(code, 503)
        self.assertEqual(_err((code, body)), "DEPENDENCY_UNAVAILABLE")

    def test_tools_path_503(self):
        code, body = self.s.real(real_token="real-tok")
        self.assertEqual(code, 503)
        self.assertEqual(_err((code, body)), "DEPENDENCY_UNAVAILABLE")

    def test_does_not_fall_back_to_mock_on_disabled(self):
        """关掉了就是关掉了，不接受「反正 MOCK 有数据，先给一份」。"""
        code, body = self.s.real(real_token="real-tok")
        self.assertNotEqual(code, 200)
        self.assertNotIn("tasks", body)
        self.assertNotIn("t_1001", json.dumps(body, ensure_ascii=False))


class TestRealEnabledWithoutToken(unittest.TestCase):
    """开了开关但没配口令 → 仍然拒绝。这是「开了就必须真」的同一条原则。"""

    @classmethod
    def setUpClass(cls):
        cls.s = _Server(CHECKD_DEMO_TOKEN="demo-tok",
                        CHECKD_REAL_ENABLED="1")

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()

    def test_missing_config_is_503(self):
        code, body = self.s.real(real_token="anything")
        self.assertEqual(code, 503)
        self.assertEqual(_err((code, body)), "DEPENDENCY_UNAVAILABLE")


class TestReverseIsolation(unittest.TestCase):
    """**本文件里最关键的一组。**

    MOCK 的口令 2026-11-08 已写进邮件、进过交付件、在多人手里。
    如果它也能开 REAL，「两套凭证隔离」就只是命名上的区别。
    两个方向都要钉住，只测一个方向不够。
    """

    DEMO = "demo-token-shared-with-everyone"
    REAL = "real-token-kept-in-env-only"

    @classmethod
    def setUpClass(cls):
        cls.s = _Server(CHECKD_DEMO_TOKEN=cls.DEMO,
                        CHECKD_REAL_ENABLED="1",
                        CHECKD_REAL_TOKEN=cls.REAL,
                        CHECKD_REAL_SUPABASE_URL=DEAD_URL,
                        CHECKD_REAL_ANON_KEY="anon",
                        CHECKD_REAL_JWT="jwt")

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()

    def test_demo_token_cannot_open_real(self):
        code, body = self.s.real(demo_token=self.DEMO)
        self.assertEqual(code, 401, "X-Demo-Token 开得了 REAL = 隔离失效")
        self.assertEqual(_err((code, body)), "AUTH_REQUIRED")
        self.assertEqual(((body.get("error") or {}).get("details") or [{}])[0]
                         .get("field"), "X-Real-Token")

    def test_real_token_cannot_open_mock(self):
        code, body = self.s.mock(real_token=self.REAL)
        self.assertEqual(code, 401, "X-Real-Token 开得了 MOCK，两条路径就没分开")
        self.assertEqual(_err((code, body)), "APPROVAL_UNTRUSTED")

    def test_both_tokens_mock_path_still_uses_demo_only(self):
        """两个口令同时带时，MOCK 路径仍然只认 `X-Demo-Token`。

        这是「反向隔离」最容易漏的一种情形：单独带错头会被拒，
        但「带了正确口令的同时夹带另一个」，如果鉴权是「任一头对就放行」，隔离就形同虚设。
        """
        code, body = self.s.mock(demo_token="wrong-demo", real_token=self.REAL)
        self.assertEqual(code, 401, "MOCK 认了 X-Real-Token = 隔离失效")
        self.assertEqual(_err((code, body)), "APPROVAL_UNTRUSTED")

    def test_both_tokens_real_path_still_uses_real_only(self):
        """反向：REAL 路径只认 `X-Real-Token`，夹带 `X-Demo-Token` 不影响判定。

        断言「不是 401/403」而不是某个具体状态码：鉴权通过之后会走到数据源配置检查，
        那一步的结果取决于本用例的 env，与本条要钉的东西无关。
        """
        code, body = self.s.real(real_token=self.REAL, demo_token=self.DEMO)
        self.assertNotIn(code, (401, 403),
                         "两个头都带时 REAL 拒了正确口令，说明鉴权看错了头")
        self.assertNotEqual(_err((code, body)), "AUTH_REQUIRED")

    def test_wrong_real_token_is_403_not_401(self):
        code, body = self.s.real(real_token="guess")
        self.assertEqual(code, 403)
        self.assertEqual(_err((code, body)), "FORBIDDEN")

    def test_absent_real_token_is_401(self):
        code, body = self.s.real()
        self.assertEqual(code, 401)
        self.assertEqual(_err((code, body)), "AUTH_REQUIRED")


class TestNoFallbackToMock(unittest.TestCase):
    """真实数据源不可达时，必须报错，**不许拿 MOCK 的 4 条任务顶上**。

    M0 2026-11-09T14:08 第 3 条：「不允许 engine:real 静默回落 MOCK」。
    这条最难靠人工评审发现：回落之后接口是 200、数据看起来完全正常。
    """

    TOKEN = "real-token-x"

    @classmethod
    def setUpClass(cls):
        cls.s = _Server(CHECKD_DEMO_TOKEN="demo-tok",
                        CHECKD_REAL_ENABLED="1", CHECKD_REAL_TOKEN=cls.TOKEN,
                        CHECKD_REAL_SUPABASE_URL=DEAD_URL,
                        CHECKD_REAL_ANON_KEY="anon", CHECKD_REAL_JWT="jwt")

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()

    def test_unreachable_source_is_503_without_mock_payload(self):
        code, body = self.s.real(real_token=self.TOKEN)
        self.assertEqual(code, 503)
        self.assertEqual(_err((code, body)), "DEPENDENCY_UNAVAILABLE")

        blob = json.dumps(body, ensure_ascii=False)
        # 任何一条内置 MOCK 任务出现，就说明回落了
        for marker in ("t_1001", "t_1002", "完成实验报告", "背单词", "c_2001"):
            self.assertNotIn(marker, blob, "响应里出现 MOCK 数据 %s，说明发生了回落" % marker)
        self.assertNotIn("tasks", body)
        # 错误也标 real：验收方才能判断失败来自哪一层
        self.assertEqual(body.get("source"), "real")

    def test_unreachable_source_via_mcp_is_error_not_success(self):
        code, body = self.s.mcp("/real/mcp", {
            "jsonrpc": "2.0", "id": 9, "method": "tools/call",
            "params": {"name": "list_tasks",
                       "arguments": {"api_version": "checkd.agent.v1",
                                     "request_id": "r1",
                                     "timezone": "Asia/Shanghai",
                                     "input": {"date_range": {
                                         "start": "2026-11-09",
                                         "end": "2026-11-09"}}}},
        }, {"X-Real-Token": self.TOKEN})
        self.assertEqual(code, 200)          # JSON-RPC 层是 200
        res = body.get("result") or {}
        self.assertTrue(res.get("isError"), "上游失败时 isError 必须为真")
        sc = res.get("structuredContent") or {}
        self.assertNotIn("tasks", sc)


class TestRealToolSurface(unittest.TestCase):
    """REAL 侧只有两个只读工具。其余五个「看不到」，而不是「看得到但报错」。"""

    TOKEN = "real-token-y"

    @classmethod
    def setUpClass(cls):
        cls.s = _Server(CHECKD_DEMO_TOKEN="demo-tok",
                        CHECKD_REAL_ENABLED="1", CHECKD_REAL_TOKEN=cls.TOKEN,
                        CHECKD_REAL_SUPABASE_URL=DEAD_URL,
                        CHECKD_REAL_ANON_KEY="anon", CHECKD_REAL_JWT="jwt")

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()

    def _tools(self, path):
        code, body = self.s.mcp(path, {
            "jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}},
            {"X-Real-Token": self.TOKEN, "X-Demo-Token": "demo-tok"})
        self.assertEqual(code, 200)
        return [t["name"] for t in (body.get("result") or {}).get("tools") or []]

    def test_real_lists_only_two_readonly_tools(self):
        names = self._tools("/real/mcp")
        self.assertEqual(sorted(names), ["get_calendar_events", "list_tasks"])

    def test_real_descriptions_are_marked(self):
        code, body = self.s.mcp("/real/mcp", {
            "jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}},
            {"X-Real-Token": self.TOKEN})
        tools = (body.get("result") or {}).get("tools") or []
        for t in tools:
            self.assertTrue(t["description"].startswith("[REAL]"),
                            "描述没标 [REAL]，模型无法区分同名工具的两个版本")

    def test_write_tools_absent_from_real_list(self):
        names = self._tools("/real/mcp")
        for forbidden in ("generate_schedule", "validate_schedule",
                          "request_approval", "get_approval_status",
                          "apply_approved_changes"):
            self.assertNotIn(forbidden, names)

    def test_calling_write_tool_over_real_is_refused(self):
        code, body = self.s.mcp("/real/mcp", {
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": {"name": "generate_schedule", "arguments": {}}},
            {"X-Real-Token": self.TOKEN})
        self.assertEqual(code, 200)
        self.assertIn("error", body, "REAL 上不该能调写工具")
        self.assertIn("REAL", body["error"]["message"])

    def test_rest_style_path_refuses_unknown_tool(self):
        code, body = self.s.real("/real/tools/generate_schedule",
                                 real_token=self.TOKEN)
        self.assertEqual(code, 404)
        self.assertEqual(_err((code, body)), "NOT_FOUND")

    def test_server_info_distinguishes_paths(self):
        code, body = self.s.mcp("/real/mcp", {
            "jsonrpc": "2.0", "id": 3, "method": "initialize",
            "params": {"protocolVersion": "2024-11-05"}},
            {"X-Real-Token": self.TOKEN})
        info = (body.get("result") or {}).get("serverInfo") or {}
        self.assertTrue(info.get("name", "").endswith("-real"),
                        "serverInfo 名字必须能看出是 REAL，否则演示时无法确认连的是哪个源")


class TestMockPathUnchanged(unittest.TestCase):
    """回归：现网 `/mcp` 与 `/tools/*` 一切照旧（M0 要求不改已部署 MOCK）。"""

    DEMO = "demo-tok-regress"

    @classmethod
    def setUpClass(cls):
        cls.s = _Server(CHECKD_DEMO_TOKEN=cls.DEMO)

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()

    def test_mock_still_lists_seven_tools(self):
        code, body = self.s.mcp("/mcp", {
            "jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}},
            {"X-Demo-Token": self.DEMO})
        names = [t["name"] for t in (body.get("result") or {}).get("tools") or []]
        self.assertEqual(len(names), 7, "现网七个工具不能变：%s" % names)

    def test_mock_list_tasks_still_works_with_demo_token(self):
        code, body = self.s.mock(demo_token=self.DEMO)
        self.assertEqual(code, 200)
        self.assertEqual(body.get("status"), "success")
        self.assertEqual(body.get("source"), "mock")
        # 工具返回值在 `data` 下（与 REAL 同一套信封，见 app.py `mock.envelope` 处注释）
        self.assertGreater(len((body.get("data") or {}).get("tasks") or []), 0)

    def test_mock_server_info_not_marked_real(self):
        code, body = self.s.mcp("/mcp", {
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {"protocolVersion": "2024-11-05"}},
            {"X-Demo-Token": self.DEMO})
        info = (body.get("result") or {}).get("serverInfo") or {}
        self.assertFalse(info.get("name", "").endswith("-real"))


class TestRealWindow(unittest.TestCase):
    """演示窗口：非法配置**拒绝**而不是放行。"""

    TOKEN = "real-token-z"

    def test_malformed_window_refuses(self):
        s = _Server(CHECKD_DEMO_TOKEN="demo-tok", CHECKD_REAL_ENABLED="1",
                    CHECKD_REAL_TOKEN=self.TOKEN,
                    CHECKD_REAL_SUPABASE_URL=DEAD_URL,
                    CHECKD_REAL_ANON_KEY="anon", CHECKD_REAL_JWT="jwt",
                    CHECKD_REAL_WINDOW="not-a-time-range")
        try:
            code, body = s.real(real_token=self.TOKEN)
            self.assertEqual(code, 403, "窗口格式写错时不能当没配置")
            self.assertEqual(_err((code, body)), "FORBIDDEN")
        finally:
            s.stop()

    def test_window_outside_current_time_refuses(self):
        # 取一个必然不含「当前分钟」的窗口：把起止都设成 00:00，
        # 只有恰好在 00:00 那一分钟才通过 —— 单测几乎不可能撞上。
        s = _Server(CHECKD_DEMO_TOKEN="demo-tok", CHECKD_REAL_ENABLED="1",
                    CHECKD_REAL_TOKEN=self.TOKEN,
                    CHECKD_REAL_SUPABASE_URL=DEAD_URL,
                    CHECKD_REAL_ANON_KEY="anon", CHECKD_REAL_JWT="jwt",
                    CHECKD_REAL_WINDOW="00:00-00:00")
        try:
            code, _ = s.real(real_token=self.TOKEN)
            if time.localtime().tm_hour == 0 and time.localtime().tm_min == 0:
                self.skipTest("恰好撞上 00:00，本用例的构造前提不成立")
            self.assertEqual(code, 403)
        finally:
            s.stop()


if __name__ == "__main__":
    unittest.main()
