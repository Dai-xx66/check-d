#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CheckD 比赛版工具服务：把已验证的 Mock 工具层暴露成单端口 HTTP 服务。

设计约束（逐条对应 M0 2026-11-05 12:53:29Z 的工作包 B/C 项与用户红线）：

1. 单一实现。工具逻辑不在这里，全部来自 tools/m1-mock/tool_server.py。
   本文件只做传输层：鉴权、JSON、HTTP 状态、证据记录。改工具行为必须改 mock，
   不在这里长第二套逻辑。
2. 只绑回环。默认 BIND=127.0.0.1；只有部署到平台沙箱时才由启动命令显式传
   BIND=0.0.0.0。绝不在本机默认对外监听。
3. 鉴权失败即关闭（fail-closed）。CHECKD_DEMO_TOKEN 与 CHECKD_DEMO_TOKEN_SHA256
   都未设置时，所有业务端点返回 503，不给"先跑起来再补密码"的空间。
   两者任一已设即可工作；指纹模式见 DEMO_TOKEN_SHA256 处的说明。
   未设置 CHECKD_ADMIN_KEY 时，reset 与 evidence 端点整体禁用。
4. 对外只认一把随机口令，内部演示身份与口令解耦。口令匹配后固定以演示用户
   身份调用工具，mock 自带的 demo-token-alice/bob 不出现在任何对外文案里。
5. HTTP 状态取自契约 §4.1 的 21 码表（errors.py，M3 已复验）。未知码不包装成
   信封透传，改为脱敏的 500。
6. 每次工具调用写入证据日志：工具名、参数、成功与否、错误码、耗时。这是
   M0 要求的「可追溯记录」，平台侧不向模型透出 tool_call id，只能由服务端出。
7. 演示数据全在进程内存，reset 用重新加载模块的方式回到初始 fixture，
   不写任何数据库。
"""

import base64
import importlib
import json
import os
import re
import sys
import threading
import time
import traceback
import uuid
import hmac
import hashlib
from collections import deque
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import errors as errs  # noqa: E402  PR-A 的 21 码 HTTP 映射

import tool_server as mock  # noqa: E402  唯一的工具实现

# REAL 适配层是隔离开发件。导入失败**不能影响现网**：MOCK 那七条工具与它毫无关系，
# 只因一个可选模块缺依赖就整站起不来，是不可接受的。所以这里吞掉导入异常，
# 等真正走到 /real/* 时再报 DEPENDENCY_UNAVAILABLE，并带上失败原因。
try:
    import real_read  # noqa: E402
    _REAL_IMPORT_ERROR = None
except Exception as _exc:                       # pragma: no cover - 正常环境不会触发
    real_read = None
    _REAL_IMPORT_ERROR = _exc

SERVICE_NAME = "checkd-agent-tools"
SERVICE_VERSION = "1.0.0"

DEMO_TOKEN = os.environ.get("CHECKD_DEMO_TOKEN", "")

# 方案 A（2026-11-08，M0 15:55 询问后定）：允许只配置**口令的指纹**，不配置明文。
#
# 起因：共享口令要求「服务端与调用方持有同一个字符串」，而「同一个」只能靠传输。
# M0 同时要求「任何渠道不得出现明文」，于是三条一起构成死锁——不是流程没写细，
# 是共享口令这个机制本身走不通。
#
# 改成存指纹：调用方自持明文，服务端只拿来访值算一遍 SHA-256 去比。
# 指纹泄露造不出口令（SHA-256 不可逆），因此部署目录里即便留的是指纹，
# 平台内部读到也拿不到可用凭证。
#
# 逗号分隔，支持多个 —— 每个调用方各自轮换，互不影响。
#
# 只接受 64 位小写十六进制，其余一律丢弃并告警。
# 起因：M2 2026-11-08 19:19 报 P1 —— 配置侧写进非 ASCII 时，比对循环里的
# want.encode("ascii") 会抛 UnicodeEncodeError，客户端拿到的是**空应答**（curl 52），
# 既不是 401 也不是 503。那等于把一个配置笔误放大成「服务不可用」，
# 排查时还会误以为是网络问题。在启动阶段就过滤，非法项永远进不了比对循环。
_SHA256_RE = re.compile(r"[0-9a-f]{64}")


def _parse_sha256_list(raw):
    good, bad = [], []
    for piece in raw.split(","):
        piece = piece.strip().lower()
        if not piece:
            continue
        if _SHA256_RE.fullmatch(piece):
            good.append(piece)
        else:
            bad.append(len(piece))     # 只记长度，绝不把疑似口令的内容打到日志
    for n in bad:
        sys.stderr.write(
            "WARN: CHECKD_DEMO_TOKEN_SHA256 含 %d 字符的非法项（须为 64 位十六进制），已丢弃。\n" % n)
    return tuple(good)


DEMO_TOKEN_SHA256 = _parse_sha256_list(os.environ.get("CHECKD_DEMO_TOKEN_SHA256", ""))

ADMIN_KEY = os.environ.get("CHECKD_ADMIN_KEY", "")
# 口令通过后固定使用的演示身份；不对外暴露 mock 内部 token
DEMO_USER_TOKEN = os.environ.get("CHECKD_DEMO_USER", "demo-token-alice")

_LOCK = threading.Lock()
_STATS = {"starts_at": None, "calls": 0, "errors": 0}
_EVIDENCE = []          # 最近 500 条工具调用
_EVIDENCE_CAP = 500

# ---------------------------------------------------------------- 防护
# 2026-11-05 用户要求「公网那边被攻击了别影响到我」。
# 四道闸，全部可用环境变量收紧，默认值按公网部署的保守面取：
#   1) body 上限    —— 防超大 payload 打爆内存
#   2) 滑动窗口限流 —— 防刷；管理端点额度更小
#   3) socket 超时  —— 防慢速连接耗尽线程
#   4) health 精简  —— 公网不暴露 bind/port/口令指纹
# 说明：这些都不改变契约内的 21 个错误码闭集，限流复用 DEPENDENCY_UNAVAILABLE(503)。
MAX_BODY_BYTES = int(os.environ.get("CHECKD_MAX_BODY", "262144"))        # 256 KiB
RATE_LIMIT_PER_MIN = int(os.environ.get("CHECKD_RATE_PER_MIN", "120"))
# 管理端点是"脚本在调"不是"人在点"，额度要给够：一次完整闭环会连打 reset + demo_confirm。
RATE_LIMIT_ADMIN_PER_MIN = int(os.environ.get("CHECKD_RATE_ADMIN_PER_MIN", "60"))
SOCKET_TIMEOUT = float(os.environ.get("CHECKD_SOCKET_TIMEOUT", "15"))
HEALTH_MINIMAL = os.environ.get("CHECKD_HEALTH_MINIMAL", "1") == "1"

# M2 引擎（可选）：CHECKD_ENGINE=1 时在容器内回环上拉起 Dart 引擎。
# 默认关，保证「引擎跑不起来也不影响已有链路」；开的时候 /diag 会如实报状态，
# 绝不在引擎不可用时假装成功。
ENGINE_ENABLED = os.environ.get("CHECKD_ENGINE", "0") == "1"
ENGINE_PORT = int(os.environ.get("M2_ENGINE_PORT", "8787"))
ENGINE_ENTRY = os.environ.get("CHECKD_ENGINE_ENTRY", "tools/m2-engine/bin/serve.dart")
_ENGINE = {"pid": None, "error": None}

# 工具层是否真的把 generate/validate 转发给 M2 引擎。
#
# 与 ENGINE_ENABLED 是两件事，必须分开：
#   ENGINE_ENABLED=1 只表示「引擎进程被拉起来了」（/diag 的 engine.up 看这个）
#   ENGINE_WIRED=1   才表示「工具调用真的打到引擎」（/health 的 scheduler_mode 看这个）
#
# 2026-11-06 现状：ENGINE_ENABLED=1 但 ENGINE_WIRED=0 —— 引擎活着、工具层仍走 mock。
# 这正是 M0 14:16:20Z 放行令第 4 条要禁止的「静默回退」形态：引擎明明在，
# 调用却不经过它，而外部看不出来。所以这个标识必须对外可见，且不许写死成 REAL。
ENGINE_WIRED = os.environ.get("CHECKD_ENGINE_WIRED", "0") == "1"

# 快照库接线开关（三态，见 _snapshot_state）。
#
#   off（默认）：走现有 mock 路径，行为与 2026-11-07 之前完全一致
#   on  + DSN 可用：工具走真快照
#   on  + DSN 缺失/连不上：503 fail-closed，**绝不回退 mock**
#
# 为什么不把默认设成 on：线上当前没有 DSN，设 on 会让能演示的链路全部 503。
# M0 2026-11-07T03:36:48Z 工单 §三 要求的是「开了就必须真」，不是「关着也要 503」。
SNAPSHOT_MODE = os.environ.get("CHECKD_SNAPSHOT_MODE", "off").lower()
DEMO_DSN = os.environ.get("CHECKD_DEMO_DSN", "")

# 需要快照支撑的工具。只有这四个在 mode=on 时受 gate 约束，其余五个不受影响。
SNAPSHOT_TOOLS = frozenset({
    "generate_schedule", "validate_schedule",
    "request_approval", "apply_approved_changes",
})

_store = {"instance": None, "error": None}


# --------------------------------------------------------------- REAL-READ
#
# 隔离开发件（M0 2026-11-09T14:08 派工）。**默认全关**，线上现网 `/mcp` 与 `/tools/*`
# 行为零变化；REAL 走独立路径 `/real/mcp`、`/real/tools/*`。
#
# 为什么开新路径而不是在旧路径上分流：M0 明确要求「不改已部署公网 MOCK」。
# 同一路径内按请求头分流，任何一处判空写错都会让现网跟着变；两条路径物理隔开，
# 出问题只影响新路径，回滚就是把 CHECKD_REAL_ENABLED 设回 0。
REAL_ENABLED = os.environ.get("CHECKD_REAL_ENABLED", "0") == "1"

# REAL 路径的独立口令。**故意不复用 CHECKD_DEMO_TOKEN**：
# 那个口令 2026-11-08 已经写进邮件、进过交付件、在多人手里。
# 若它也能开 REAL，等于「隔离」只存在于命名上。反向隔离是这套设计的地基。
REAL_TOKEN = os.environ.get("CHECKD_REAL_TOKEN", "")

REAL_SUPABASE_URL = os.environ.get("CHECKD_REAL_SUPABASE_URL", "")
REAL_ANON_KEY = os.environ.get("CHECKD_REAL_ANON_KEY", "")
# 用户级短期 access_token（约 1 小时过期）。只从环境变量读，不落盘、不回显。
# M0 2026-11-09T14:20 决定：不做自动续期，由 M0 演示前手动更新。
REAL_JWT = os.environ.get("CHECKD_REAL_JWT", "")

# 运行时可注入的 access_token（M0 手动更新用，**不是自动续期**）。
# 为什么需要：环境变量只在进程启动时读一次，演示前换令牌就得重新部署——
# 而 2026-11-07 那次重新部署把全站弄成 503 过。有了这个入口，
# 更新令牌是「一次带管理口令的 POST」，不触碰部署、地址与 sharecode 都不变。
# 只驻内存：进程重启即失效（回到环境变量里的值），不落盘、不写任何文件。
_REAL_JWT_OVERRIDE = {"value": None, "set_at": None}


def _current_real_jwt():
    """运行时注入优先，其次环境变量。"""
    return _REAL_JWT_OVERRIDE["value"] or REAL_JWT


def _looks_like_jwt(tok):
    """粗判形状：三段、中间段能解出 `exp`。

    **这不是验签**，本服务没有 JWT secret 也不该有（那等于能伪造任意用户，
    比 service_role 更危险）。这里只拦「明显不是 JWT 的东西」，
    真实校验由 Supabase 端做：令牌无效时它会 401，走到 AUTH_REQUIRED。
    """
    if not isinstance(tok, str):
        return False, "令牌必须是字符串"
    parts = tok.split(".")
    if len(parts) != 3:
        return False, "不是三段式 JWT"
    try:
        pad = "=" * (-len(parts[1]) % 4)
        claims = json.loads(base64.urlsafe_b64decode(parts[1] + pad).decode("utf-8"))
    except Exception:
        return False, "载荷段无法解析"
    if not isinstance(claims, dict) or "exp" not in claims:
        return False, "载荷里没有 exp"
    return True, claims


# 演示窗口（形如 "14:00-16:00"，按服务器本地时间）。留空 = 不限制。
# M0 说方案②只是候选策略、时段须他单独确认，所以这里只提供能力，不预设开启。
REAL_WINDOW = os.environ.get("CHECKD_REAL_WINDOW", "").strip()

# REAL 侧只挂两个只读工具。其余五个**不出现在 tools/list 里**，
# 而不是出现后返回错误——Agent 看不到就无从误调，比让它先试一次再报错干净。
REAL_TOOL_NAMES = ("list_tasks", "get_calendar_events")


def _in_real_window(now=None):
    """演示窗口判定。未配置即恒真。配置非法时**拒绝**而不是放行。"""
    if not REAL_WINDOW:
        return True, None
    now = now or datetime.now()
    try:
        a, b = REAL_WINDOW.split("-")
        ha, ma = [int(x) for x in a.split(":")]
        hb, mb = [int(x) for x in b.split(":")]
    except Exception:
        return False, "CHECKD_REAL_WINDOW 格式非法（应为 HH:MM-HH:MM）"
    cur = now.hour * 60 + now.minute
    if ha * 60 + ma <= cur <= hb * 60 + mb:
        return True, None
    return False, "当前不在 REAL 演示窗口内（%s）" % REAL_WINDOW



def _snapshot_store():
    """懒加载快照存储。mode=off 或没 DSN 时返回 None，不抛。"""
    if SNAPSHOT_MODE != "on" or not DEMO_DSN:
        return None
    if _store["instance"] is not None:
        return _store["instance"]
    try:
        import snapshot_store
        st = snapshot_store.SnapshotStore(dsn=DEMO_DSN)
        st.open()
        if not st.health():
            raise RuntimeError("pool_open_but_unhealthy")
        _store["instance"] = st
        _store["error"] = None
        return st
    except Exception as e:                                   # noqa: BLE001
        # 记住失败原因，但不把 DSN 或异常原文带回公网（可能含连接串）。
        _store["error"] = type(e).__name__
        return None


def _snapshot_state():
    """给 /health 与 /diag 的只读状态。不主动探测时返回静态值。"""
    if SNAPSHOT_MODE != "on":
        return {"mode": SNAPSHOT_MODE, "dsn_configured": bool(DEMO_DSN), "ready": False}
    st = _snapshot_store()
    return {"mode": SNAPSHOT_MODE, "dsn_configured": True,
            "ready": st is not None, "error": _store.get("error")}

_RATE = {}              # (ip, bucket) -> deque[monotonic ts]
_RATE_LOCK = threading.Lock()


def _rate_ok(ip, limit, bucket="biz"):
    """滑动窗口计数。True = 放行；False = 已超限。

    **按 (IP, 类别) 分别计数**。2026-11-05 实测踩到的坑：起初只按 IP 记一个 deque，
    结果业务请求把窗口塞满后，管理端点（额度更小）被连带拒掉——
    demo_loop 的 admin/reset 与 demo/confirm 双双 503，链路在第 5、7 步断。
    两类流量必须各自成桶，否则收紧 A 就等于误伤 B。
    """
    now = time.monotonic()
    cutoff = now - 60.0
    key = (ip, bucket)
    with _RATE_LOCK:
        dq = _RATE.get(key)
        if dq is None:
            dq = _RATE[key] = deque()
        while dq and dq[0] < cutoff:
            dq.popleft()
        if len(dq) >= limit:
            return False
        dq.append(now)
        if len(_RATE) > 4096:          # 防字典无限增长（长跑场景）
            for k in [k for k, v in list(_RATE.items()) if not v][:1024]:
                _RATE.pop(k, None)
    return True


class _BodyTooLarge(Exception):
    def __init__(self, size):
        super().__init__(size)
        self.size = size


# ---------------------------------------------------------------- 工具函数

def _now():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


# 进程启动时刻：用来判断「令牌是在本进程里丢的，还是进程换了一个」。
_BOOT_TS = time.time()
_BOOT_AT = _now()


def _iso_from_epoch(epoch):
    try:
        return datetime.fromtimestamp(int(epoch), timezone.utc).isoformat()
    except Exception:                                        # noqa: BLE001
        return None


# ---- 运行时标记（判定「容器重启时磁盘是否沿用」的唯一用途）--------------
# **刻意用懒加载**：这一小块是临时诊断能力，如果哪天没打进部署包，
# 也只有这两个端点报「不可用」，不能让整个服务启动即崩
# （11-08 就吃过「模块没打包 → 500」的亏）。
_PKG_DIR = os.path.dirname(os.path.abspath(__file__))


def _marker_module():
    import runtime_marker
    return runtime_marker


def _marker_envelope(extra):
    """统一带上「是哪个进程写的/读的」，否则重启前后两份结果没法对齐。"""
    out = {
        "pid": os.getpid(),
        "boot_at": _BOOT_AT,
        "uptime_seconds": int(time.time() - _BOOT_TS),
        "note": "本接口只用于判定容器重启后磁盘是否沿用；不涉及任何凭据。",
    }
    out.update(extra)
    return out


def _marker_write():
    try:
        rm = _marker_module()
    except Exception:
        return _marker_envelope({"ok": False, "reason": "runtime_marker_missing"})
    return _marker_envelope({"ok": True, "action": "write",
                             **rm.write_markers(_PKG_DIR)})


def _marker_read():
    try:
        rm = _marker_module()
    except Exception:
        return _marker_envelope({"ok": False, "reason": "runtime_marker_missing"})
    return _marker_envelope({"ok": True, "action": "read",
                             **rm.read_markers(_PKG_DIR)})


def _marker_clean():
    try:
        rm = _marker_module()
    except Exception:
        return _marker_envelope({"ok": False, "reason": "runtime_marker_missing"})
    return _marker_envelope({"ok": True, "action": "clean",
                             **rm.clean_markers(_PKG_DIR)})


def _fp(secret):
    """口令指纹：只用于核对"环境变量是不是这份值"，不可逆，不泄露明文。"""
    if not secret:
        return ""
    import hashlib
    return hashlib.sha256(secret.encode("utf-8")).hexdigest()[:8]


def _env_diag():
    """只读环境诊断。回答"容器能不能跑第二个进程"这一类问题，用实测替代推测。

    约束：不返回任何口令值；不监听任何端口（只 bind 后立即关闭）；不写文件时
    只试一次临时文件并删除；所有外部动作都有超时，失败即记 False 而不抛异常。
    """
    import platform
    import shutil
    import socket
    import subprocess
    import tempfile
    import urllib.parse

    diag = {
        "os": {"platform": sys.platform, "release": platform.release(),
               "machine": platform.machine(), "python": platform.python_version()},
        "cpu_count": os.cpu_count(),
    }

    # 1) 有没有可用的子进程运行时：先看可执行文件在不在，再真跑一次。
    binaries = ("dart", "flutter", "node", "git", "bash", "sh", "curl", "java")
    diag["binaries"] = {b: shutil.which(b) for b in binaries}
    # 关键版本号：Dart 3 的语法（switch 表达式等）在 Dart 2 上编不过，
    # 这是「引擎能不能在本容器跑」的第一判据，必须报出来。
    #
    # 并发跑 + 收紧超时。原来串行 timeout=25，实测 /diag 要 29 秒——
    # 多数客户端默认 30s 就断，等于诊断端点自己先超时，失去诊断意义。
    # Dart VM 冷启动确实要几秒，所以给 8s 而不是 2s；两个并发，总耗时≈最慢那个。
    versions = {}
    vjobs = [b for b in ("dart", "flutter") if diag["binaries"].get(b)]

    def _ver(b):
        try:
            pv = subprocess.run([b, "--version"], capture_output=True,
                                text=True, timeout=8)
            versions[b] = ((pv.stdout or "") + (pv.stderr or "")).strip().splitlines()[:2]
        except Exception as e:                               # noqa: BLE001
            versions[b] = [type(e).__name__]

    vthreads = [threading.Thread(target=_ver, args=(b,), daemon=True) for b in vjobs]

    # spawn 探测跟着同一批并发跑：它也是一次 subprocess，串在后面就是白等 5 秒。
    spawn = {"ok": False}

    def _spawn_probe():
        try:
            p = subprocess.run([sys.executable, "-c", "print('spawn-ok')"],
                               capture_output=True, text=True, timeout=5)
            spawn.update({"ok": p.returncode == 0,
                          "stdout": (p.stdout or "").strip()[:40],
                          "returncode": p.returncode})
        except Exception as e:                               # noqa: BLE001
            spawn.update({"ok": False, "error": type(e).__name__})

    vthreads.append(threading.Thread(target=_spawn_probe, daemon=True))
    for t in vthreads:
        t.start()
    vdeadline = time.time() + 9.0
    for t in vthreads:
        t.join(max(0.05, vdeadline - time.time()))
    diag["versions"] = versions
    diag["subprocess"] = spawn

    # 2) 回环端口能否监听（第二个进程要靠它把引擎挂起来）。
    loop = {"ok": False}
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("127.0.0.1", 0))
        s.listen(1)
        loop = {"ok": True, "port": s.getsockname()[1]}
        s.close()
    except Exception as e:                                   # noqa: BLE001
        loop = {"ok": False, "error": type(e).__name__}
    diag["loopback_listen"] = loop

    # 3) 出站能不能连出去（决定构建期能否拉依赖；只测连接，不发数据）。
    # 出站探测：并发跑，总耗时≈最慢一项而不是累加。
    # 串行时 6 个目标 × 4s 超时 ≈ 24s，加引擎探测实测 /diag 要 31s——
    # 多数客户端默认 30s 超时，等于诊断端点自己先超时，失去意义。
    egress = {}
    targets = [("1.1.1.1", 443), ("pypi.org", 443),
               ("pub.dev", 443), ("storage.googleapis.com", 443),
               ("raw.githubusercontent.com", 443), ("github.com", 443)]

    # 2026-11-10 M0 报 REAL 调用 URLError / HTTP 0 后加的：把真实数据源主机也探一遍。
    # 目的不是「构建依赖」，是回答一个具体问题——**容器到底出不出得去那个域名**。
    # 不探这一项时，只能看到「无法连接数据源」，分不清是地址写错、DNS 挂了还是出口被拦。
    _real_host = ""
    try:
        _real_host = (urllib.parse.urlparse(REAL_SUPABASE_URL or "").hostname or "")
    except Exception:                                        # noqa: BLE001
        _real_host = ""
    if _real_host:
        targets.append((_real_host, 443))
        # DNS 单独记一条：解析失败与连不上是两种完全不同的故障。
        try:
            egress["dns:" + _real_host] = socket.gethostbyname(_real_host)
        except Exception as e:                               # noqa: BLE001
            egress["dns:" + _real_host] = type(e).__name__

    def _probe(host, port):
        key = "%s:%d" % (host, port)
        try:
            s = socket.create_connection((host, port), timeout=4)
            s.close()
            egress[key] = True
        except Exception as e:                               # noqa: BLE001
            egress[key] = type(e).__name__

    workers = [threading.Thread(target=_probe, args=t, daemon=True) for t in targets]
    for w in workers:
        w.start()
    deadline = time.time() + 5.0
    for w in workers:
        w.join(max(0.05, deadline - time.time()))
    diag["egress"] = egress

    # 4) 工作目录是否可写（引擎二进制要落盘）。
    try:
        with tempfile.NamedTemporaryFile(dir=os.getcwd(), delete=True):
            diag["cwd_writable"] = True
    except Exception:                                        # noqa: BLE001
        diag["cwd_writable"] = False
    diag["cwd"] = os.getcwd()

    # 5) 只报环境变量名，不报值。
    diag["env_keys"] = sorted(k for k in os.environ
                              if k.startswith("CHECKD_") or k in ("BIND", "PORT", "PATH"))
    # 6) M2 引擎存活状态（只走回环）。
    diag["engine"] = _engine_status()

    # 7) 运行态：进程何时起来、注入的令牌还在不在。
    # 2026-11-10 M0 报「注入成功但随后读不到」后加的：没有这一项，
    # 「令牌没到达」「令牌到了但进程被重启掉了」「打到了另一个实例」三种情况
    # 从外部看完全一样，只能靠猜。这里只报**在不在、什么时候设的、什么时候到期**，
    # 不报值、不报长度、不报指纹。
    _jwt = _REAL_JWT_OVERRIDE.get("value") or REAL_JWT or ""
    _exp = None
    if _jwt:
        try:
            _ok, _info = _looks_like_jwt(_jwt)
            _exp = _info.get("exp") if _ok else None
        except Exception:                                    # noqa: BLE001
            _exp = None
    diag["runtime"] = {
        "pid": os.getpid(),
        "boot_at": _BOOT_AT,
        "uptime_seconds": int(time.time() - _BOOT_TS),
        "real_jwt_present": bool(_jwt),
        "real_jwt_source": ("override" if _REAL_JWT_OVERRIDE.get("value")
                            else ("env" if REAL_JWT else None)),
        "real_jwt_set_at": _REAL_JWT_OVERRIDE.get("set_at"),
        "real_jwt_exp": (_iso_from_epoch(_exp) if _exp else None),
        "real_jwt_expired": bool(_exp and _exp < int(time.time())),
    }
    # 快照库：mode=on 时才真去连（这里被低频访问，连一次可以接受）。
    diag["snapshot"] = _snapshot_state()
    # explanations 过滤统计：被剔除多少条、有没有未登记的码。
    # 只报码名与条数，不报被剔除的内容。
    try:
        import explanations_filter
        diag["explanations_filter"] = explanations_filter.STATS.snapshot()
    except Exception:                                        # noqa: BLE001
        diag["explanations_filter"] = {"error": "unavailable"}
    return diag


def _reset_demo_state():
    """重新加载 mock 模块，回到源码里的初始 fixture。

    不使用逐表清空：逐表清空要维护一份与 STATE 结构同步的清单，结构一变就漏。
    reload 的语义就是"回到初始"，没有维护成本。
    """
    global mock
    with _LOCK:
        mock = importlib.reload(mock)
    return {
        "tasks": len(mock.STATE["tasks"]),
        "courses": len(mock.STATE["courses"]),
        "proposals": len(mock.STATE["proposals"]),
        "approvals": len(mock.STATE["approvals"]),
        "writes": mock.STATE["writes"],
    }


def _snapshot_counts():
    return {
        "tasks": len(mock.STATE["tasks"]),
        "courses": len(mock.STATE["courses"]),
        "proposals": len(mock.STATE["proposals"]),
        "approvals": len(mock.STATE["approvals"]),
        "writes": mock.STATE["writes"],
    }


def _sanitize_explanations(body):
    """把响应里的 explanations 过公开白名单（契约 L316-318）。

    只处理确实带 explanations 数组的层，找不到就什么都不做——
    过滤层出问题不能影响主流程，但也不能假装过滤过。
    """
    try:
        import explanations_filter
    except Exception:                                        # noqa: BLE001
        sys.stderr.write("explanations_filter unavailable; skipped\n")
        return
    if not isinstance(body, dict):
        return
    layers = [body]
    for key in ("data", "result"):
        inner = body.get(key)
        if isinstance(inner, dict):
            layers.append(inner)
    for layer in layers:
        if isinstance(layer.get("explanations"), list):
            layer["explanations"] = explanations_filter.filter_explanations(
                layer["explanations"])


def _detail_list(details):
    """把各种 details 形状收成契约要求的数组。

    `SnapshotStoreError.details` 是 dict，`ToolError.details` 是 list，
    而 `errors.to_envelope` 只接受 list —— 直接传 dict 会 TypeError，
    于是一次参数错误会变成 500，把可诊断的失败伪装成服务端故障。
    """
    if not details:
        return None
    if isinstance(details, list):
        return details
    if isinstance(details, dict):
        return [{"field": str(k), "reason": str(v)[:200]} for k, v in details.items()]
    return None


def _snapshot_dispatch(name, args, trace, started):
    """mode=on 时的分派：四个快照工具走持久快照，其余工具仍走 mock。

    刻意独立成函数、且异常在这里就地转信封 —— `_call` 那段 try/except 是
    mock 路径的，两套错误面混在一起会让「库连不上」被记成「工具崩溃」。
    """
    st = _snapshot_store()
    ok = False
    code = None

    if st is None:                      # 双保险：调用方前面已拦过一次
        status = 503
        code = "DEPENDENCY_UNAVAILABLE"
        body = errs.to_envelope(
            code, "快照库不可用，本次调用未执行。",
            request_id=(args or {}).get("request_id"), trace_id=trace)
    else:
        try:
            import snapshot_tools
            user = mock.user_from_token(DEMO_USER_TOKEN)
            body = snapshot_tools.SnapshotTools(st).call(name, args, user)
            _sanitize_explanations(body)
            if not body.get("trace_id"):
                body["trace_id"] = trace
            # 快照来自库，但仍是演示数据，不是真实 App 数据 ——
            # source 二值里属 mock，具体来源用 data_source 区分（M3 P1-b）。
            body["source"] = "mock"
            body["data_source"] = "snapshot"
            status = 200
            ok = True
        except Exception as exc:                             # noqa: BLE001
            code = getattr(exc, "code", None)
            if code and errs.is_known_code(code):
                status = errs.http_status(code)
                body = errs.to_envelope(
                    code, getattr(exc, "message", "") or "请求未能完成。",
                    request_id=(args or {}).get("request_id"), trace_id=trace,
                    details=_detail_list(getattr(exc, "details", None)))
            else:
                sys.stderr.write("snapshot tool %s crashed:\n%s\n"
                                 % (name, traceback.format_exc()))
                code = "INTERNAL_ERROR"
                status = 500
                body = errs.to_envelope(
                    code, "服务端内部错误，请稍后重试并附 trace_id。",
                    request_id=(args or {}).get("request_id"), trace_id=trace)

    entry = {
        "ts": _now(),
        "trace_id": trace,
        "tool": name,
        "arguments": args,
        "ok": ok,
        "error_code": code,
        "duration_ms": int((time.time() - started) * 1000),
        "path": "snapshot",
    }
    with _LOCK:
        _STATS["calls"] += 1
        if not ok:
            _STATS["errors"] += 1
        _EVIDENCE.append(entry)
        if len(_EVIDENCE) > _EVIDENCE_CAP:
            del _EVIDENCE[:len(_EVIDENCE) - _EVIDENCE_CAP]
    return status, body, entry


def _validate_input(name, args):
    """按 tool_server.SCHEMAS 校验 input —— schema 写了的，服务端必须真执行。

    M3 2026-11-09T12:56:42Z 报 P1-b：`input` 里塞 `engine:"real"` 被静默接受，
    还返回一份**看不出是 MOCK** 的成功结果。schema 明写 `additionalProperties: false`，
    服务端却从未执行 —— 声明与实现脱节比不写 schema 更糟：调用方会以为被校验了。

    P2 是同一根因：`get_approval_status` 传 `proposal_id`（schema 要 `approval_id`）
    报 `NOT_FOUND` 而非 `INVALID_ARGUMENT`，现场调试分不清「参数错」还是「状态丢了」。
    未知字段一律在这里拦住，两条一起解决。

    只校验 `input` 内部：`SCHEMAS[name]` 描述的就是这一层（顶层信封另有其校验）。
    没有 schema 的工具不拦，保持原行为。
    """
    spec = mock.SCHEMAS.get(name)
    if not isinstance(spec, dict):
        return None

    inp = args.get("input")
    if inp is None:
        if spec.get("required"):
            return ("INVALID_ARGUMENT", "缺少必填字段 input。",
                    [{"field": "input", "reason": "missing"}])
        return None
    if not isinstance(inp, dict):
        return ("INVALID_ARGUMENT", "input 必须是对象。",
                [{"field": "input", "reason": "not_object"}])

    props = spec.get("properties") or {}
    if spec.get("additionalProperties") is False:
        extra = sorted(str(k) for k in inp if k not in props)
        if extra:
            return ("INVALID_ARGUMENT",
                    "input 含未定义字段：%s（该工具只接受 %s）。"
                    % (", ".join(extra), ", ".join(sorted(props)) or "无"),
                    [{"field": k, "reason": "unknown_field"} for k in extra])

    missing = sorted(k for k in (spec.get("required") or []) if k not in inp)
    if missing:
        return ("INVALID_ARGUMENT",
                "input 缺少必填字段：%s。" % ", ".join(missing),
                [{"field": k, "reason": "missing"} for k in missing])
    return None


def _call(name, args):
    """调用一个工具，返回 (http_status, body, evidence_entry)。"""
    started = time.time()
    trace = uuid.uuid4().hex[:16]
    ok = False
    code = None

    # 参数校验先于一切副作用：schema 声明了 additionalProperties:false，
    # 就必须在进入工具前拦住未知字段（M3 P1-b / P2）。
    bad = _validate_input(name, args)
    if bad is not None:
        vcode, vmsg, vdetails = bad
        body = errs.to_envelope(
            vcode, vmsg,
            request_id=(args or {}).get("request_id") if isinstance(args, dict) else None,
            trace_id=trace, details=vdetails)
        body["source"] = "mock"          # 没进任何数据源，但归属仍是 mock 服务
        entry = {"ts": _now(), "trace_id": trace, "tool": name, "arguments": args,
                 "ok": False, "error_code": vcode, "duration_ms": 0,
                 "gate": "input_schema"}
        with _LOCK:
            _STATS["calls"] += 1
            _STATS["errors"] += 1
            _EVIDENCE.append(entry)
        return errs.http_status(vcode), body, entry

    # 快照闸：仅在 CHECKD_SNAPSHOT_MODE=on 时生效。
    # 开了就必须真——库不可用一律 503，绝不悄悄回退 mock（M0 §三）。
    # 关着时（默认）本分支直接跳过，行为与接线前完全一致。
    if SNAPSHOT_MODE == "on" and name in SNAPSHOT_TOOLS and _snapshot_store() is None:
        body = errs.to_envelope(
            "DEPENDENCY_UNAVAILABLE",
            "快照库不可用，本次调用未执行。",
            request_id=(args or {}).get("request_id"), trace_id=trace)
        entry = {"ts": _now(), "trace_id": trace, "tool": name, "arguments": args,
                 "ok": False, "error_code": "DEPENDENCY_UNAVAILABLE", "duration_ms": 0,
                 "gate": "snapshot_not_ready"}
        with _LOCK:
            _STATS["calls"] += 1
            _STATS["errors"] += 1
            _EVIDENCE.append(entry)
        return 503, body, entry

    # mode=on 时四个快照工具改走持久快照（snapshot_tools）；其余工具仍走 mock，
    # 所以 get_approval_status / list_tasks 这些读写不受影响，演示链路不会整条断。
    if SNAPSHOT_MODE == "on" and name in SNAPSHOT_TOOLS:
        return _snapshot_dispatch(name, args, trace, started)

    try:
        result = mock.call_tool(name, args, DEMO_USER_TOKEN)
        body = result.get("structuredContent") or {}
        ok = not result.get("isError", False)
        # 引擎/工具的 explanations 一律过公开白名单（契约 L316-318）。
        # 非 dict 或没有 explanations 时原样返回，不因过滤层出错影响主流程。
        if ok:
            _sanitize_explanations(body)
        if ok:
            status = 200
        else:
            code = ((body.get("error") or {}).get("code")) or "INTERNAL_ERROR"
            status = errs.http_status(code) if errs.is_known_code(code) else 500
        if not body.get("trace_id"):
            body["trace_id"] = trace
        # M0 2026-11-09T10:51 「必须清晰区分 REAL-READ / MOCK-SCHEDULE / REAL-WRITE」。
        # M3 P1-b 实测：generate 载荷里 mock 出现 0 次，唯一可辨识痕迹是 approval_url 的域名 ——
        # 靠域名猜是不是 MOCK 太脆，直接在顶层给出来源，调用方与验收方都不必推断。
        # source 只用二值 mock/real（M3 的断言按这个写）；更细的来源放 data_source。
        body["source"] = "mock"
        body["data_source"] = "builtin"
    except Exception:
        sys.stderr.write("tool %s crashed:\n%s" % (name, traceback.format_exc()))
        code = "INTERNAL_ERROR"
        status = 500
        body = errs.to_envelope(code, "服务端内部错误，请稍后重试并附 trace_id。",
                                request_id=(args or {}).get("request_id"), trace_id=trace)

    entry = {
        "ts": _now(),
        "trace_id": trace,
        "tool": name,
        "arguments": args,
        "ok": ok,
        "error_code": code,
        "duration_ms": int((time.time() - started) * 1000),
    }
    with _LOCK:
        _STATS["calls"] += 1
        if not ok:
            _STATS["errors"] += 1
        _EVIDENCE.append(entry)
        if len(_EVIDENCE) > _EVIDENCE_CAP:
            del _EVIDENCE[:len(_EVIDENCE) - _EVIDENCE_CAP]
    return status, body, entry


def _demo_confirm(aid):
    """演示确认：把一条待审记录置为 approved，仅用于隔离演示环境。

    这不是真实审批。真实 approval_token 链（G5）要求独立审批服务、私钥签发、
    撤销机制与外部确认页，全部仍 BLOCKED。这里只发一个"演示用"令牌，
    让纵向闭环能在演示数据上真的跑完，并在响应里明写 demo=true。

    为什么必须同时写文件：mock 的 refresh_approval 会用审批文件覆盖内存状态，
    只改内存会在下一次读取时被打回 pending。
    """
    rec = mock.STATE["approvals"].get(aid)
    if not rec:
        return None
    rec["status"] = "approved"
    mock.STATE["approvals"][aid] = rec
    persisted = False
    try:
        approvals = mock.read_approvals()
        approvals[aid] = rec
        mock.write_approvals(approvals)
        persisted = True
    except Exception as exc:
        sys.stderr.write("demo_confirm persist failed: %s\n" % exc)
    return {"approval_id": aid, "status": "approved", "demo": True, "persisted": persisted}


# ---------------------------------------------------------------- MCP over HTTP

MCP_PROTOCOL = "2024-11-05"


def _mcp_result(rid, result):
    return {"jsonrpc": "2.0", "id": rid, "result": result}


def _mcp_error(rid, code, message):
    return {"jsonrpc": "2.0", "id": rid, "error": {"code": code, "message": message}}


def _real_call(name, args):
    """REAL 只读工具的唯一执行入口。返回 (http_status, body)。

    **与 `_call` 分开写，不是重复代码。** 两者的失败语义相反：
    `_call` 走 MOCK，出错只是这次调用失败；REAL 侧任何失败都**不许**退回 MOCK 顶上，
    否则验收方拿到的是一份「看起来成功」的假数据，而这正是 M0 反复强调要避免的
    （2026-11-09T14:08 第 3 条「不允许 engine:real 静默回落 MOCK」）。

    合在一个函数里迟早会有人图省事写 `except: return _call(name, args)`。
    """
    started = time.time()
    trace = uuid.uuid4().hex[:16]
    ok = False
    code = None
    request_id = args.get("request_id") if isinstance(args, dict) else None

    # 参数校验复用与 MOCK 完全相同的一份，避免两条路径对同一个错参数给出不同结论。
    bad = _validate_input(name, args)
    if bad is not None:
        vcode, vmsg, vdetails = bad
        body = errs.to_envelope(vcode, vmsg, request_id=request_id,
                                trace_id=trace, details=vdetails)
        body["source"] = "real"
        entry = {"ts": _now(), "trace_id": trace, "tool": name, "arguments": args,
                 "ok": False, "error_code": vcode, "duration_ms": 0,
                 "gate": "input_schema", "source": "real"}
        with _LOCK:
            _STATS["calls"] += 1
            _STATS["errors"] += 1
            _EVIDENCE.append(entry)
        return errs.http_status(vcode), body

    try:
        if real_read is None:
            raise RuntimeError("REAL 适配层未加载：%s" % (_REAL_IMPORT_ERROR,))
        # 信封与日期范围仍用 mock 的解析器：同一份契约只实现一次。
        inp = mock.validate_envelope(args)
        start, end = mock.date_range(inp)

        reader = real_read.SupabaseReader(REAL_SUPABASE_URL, REAL_ANON_KEY,
                                          _current_real_jwt())
        impl = real_read.RealRead(reader)
        if name == "list_tasks":
            payload = impl.list_tasks(start.isoformat(), end.isoformat(),
                                      kinds=inp.get("kinds"),
                                      statuses=inp.get("statuses"))
        else:
            payload = impl.get_calendar_events(start.isoformat(), end.isoformat())

        # **信封必须与 MOCK 走同一个 `mock.envelope`。**
        # 否则 Agent 侧要为同一件事写两套解析（`data.tasks` vs 顶层 `tasks`），
        # 而且切换数据源时最容易出的 bug 就是「字段读不到但没报错，只是空」。
        # 结构一致是这个模块能被「换源不换代码」的前提。
        body = mock.envelope(request_id, "success", {"data": payload})
        body["trace_id"] = "trace_" + trace
        # M0 2026-11-09T10:51 要求区分 REAL-READ / MOCK-SCHEDULE / REAL-WRITE。
        # 信封层强制写 real，不依赖下层是否老实标注。
        body["source"] = "real"
        body["data_source"] = "supabase"
        status = 200
        ok = True
    except Exception as exc:
        code = getattr(exc, "code", None)
        if not (code and errs.is_known_code(code)):
            # 未知异常不吞：打栈到 stderr，对外只给 INTERNAL_ERROR。
            # 这里如果把 exc 文案直接回给调用方，数据库连接串/库名可能一起漏出去。
            sys.stderr.write("REAL tool %s failed:\n%s" % (name, traceback.format_exc()))
            code = "INTERNAL_ERROR"
        msg = getattr(exc, "message", None) or "REAL 读取失败。"
        details = getattr(exc, "details", None) or []
        body = errs.to_envelope(code, msg, request_id=request_id,
                                trace_id=trace, details=details)
        # 错误也标 real：验收方才能判断「这条失败来自真实数据层」，
        # 而不是去查 MOCK 服务是不是挂了。
        body["source"] = "real"
        status = errs.http_status(code)

    entry = {"ts": _now(), "trace_id": trace, "tool": name, "arguments": args,
             "ok": ok, "error_code": code,
             "duration_ms": int((time.time() - started) * 1000), "source": "real"}
    with _LOCK:
        _STATS["calls"] += 1
        if not ok:
            _STATS["errors"] += 1
        _EVIDENCE.append(entry)
        if len(_EVIDENCE) > _EVIDENCE_CAP:
            del _EVIDENCE[:len(_EVIDENCE) - _EVIDENCE_CAP]
    return status, body


def _real_tool_defs():
    """REAL 侧对外的工具清单：只有两个只读工具。

    其余五个不出现，而不是出现后报错 —— Agent 看不到就无从误调。
    描述前缀 `[REAL]` 让模型能区分同名工具的两个版本（MOCK / 真实数据）。
    """
    out = []
    for spec in mock.tool_defs():
        if spec.get("name") in REAL_TOOL_NAMES:
            spec = dict(spec)
            spec["description"] = "[REAL] " + (spec.get("description") or "")
            out.append(spec)
    return out


def _mcp_handle(msg, real=False):
    """处理一条 JSON-RPC 报文。

    无状态实现：不发放 session id，每次请求自带全部语义。这样反向代理后面
    多副本也能工作，也不会因为一个客户端崩溃留下僵死会话。
    """
    if not isinstance(msg, dict):
        return _mcp_error(None, -32600, "invalid request")
    method = msg.get("method")
    rid = msg.get("id")
    params = msg.get("params") or {}

    if method == "initialize":
        # REAL 路径用不同的 serverInfo 名字：MCP 客户端会把 serverInfo 显示给用户，
        # 看到 "checkd-agent-tools" 和看到 "checkd-agent-tools-real" 是两件事，
        # 演示时能一眼确认当前连的是哪个数据源，不必去猜。
        info = {"name": SERVICE_NAME + ("-real" if real else ""),
                "version": SERVICE_VERSION}
        return _mcp_result(rid, {
            "protocolVersion": params.get("protocolVersion") or MCP_PROTOCOL,
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": info,
        })

    if method in ("notifications/initialized", "notifications/cancelled"):
        return None  # 通知不回包

    if method == "ping":
        return _mcp_result(rid, {})

    if method == "tools/list":
        return _mcp_result(rid, {"tools": _real_tool_defs() if real else mock.tool_defs()})

    if method == "tools/call":
        name = params.get("name")
        args = params.get("arguments") or {}
        if real:
            if name not in REAL_TOOL_NAMES:
                # 明确说清是「REAL 侧不提供」，不是「工具不存在」——
                # 后者会让排查方向跑到注册表上。
                return _mcp_error(rid, -32602,
                                  "tool not available on REAL path: %s" % name)
            status, body = _real_call(name, args)
            return _mcp_result(rid, {
                "content": [{"type": "text", "text": json.dumps(body, ensure_ascii=False)}],
                "structuredContent": body,
                "isError": status >= 400,
            })
        if name not in mock.TOOLS:
            return _mcp_error(rid, -32602, "unknown tool: %s" % name)
        # 只调用一次：_call 里已经执行并记了证据，这里只把结果包成 MCP 形状。
        # 早先写成"先 _call 再 call_tool"会把工具跑两遍，写操作会被执行两次。
        status, body, _entry = _call(name, args)
        return _mcp_result(rid, {
            "content": [{"type": "text", "text": json.dumps(body, ensure_ascii=False)}],
            "structuredContent": body,
            "isError": status >= 400,
        })

    return _mcp_error(rid, -32601, "method not found: %s" % method)


# ---------------------------------------------------------------- HTTP 层

class Handler(BaseHTTPRequestHandler):
    server_version = "%s/%s" % (SERVICE_NAME, SERVICE_VERSION)
    protocol_version = "HTTP/1.1"
    # 单连接读超时：慢速发 body 的连接到点即断，不会一直占着线程。
    timeout = SOCKET_TIMEOUT

    # ---- 基础工具

    def _send(self, status, payload):
        raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def _fail(self, status, code, message, request_id=None, details=None):
        trace = uuid.uuid4().hex[:16]
        if errs.is_known_code(code):
            body = errs.to_envelope(code, message, request_id=request_id,
                                    trace_id=trace, details=details)
        else:
            body = {"api_version": "checkd.agent.v1", "request_id": request_id,
                    "trace_id": trace, "status": "error",
                    "error": {"code": "INTERNAL_ERROR", "message": message,
                              "retryable": False, "details": []}}
        self._send(status, body)

    def _json_body(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            n = 0
        if n <= 0:
            return {}
        if n > MAX_BODY_BYTES:
            # 一个字节都不读：读了才拒等于自己先吃掉一次攻击。
            raise _BodyTooLarge(n)
        raw = self.rfile.read(n).decode("utf-8")
        return json.loads(raw)

    def _body_too_large(self, exc):
        self._fail(413, "INVALID_ARGUMENT",
                   "请求体超过上限 %d 字节（收到 %d）。" % (MAX_BODY_BYTES, exc.size))

    def _rate_check(self):
        """按 IP + 类别限流。管理端点单独成桶，额度独立。"""
        ip = self.client_address[0] if self.client_address else "-"
        path = self.path.split("?")[0]
        admin_like = path.startswith("/admin/") or path == "/demo/confirm"
        if admin_like:
            limit, bucket = RATE_LIMIT_ADMIN_PER_MIN, "admin"
        else:
            limit, bucket = RATE_LIMIT_PER_MIN, "biz"
        if _rate_ok(ip, limit, bucket):
            return True
        # 契约闭集里没有专门的限流码，复用 DEPENDENCY_UNAVAILABLE(503)；
        # 额外带 Retry-After 让客户端知道多久后重试。
        self.send_response(503)
        body = errs.to_envelope("DEPENDENCY_UNAVAILABLE", "请求过于频繁，请稍后再试。",
                                request_id=None, trace_id=uuid.uuid4().hex[:16])
        raw = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Retry-After", "60")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)
        return False

    def _candidates(self):
        """收集所有可能承载口令的头。

        为什么不能只看 Authorization：平台反代会注入/覆盖这个头，
        自定义头也会被拼进来。实测结论——只认 Authorization 时永远 401，
        而 X-Admin-Key 能正常透传。所以这里把两个来源都收齐，逐个比对。
        """
        out = []
        for raw in (self.headers.get_all("X-Demo-Token") or []):
            for part in raw.split(","):
                if part.strip():
                    out.append(part.strip())
        for raw in (self.headers.get_all("Authorization") or []):
            for part in raw.split(","):
                part = part.strip()
                if part.lower().startswith("bearer "):
                    out.append(part[7:].strip())
                elif part:
                    out.append(part)
        return out

    def _auth_ok(self):
        # 明文与指纹任一配置即可工作（方案 A：两者并行，不破坏既有能力）。
        if not DEMO_TOKEN and not DEMO_TOKEN_SHA256:
            self._fail(503, "DEPENDENCY_UNAVAILABLE",
                       "服务未配置访问口令，已按失败即关闭处理。")
            return False
        cands = self._candidates()
        # N6（M0 2026-11-07 令 D）：区分「完全没带凭证」与「凭证无效」。
        # 错误码仍是闭集内的 APPROVAL_UNTRUSTED，不新增码；可区分性靠 message +
        # details.reason，客户端可以按字段判定，不必解析中文文案。
        if not cands:
            self._fail(401, "APPROVAL_UNTRUSTED",
                       "缺少访问凭证：请在 X-Demo-Token 请求头提供。",
                       details=[{"field": "X-Demo-Token", "reason": "missing"}])
            return False
        # 常量时间比对：逐个候选走 compare_digest，不用 in / == 提前返回。
        # 方案 A：明文命中 或 指纹命中，都算通过。
        ok = False
        for cand in cands:
            if DEMO_TOKEN and hmac.compare_digest(cand, DEMO_TOKEN):
                ok = True
            if DEMO_TOKEN_SHA256:
                # 用 bytes 比较：指纹是纯 ASCII，但候选值可能含非 ASCII
                # （请求头被塞了奇怪内容），str 版 compare_digest 会抛 TypeError 变 500。
                got = hashlib.sha256(cand.encode("utf-8", "surrogatepass")).hexdigest()
                for want in DEMO_TOKEN_SHA256:
                    if hmac.compare_digest(got.encode("ascii"), want.encode("ascii")):
                        ok = True
        if not ok:
            self._fail(401, "APPROVAL_UNTRUSTED", "凭证无效。",
                       details=[{"field": "X-Demo-Token", "reason": "invalid"}])
            return False
        return True

    def _real_ok(self):
        """REAL 路径的鉴权。**只认 `X-Real-Token` 一个头。**

        三条与 `_auth_ok` 故意不同，每条都有原因：

        1. **不收 `Authorization`**。`_auth_ok` 收它是因为平台反代会注入、
           而 MOCK 的用户可能只配了那一个头。REAL 侧反过来：反代注入的内容
           来源不可控，把它当凭证等于让网关替我们做鉴权决定。
        2. **不收 `X-Demo-Token`**。那个口令 2026-11-08 已写进邮件、进过交付件、
           在多人手里。若它能开 REAL，「两套凭证隔离」就只剩命名上的区别。
        3. **未配置即拒绝（fail-closed）**，不回落到 MOCK。
           这条最容易被人「优化」成 `return True`，那样 REAL 路径会变成
           无鉴权的真实数据出口 —— 正是 M0 2026-11-09T10:51 明令禁止的。
        """
        if not REAL_ENABLED:
            self._fail(503, "DEPENDENCY_UNAVAILABLE",
                       "REAL-READ 未启用（CHECKD_REAL_ENABLED 未设为 1）。")
            return False
        if not REAL_TOKEN:
            self._fail(503, "DEPENDENCY_UNAVAILABLE",
                       "REAL-READ 未配置访问口令，已按失败即关闭处理。")
            return False
        in_window, why = _in_real_window()
        if not in_window:
            self._fail(403, "FORBIDDEN", why or "不在演示窗口内。")
            return False

        got = self.headers.get("X-Real-Token")
        if not got:
            self._fail(401, "AUTH_REQUIRED",
                       "缺少 REAL 访问凭证：请在 X-Real-Token 请求头提供。",
                       details=[{"field": "X-Real-Token", "reason": "missing"}])
            return False
        if not hmac.compare_digest(got.strip(), REAL_TOKEN):
            self._fail(403, "FORBIDDEN", "REAL 访问凭证无效。",
                       details=[{"field": "X-Real-Token", "reason": "invalid"}])
            return False
        return True

    def _admin_ok(self):
        if not ADMIN_KEY:
            self._fail(404, "NOT_FOUND", "该端点未启用。")
            return False
        if not hmac.compare_digest(self.headers.get("X-Admin-Key") or "", ADMIN_KEY):
            self._fail(401, "APPROVAL_UNTRUSTED", "管理凭证无效。")
            return False
        return True

    def log_message(self, fmt, *a):  # 请求日志进 stderr，不进响应
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % a))

    # ---- 路由

    def do_GET(self):
        path = self.path.split("?")[0]

        if path in ("/", "/health"):
            # 健康检查不鉴权，但也不给攻击者任何可用情报。
            # CHECKD_HEALTH_MINIMAL=1（公网默认）只回三样：活着、叫什么、什么版本。
            # 置 0 才给 bind/port/口令指纹——那是部署时自检用的，不该挂在公网。
            if HEALTH_MINIMAL:
                self._send(200, {"ok": True, "service": SERVICE_NAME,
                                 "version": SERVICE_VERSION,
                                 "scheduler_mode": _scheduler_mode()})
                return
            # 只给配置指纹（不可逆），用来判断"环境变量到底进没进来"，
            # 不打印明文口令。
            self._send(200, {
                "ok": True,
                "service": SERVICE_NAME,
                "version": SERVICE_VERSION,
                "mock_version": getattr(mock, "SERVER_VERSION", "?"),
                "tool_count": len(mock.TOOLS),
                "auth_required": True,
                "auth_configured": bool(DEMO_TOKEN or DEMO_TOKEN_SHA256),
                "admin_configured": bool(ADMIN_KEY),
                # M0 2026-11-07 令 D：删掉 token_sha8 / admin_sha8。口令指纹即便不可逆，
                # 也让人可以离线比对字典，且对运维没有用处（要验「变量进没进来」只看
                # 上面两个 bool 就够）。
                "bind": os.environ.get("BIND", "127.0.0.1"),
                "port": os.environ.get("PORT", "8790"),
                "starts_at": _STATS["starts_at"],
                "calls": _STATS["calls"],
                "errors": _STATS["errors"],
                # M0 14:16:20Z 放行令第 4 条：保留可识别的 REAL/MOCK 状态。
                # 当前恒为 MOCK（工具层未接线），引擎进程存活另见 /diag 的 engine.up。
                "scheduler_mode": _scheduler_mode(),
                "engine_enabled": ENGINE_ENABLED,
                # 快照库接线状态。只报静态配置事实，不在这里连库——
                # /health 被高频探活，不能因为它去 ping 数据库。
                "snapshot_mode": SNAPSHOT_MODE,
                "snapshot_dsn_configured": bool(DEMO_DSN),
                # REAL-READ 接线状态（隔离开发件）。只报**事实**，不报令牌内容：
                # 演示前 M0 最需要知道的是「令牌还有多久过期」，
                # 因为过期的表现是 401，容易被当成配置写错而白折腾半小时。
                "real_enabled": REAL_ENABLED,
                "real_token_source": _real_token_source(),
                "real_token_expires_at": _real_token_exp(),
                "real_data_source_configured": bool(REAL_SUPABASE_URL and REAL_ANON_KEY),
            })
            return

        if path == "/diag":
            # 只读环境诊断，仅管理凭证可读，且不返回任何口令值。
            # 用途：回答 M2 2026-11-05 16:54:03Z 的三个问题（能否跑第二进程 /
            # 容器里有没有 dart / 回环端口能否监听），用实测替代推测。
            if not self._admin_ok():
                return
            self._send(200, _env_diag())
            return

        if path == "/admin/marker":
            # 运行时标记文件的读回入口。**只读，不写。**
            # 为什么要有它：2026-11-10 实测容器会在没有任何发布的情况下自行重启
            # （15:38:03Z、15:55:34Z 两次），所以「容器重启时磁盘是否沿用」
            # 成了决定「令牌能不能落盘」的唯一事实前提。这个端点只回答这个事实问题。
            # 它不接触任何凭据，写进文件的只有随机无用字符。详见 runtime_marker.py。
            if not self._admin_ok():
                return
            self._send(200, _marker_read())
            return

        if path == "/tools":
            if not self._auth_ok():
                return
            self._send(200, {"tools": mock.tool_defs(), "count": len(mock.TOOLS)})
            return

        if path == "/evidence":
            if not self._admin_ok():
                return
            with _LOCK:
                items = list(_EVIDENCE)
            self._send(200, {"count": len(items), "items": items})
            return

        if path == "/state":
            if not self._admin_ok():
                return
            self._send(200, _snapshot_counts())
            return

        if path == "/mcp":
            # 无状态实现不提供服务端推送流；明确拒绝而不是留空连接，
            # 让客户端立刻走 POST 路径，不会挂在等 SSE 上。
            self.send_response(405)
            self.send_header("Allow", "POST")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        self._fail(404, "NOT_FOUND", "路径不存在。")

    def do_POST(self):
        if not self._rate_check():
            return
        path = self.path.split("?")[0]

        if path == "/admin/reset":
            if not self._admin_ok():
                return
            counts = _reset_demo_state()
            with _LOCK:
                _EVIDENCE.clear()
                _STATS["calls"] = 0
                _STATS["errors"] = 0
            self._send(200, {"ok": True, "reset": True, "counts": counts})
            return

        if path == "/admin/marker":
            # 写 / 清理运行时标记。**只写随机无用字符**，不写任何凭据。
            # 一次发布只跑一次 write；读回走 GET /admin/marker。
            if not self._admin_ok():
                return
            try:
                payload = self._json_body()
            except _BodyTooLarge as exc:
                self._body_too_large(exc)
                return
            except Exception:
                self._fail(400, "INVALID_ARGUMENT", "请求体不是合法 JSON。")
                return
            action = (payload or {}).get("action")
            if action == "write":
                self._send(200, _marker_write())
                return
            if action == "clean":
                self._send(200, _marker_clean())
                return
            self._fail(400, "INVALID_ARGUMENT",
                       "action 只接受 write 或 clean。")
            return

        if path == "/admin/real-token":
            # M0 手动更新 REAL 短期授权的唯一入口。**不是自动续期**：
            # 没有定时器、没有 refresh_token、没有任何后台动作，
            # 只有人拿管理口令 POST 一次才变。
            #
            # 为什么要有它：环境变量只在进程启动时读一次，换令牌就得重新部署；
            # 而 2026-11-07 那次重新部署把全站弄成 503 过。有了这个入口，
            # 演示前更新令牌不必碰部署，地址与 sharecode 都不变。
            if not self._admin_ok():
                return
            try:
                payload = self._json_body()
            except _BodyTooLarge as exc:
                self._body_too_large(exc)
                return
            except Exception:
                self._fail(400, "INVALID_ARGUMENT", "请求体不是合法 JSON。")
                return
            tok = (payload or {}).get("access_token")
            ok_shape, detail = _looks_like_jwt(tok)
            if not ok_shape:
                # 报错里**不回显令牌内容**，只说要什么形状。
                self._fail(400, "INVALID_ARGUMENT",
                           "access_token 不像 JWT：%s。" % detail)
                return
            exp = detail.get("exp")
            now = int(time.time())
            if isinstance(exp, (int, float)) and exp < now:
                # 收下一个已过期的令牌没有意义，只会让后续 401 看起来像配置错。
                self._fail(400, "INVALID_ARGUMENT",
                           "该 access_token 已经过期，请在 M0 本机重新获取。")
                return
            _REAL_JWT_OVERRIDE["value"] = tok
            _REAL_JWT_OVERRIDE["set_at"] = _now()
            # 响应只说「收了、何时过期」，不返回值本身、不回显指纹。
            self._send(200, {
                "ok": True,
                "real_token_updated": True,
                "expires_at": (datetime.fromtimestamp(exp, timezone.utc).isoformat()
                               if isinstance(exp, (int, float)) else None),
                "expires_in_seconds": (int(exp - now)
                                       if isinstance(exp, (int, float)) else None),
                "note": "只驻内存，进程重启后回到环境变量里的值。",
            })
            return

        if path == "/real/mcp":
            # REAL 是**独立路径**，不与 /mcp 共用。M0 2026-11-09T14:08 要求
            # 「不改已部署公网 MOCK」，同路径内按头分流任何一处判断写错都会波及现网。
            if not self._real_ok():
                return
            try:
                payload = self._json_body()
            except _BodyTooLarge as exc:
                self._body_too_large(exc)
                return
            except Exception:
                self._send(400, _mcp_error(None, -32700, "parse error"))
                return
            if isinstance(payload, list):
                out = [r for r in (_mcp_handle(m, real=True) for m in payload)
                       if r is not None]
                self._send(200, out)
                return
            resp = _mcp_handle(payload, real=True)
            if resp is None:
                self.send_response(202)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            self._send(200, resp)
            return

        if path.startswith("/real/tools/"):
            if not self._real_ok():
                return
            name = path[len("/real/tools/"):]
            if name not in REAL_TOOL_NAMES:
                # 404 + 明确文案：这是「本路径不提供」，不是「工具没实现」。
                # 两者混淆会让排查跑到工具注册表上，而真实原因只是走了别的路径。
                self._fail(404, "NOT_FOUND",
                           "REAL 路径不提供该工具：%s（仅 %s）"
                           % (name, "/".join(REAL_TOOL_NAMES)))
                return
            try:
                args = self._json_body()
            except _BodyTooLarge as exc:
                self._body_too_large(exc)
                return
            except Exception:
                self._fail(400, "INVALID_ARGUMENT", "请求体不是合法 JSON。")
                return
            if not isinstance(args, dict):
                self._fail(400, "INVALID_ARGUMENT", "请求体必须是对象。")
                return
            status, body = _real_call(name, args)
            self._send(status, body)
            return

        if path == "/mcp":
            if not self._auth_ok():
                return
            try:
                payload = self._json_body()
            except _BodyTooLarge as exc:
                self._body_too_large(exc)
                return
            except Exception:
                self._send(400, _mcp_error(None, -32700, "parse error"))
                return
            if isinstance(payload, list):          # 批量报文
                out = [r for r in (_mcp_handle(m) for m in payload) if r is not None]
                self._send(200, out)
                return
            resp = _mcp_handle(payload)
            if resp is None:                        # 通知：无 body
                self.send_response(202)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            self._send(200, resp)
            return

        if path == "/demo/confirm":
            # 演示确认：只允许管理口令调用，且响应里带 demo=true。
            if not self._admin_ok():
                return
            try:
                body = self._json_body()
            except _BodyTooLarge as exc:
                self._body_too_large(exc)
                return
            except Exception:
                self._fail(400, "INVALID_ARGUMENT", "请求体不是合法 JSON。")
                return
            aid = (body or {}).get("approval_id")
            if not aid:
                self._fail(400, "INVALID_ARGUMENT", "approval_id 必填。")
                return
            out = _demo_confirm(aid)
            if not out:
                self._fail(404, "NOT_FOUND", "找不到该审批请求。")
                return
            self._send(200, out)
            return

        if path.startswith("/tools/"):
            if not self._auth_ok():
                return
            name = path[len("/tools/"):]
            if name not in mock.TOOLS:
                self._fail(404, "NOT_FOUND", "工具不存在：%s" % name)
                return
            try:
                args = self._json_body()
            except _BodyTooLarge as exc:
                self._body_too_large(exc)
                return
            except Exception:
                self._fail(400, "INVALID_ARGUMENT", "请求体不是合法 JSON。")
                return
            if not isinstance(args, dict):
                self._fail(400, "INVALID_ARGUMENT", "请求体必须是对象。")
                return
            status, body, _entry = _call(name, args)
            self._send(status, body)
            return

        self._fail(404, "NOT_FOUND", "路径不存在。")

    def do_DELETE(self):
        self._fail(405, "INVALID_ARGUMENT", "不支持的方法。")


def _real_token_source():
    """令牌从哪来。三值而非 bool：排障时要区分「没配」和「配了但被运行时覆盖」。"""
    if _REAL_JWT_OVERRIDE["value"]:
        return "runtime"
    if REAL_JWT:
        return "env"
    return "none"


def _real_token_exp():
    """从 JWT 载荷里取 exp 转 ISO。**不验签**，只用于诊断。

    解析失败一律返回 None，不抛异常 —— `/health` 是探活端点，
    不能因为一个畸形令牌就整个 500。
    """
    tok = _current_real_jwt()
    if not tok:
        return None
    ok, detail = _looks_like_jwt(tok)
    if not ok or not isinstance(detail, dict):
        return None
    exp = detail.get("exp")
    if not isinstance(exp, (int, float)):
        return None
    try:
        return datetime.fromtimestamp(exp, timezone.utc).isoformat()
    except Exception:
        return None


def _scheduler_mode():
    """工具层实际走哪条路。**不探测引擎**，纯静态判定，保证 /health 不因回环探测变慢。

    MOCK              ：工具调用走 tools/m1-mock/tool_server.py（当前状态）
    REAL              ：工具调用已转发 M2 引擎（ENGINE_WIRED=1 且引擎已启用）
    MOCK_ENGINE_WIRED ：接线开关打开但引擎没启用——配置自相矛盾，必须显式暴露

    注意：REAL 只表示「转发已启用」，不表示引擎此刻可用。引擎存活看 /diag 的 engine.up。
    两件事分开报，免得把「进程在」误读成「链路通」。
    """
    if not ENGINE_WIRED:
        return "MOCK"
    if not ENGINE_ENABLED:
        return "MOCK_ENGINE_WIRED"
    return "REAL"


def _engine_status():
    """查容器内的 M2 引擎是否活着。只读，只走回环。"""
    import urllib.request
    st = {"enabled": ENGINE_ENABLED, "port": ENGINE_PORT,
          "entry": ENGINE_ENTRY, "entry_exists": os.path.exists(ENGINE_ENTRY),
          "pid": _ENGINE.get("pid"), "spawn_error": _ENGINE.get("error"),
          # 接线状态与进程状态分开报：前者是配置事实，后者要探测。
          "wired": ENGINE_WIRED, "scheduler_mode": _scheduler_mode()}
    if not ENGINE_ENABLED:
        return st
    try:
        with urllib.request.urlopen("http://127.0.0.1:%d/health" % ENGINE_PORT,
                                    timeout=5) as r:
            st["health"] = json.loads(r.read().decode("utf-8"))
            st["up"] = True
    except Exception as e:                                   # noqa: BLE001
        st["up"] = False
        st["health_error"] = type(e).__name__
    # 引擎日志尾部：起不来时唯一能定位原因的东西。只回最后 12 行。
    try:
        with open(os.path.join(os.getcwd(), "engine.log"), "rb") as f:
            lines = f.read().decode("utf-8", "replace").splitlines()[-12:]
        st["log_tail"] = lines
    except Exception:                                        # noqa: BLE001
        st["log_tail"] = []
    return st


def _start_engine():
    """把 M2 的 Dart 引擎拉到容器内回环上跑。失败不致命，但会被 /diag 如实暴露。

    只用相对路径 `dart run tools/m2-engine/bin/serve.dart`：M2 2026-11-05
    17:33:55Z 已确认这套包相对导入、不要 pubspec、不要 pub get。
    """
    import subprocess
    if not ENGINE_ENABLED:
        return
    if not os.path.exists(ENGINE_ENTRY):
        _ENGINE["error"] = "entry_missing"
        return
    env = dict(os.environ)
    env["M2_ENGINE_PORT"] = str(ENGINE_PORT)
    env.setdefault("M2_ENGINE_HOST", "127.0.0.1")
    try:
        log = open(os.path.join(os.getcwd(), "engine.log"), "ab")
        # 直接执行，不用 `dart run`：容器里没有 pubspec，`dart run` 会去找
        # package config 而失败；脚本本身只有相对导入，直接跑即可。
        p = subprocess.Popen(["dart", ENGINE_ENTRY], env=env,
                             stdout=log, stderr=log, cwd=os.getcwd())
        _ENGINE["pid"] = p.pid
        sys.stderr.write("engine: spawned pid=%d port=%d entry=%s\n"
                         % (p.pid, ENGINE_PORT, ENGINE_ENTRY))
    except Exception as e:                                   # noqa: BLE001
        _ENGINE["error"] = "%s: %s" % (type(e).__name__, e)
        sys.stderr.write("engine: spawn failed %s\n" % _ENGINE["error"])


def main():
    bind = os.environ.get("BIND", "127.0.0.1")
    port = int(os.environ.get("PORT", "8790"))
    _STATS["starts_at"] = _now()

    if not DEMO_TOKEN and not DEMO_TOKEN_SHA256:
        sys.stderr.write("WARN: CHECKD_DEMO_TOKEN / CHECKD_DEMO_TOKEN_SHA256 均未设置，"
                         "业务端点将全部拒答（fail-closed）。\n")
    if not ADMIN_KEY:
        sys.stderr.write("WARN: CHECKD_ADMIN_KEY 未设置，reset/evidence 已禁用。\n")
    if bind not in ("127.0.0.1", "localhost", "::1"):
        sys.stderr.write("WARN: 绑定 %s 非回环。仅限平台沙箱；本机运行请用默认值。\n" % bind)

    _start_engine()
    srv = ThreadingHTTPServer((bind, port), Handler)
    srv.daemon_threads = True
    sys.stderr.write("%s %s on %s:%d (tools=%d)\n"
                     % (SERVICE_NAME, SERVICE_VERSION, bind, port, len(mock.TOOLS)))
    sys.stderr.write("guard: body<=%d B, rate=%d/min (admin %d/min), timeout=%.0fs, health_minimal=%s\n"
                     % (MAX_BODY_BYTES, RATE_LIMIT_PER_MIN, RATE_LIMIT_ADMIN_PER_MIN,
                        SOCKET_TIMEOUT, HEALTH_MINIMAL))
    srv.serve_forever()


if __name__ == "__main__":
    main()
