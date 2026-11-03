#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""B 轨录制驱动：交互式逐镜调用 M1 mock（MCP over stdio），把真实响应打上屏。

为什么用驱动脚本而不是直接开 mock：
    mock 是 stdio 的 MCP 服务，人手动敲 JSON-RPC 不现实，也无法保证状态
    （proposal / approval / token / 幂等键）在 8 镜之间连续。本脚本保持单一
    长驻进程，状态天然连续；每一镜只做该镜的调用，屏幕上能看到 request_id、
    proposal_id、error.code、details 等断言字段。

用法：
    python tools/m3-checks/demo_driver.py --mock <path>/tools/m1-mock/tool_server.py

    进入交互后输入镜号回车即执行该镜：
      1  片头：initialize + tools/list（7/7 工具）
      2  只读：list_tasks + get_calendar_events
      3  提案：generate_schedule（draft / changes / blocks / explanations / expires_at）
      3u （选做）排不下的样子：把可用窗口压窄，看 unplanned_tasks + reason_code
      4  校验：validate_schedule（valid / pending_approval）
      5  审批：request_approval -> pending（无 Token）
      5a 外部审批页批准 -> 首次交付一次性 Token（打码）
      5x （选做）取消路径：另一条提案被拒 -> APPROVAL_REJECTED，写入增量 0
      6  写入：apply（simulate_applying_crash）-> READBACK_PENDING + applying + delta 0
      7  回读：再 list_tasks 逐条对比，固定课程未动，写入计数 0
      8  防重：同键重试 -> IDEMPOTENCY_IN_PROGRESS；换新键 -> READBACK_PENDING delta 0
    q  退出

场景（与 fixture 一致的内置数据）：
    任务 t_1001 实验报告（截止 2026-10-31 18:00）、t_1002 六级听力（截止 11-02）、
    t_1003 背单词（每日 30 分钟）、t_1004 线代（每日 60 分钟）；课程 c_2001 离散数学
    每周四 08:00-09:40。演示窗口取 2026-10-29 ~ 11-01，并在 10-30 15:00-16:30
    插入一个外部固定会议（不可移动）。

边界（录制时必须一起说）：
    全部为 Mock 后端行为，不代表真实端点、真实审批、生产回读已验证。
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import uuid

API_VERSION = "checkd.agent.v1"
TZ = "Asia/Shanghai"
RANGE = {"start": "2026-10-29", "end": "2026-11-01"}
MEETING = {
    "external_event_id": "ext_meeting_1030",
    "title": "临时会议（外部日历）",
    "start_at": "2026-10-30T15:00:00+08:00",
    "end_at": "2026-10-30T16:30:00+08:00",
}
PREFS = {"day_start_minute": 480, "day_end_minute": 1350, "minimum_block_minutes": 25}

# M0 裁定：全程角标 + 片头全屏。做进画面而不是贴窗口，避免录制中切换窗口导致时间轴断裂。
BANNER = "[MOCK · 非真实写入]  非真实业务端点 / 不产生真实写入"

# 片头卡上要写清「按哪个契约返回」。契约 SHA 不得硬编码：滚动换契约时
# 画面里写错 SHA 等于误述，由 --contract-sha 注入，默认取当前冻结值。
DEFAULT_CONTRACT_SHA = "39f7f96559abac9d4bc59d5c560e6a706ec19946"
CONTRACT_SHA = DEFAULT_CONTRACT_SHA


def intro_text():
    short = CONTRACT_SHA[:8]
    return r"""
   ███╗   ███╗ ██████╗  ██████╗██╗  ██╗
   ████╗ ████║██╔═══██╗██╔════╝██║ ██╔╝
   ██╔████╔██║██║   ██║██║     █████╔╝
   ██║╚██╔╝██║██║   ██║██║     ██╔═██╗
   ██║ ╚═╝ ██║╚██████╔╝╚██████╗██║  ██╗
   ╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝

        非真实写入 · 非真实业务端点 · 非生产环境

   本段为 B 轨 Mock 环境流程演示，画面中的响应体
   由 Mock 服务按契约 {sha} 返回，不是真实后端。
""".format(sha=CONTRACT_SHA)


INTRO = intro_text()
CLOSING = """
收尾声明（必须念）：
  「以上全部为 Mock 环境流程演示；真实写入、真实审批、
    生产回读仍为 BLOCKED，待 A 轨补录。」
"""


def hr(ch="=", n=96):
    print(ch * n)


def title(text):
    print()
    hr()
    print("  " + BANNER)
    print("  " + text)
    hr()


def kv(k, v, width=24):
    print("  %-*s : %s" % (width, k, v))


def mask(token):
    if not token:
        return "(none)"
    return token[:8] + "*" * 8 + token[-4:]


def _win_path(p):
    """把 Git Bash 的 /c/Users/... 转成 Windows 的 C:/Users/...（仅 Windows）。"""
    if os.name == "nt":
        m = re.match(r"^/([A-Za-z])/(.*)$", p)
        if m:
            return m.group(1).upper() + ":/" + m.group(2)
    return p


class Driver:
    def __init__(self, mock_path):
        self.mock_path = os.path.abspath(_win_path(mock_path))
        raw = open(self.mock_path, "rb").read()
        self.mock_sha = hashlib.sha256(raw).hexdigest()
        self.tmp = tempfile.mkdtemp(prefix="d4_demo_")
        self.approval_file = os.path.join(self.tmp, "approvals.json")
        self.flags_file = os.path.join(self.tmp, "flags.json")
        for p in (self.approval_file, self.flags_file):
            with open(p, "w", encoding="utf-8") as f:
                json.dump({}, f)
        env = dict(os.environ)
        env.update({
            "PYTHONIOENCODING": "utf-8",
            "CHECKD_TOKEN": "demo-token-alice",
            "MOCK_APPROVAL_FILE": self.approval_file,
            "MOCK_TEST_FLAGS": self.flags_file,
        })
        self.proc = subprocess.Popen(
            [sys.executable, self.mock_path], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env,
            text=True, encoding="utf-8", bufsize=1)
        self._id = 0
        self.s = {}

    # ---------------------------------------------------------- MCP plumbing
    def rpc(self, method, params=None):
        self._id += 1
        mid = self._id
        self.proc.stdin.write(json.dumps(
            {"jsonrpc": "2.0", "id": mid, "method": method, "params": params or {}},
            ensure_ascii=False) + "\n")
        self.proc.stdin.flush()
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError("mock 已关闭 stdout")
            msg = json.loads(line)
            if msg.get("id") == mid:
                return msg

    def notify(self, method, params=None):
        """通知类消息不占 id，服务端不回包，不能等。"""
        self.proc.stdin.write(json.dumps(
            {"jsonrpc": "2.0", "method": method, "params": params or {}},
            ensure_ascii=False) + "\n")
        self.proc.stdin.flush()

    def call(self, tool, inp, tag=""):
        rid = "req_" + uuid.uuid4().hex[:12]
        args = {"api_version": API_VERSION, "request_id": rid, "timezone": TZ, "input": inp}
        print("  -> tools/call %s   request_id=%s" % (tool, rid))
        if tag:
            print("     入参：%s" % tag)
        r = self.rpc("tools/call", {"name": tool, "arguments": args})
        body = (r.get("result") or {}).get("structuredContent") or {}
        return rid, body

    # ------------------------------------------------------------- helpers
    def writes(self):
        try:
            return json.load(open(self.flags_file, encoding="utf-8")).get("writes", 0)
        except Exception:
            return 0

    def set_flag(self, name, value):
        data = {}
        try:
            data = json.load(open(self.flags_file, encoding="utf-8"))
        except Exception:
            pass
        data[name] = value
        with open(self.flags_file, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)

    def approve_externally(self, aid, status="approved"):
        data = {}
        try:
            data = json.load(open(self.approval_file, encoding="utf-8"))
        except Exception:
            pass
        rec = data.setdefault(aid, {})
        rec["status"] = status
        with open(self.approval_file, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
        print("  ~~ 外部审批页动作：%s -> %s（模拟用户在审批页点「%s」）"
              % (aid, status, "确认" if status == "approved" else "取消"))

    @staticmethod
    def brief(body):
        st = body.get("status")
        if st == "success":
            return "status=success"
        e = body.get("error") or {}
        return "status=error code=%s retryable=%s" % (e.get("code"), e.get("retryable"))

    # ---------------------------------------------------------------- shots
    def shot0(self):
        """片头卡：停满 3 秒再往下走（M0 纪律第 1 条）。"""
        print(intro_text())
        print("  " + BANNER)
        print("  ↑ 片头卡：请停满 3 秒再说第一句。")
        hr()
        print("  第一句（必须说）：「本段演示使用 Mock 后端，不是真实业务端点，不产生真实写入。」")
        print("  第二句（本机实况）：「任务窗尚未接入 Mock，下面由驱动脚本直接向同一个 Mock 发起调用，")
        print("                        响应体是真实返回，不是回放。」")
        hr()

    def shot1(self):
        title("镜 1/8  片头：工具已加载（MOCK · 非真实写入）")
        r = self.rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                                    "clientInfo": {"name": "d4-demo-driver", "version": "1.0"}})
        info = (r.get("result") or {}).get("serverInfo") or {}
        self.notify("notifications/initialized")
        tl = self.rpc("tools/list", {})
        tools = (tl.get("result") or {}).get("tools") or []
        kv("server", "%s %s" % (info.get("name"), info.get("version")))
        kv("tools loaded", "%d/7" % len(tools))
        kv("mock file", os.path.basename(self.mock_path))
        kv("mock sha256", self.mock_sha)
        print("  工具：%s" % ", ".join(t["name"] for t in tools))
        print()
        print("  [!] 本段演示使用 Mock 后端，不是真实业务端点，不产生真实写入。")

    def shot2(self):
        title("镜 2/8  只读调用：list_tasks + get_calendar_events")
        rid1, b1 = self.call("list_tasks", {"date_range": RANGE},
                             "%s ~ %s" % (RANGE["start"], RANGE["end"]))
        d1 = b1.get("data") or {}
        kv("list_tasks", self.brief(b1))
        kv("  request_id", rid1)
        kv("  query_version", (d1.get("query_version") or "")[:16] + "...")
        tasks = d1.get("tasks") or []
        kv("  tasks", "%d 条" % len(tasks))
        for t in tasks:
            kv("    " + str(t.get("task_id")), "%s [%s]" % (t.get("name"), t.get("kind")))
        self.s["tasks_before"] = {
            t["task_id"]: (t.get("planned_date"), t.get("scheduled_at")) for t in tasks}

        rid2, b2 = self.call("get_calendar_events", {"date_range": RANGE}, "同一窗口")
        d2 = b2.get("data") or {}
        kv("get_calendar_events", self.brief(b2))
        kv("  request_id", rid2)
        kv("  courses", "%d 门" % len(d2.get("courses") or []))
        ev = d2.get("events") or []
        kv("  events", "%d 个（固定 %d）" % (len(ev), sum(1 for e in ev if e.get("fixed"))))
        for e in ev[:5]:
            kv("    " + str(e.get("event_type")),
               "%s %s→%s fixed=%s" % (str(e.get("date")), str(e.get("start_at"))[11:16],
                                      str(e.get("end_at"))[11:16], e.get("fixed")))
        print()
        print("  [!] 这两个是只读调用，不是我编的提示词。")

    def shot3(self):
        title("镜 3/8  提案：generate_schedule（只读，不写入）")
        rid, b = self.call("generate_schedule",
                           {"date_range": RANGE, "external_fixed_events": [MEETING],
                            "preferences": PREFS},
                           "含外部固定会议 10-30 15:00-16:30")
        d = b.get("data") or {}
        kv("generate_schedule", self.brief(b))
        kv("  request_id", rid)
        kv("  proposal_id", d.get("proposal_id"))
        kv("  status", d.get("status"))
        kv("  base_version", (d.get("base_version") or "")[:16] + "...")
        ch = d.get("changes") or []
        by_type = {}
        for c in ch:
            by_type[c.get("type")] = by_type.get(c.get("type"), 0) + 1
        kv("  changes", "%d 条 %s" % (len(ch), by_type))
        blocks = d.get("blocks") or []
        kv("  blocks", "%d 块（合计 %d 分钟）"
           % (len(blocks), sum(int(x.get("duration_seconds") or 0) for x in blocks) // 60))
        for bl in blocks[:3]:
            kv("    " + str(bl.get("task_id")),
               "%s→%s" % (str(bl.get("start_at"))[:16].replace("T", " "),
                          str(bl.get("end_at"))[11:16]))
        un = d.get("unplanned_tasks") or []
        kv("  unplanned_tasks", "%d 条" % len(un))
        for u in un[:3]:
            kv("    " + str(u.get("task_id")), "reason_code=%s" % u.get("reason_code"))
        kv("  explanations", ", ".join(e.get("code") for e in d.get("explanations") or []))
        kv("  expires_at", d.get("expires_at"))
        self.s["pid"] = d.get("proposal_id")
        self.s["base_version"] = d.get("base_version")
        print()
        print("  [!] 这是提案，不是写入；排不下的进 unplanned_tasks 并给 reason_code。")

    def shot3u(self):
        title("镜 3u（选做）排不下的样子：把可用窗口压到 20:00-22:30 → unplanned_tasks")
        rid, b = self.call("generate_schedule",
                           {"date_range": RANGE, "external_fixed_events": [MEETING],
                            "preferences": {"day_start_minute": 1200,
                                            "day_end_minute": 1350,
                                            "minimum_block_minutes": 25}},
                           "窗口 20:00-22:30，刻意压窄")
        d = b.get("data") or {}
        kv("generate_schedule", self.brief(b))
        kv("  proposal_id", d.get("proposal_id"))
        un = d.get("unplanned_tasks") or []
        kv("  unplanned_tasks", "%d 条" % len(un))
        for u in un:
            kv("    " + str(u.get("task_id")),
               "%s / 缺 %s 分钟 / %s" % (u.get("reason_code"), u.get("remaining_minutes"),
                                        str(u.get("message"))[:24]))
        kv("  explanations", ", ".join(e.get("code") for e in d.get("explanations") or []))
        print()
        print("  [!] 排不下就明说排不下，给 reason_code，不硬塞、不静默丢弃。")
        test = self.call("validate_schedule", {"proposal_id": d.get("proposal_id")},
                         "看这条提案能不能进审批")[1]
        dd = test.get("data") or {}
        kv("  validate", "validation=%s / approval=%s"
           % (dd.get("validation_status"), dd.get("approval_status")))

    def shot4(self):
        pid = self.s.get("pid")
        title("镜 4/8  校验：validate_schedule")
        rid, b = self.call("validate_schedule", {"proposal_id": pid}, "proposal_id=%s" % pid)
        d = b.get("data") or {}
        kv("validate_schedule", self.brief(b))
        kv("  request_id", rid)
        kv("  validation_status", d.get("validation_status"))
        kv("  proposal_status", d.get("proposal_status"))
        kv("  approval_status", d.get("approval_status"))
        vio = d.get("violations") or []
        kv("  violations", "%d 条" % len(vio))
        for v in vio[:5]:
            kv("    " + str(v.get("code")), "task_id=%s" % v.get("task_id"))
        print()
        print("  [!] 冲突要说清哪一条违规、为什么；code 是 8 值闭集（含 BLOCK_OVERLAP），集外即越界。")

    def shot5(self):
        pid = self.s.get("pid")
        title("镜 5/8  审批：request_approval -> pending（此时没有 Token）")
        rid, b = self.call("request_approval",
                           {"proposal_id": pid, "idempotency_key": "idem-approval-001"},
                           "idempotency_key=idem-approval-001")
        d = b.get("data") or {}
        kv("request_approval", self.brief(b))
        kv("  approval_id", d.get("approval_id"))
        kv("  status", d.get("status"))
        kv("  approval_url", d.get("approval_url"))
        kv("  expires_at", d.get("expires_at"))
        self.s["aid"] = d.get("approval_id")

        rid2, b2 = self.call("get_approval_status", {"approval_id": self.s["aid"]},
                             "批准前轮询")
        d2 = b2.get("data") or {}
        kv("get_approval_status", self.brief(b2))
        kv("  status", d2.get("status"))
        kv("  approval_token", d2.get("approval_token") or "(none)")
        print()
        print("  [!] 用户不点确认，数据库一个字节都不变。")
        print("  下一步输入 5a：让外部审批页批准，再取 Token。")

    def shot5a(self):
        aid = self.s.get("aid")
        if not aid:
            print("  先执行镜 5。")
            return
        title("镜 5a  外部审批页批准 -> 首次交付一次性 Token")
        self.approve_externally(aid, "approved")
        rid, b = self.call("get_approval_status", {"approval_id": aid}, "批准后首次轮询")
        d = b.get("data") or {}
        kv("get_approval_status", self.brief(b))
        kv("  status", d.get("status"))
        tok = d.get("approval_token")
        kv("  approval_token", mask(tok))
        kv("  token_expires_at", d.get("token_expires_at"))
        self.s["token"] = tok
        print()
        print("  [!] Token 只在批准后首次交付，且一次性；屏幕已打码。")

    def shot5x(self):
        title("镜 5x（选做）取消路径：另一条提案被拒 -> APPROVAL_REJECTED，写入增量 0")
        w0 = self.writes()
        d = self.call("generate_schedule",
                      {"date_range": RANGE, "preferences": PREFS}, "第二条提案（用于演示取消）")[1]
        pid2 = (d.get("data") or {}).get("proposal_id")
        kv("新 proposal_id", pid2)
        self.call("validate_schedule", {"proposal_id": pid2}, "先校验")
        rb = self.call("request_approval",
                       {"proposal_id": pid2, "idempotency_key": "idem-approval-002"})[1]
        aid2 = (rb.get("data") or {}).get("approval_id")
        kv("approval_id", aid2)
        self.approve_externally(aid2, "rejected")
        b3 = self.call("apply_approved_changes",
                       {"proposal_id": pid2,
                        "base_version": (d.get("data") or {}).get("base_version"),
                        "approval_token": "tok_rejected_demo",
                        "idempotency_key": "idem-reject-001"},
                       "被拒后强行 apply")[1]
        e3 = b3.get("error") or {}
        kv("apply", self.brief(b3))
        kv("  code", e3.get("code"))
        kv("  message", e3.get("message"))
        kv("写入计数 delta", self.writes() - w0)
        print()
        print("  [!] 取消就是取消：被拒后写入增量 0，不留半截写入。")

    def shot6(self):
        pid = self.s.get("pid")
        title("镜 6/8  写入：apply（幂等键 + 一次 Token）-> READBACK_PENDING / applying")
        w0 = self.writes()
        self.set_flag("simulate_applying_crash", True)
        print("  ~~ 测试标志：simulate_applying_crash（Mock 专用：写入后进程崩溃、结果未知）")
        rid, b = self.call("apply_approved_changes",
                           {"proposal_id": pid,
                            "base_version": self.s.get("base_version"),
                            "approval_token": self.s.get("token"),
                            "idempotency_key": "idem-demo-001"},
                           "idempotency_key=idem-demo-001 / 单次 Token")
        e = b.get("error") or {}
        kv("apply", self.brief(b))
        kv("  request_id", rid)
        kv("  error.code", e.get("code"))
        kv("  error.message", str(e.get("message"))[:30])
        kv("  error.retryable", e.get("retryable"))
        for dt in e.get("details") or []:
            kv("  details." + str(dt.get("field")), dt.get("reason"))
        kv("服务端写入计数 delta", self.writes() - w0)
        ok = (e.get("code") == "READBACK_PENDING" and e.get("retryable") is True
              and any(x.get("field") == "proposal_status" and x.get("reason") == "applying"
                      for x in e.get("details") or []))
        print()
        print("  [%s] 断言：code=READBACK_PENDING / retryable=true / "
              "details.proposal_status=applying / delta=0" % ("PASS" if ok else "FAIL"))
        print("  [!] 这是 Mock 按契约给出的断言，不代表真实端点已验证。")

    def shot7(self):
        title("镜 7/8  回读：再调 list_tasks，与写入前逐条对比")
        rid, b = self.call("list_tasks", {"date_range": RANGE}, "同一窗口再读一次")
        d = b.get("data") or {}
        kv("list_tasks", self.brief(b))
        kv("  request_id", rid)
        before = self.s.get("tasks_before") or {}
        moved, same = [], 0
        for t in d.get("tasks") or []:
            now_v = (t.get("planned_date"), t.get("scheduled_at"))
            old_v = before.get(t["task_id"])
            if old_v is None:
                continue
            if now_v == old_v:
                same += 1
            else:
                moved.append((t["task_id"], old_v, now_v))
        kv("逐条一致", "%d/%d" % (same, len(before)))
        kv("发生变化的条目", "%d 条" % len(moved))
        for tid, o, nv in moved:
            kv("    " + tid, "%s -> %s" % (o, nv))
        kv("服务端写入计数", self.writes())
        print()
        print("  [!] 崩溃路径停在 applying，同键只回 IDEMPOTENCY_IN_PROGRESS；")
        print("      这条路径没有完成收敛，我不会说成已收敛。")

    def shot8(self):
        pid = self.s.get("pid")
        title("镜 8/8  防重：同键重试 vs 换新键")
        w0 = self.writes()
        b1 = self.call("apply_approved_changes",
                       {"proposal_id": pid,
                        "base_version": self.s.get("base_version"),
                        "approval_token": self.s.get("token"),
                        "idempotency_key": "idem-demo-001"},
                       "同键 idem-demo-001 重试")[1]
        e1 = b1.get("error") or {}
        kv("同键重试", self.brief(b1))
        kv("  code", e1.get("code"))
        kv("  retryable", e1.get("retryable"))
        kv("  delta", self.writes() - w0)
        print()
        b2 = self.call("apply_approved_changes",
                       {"proposal_id": pid,
                        "base_version": self.s.get("base_version"),
                        "approval_token": self.s.get("token"),
                        "idempotency_key": "idem-demo-002"},
                       "换新键 idem-demo-002")[1]
        e2 = b2.get("error") or {}
        kv("换新键", self.brief(b2))
        kv("  code", e2.get("code"))
        kv("  details", ", ".join("%s=%s" % (x.get("field"), x.get("reason"))
                                  for x in e2.get("details") or []))
        kv("  delta", self.writes() - w0)
        print()
        print("  [!] 这就是防重复写入的三道闸：同键幂等 / 换键仍拦 / 执行中不二次写。")

    def shotfin(self):
        title("收尾：声明边界（念完即可停止录制）")
        print(CLOSING)

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.terminate()
        except Exception:
            pass


# --------------------------------------------------------------- 提词（旁白稿）
# 自动播放时逐镜显示，录制者照着念；同时充当画面字幕。
# 用词与 docs/demo/b-track-recording-card-20261103.md 逐句对应，改稿请同步改卡。
NARRATION = {
    "0": ["本段演示使用 Mock 后端，不是真实业务端点，不产生真实写入。",
          "WorkBuddy 任务窗尚未接入 Mock，下面由驱动脚本直接向同一个 Mock 发起调用，",
          "屏幕上看到的是真实返回的 request_id 与响应体，不是回放。"],
    "1": ["本镜验证：Agent 已连上 Mock，工具清单 7 个都在。",
          "教育场景：一周学习计划，含固定课程与一次临时会议。工具已加载 7 个。"],
    "2": ["本镜验证：任务和课表是从 Mock 真读出来的，不是提示词编的。",
          "这两个是只读调用，不是我编的提示词；每条都带独立 request_id。"],
    "3": ["本镜验证：一句需求被整理成结构化提案，不是嘴上说已拆解。",
          "这是提案，不是写入。",
          "排不下的进 unplanned_tasks 并给 reason_code，不硬塞、不静默丢弃。",
          "提案会过期，expires_at 就是它的寿命。"],
    "3u": ["本镜验证：排不下的时候它明说排不下，不硬塞。",
           "把可用窗口压窄，排不下就明说排不下，给 reason_code。"],
    "4": ["本镜验证：冲突能被指到具体哪一条、为什么。",
          "冲突要说清哪一条违规、为什么。违规码是 8 值闭集，含 BLOCK_OVERLAP，集外即越界。"],
    "5": ["本镜验证：没点确认之前，什么都改不了。",
          "用户不在审批页点确认，数据库一个字节都不变。此时拿不到 Token。",
          "本段为 Mock 演示，不构成真实身份认证，也不构成真实用户授权。"],
    "5a": ["本镜验证：Token 只在批准后一次性交付，屏幕已打码。",
           "Token 只在批准后首次交付，且一次性；屏幕已打码。"],
    "5x": ["本镜验证：取消就是取消，不留半截写入。",
           "取消就是取消：被拒后写入增量 0，不留半截写入。"],
    "6": ["本镜验证：写一次就只写一次；未终局就如实说未终局。",
          "写入次数只有一次。重复点、换键、执行中重试，都拿到零写入的确定性错误。",
          "这是 Mock 按契约给出的断言，不代表真实端点已验证。"],
    "7": ["本镜验证：回读一致才算成功；崩溃路径不假装已收敛。",
          "回读一致才叫成功。",
          "崩溃路径停在 applying、同键只回 IDEMPOTENCY_IN_PROGRESS。",
          "这条路径没有收敛，我不说成已收敛。"],
    "8": ["本镜验证：三道闸各拦一次。",
          "这就是防重复写入的三道闸：同键幂等、换键仍拦、执行中不二次写。"],
    "fin": ["以上全部为 Mock 环境流程演示；真实写入、真实审批、生产回读仍为 BLOCKED，待 A 轨补录。"],
}
AUTO_SEQ = ["0", "1", "2", "3", "4", "5", "5a", "6", "7", "8", "fin"]


def teleprompt(key):
    lines = NARRATION.get(key) or []
    if not lines:
        return
    print()
    print("  " + "-" * 92)
    print("  【旁白 · 照念】")
    for ln in lines:
        print("    " + ln)
    print("  " + "-" * 92)


def run_auto(d, table, seq, lead, hold, start_delay):
    import time
    print()
    print("  自动播放：%s" % " → ".join(seq))
    print("  每镜节奏：显示镜号 → 执行（画面出结果）→ 显示旁白 → 停留 %ds 换镜" % hold)
    if start_delay:
        print("  录制软件就位后，%d 秒后自动开始……" % start_delay)
        time.sleep(start_delay)
    t0 = time.time()
    stamp = []
    for i, key in enumerate(seq, 1):
        el = time.time() - t0
        print()
        print("=" * 96)
        print("  [自动 %d/%d]  镜 %s   录制内时间 %02d:%05.2f" % (i, len(seq), key, int(el) // 60, el % 60))
        print("=" * 96)
        fn = table.get(key)
        if fn is None:
            print("  未知镜号，跳过：%s" % key)
            continue
        if lead:
            time.sleep(lead)
        try:
            fn()
        except Exception as exc:
            print("  [执行异常] %s: %s" % (type(exc).__name__, exc))
            print("  现场已保留，按纪律不重来、不掩盖，继续下一镜。")
        teleprompt(key)
        stamp.append((key, time.time() - t0))
        if hold:
            # 停留倒计时：让录制者看得到还剩几秒，不必猜节奏。
            n = max(1, int(round(hold)))
            for s in range(n, 0, -1):
                sys.stdout.write("\r     [停留 %2ds]  念完就等，不要碰键盘……" % s)
                sys.stdout.flush()
                time.sleep(1)
            sys.stdout.write("\r" + " " * 64 + "\r")
            sys.stdout.flush()
    print()
    hr()
    print("  自动播放结束。各镜录制内时间点（写进交付说明用）：")
    for key, t in stamp:
        print("    镜 %-4s %02d:%05.2f" % (key, int(t) // 60, t % 60))
    print("  画面可停止录制；确认自检 8 条后归档到 docs/demo/evidence/b-track-20261103/")
    hr()


def main():
    global CONTRACT_SHA
    ap = argparse.ArgumentParser()
    ap.add_argument("--mock", required=True, help="M1 mock 的 tool_server.py 路径")
    ap.add_argument("--contract-sha", default=DEFAULT_CONTRACT_SHA,
                    help="录制所用契约 commit（写在片头卡上，默认当前冻结值）")
    ap.add_argument("--auto", action="store_true",
                    help="自动按 0→1→2→3→4→5→5a→6→7→8→fin 播放，无需键入镜号")
    ap.add_argument("--lead", type=float, default=2.0,
                    help="每镜执行前的静置秒数（默认 2）")
    ap.add_argument("--hold", type=float, default=20.0,
                    help="每镜旁白出现后停留秒数，给你念完的时间（默认 20，屏幕上会倒计时）")
    ap.add_argument("--start-delay", type=float, default=10.0,
                    help="自动播放启动倒计时秒数（默认 10，留时间按录制键）")
    ap.add_argument("--seq", default="",
                    help="自定义镜序，逗号分隔，如 1,2,3,4,5,5a,6,7,8")
    a = ap.parse_args()
    CONTRACT_SHA = a.contract_sha
    d = Driver(a.mock)
    hr()
    print("  D4 B 轨录制驱动  |  连接 %s" % os.path.basename(d.mock_path))
    print("  mock sha256 = %s" % d.mock_sha)
    print("  契约 commit = %s" % CONTRACT_SHA)
    print("  演示窗口 %s ~ %s（含 10-30 15:00 外部固定会议）" % (RANGE["start"], RANGE["end"]))
    print("  镜号：0 片头卡 | 1 2 3 3u 4 5 5a 5x 6 7 8 | fin 收尾      q = 退出")
    hr()
    table = {"0": d.shot0, "1": d.shot1, "2": d.shot2, "3": d.shot3, "3u": d.shot3u,
             "4": d.shot4, "5": d.shot5, "5a": d.shot5a, "5x": d.shot5x, "6": d.shot6,
             "7": d.shot7, "8": d.shot8, "fin": d.shotfin}
    if a.auto:
        seq = [s.strip() for s in a.seq.split(",") if s.strip()] or AUTO_SEQ
        try:
            run_auto(d, table, seq, a.lead, a.hold, a.start_delay)
        finally:
            d.close()
        return
    try:
        while True:
            try:
                cmd = input("\n镜> ").strip()
            except EOFError:
                break
            if not cmd:
                continue
            if cmd in ("q", "quit", "exit"):
                break
            fn = table.get(cmd)
            if fn is None:
                print("  未知指令：%s（可用：%s）" % (cmd, " ".join(table)))
                continue
            try:
                fn()
            except Exception as exc:
                print("  [执行异常] %s: %s" % (type(exc).__name__, exc))
    finally:
        d.close()
        print("\n  驱动已退出（mock 进程已关闭）。")


if __name__ == "__main__":
    main()
