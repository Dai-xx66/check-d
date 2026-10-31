#!/usr/bin/env python3
"""LEGACY baseline runner (26/26, pre-2c48579 mock). Kept for history only;
run_evidence_m0.py is the current runner.

Conformance evidence runner for the mock CheckD MCP tool server.

Spawns tool_server.py over stdio and exercises the v1 contract plus the two
candidate extensions, then writes docs/contracts/reviews/m1-evidence.{md,json}.

Edge states that a closed input schema cannot express (invalid proposal, bumped
snapshot, readback failure, missing item) are created through a test-only flag
file, never through a tool parameter.
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
OUT_DIR = os.path.abspath(os.path.join(HERE, "..", "..", "docs", "contracts", "reviews"))

ENV = {"api_version": "checkd.agent.v1", "timezone": "Asia/Shanghai"}
RANGE = {"start": "2026-10-29", "end": "2026-10-31"}

APPROVAL_FILE = os.path.join(tempfile.gettempdir(), "checkd_mock_approvals.json")
FLAGS_FILE = os.path.join(tempfile.gettempdir(), "checkd_mock_flags.json")
for f in (APPROVAL_FILE, FLAGS_FILE):
    if os.path.exists(f):
        os.remove(f)


def set_flags(data):
    with open(FLAGS_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)


class Client:
    def __init__(self):
        env = dict(os.environ, PYTHONIOENCODING="utf-8",
                   MOCK_APPROVAL_FILE=APPROVAL_FILE, MOCK_TEST_FLAGS=FLAGS_FILE)
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
                                    "clientInfo": {"name": "evidence-runner", "version": "3"}})
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


def human_approve(approval_id):
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


def check_objects(schema, path="root"):
    bad = []
    if isinstance(schema, dict):
        if schema.get("type") == "object" and schema.get("additionalProperties") is not False:
            bad.append(path)
        for k, v in schema.get("properties", {}).items():
            bad += check_objects(v, f"{path}.{k}")
        if isinstance(schema.get("items"), dict):
            bad += check_objects(schema["items"], f"{path}[]")
    return bad


def check_refs(schema, root, path="root"):
    bad = []
    if isinstance(schema, dict):
        ref = schema.get("$ref")
        if isinstance(ref, str) and ref.startswith("#/"):
            node = root
            for part in ref[2:].split("/"):
                node = node.get(part) if isinstance(node, dict) else None
            if node is None:
                bad.append(f"{path}:{ref}")
        for k, v in schema.items():
            if k != "$ref":
                bad += check_refs(v, root, f"{path}.{k}")
    elif isinstance(schema, list):
        for i, v in enumerate(schema):
            bad += check_refs(v, root, f"{path}[{i}]")
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
    blob = json.dumps(p, ensure_ascii=False)
    rec_blocks = [b for b in p["blocks"] if b["task_id"] == "t_1004"]
    rec_ok = bool(rec_blocks) and rec_blocks[0]["duration_seconds"] == 3600 \
        and rec_blocks[0]["duration_source"] == "task_target"
    first_task = p["blocks"][0]["task_id"] if p["blocks"] else None
    assert_case("A5 generate_schedule：不伪造 deadline 即时、周期任务用目标时长",
                "T23:59:59" not in blob and rec_ok and first_task == "t_1001",
                "no synthesized instant; recurring 3600s/task_target; exact-deadline first",
                f'has_2359={"T23:59:59" in blob} recurring_ok={rec_ok} first={first_task}',
                note=f'{p["proposal_id"]} blocks={len(p["blocks"])} unplanned={len(p["unplanned_tasks"])}',
                resp=r)

    r = c.call("generate_schedule", {"date_range": RANGE, "tasks": [{"task_id": "fake"}]})
    record("A6 远程提交 tasks 被拒", "error:INVALID_ARGUMENT", r)

    r = c.call("validate_schedule", {"proposal_id": p["proposal_id"]})
    v = data_of(r)
    record("A7 validate 通过并进入 pending_approval", "success", r,
           note=f'validation={v["validation_status"]} approval={v["approval_status"]}')

    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"],
                                          "base_version": p["base_version"],
                                          "approval_token": "", "idempotency_key": "k1"})
    record("A8 未审批 apply → APPROVAL_REQUIRED", "error:APPROVAL_REQUIRED", r)

    r = c.call("request_approval", {"proposal_id": p["proposal_id"]})
    req = data_of(r)
    assert_case("A9 request_approval 只建 pending 请求（无 token）",
                req["status"] == "pending" and bool(req.get("approval_url")) and "approval_token" not in req,
                "pending + approval_url, no token",
                f'{req.get("status")} url={bool(req.get("approval_url"))}',
                note=req.get("approval_id"), resp=r)
    aid = req["approval_id"]

    r = c.call("request_approval", {"proposal_id": p["proposal_id"]})
    same = data_of(r)["approval_id"] == aid
    assert_case("A10 同一 Proposal 重复 request 幂等", same, "same approval_id",
                f'same={same}', resp=r)

    human_approve(aid)
    r = c.call("get_approval_status", {"approval_id": aid})
    st = data_of(r)
    token = st.get("approval_token")
    assert_case("A11 外部确认后轮询才签发 token",
                st["status"] == "approved" and isinstance(token, str) and token.startswith("tok_"),
                "approved + token", f'{st["status"]} token={bool(token)}', resp=r)

    r = c.call("get_approval_status", {"approval_id": aid})
    st2 = data_of(r)
    assert_case("A12 已签发后第三态：approved + token=null",
                st2["status"] == "approved" and st2.get("approval_token") is None,
                "approved + null", f'{st2["status"]} token={st2.get("approval_token")}', resp=r)

    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"],
                                          "base_version": p["base_version"],
                                          "approval_token": token, "idempotency_key": "k1"})
    d = data_of(r)
    override_ok = any(x["type"] == "upsert_daily_override" for x in d["applied_changes"]) \
        and any(x["type"] == "schedule_one_time" for x in d["applied_changes"])
    assert_case("A13 审批后原子应用 + 单次/单日例外回读", d["readback_verified"] and override_ok,
                "readback_verified + both change kinds",
                f'verified={d["readback_verified"]} kinds={override_ok}',
                note=f'{len(d["applied_changes"])} changes', resp=r)

    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"],
                                          "base_version": p["base_version"],
                                          "approval_token": token, "idempotency_key": "k1"})
    d2 = data_of(r)
    assert_case("A14 同幂等键重放返回原结果", d2["result_version"] == d["result_version"],
                "same result_version", f'same={d2["result_version"] == d["result_version"]}', resp=r)

    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"],
                                          "base_version": p["base_version"],
                                          "approval_token": token, "idempotency_key": "k2"})
    record("A15 已应用提案换幂等键 → ALREADY_APPLIED", "error:ALREADY_APPLIED", r)

    r2 = c.call("generate_schedule", {"date_range": RANGE})
    p2 = data_of(r2)
    c.call("validate_schedule", {"proposal_id": p2["proposal_id"]})
    a2 = data_of(c.call("request_approval", {"proposal_id": p2["proposal_id"]}))["approval_id"]
    human_approve(a2)
    tok2 = data_of(c.call("get_approval_status", {"approval_id": a2}))["approval_token"]
    r = c.call("apply_approved_changes", {"proposal_id": p2["proposal_id"],
                                          "base_version": p2["base_version"],
                                          "approval_token": tok2, "idempotency_key": "k1"})
    record("A16 同幂等键不同请求 → IDEMPOTENCY_CONFLICT", "error:IDEMPOTENCY_CONFLICT", r)

    c.n += 1
    r = c.rpc("tools/call", {"name": "list_tasks", "arguments": {
        "api_version": "checkd.agent.v1", "request_id": "req_auth", "timezone": "Asia/Shanghai",
        "input": {"date_range": RANGE}}, "_meta": {"authorization": "Bearer bad-token"}})
    record("A17 无效凭据 → AUTH_REQUIRED", "error:AUTH_REQUIRED", r)

    r3 = c.call("generate_schedule", {"date_range": RANGE}, meta={"authorization": "Bearer demo-token-alice"})
    p3 = data_of(r3)
    c.call("validate_schedule", {"proposal_id": p3["proposal_id"]})
    set_flags({"expire_proposal": True})
    r = c.call("request_approval", {"proposal_id": p3["proposal_id"]})
    record("A18 过期提案不得创建审批 → PROPOSAL_EXPIRED", "error:PROPOSAL_EXPIRED", r)

    r4 = c.call("generate_schedule", {"date_range": RANGE})
    p4 = data_of(r4)
    set_flags({"bump_task": "t_1001"})
    r = c.call("validate_schedule", {"proposal_id": p4["proposal_id"]})
    record("A19 快照变化 → SNAPSHOT_CONFLICT（validate 重算摘要）", "error:SNAPSHOT_CONFLICT", r)

    r5 = c.call("generate_schedule", {"date_range": RANGE})
    p5 = data_of(r5)
    set_flags({"inject_missing_change": {"change_id": "ch_x", "type": "schedule_one_time",
                                         "task_id": "t_missing", "planned_date": "2026-10-29",
                                         "scheduled_at": "2026-10-29T10:00:00+08:00"}})
    r = c.call("validate_schedule", {"proposal_id": p5["proposal_id"]})
    record("A20 引用不存在事项 → NOT_FOUND（不再 KeyError 崩溃）", "error:NOT_FOUND", r)

    r6 = c.call("generate_schedule", {"date_range": RANGE})
    p6 = data_of(r6)
    r = c.call("validate_schedule", {"proposal_id": p6["proposal_id"]})
    v6 = data_of(r)
    record("A21 无冲突提案 validate 通过", "success", r,
           note=f'validation={v6["validation_status"]}')

    r7 = c.call("generate_schedule", {"date_range": RANGE})
    p7 = data_of(r7)
    c.call("validate_schedule", {"proposal_id": p7["proposal_id"]})
    conflict = {"external_event_id": "x_conflict_day", "title": "整日冲突测试",
                "start_at": "2026-10-29T00:00:00+08:00", "end_at": "2026-10-29T23:59:00+08:00"}
    set_flags({"conflict_event": conflict})
    r8 = c.call("generate_schedule", {"date_range": RANGE})
    p8 = data_of(r8)
    r = c.call("validate_schedule", {"proposal_id": p8["proposal_id"]})
    v8 = data_of(r)
    codes = [x["code"] for x in v8.get("violations", [])]
    assert_case("A22 固定事件冲突 → invalid + draft + FIXED_EVENT_CONFLICT",
                v8["validation_status"] == "invalid" and v8["proposal_status"] == "draft"
                and "FIXED_EVENT_CONFLICT" in codes,
                "invalid/draft/FIXED_EVENT_CONFLICT",
                f'{v8["validation_status"]}/{v8["proposal_status"]}/{codes}', resp=r)

    r9 = c.call("generate_schedule", {"date_range": RANGE})
    p9 = data_of(r9)
    c.call("validate_schedule", {"proposal_id": p9["proposal_id"]})
    a9 = data_of(c.call("request_approval", {"proposal_id": p9["proposal_id"]}))["approval_id"]
    human_approve(a9)
    tok9 = data_of(c.call("get_approval_status", {"approval_id": a9}))["approval_token"]
    set_flags({"readback_mismatch": True})
    r = c.call("apply_approved_changes", {"proposal_id": p9["proposal_id"],
                                          "base_version": p9["base_version"],
                                          "approval_token": tok9, "idempotency_key": "r1"})
    record("A23 回读失败 → READBACK_MISMATCH 且标记 readback_pending", "error:READBACK_MISMATCH", r)
    r = c.call("apply_approved_changes", {"proposal_id": p9["proposal_id"],
                                          "base_version": p9["base_version"],
                                          "approval_token": tok9, "idempotency_key": "r1"})
    d9 = data_of(r)
    assert_case("A24 同幂等键重试只回读、不二次写入", isinstance(d9, dict) and d9.get("readback_verified"),
                "success via re-readback only", f'verified={d9.get("readback_verified") if d9 else None}',
                note="no duplicate write", resp=r)

    cand = json.load(open(CANDIDATE, encoding="utf-8"))
    cand_by = {t["name"]: t for t in cand["tools"]}
    by_name = {t["name"]: t for t in tools}
    same_names = set(by_name) == set(cand_by)
    schema_equal = same_names and all(
        by_name[n]["inputSchema"] == cand_by[n]["inputSchema"] for n in by_name)
    bad_objs, bad_refs = [], []
    for t in tools:
        bad_objs += check_objects(t["inputSchema"], t["name"])
        bad_refs += check_refs(t["inputSchema"], t["inputSchema"], t["name"])
    assert_case("A25 schema 一致、$ref 可解析、各对象层 additionalProperties:false",
                schema_equal and not bad_objs and not bad_refs,
                "identical + resolvable refs + closed objects",
                f"names={same_names} schemas={schema_equal} open={len(bad_objs)} bad_refs={len(bad_refs)}",
                note=", ".join((bad_objs + bad_refs)[:5]), resp=tl)

    c.close()

    passed = sum(1 for x in results if x["pass"])
    print(f"\n{passed}/{len(results)} passed")
    summary = {"server": init["result"]["serverInfo"], "tools": names,
               "passed": passed, "total": len(results), "results": results}
    with open(os.path.join(OUT_DIR, "m1-evidence.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=1)

    lines = ["# M1 工具契约一致性测试证据", "",
             "对象：`agent-api-v1.md` v1 CANDIDATE（MCP stdio mock 实现，非 WorkBuddy 实机）",
             f"结果：**{passed}/{len(results)} 通过**", "",
             "## 复现命令", "",
             "```bash",
             "cd <repo>",
             "python tools/m1-mock/export_schema.py",
             "python tools/m1-mock/run_evidence.py",
             "```", "",
             f"- 运行环境：Windows / Python {platform.python_version()} / MCP stdio（JSON-RPC 2.0）",
             "- 证据文件：`docs/contracts/reviews/m1-evidence.md`、`m1-evidence.json`",
             "- 代码提交：见文末 Commit 段", "",
             "## 用例与结果", "",
             "| 用例 | 预期 | 实际 | 结论 | 说明 |", "|---|---|---|---|---|"]
    for x in results:
        lines.append(f"| {x['case']} | {x['expected']} | {x['got']} | "
                     f"{'✅' if x['pass'] else '❌'} | {x.get('note','')} |")
    lines += ["", "## 边界说明", "",
              "- A19/A20/A22/A23 的边界状态由**测试专用 flag 文件**构造，不是工具入参；请求 schema 保持闭合。",
              "- `request_approval` / `get_approval_status` 是**候选扩展**，是否写入 v1 待 M0 最终确认，不预设 v1.1。",
              "- WorkBuddy 实机（stdio、env token、确认回调、外部分享）仍为 **BLOCKED**，本证据不构成平台能力证明。",
              "- token 无签名、无 TTL、审批文件无访问控制、确认者身份未验证：保持 BLOCKED。",
              "", "## Commit", "",
              "- 本文件在修复提交之后回填；分支 HEAD 以 `git log -1` 为准。"]
    with open(os.path.join(OUT_DIR, "m1-evidence.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("written m1-evidence.md / m1-evidence.json")


if __name__ == "__main__":
    main()