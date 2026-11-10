#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""一条命令验证「MOCK / REAL 双向隔离」，输出可直接粘贴进核验件的日志。

为什么要有这个脚本
------------------
M3 2026-11-09 报：本地起服务打六场景的动态验证**被环境审批拦了，未执行**。
M0 2026-11-10 的要求是「若本机执行环境被权限拦截，请 M1 提供可复验命令/日志」。

所以这里给的不是「跑测试」，而是**一条命令 + 一段可贴的日志**：
不连任何外部服务、不需要任何真实凭证，起的是本机进程，数据源故意指向必然连不上的地址。

用法
----
    python verify_real_isolated.py
    python verify_real_isolated.py --verbose     # 额外打印每个场景的响应体

退出码：全部符合预期 = 0，有任一不符 = 1。

**这个脚本证明什么**：两条路径的鉴权互不串门、失败时不回落 MOCK。
**不证明什么**：读过真实账号数据。真实读取要真实令牌，见 RUNBOOK §十三。
"""

import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.join(HERE, "app.py")
MOCK_DIR = os.path.abspath(os.path.join(HERE, "..", "m1-mock"))

# 这些值都是本脚本自己造的临时值，不是任何环境的真凭证。
DEMO_TOKEN = "verify-demo-token-not-real"
REAL_TOKEN = "verify-real-token-not-real"
ADMIN_KEY = "verify-admin-key-not-real"

# 127.0.0.1:1 是保留端口，正常环境不会有服务在听 → 用来验证「源不可用时不回落 MOCK」
DEAD_URL = "http://127.0.0.1:1"

# 形状合法但无意义的假 JWT（三段、载荷带 exp=2100），只为让请求能走到数据源那一步。
# 不是任何环境的真令牌，也不被任何服务验签通过。
FAKE_JWT = ("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
            ".eyJzdWIiOiJ2ZXJpZnktb25seSIsImV4cCI6NDEwMjQ0NDgwMH0"
            ".dmVyaWZ5LW9ubHktc2lnbmF0dXJl")

_RELEVANT_ENV = (
    "CHECKD_DEMO_TOKEN", "CHECKD_DEMO_TOKEN_SHA256", "CHECKD_ADMIN_KEY",
    "CHECKD_HEALTH_MINIMAL", "CHECKD_REAL_ENABLED", "CHECKD_REAL_TOKEN",
    "CHECKD_REAL_SUPABASE_URL", "CHECKD_REAL_ANON_KEY", "CHECKD_REAL_JWT",
    "CHECKD_REAL_WINDOW",
)


def _free_port():
    s = socket.socket()
    try:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]
    finally:
        s.close()


class Server:
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
            [sys.executable, APP], env=env, cwd=HERE,
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

    def post(self, path, headers, payload=None):
        body = json.dumps(payload or {
            "api_version": "checkd.agent.v1", "request_id": "verify-1",
            "timezone": "Asia/Shanghai",
            "input": {"date_range": {"start": "2026-11-10", "end": "2026-11-10"}},
        }).encode()
        req = urllib.request.Request(
            "http://127.0.0.1:%d%s" % (self.port, path),
            data=body, method="POST",
            headers=dict({"Content-Type": "application/json"}, **headers))
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return r.status, json.loads(r.read().decode() or "{}")
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


def _err_code(body):
    return ((body or {}).get("error") or {}).get("code")


def _looks_like_mock_payload(body):
    """REAL 侧如果吐出 MOCK 数据，就是这个函数报警。

    MOCK 的响应一定带 `mock` 字样或 `data_source: "builtin"`；
    REAL 必须带 `source: "real"`。
    """
    text = json.dumps(body or {}, ensure_ascii=False)
    if (body or {}).get("source") == "real":
        return False
    return ("mock" in text.lower()) or ((body or {}).get("data_source") == "builtin")


# --------------------------------------------------------------------------
# 六个场景
# --------------------------------------------------------------------------

def run(verbose=False):
    rows = []
    detail = []

    def check(idx, name, expect, got, ok, note=""):
        rows.append((idx, name, expect, got, "OK" if ok else "MISMATCH", note))
        return ok

    # ---- 服务 A：REAL 未启用 ----
    a = Server(CHECKD_DEMO_TOKEN=DEMO_TOKEN, CHECKD_ADMIN_KEY=ADMIN_KEY)
    try:
        code, body = a.post("/real/tools/list_tasks",
                            {"X-Real-Token": REAL_TOKEN})
        detail.append(("A /real/tools/list_tasks (REAL off)", code, body))
        check(1, "REAL 未启用时 /real/* 不可用",
              "503 且响应里没有 MOCK 数据",
              "%s / %s" % (code, _err_code(body)),
              code == 503 and not _looks_like_mock_payload(body))
    finally:
        a.stop()

    # ---- 服务 B：REAL 启用，数据源指向必然连不上的地址 ----
    # 必须给一个「形状合法的假 JWT」，否则请求会先被 401 AUTH_REQUIRED 挡下，
    # 根本走不到数据源——那样场景 5 测的就是「缺令牌」而不是「源不可用」。
    b = Server(CHECKD_DEMO_TOKEN=DEMO_TOKEN, CHECKD_ADMIN_KEY=ADMIN_KEY,
               CHECKD_REAL_ENABLED="1", CHECKD_REAL_TOKEN=REAL_TOKEN,
               CHECKD_REAL_SUPABASE_URL=DEAD_URL,
               CHECKD_REAL_ANON_KEY="verify-anon-not-real",
               CHECKD_REAL_JWT=FAKE_JWT)
    try:
        code, body = b.post("/real/tools/list_tasks", {})
        detail.append(("B /real/tools/list_tasks (no token)", code, body))
        check(2, "REAL 无凭证", "401 AUTH_REQUIRED",
              "%s / %s" % (code, _err_code(body)),
              code == 401 and _err_code(body) == "AUTH_REQUIRED")

        code, body = b.post("/real/tools/list_tasks", {"X-Real-Token": "wrong"})
        detail.append(("B /real/tools/list_tasks (wrong token)", code, body))
        check(3, "REAL 错凭证", "403 FORBIDDEN",
              "%s / %s" % (code, _err_code(body)),
              code == 403 and _err_code(body) == "FORBIDDEN")

        code, body = b.post("/real/tools/list_tasks",
                            {"X-Demo-Token": DEMO_TOKEN})
        detail.append(("B /real/tools/list_tasks (demo token)", code, body))
        check(4, "演示口令打不开 REAL", "401 AUTH_REQUIRED",
              "%s / %s" % (code, _err_code(body)),
              code == 401 and _err_code(body) == "AUTH_REQUIRED")

        code, body = b.post("/real/tools/list_tasks", {"X-Real-Token": REAL_TOKEN})
        detail.append(("B /real/tools/list_tasks (correct, dead source)", code, body))
        check(5, "正确口令 + 源不可用 → 不回落 MOCK",
              "非 200，且响应里没有 MOCK 数据",
              "%s / %s" % (code, _err_code(body)),
              code != 200 and not _looks_like_mock_payload(body))

        code, body = b.post("/tools/list_tasks", {"X-Real-Token": REAL_TOKEN})
        detail.append(("B /tools/list_tasks (real token)", code, body))
        check(6, "真实口令打不开 MOCK", "401 APPROVAL_UNTRUSTED",
              "%s / %s" % (code, _err_code(body)),
              code == 401 and _err_code(body) == "APPROVAL_UNTRUSTED")

        code, body = b.post("/tools/list_tasks", {"X-Demo-Token": DEMO_TOKEN})
        detail.append(("B /tools/list_tasks (demo token)", code, body))
        check(7, "MOCK 回归：正确演示口令仍可用", "200 success",
              "%s / %s" % (code, (body or {}).get("status") or _err_code(body)),
              code == 200 and (body or {}).get("status") == "success")
    finally:
        b.stop()

    # ---- 输出 ----
    print("M1 REAL/MOCK 双向隔离 · 本地实跑日志")
    print("时间：%s" % time.strftime("%Y-%m-%d %H:%M:%S %z"))
    print("环境：本地进程，无外部网络，无真实凭证；数据源指向 %s" % DEAD_URL)
    print("")
    head = ("#", "场景", "期望", "实际", "判定")
    widths = (2, 30, 28, 26, 9)
    print("  ".join(str(h).ljust(w) for h, w in zip(head, widths)))
    print("-" * (sum(widths) + 8))
    for r in rows:
        print("  ".join(str(v).ljust(w) for v, w in zip(r[:5], widths)))
    print("")

    bad = [r for r in rows if r[4] != "OK"]
    if bad:
        print("MISMATCH %d 项：" % len(bad))
        for r in bad:
            print("  - #%s %s：期望 %s，实际 %s" % (r[0], r[1], r[2], r[3]))
    else:
        print("全部 %d 项符合预期。" % len(rows))

    if verbose:
        print("")
        print("---- 原始响应（已剥掉令牌，只留状态与错误码）----")
        for name, code, body in detail:
            print("%s -> %s %s" % (name, code, json.dumps(body, ensure_ascii=False)[:300]))

    print("")
    print("判定说明：本日志只证「两条路径的鉴权互不串门、失败不回落 MOCK」；")
    print("          真实账号数据读取需真实令牌，不在本脚本范围内。")
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(run("--verbose" in sys.argv))
