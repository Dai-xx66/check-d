#!/usr/bin/env python3
"""Conformance evidence runner for the mock CheckD MCP tool server.

Spawns tool_server.py over stdio, exercises the v1 contract behaviours plus the
candidate approval flow, and writes m1-evidence.md / m1-evidence.json.

The external approval page is simulated by writing to the same JSON store the
server reads (MOCK_APPROVAL_FILE); this keeps "tool call is not approval"
explicit and lets the token be issued only after a human decision.
"""
import json
import os
import platform
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(HERE, "tool_server.py")
CANDIDATE = os.path.abspath(os.path.join(HERE, "..", "..", "docs", "contracts", "tools.candidate.json"))

ENV = {"api_version": "checkd.agent.v1", "timezone": "Asia/Shanghai"}
RANGE = {"start": "2026-10-29", "end": "2026-10-31"}

APPROVAL_FILE = os.path.join(tempfile.gettempdir(), "checkd_mock_approvals.json")
if os.path.exists(APPROVAL_FILE):
    os.remove(APPROVAL_FILE)


class Client:
    def __init__(self):
        env = dict(os.environ, PYTHONIOENCODING="utf-8", MOCK_APPROVAL_FILE=APPROVAL_FILE)
        self.p = subprocess.Popen([sys.executable, SERVER], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True, encoding="utf-8", bufsize=1, env=env)
        self.n = 0

    def rpc(self, method, params=None):
        self.n += 1
        msg = {"jsonrpc": "2.0", "id": self.n, "method": method, "params": params or {}}
        self.p.stdin.write(json.dumps(msg, ensure_ascii=False) + "\n")
        self.p.stdin.flush()
        return json.loads(self.p.stdout.readline())

    def initialize(self):
        r = self.rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                                    "clientInfo": {"name": "evidence-runner", "version": "2"}})
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        self.p.stdin.flush()
        return r

    def call(self, name, inp, meta=None):
        args = dict(ENV)
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
    return resp["result"].get("structuredContent", {}).get("error", {}).get("code")


def human_approve(approval_id):
    """Simulate the user clicking Approve on the approval page (outside tools)."""
    data = {}
    if os.path.exists(APPROVAL_FILE):
        data = json.load(open(APPROVAL_FILE, encoding="utf-8"))
    data[approval_id]["status"] = "approved"
    with open(APPROVAL_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)


results = []


def record(case, expected, resp, note=""):
    sc = resp["result"].get("structuredContent", {})
    is_error = resp["result"].get("isError")
    got = ("error:" + sc["error"]["code"]) if is_error and "error" in sc else "success"
    ok = (got == expected)
    results.append({"case": case, "expected": expected, "got": got, "pass": ok,
                    "note": note, "response": resp})
    print(f"[{'PASS' if ok else 'FAIL'}] {case}: expected {expected}, got {got}")


def assert_case(case, ok, expected, got, note="", resp=None):
    results.append({"case": case, "expected": expected, "got": got, "pass": bool(ok),
                    "note": note, "response": resp or {}})
    print(f"[{'PASS' if ok else 'FAIL'}] {case}: expected {expected}, got {got}")


def check_additional_properties(schema, path="root"):
    """Every object node in a JSON Schema must set additionalProperties:false."""
    bad = []
    if isinstance(schema, dict):
        if schema.get("type") == "object" and schema.get("additionalProperties") is not False:
            bad.append(path)
        for k, v in schema.get("properties", {}).items():
            bad += check_additional_properties(v, f"{path}.{k}")
        if isinstance(schema.get("items"), dict):
            bad += check_additional_properties(schema["items"], f"{path}[]")
    return bad


def main():
    c = Client()
    init = c.initialize()
    print("server:", init["result"]["serverInfo"])

    tl = c.rpc("tools/list")
    tools = tl["result"]["tools"]
    names = [t["name"] for t in tools]
    print("tools:", names)
    assert_case("A0 tools/list", len(names) == 7 and set(names) == {
        "list_tasks", "get_calendar_events", "generate_schedule", "validate_schedule",
        "apply_approved_changes", "request_approval", "get_approval_status"},
        "7 tools (5 v1 + 2 candidate)", f"{len(names)} tools", note=str(names), resp=tl)

    r = c.call("list_tasks", {"date_range": RANGE})
    record("A1 list_tasks 正常读取", "success", r, note=f'{len(data_of(r)["tasks"])} tasks')

    r = c.call("list_tasks", {"date_range": RANGE, "user_id": "u_bob"})
    record("A2 请求体携带 user_id 被拒", "error:INVALID_ARGUMENT", r)

    c.n += 1
    r = c.rpc("tools/call", {"name": "list_tasks", "arguments": {
        "api_version": "checkd.agent.v1", "request_id": "req_tz", "timezone": "UTC",
        "input": {"date_range": RANGE}}})
    record("A3 非 Asia/Shanghai 被拒", "error:INVALID_ARGUMENT", r)

    ext = [{"external_event_id": "x_meeting_1", "title": "临时会议",
            "start_at": "2026-10-30T14:00:00+08:00", "end_at": "2026-10-30T15:00:00+08:00"}]
    r = c.call("get_calendar_events", {"date_range": RANGE, "external_fixed_events": ext})
    evs = data_of(r)["events"]
    record("A4 日历包含固定课程与外部会议", "success", r,
           note=f'{len(evs)} events, {len([e for e in evs if e["fixed"]])} fixed')

    r = c.call("generate_schedule", {"date_range": RANGE, "external_fixed_events": ext})
    p = data_of(r)
    record("A5 generate_schedule 生成 draft 提案", "success", r,
           note=f'{p["proposal_id"]} blocks={len(p["blocks"])} changes={len(p["changes"])}')

    r = c.call("generate_schedule", {"date_range": RANGE, "tasks": [{"task_id": "fake"}]})
    record("A6 远程提交 tasks 被拒", "error:INVALID_ARGUMENT", r)

    r = c.call("validate_schedule", {"proposal_id": p["proposal_id"]})
    v = data_of(r)
    record("A7 validate 通过并进入 pending_approval", "success", r,
           note=f'validation={v["validation_status"]} approval={v["approval_status"]}')

    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"],
                                          "base_version": p["base_version"],
                                          "approval_token": "", "idempotency_key": "k1"})
    record("A8 未审批 apply 返回 APPROVAL_REQUIRED", "error:APPROVAL_REQUIRED", r)

    r = c.call("request_approval", {"proposal_id": p["proposal_id"]})
    req = data_of(r)
    no_token = "approval_token" not in req
    assert_case("A9 request_approval 只创建 pending 请求（不返回 token）",
                req["status"] == "pending" and bool(req.get("approval_url")) and no_token,
                "pending + approval_url, no token",
                f'{req.get("status")} url={bool(req.get("approval_url"))} token={not no_token}',
                note=req.get("approval_id"), resp=r)
    aid = req["approval_id"]

    human_approve(aid)
    r = c.call("get_approval_status", {"approval_id": aid})
    st = data_of(r)
    token = st.get("approval_token")
    assert_case("A10 外部确认后轮询才签发 token",
                st["status"] == "approved" and isinstance(token, str) and token.startswith("tok_"),
                "approved + token", f'{st["status"]} token={bool(token)}', resp=r)

    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"],
                                          "base_version": p["base_version"],
                                          "approval_token": token, "idempotency_key": "k1"})
    d = data_of(r)
    record("A11 审批后原子应用并回读", "success", r,
           note=f'readback_verified={d["readback_verified"]} changes={len(d["applied_changes"])}')

    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"],
                                          "base_version": p["base_version"],
                                          "approval_token": token, "idempotency_key": "k1"})
    d2 = data_of(r)
    assert_case("A12 同幂等键重放返回原结果", d2["result_version"] == d["result_version"],
                "same result_version", f'same={d2["result_version"] == d["result_version"]}', resp=r)

    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"],
                                          "base_version": p["base_version"],
                                          "approval_token": token, "idempotency_key": "k2"})
    record("A13 已消费 token 再用被拒", "error:APPROVAL_CONSUMED", r)

    # A14: same idempotency key, different request -> conflict
    r2 = c.call("generate_schedule", {"date_range": RANGE})
    p2 = data_of(r2)
    c.call("validate_schedule", {"proposal_id": p2["proposal_id"]})
    a2 = data_of(c.call("request_approval", {"proposal_id": p2["proposal_id"]}))["approval_id"]
    human_approve(a2)
    tok2 = data_of(c.call("get_approval_status", {"approval_id": a2}))["approval_token"]
    r = c.call("apply_approved_changes", {"proposal_id": p2["proposal_id"],
                                          "base_version": p2["base_version"],
                                          "approval_token": tok2, "idempotency_key": "k1"})
    record("A14 同幂等键不同请求被拒", "error:IDEMPOTENCY_CONFLICT", r)

    c.n += 1
    r = c.rpc("tools/call", {"name": "list_tasks", "arguments": {
        "api_version": "checkd.agent.v1", "request_id": "req_auth", "timezone": "Asia/Shanghai",
        "input": {"date_range": RANGE}}, "_meta": {"authorization": "Bearer bad-token"}})
    record("A15 无效凭据被拒", "error:AUTH_REQUIRED", r)

    # A16: conflict -> invalid proposal
    conflict = {"external_event_id": "x_conflict_day", "title": "整日冲突测试",
                "start_at": "2026-10-29T00:00:00+08:00", "end_at": "2026-10-29T23:59:00+08:00"}
    r = c.call("generate_schedule", {"date_range": RANGE,
                                     "preferences": {"__test_conflict_event": conflict}},
               meta={"authorization": "Bearer demo-token-alice"})
    p3 = data_of(r)
    r = c.call("validate_schedule", {"proposal_id": p3["proposal_id"]})
    v = data_of(r)
    codes = [x["code"] for x in v.get("violations", [])]
    assert_case("A16 固定事件冲突 → invalid + draft + FIXED_EVENT_CONFLICT",
                v["validation_status"] == "invalid" and v["proposal_status"] == "draft"
                and "FIXED_EVENT_CONFLICT" in codes,
                "invalid/draft/FIXED_EVENT_CONFLICT",
                f'{v["validation_status"]}/{v["proposal_status"]}/{codes}', resp=r)

    # A17: tools/list schema must equal the candidate file and forbid extra properties
    cand = json.load(open(CANDIDATE, encoding="utf-8"))["tools"]
    by_name = {t["name"]: t for t in tools}
    cand_by_name = {t["name"]: t for t in cand}
    same_names = set(by_name) == set(cand_by_name)
    schema_equal = same_names and all(
        by_name[n]["inputSchema"] == cand_by_name[n]["inputSchema"] for n in by_name)
    bad_paths = []
    for t in tools:
        bad_paths += check_additional_properties(t["inputSchema"], t["name"])
    assert_case("A17 tools/list 与 tools.candidate.json 一致且各对象层 additionalProperties:false",
                schema_equal and not bad_paths,
                "identical schemas + no open objects",
                f"names_equal={same_names} schemas_equal={schema_equal} open_objects={len(bad_paths)}",
                note=", ".join(bad_paths[:5]), resp=tl)

    c.close()

    passed = sum(1 for x in results if x["pass"])
    print(f"\n{passed}/{len(results)} passed")
    summary = {"server": init["result"]["serverInfo"], "tools": names,
               "passed": passed, "total": len(results), "results": results}
    out_dir = os.path.abspath(os.path.join(HERE, "..", "..", "docs", "contracts", "reviews"))
    with open(os.path.join(out_dir, "m1-evidence.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=1)

    lines = ["# M1 工具契约一致性测试证据", "",
             "对象：`agent-api-v1.md` v1 CANDIDATE（MCP stdio mock 实现，非 WorkBuddy 实机）",
             f"结果：**{passed}/{len(results)} 通过**", "",
             "## 复现命令", "",
             "```bash",
             "cd <repo>",
             "python tools/m1-mock/run_evidence.py",
             "```", "",
             f"- 运行环境：Windows / Python {platform.python_version()} / MCP stdio（JSON-RPC 2.0）",
             "- 证据文件：`docs/contracts/reviews/m1-evidence.md`、`m1-evidence.json`",
             "- 代码提交：`6683289`（首版）；后续修正提交见文末 Commit 段", "",
             "## 用例与结果", "",
             "| 用例 | 预期 | 实际 | 结论 | 说明 |", "|---|---|---|---|---|"]
    for x in results:
        lines.append(f"| {x['case']} | {x['expected']} | {x['got']} | "
                     f"{'✅' if x['pass'] else '❌'} | {x.get('note','')} |")
    lines += ["", "## 边界说明", "",
              "- `request_approval` / `get_approval_status` 是**候选扩展**，不是 v1 契约内容；用于证明“工具调用 ≠ 用户确认”。",
              "- 外部确认由测试脚本写 `MOCK_APPROVAL_FILE` 模拟（等价于用户在 approval_url 点确认），token 只在确认后签发、且一次性消费。",
              "- WorkBuddy 实机（stdio、env token、确认回调、外部分享）仍为 **BLOCKED**；mock 不构成平台能力证明。",
              "- A16 通过测试注入口 `__test_conflict_event` 在排程后注入冲突事件，仅证明 validate 会拒绝。",
              "", "## Commit", "",
              "- 首版用例代码：`6683289891c7772b033deb23148a2c043f37c029`",
              "- 本次修正（approval 占位、consumed、A17 schema 比对）提交后回填。"]
    with open(os.path.join(out_dir, "m1-evidence.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("written m1-evidence.md / m1-evidence.json")


if __name__ == "__main__":
    main()