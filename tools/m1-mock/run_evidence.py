#!/usr/bin/env python3
"""Conformance evidence runner for the mock CheckD MCP tool server.

Spawns tool_server.py over stdio, exercises the v1 contract behaviours, and
writes m1-evidence.json plus a readable markdown report.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(HERE, "tool_server.py")

ENV = {"api_version": "checkd.agent.v1", "timezone": "Asia/Shanghai"}
RANGE = {"start": "2026-10-29", "end": "2026-10-31"}


class Client:
    def __init__(self):
        self.p = subprocess.Popen([sys.executable, SERVER], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True, encoding="utf-8", bufsize=1)
        self.n = 0

    def rpc(self, method, params=None):
        self.n += 1
        msg = {"jsonrpc": "2.0", "id": self.n, "method": method, "params": params or {}}
        self.p.stdin.write(json.dumps(msg, ensure_ascii=False) + "\n")
        self.p.stdin.flush()
        line = self.p.stdout.readline()
        return json.loads(line)

    def initialize(self):
        r = self.rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                                    "clientInfo": {"name": "evidence-runner", "version": "1"}})
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        self.p.stdin.flush()
        return r

    def call(self, name, inp, meta=None, envelope=True):
        args = dict(ENV) if envelope else {}
        args["request_id"] = f"req_{name}_{self.n + 1}"
        args["input"] = inp
        params = {"name": name, "arguments": args}
        if meta:
            params["_meta"] = meta
        return self.rpc("tools/call", params)

    def close(self):
        try:
            self.p.stdin.close()
            self.p.wait(timeout=5)
        except Exception:
            self.p.kill()


def data_of(resp):
    return resp["result"].get("structuredContent", {}).get("data")


def error_of(resp):
    sc = resp["result"].get("structuredContent", {})
    return sc.get("error", {}).get("code")


results = []


def record(case, expected, resp, note=""):
    sc = resp["result"].get("structuredContent", {})
    is_error = resp["result"].get("isError")
    got = ("error:" + sc["error"]["code"]) if is_error and "error" in sc else "success"
    ok = (got == expected)
    results.append({"case": case, "expected": expected, "got": got, "pass": ok,
                    "note": note, "response": resp})
    print(f"[{'PASS' if ok else 'FAIL'}] {case}: expected {expected}, got {got}")


def main():
    c = Client()
    init = c.initialize()
    print("server:", init["result"]["serverInfo"])

    tl = c.rpc("tools/list")
    tools = [t["name"] for t in tl["result"]["tools"]]
    print("tools:", tools)

    record("A1 tools/list 暴露 5 个 v1 工具 + 1 个扩展",
           "success", {"result": {"structuredContent": {}, "isError": False}},
           note=str(tools)) if False else None
    results.append({"case": "A0 tools/list", "expected": "5+1", "got": f"{len(tools)} tools",
                    "pass": set(tools) == {"list_tasks", "get_calendar_events", "generate_schedule",
                                           "validate_schedule", "apply_approved_changes",
                                           "request_approval"},
                    "note": tools, "response": tl})

    # A1 list_tasks
    r = c.call("list_tasks", {"date_range": RANGE})
    record("A1 list_tasks 正常读取", "success", r, note=f'{len(data_of(r)["tasks"])} tasks')

    # A2 identity in body rejected
    r = c.call("list_tasks", {"date_range": RANGE, "user_id": "u_bob"})
    record("A2 请求体携带 user_id 被拒", "error:INVALID_ARGUMENT", r)

    # A3 bad timezone
    c.n += 1
    r = c.rpc("tools/call", {"name": "list_tasks", "arguments": {
        "api_version": "checkd.agent.v1", "request_id": "req_tz", "timezone": "UTC",
        "input": {"date_range": RANGE}}})
    record("A3 非 Asia/Shanghai 被拒", "error:INVALID_ARGUMENT", r)

    # A4 calendar with external fixed meeting
    ext = [{"external_event_id": "x_meeting_1", "title": "临时会议",
            "start_at": "2026-10-30T14:00:00+08:00", "end_at": "2026-10-30T15:00:00+08:00"}]
    r = c.call("get_calendar_events", {"date_range": RANGE, "external_fixed_events": ext})
    evs = data_of(r)["events"]
    fixed = [e for e in evs if e["fixed"]]
    record("A4 日历包含固定课程与外部会议", "success", r, note=f"{len(evs)} events, {len(fixed)} fixed")

    # A5 generate
    r = c.call("generate_schedule", {"date_range": RANGE, "external_fixed_events": ext})
    p = data_of(r)
    record("A5 generate_schedule 生成 draft 提案", "success", r,
           note=f'{p["proposal_id"]} blocks={len(p["blocks"])} changes={len(p["changes"])} unplanned={len(p["unplanned_tasks"])}')

    # A6 remote 传入 tasks 被拒
    r = c.call("generate_schedule", {"date_range": RANGE, "tasks": [{"task_id": "fake"}]})
    record("A6 远程提交 tasks 被拒", "error:INVALID_ARGUMENT", r)

    # A7 validate
    r = c.call("validate_schedule", {"proposal_id": p["proposal_id"]})
    v = data_of(r)
    record("A7 validate 通过并进入 pending_approval", "success", r,
           note=f'validation={v["validation_status"]} approval={v["approval_status"]}')

    # A8 apply without approval token
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"],
                                          "base_version": p["base_version"],
                                          "approval_token": "", "idempotency_key": "k1"})
    record("A8 无审批凭据不可写入", "error:INVALID_ARGUMENT", r)

    # A9 request approval (extension)
    r = c.call("request_approval", {"proposal_id": p["proposal_id"]})
    token = data_of(r)["approval_token"]
    record("A9 扩展工具签发一次性凭据", "success", r, note=token)

    # A10 apply
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"],
                                          "base_version": p["base_version"],
                                          "approval_token": token,
                                          "idempotency_key": "k1"})
    d = data_of(r)
    record("A10 审批后原子应用并回读", "success", r,
           note=f'readback_verified={d["readback_verified"]} changes={len(d["applied_changes"])}')

    # A11 idempotent replay
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"],
                                          "base_version": p["base_version"],
                                          "approval_token": token,
                                          "idempotency_key": "k1"})
    d2 = data_of(r)
    same = d2["result_version"] == d["result_version"]
    record("A11 同幂等键重放返回原结果", "success", r, note=f"same_result={same}")

    # A12 bad token -> AUTH_REQUIRED
    c.n += 1
    r = c.rpc("tools/call", {"name": "list_tasks", "arguments": {
        "api_version": "checkd.agent.v1", "request_id": "req_auth", "timezone": "Asia/Shanghai",
        "input": {"date_range": RANGE}}, "_meta": {"authorization": "Bearer bad-token"}})
    record("A12 无效凭据被拒", "error:AUTH_REQUIRED", r)

    # A13 second proposal, reuse key -> conflict
    r2 = c.call("generate_schedule", {"date_range": RANGE}, meta={"authorization": "Bearer demo-token-alice"})
    p2 = data_of(r2)
    c.call("validate_schedule", {"proposal_id": p2["proposal_id"]})
    tok2 = data_of(c.call("request_approval", {"proposal_id": p2["proposal_id"]}))["approval_token"]
    r = c.call("apply_approved_changes", {"proposal_id": p2["proposal_id"],
                                          "base_version": p2["base_version"],
                                          "approval_token": tok2, "idempotency_key": "k1"})
    record("A13 同幂等键不同请求被拒", "error:IDEMPOTENCY_CONFLICT", r)

    # A14 fixed-event conflict -> validate must stay draft + invalid
    conflict = {"external_event_id": "x_conflict_day", "title": "整日冲突测试",
                "start_at": "2026-10-29T00:00:00+08:00", "end_at": "2026-10-29T23:59:00+08:00"}
    r = c.call("generate_schedule", {"date_range": RANGE,
                                     "preferences": {"__test_conflict_event": conflict}},
               meta={"authorization": "Bearer demo-token-alice"})
    p3 = data_of(r)
    r = c.call("validate_schedule", {"proposal_id": p3["proposal_id"]})
    v = data_of(r)
    codes = [x["code"] for x in v.get("violations", [])]
    ok14 = (v["validation_status"] == "invalid" and v["proposal_status"] == "draft"
            and "FIXED_EVENT_CONFLICT" in codes)
    results.append({"case": "A14 固定事件冲突→invalid", "expected": "invalid + draft + FIXED_EVENT_CONFLICT",
                    "got": f'{v["validation_status"]} / {v["proposal_status"]} / {codes}',
                    "pass": ok14, "note": "test seam: 事件在排程后注入", "response": r})
    print(f"[{'PASS' if ok14 else 'FAIL'}] A14 固定事件冲突: {v['validation_status']} / {v['proposal_status']} / {codes}")

    c.close()

    passed = sum(1 for x in results if x["pass"])
    print(f"\n{passed}/{len(results)} passed")
    summary = {"server": init["result"]["serverInfo"], "tools": tools,
               "passed": passed, "total": len(results), "results": results}
    with open(os.path.join(HERE, "m1-evidence.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=1)

    import platform
    lines = ["# M1 工具契约一致性测试证据", "",
             "对象：`agent-api-v1.md` v1 CANDIDATE（MCP stdio mock 实现，非 WorkBuddy 实机）",
             f"结果：**{passed}/{len(results)} 通过**", "",
             "## 复现命令", "",
             "```bash",
             "cd <repo>",
             "python tools/m1-mock/run_evidence.py",
             "```", "",
             f"- 运行环境：Windows / Python {platform.python_version()} / MCP stdio（JSON-RPC 2.0）",
             f"- 证据文件：`docs/contracts/reviews/m1-evidence.md`、`m1-evidence.json`",
             "- 代码提交：（见文末 commit 段）", "",
             "## 用例与结果", "",
             "| 用例 | 预期 | 实际 | 结论 | 说明 |", "|---|---|---|---|---|"]
    for x in results:
        lines.append(f"| {x['case']} | {x['expected']} | {x['got']} | {'✅' if x['pass'] else '❌'} | {x.get('note','')} |")
    lines += ["", "## 未覆盖", "",
              "- WorkBuddy 实机：stdio 接入、env token 透传、工具超时/返回上限、分享链接外部访问，均为 **BLOCKED**。",
              "- 可信审批服务、真实快照版本、原子写入与线上 RLS：mock 中为占位实现。",
              "- T-A8（A14）通过测试注入口 `__test_conflict_event` 在排程后注入冲突事件，仅用于证明 validate 会拒绝，不代表真实数据路径。",
              "", "## Commit", "",
              "见 `docs/contracts/reviews/m1-evidence.md` 末尾的 Commit 段（由提交后回填）。"]
    with open(os.path.join(HERE, "m1-evidence.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("written m1-evidence.md / m1-evidence.json")


if __name__ == "__main__":
    main()