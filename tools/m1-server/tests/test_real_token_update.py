"""`/admin/real-token` 运行时注入的测试。

M0 2026-11-09T14:20 决定「演示前手动更新短期授权」。若令牌只能走环境变量，
每次更新都要重新部署 —— 而 2026-11-07 那次重部署把全站弄成 503 过。
这个端点让更新变成「一次带管理口令的 POST」，不碰部署。

四条必须钉住的事：

  1. **没有管理口令就进不来**，而且不能退回 MOCK 顶上
  2. **明显不是 JWT 的东西收下会害人**：后续 401 会被误判成配置错，所以在入口拒掉
  3. **已过期的令牌不收**：收下等于把「过期」变成「配置错误」
  4. **响应里绝不回显令牌**，只回过期时刻
"""

import base64
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


def _b64(obj):
    raw = json.dumps(obj, separators=(",", ":")).encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def make_jwt(exp_offset=3600, sub="m0-user-uuid"):
    """造一个形状合法的 JWT。**签名段是假的** —— 本服务不验签（也不该有 secret）。"""
    head = _b64({"alg": "HS256", "typ": "JWT"})
    body = _b64({"sub": sub,
                 "exp": int(time.time()) + exp_offset,
                 "role": "authenticated"})
    return "%s.%s.%s" % (head, body, "not-a-real-signature")


def _free_port():
    s = socket.socket()
    try:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]
    finally:
        s.close()


class _Server:
    ADMIN = "admin-key-for-tests"
    REAL = "real-token-for-tests"

    def __init__(self):
        self.port = _free_port()
        env = dict(os.environ)
        for k in _RELEVANT_ENV:
            env.pop(k, None)
        env.update({
            "PORT": str(self.port), "BIND": "127.0.0.1",
            "CHECKD_SNAPSHOT_MODE": "off",
            "CHECKD_DEMO_TOKEN": "demo-tok",
            "CHECKD_ADMIN_KEY": self.ADMIN,
            "CHECKD_REAL_ENABLED": "1",
            "CHECKD_REAL_TOKEN": self.REAL,
            # 指向必连不上的地址：这样即使注入了令牌，REAL 读取也会 503。
            # 本文件不测「读得到」，只测「令牌怎么进来」。
            "CHECKD_REAL_SUPABASE_URL": "http://127.0.0.1:1",
            "CHECKD_REAL_ANON_KEY": "anon",
        })
        env["PYTHONPATH"] = os.pathsep.join(
            [MOCK_DIR] + ([env["PYTHONPATH"]] if env.get("PYTHONPATH") else []))
        self.proc = subprocess.Popen(
            [sys.executable, APP], env=env, cwd=SRC_DIR,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self._wait()

    def _wait(self):
        deadline = time.time() + 20
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError("app.py 启动即退出")
            try:
                with socket.create_connection(("127.0.0.1", self.port), timeout=0.5):
                    return
            except OSError:
                time.sleep(0.1)
        raise RuntimeError("20 秒内没起来")

    def post(self, path, payload, admin=None):
        headers = {"Content-Type": "application/json"}
        if admin is not None:
            headers["X-Admin-Key"] = admin
        req = urllib.request.Request(
            "http://127.0.0.1:%d%s" % (self.port, path),
            data=json.dumps(payload).encode(), method="POST", headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return r.status, json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", "replace")
            try:
                return e.code, json.loads(raw)
            except Exception:
                return e.code, {"raw": raw}

    def real_read(self):
        payload = {"api_version": "checkd.agent.v1", "request_id": "r",
                   "timezone": "Asia/Shanghai",
                   "input": {"date_range": {"start": "2026-11-09",
                                            "end": "2026-11-09"}}}
        return self._real_post(payload)

    def _real_post(self, payload):
        req = urllib.request.Request(
            "http://127.0.0.1:%d/real/tools/list_tasks" % self.port,
            data=json.dumps(payload).encode(), method="POST",
            headers={"Content-Type": "application/json",
                     "X-Real-Token": self.REAL})
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
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


def _err(resp):
    return ((resp[1].get("error") or {}).get("code") if isinstance(resp[1], dict) else None)


class TestAdminRealToken(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s = _Server()

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()

    def test_requires_admin_key(self):
        code, body = self.s.post("/admin/real-token", {"access_token": make_jwt()})
        self.assertIn(code, (401, 403), "没有管理口令也能写令牌，等于没有鉴权")
        self.assertNotEqual(code, 200)

    def test_wrong_admin_key_rejected(self):
        code, body = self.s.post("/admin/real-token", {"access_token": make_jwt()},
                                 admin="wrong")
        self.assertIn(code, (401, 403))

    def test_accepts_valid_shape(self):
        tok = make_jwt()
        code, body = self.s.post("/admin/real-token", {"access_token": tok},
                                 admin=_Server.ADMIN)
        self.assertEqual(code, 200, body)
        self.assertTrue(body.get("real_token_updated"))
        self.assertGreater(body.get("expires_in_seconds") or 0, 0)

    def test_response_never_echoes_token(self):
        tok = make_jwt()
        code, body = self.s.post("/admin/real-token", {"access_token": tok},
                                 admin=_Server.ADMIN)
        blob = json.dumps(body, ensure_ascii=False)
        self.assertNotIn(tok, blob, "响应里回显了令牌本体")
        # 连任意一段都不该出现
        for part in tok.split("."):
            self.assertNotIn(part, blob, "响应里出现了令牌的某一段")

    def test_rejects_non_jwt(self):
        code, body = self.s.post("/admin/real-token",
                                 {"access_token": "my-plain-password"},
                                 admin=_Server.ADMIN)
        self.assertEqual(code, 400)
        self.assertEqual(_err((code, body)), "INVALID_ARGUMENT")
        self.assertNotIn("my-plain-password", json.dumps(body, ensure_ascii=False),
                         "报错里不该回显用户提交的内容")

    def test_rejects_too_few_segments(self):
        code, body = self.s.post("/admin/real-token",
                                 {"access_token": "a.b"}, admin=_Server.ADMIN)
        self.assertEqual(code, 400)

    def test_rejects_payload_without_exp(self):
        head = _b64({"alg": "HS256", "typ": "JWT"})
        body_seg = _b64({"sub": "u"})
        code, resp = self.s.post("/admin/real-token",
                                 {"access_token": "%s.%s.sig" % (head, body_seg)},
                                 admin=_Server.ADMIN)
        self.assertEqual(code, 400)
        self.assertIn("exp", json.dumps(resp, ensure_ascii=False))

    def test_rejects_expired_token(self):
        code, body = self.s.post("/admin/real-token",
                                 {"access_token": make_jwt(exp_offset=-60)},
                                 admin=_Server.ADMIN)
        self.assertEqual(code, 400, "收下已过期令牌，后续 401 会被误判成配置错")

    def test_override_does_not_enable_read_by_itself(self):
        """注入令牌只是让它能发请求；数据源不可达仍要 503，不回落 MOCK。"""
        self.s.post("/admin/real-token", {"access_token": make_jwt()},
                    admin=_Server.ADMIN)
        code, body = self.s.real_read()
        self.assertEqual(code, 503)
        self.assertEqual(body.get("source"), "real")
        self.assertNotIn("t_1001", json.dumps(body, ensure_ascii=False))


if __name__ == "__main__":
    unittest.main()
