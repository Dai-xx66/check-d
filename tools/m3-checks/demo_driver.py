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


def hr(ch="=", n=96):
    print(ch * n)


def title(text):
    print()
    hr()
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
        print("  [!] 冲突要说清哪一条违规、为什么；code 是 7 值闭集，集外即越界。")

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

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.terminate()
        except Exception:
            pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mock", required=True, help="M1 mock 的 tool_server.py 路径")
    a = ap.parse_args()
    d = Driver(a.mock)
    hr()
    print("  D4 B 轨录制驱动  |  连接 %s" % os.path.basename(d.mock_path))
    print("  mock sha256 = %s" % d.mock_sha)
    print("  演示窗口 %s ~ %s（含 10-30 15:00 外部固定会议）" % (RANGE["start"], RANGE["end"]))
    print("  镜号：1 2 3 3u 4 5 5a 5x 6 7 8      q = 退出")
    hr()
    table = {"1": d.shot1, "2": d.shot2, "3": d.shot3, "3u": d.shot3u, "4": d.shot4,
             "5": d.shot5, "5a": d.shot5a, "5x": d.shot5x, "6": d.shot6,
             "7": d.shot7, "8": d.shot8}
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
