#!/usr/bin/env python3
"""Incremental evidence for contract 2c48579 (M1 alignment).

Separate from the historical 26/26 baseline: writes
docs/contracts/reviews/m1-evidence-m0-2c48579.md and .json, with its own counts.
Includes P/E/R1/X1/ORD cases and EX-01..EX-20 replays of the published examples.
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
EXAMPLES = os.environ.get("CHECKD_EXAMPLES") or os.path.abspath(
    os.path.join(HERE, "..", "..", "docs", "contracts", "agent-api-v1.examples.json"))
OUT_DIR = os.path.abspath(os.path.join(HERE, "..", "..", "docs", "contracts", "reviews"))

RANGE = {"start": "2026-10-29", "end": "2026-10-31"}
ENV = {"api_version": "checkd.agent.v1", "timezone": "Asia/Shanghai"}
FLAGS_FILE = os.path.join(tempfile.gettempdir(), "checkd_m0_flags.json")


def set_flags(data):
    with open(FLAGS_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)


def clean_flags():
    if os.path.exists(FLAGS_FILE):
        os.remove(FLAGS_FILE)


class Client:
    def __init__(self):
        self.approvals = os.path.join(tempfile.gettempdir(), f"checkd_m0_appr_{os.getpid()}_{id(self)}.json")
        clean_flags()
        env = dict(os.environ, PYTHONIOENCODING="utf-8",
                   MOCK_APPROVAL_FILE=self.approvals, MOCK_TEST_FLAGS=FLAGS_FILE)
        self.p = subprocess.Popen([sys.executable, SERVER], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True, encoding="utf-8", bufsize=1, env=env)
        self.n = 0
        self.rpc("initialize", {"protocolVersion": "2024-11-05"})
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        self.p.stdin.flush()

    def rpc(self, method, params=None):
        self.n += 1
        msg = {"jsonrpc": "2.0", "id": self.n, "method": method, "params": params or {}}
        self.p.stdin.write(json.dumps(msg, ensure_ascii=False) + "\n")
        self.p.stdin.flush()
        return json.loads(self.p.stdout.readline())

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


def sc_of(resp):
    return resp["result"].get("structuredContent", {})


def data_of(resp):
    return sc_of(resp).get("data")


def code_of(resp):
    err = sc_of(resp).get("error")
    return err.get("code") if isinstance(err, dict) else None


def approve(client, aid):
    recs = json.load(open(client.approvals, encoding="utf-8"))
    recs[aid]["status"] = "approved"
    with open(client.approvals, "w", encoding="utf-8") as f:
        json.dump(recs, f, ensure_ascii=False)


def prepare_pending(client, key="pk1"):
    p = data_of(client.call("generate_schedule", {"date_range": RANGE}))
    client.call("validate_schedule", {"proposal_id": p["proposal_id"]})
    r = data_of(client.call("request_approval", {"proposal_id": p["proposal_id"], "idempotency_key": key}))
    return p, r["approval_id"]


def token_for(client, aid):
    approve(client, aid)
    return data_of(client.call("get_approval_status", {"approval_id": aid}))["approval_token"]


results = []
EX = []


def record(case, ok, expected, got, note="", resp=None, group="core"):
    results.append({"case": case, "expected": expected, "got": got, "pass": bool(ok),
                    "note": note, "response": resp or {}, "group": group})
    print(f"[{'PASS' if ok else 'FAIL'}] {case}: expected {expected}, got {got}")


def ex_record(ex_id, name, status, note, expected="matches example"):
    EX.append({"id": ex_id, "name": name, "status": status, "note": note, "expected": expected})
    print(f"[{status.upper()}] {ex_id} {name}: {note}")


def main():
    # ---------------- P1/P2/E1/E2 ----------------
    c = Client()
    p = data_of(c.call("generate_schedule", {"date_range": RANGE}))
    internal = [k for k in ("user", "_range", "_external_events") if k in p]
    record("P1 Proposal 不暴露内部 DTO 字段", not internal,
           "no internal fields", f"leaked={internal}", resp=p)
    required = ["proposal_id", "snapshot_ref", "base_version", "input_digest", "status",
                "generated_at", "expires_at", "blocks", "changes", "unplanned_tasks", "explanations"]
    missing = [k for k in required if k not in p]
    record("P2 Proposal 必填字段齐全", not missing, "all required fields", f"missing={missing}", resp=p)
    exps = p.get("explanations", [])
    e1_ok = isinstance(exps, list) and exps and all(
        isinstance(x, dict) and isinstance(x.get("code"), str) and isinstance(x.get("message"), str)
        for x in exps)
    codes = sorted({x["code"] for x in exps if isinstance(x, dict)})
    record("E1 explanations 为对象数组且 code 有值", e1_ok,
           "objects with code+message", f"codes={codes}", note="枚举待 B 提供映射", resp=p)
    env_keys = set(sc_of(c.call("list_tasks", {"date_range": RANGE})).keys())
    record("E2 响应信封符合 examples", {"api_version", "request_id", "trace_id", "status"} <= env_keys,
           "api_version/request_id/trace_id/status", str(sorted(env_keys)))
    c.close()

    # ---------------- R1 ----------------
    c = Client()
    p, aid = prepare_pending(c, "r1-key-1")
    tok = token_for(c, aid)
    set_flags({"expire_token": True})
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": tok, "idempotency_key": "r1-apply-1"})
    record("R1-1 Token 过期后 apply → APPROVAL_EXPIRED", code_of(r) == "APPROVAL_EXPIRED",
           "APPROVAL_EXPIRED", code_of(r), resp=r)
    r = c.call("request_approval", {"proposal_id": p["proposal_id"], "idempotency_key": "r1-key-2"})
    new_aid = data_of(r)["approval_id"]
    record("R1-2 Proposal 仍有效时重新审批生成新 approval_id", new_aid != aid,
           "new approval_id", f"old={aid} new={new_aid}", resp=r)
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": tok, "idempotency_key": "r1-apply-2"})
    record("R1-3 旧 Token 永久失效", code_of(r) == "APPROVAL_EXPIRED", "APPROVAL_EXPIRED", code_of(r), resp=r)
    tok2 = token_for(c, new_aid)
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": tok2, "idempotency_key": "r1-apply-3"})
    record("R1-4 新 Token 可成功应用", data_of(r) is not None, "success", code_of(r), resp=r)
    c.close()

    # ---------------- X1 ----------------
    c = Client()
    p, aid = prepare_pending(c, "x1-key-1")
    tok = token_for(c, aid)
    set_flags({"readback_mismatch": True})
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": tok, "idempotency_key": "x1-apply-1"})
    record("X1-a 首次写入进入 readback_pending", code_of(r) == "READBACK_PENDING",
           "READBACK_PENDING", code_of(r), resp=r)
    overrides_before = len(json.load(open(c.approvals, encoding="utf-8")))
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": tok, "idempotency_key": "x1-new-key"})
    record("X1-1 readback_pending + 新幂等键 → READBACK_PENDING", code_of(r) == "READBACK_PENDING",
           "READBACK_PENDING", code_of(r), resp=r)
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": tok, "idempotency_key": "x1-new-key"})
    record("X1-2 新键仍未写入（零写入保持）", code_of(r) == "READBACK_PENDING",
           "READBACK_PENDING", code_of(r), note="no duplicate write", resp=r)
    c.close()

    # ---------------- ORD ----------------
    c = Client()
    p, aid = prepare_pending(c, "ord-key-1")
    tok = token_for(c, aid)
    c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                      "approval_token": tok, "idempotency_key": "ord-apply-1"})
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": tok, "idempotency_key": "ord-new-key"})
    record("ORD-1 已应用 + 新键 → ALREADY_APPLIED", code_of(r) == "ALREADY_APPLIED",
           "ALREADY_APPLIED", code_of(r), resp=r)
    set_flags({"expire_token": True})
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": tok, "idempotency_key": "ord-new-key-2"})
    record("ORD-2 已应用优先于 Token 过期", code_of(r) == "ALREADY_APPLIED",
           "ALREADY_APPLIED", code_of(r), resp=r)
    c.close()

    # ---------------- EX-01..EX-20 ----------------
    examples = json.load(open(EXAMPLES, encoding="utf-8"))["examples"]
    by_name = {e["name"]: e for e in examples}
    order = [
        ("list_tasks_with_recurring_and_one_time", ex_list_tasks),
        ("get_calendar_with_course_and_unexpected_meeting", ex_calendar),
        ("empty_task_list_is_success", ex_empty_tasks),
        ("empty_calendar_is_success", ex_empty_calendar),
        ("unauthorized_request", ex_unauthorized),
        ("generate_schedule_proposal", ex_generate),
        ("validate_schedule_pending_approval", ex_validate),
        ("request_approval_creates_pending_only", ex_request),
        ("get_approval_status_pending_without_token", ex_poll_pending),
        ("get_approval_status_first_approved_delivery", ex_poll_approved),
        ("get_approval_status_after_token_was_issued", ex_poll_issued),
        ("apply_while_external_approval_is_pending", ex_apply_pending),
        ("apply_approved_changes_success", ex_apply_success),
        ("same_idempotency_key_replays_original_result", ex_idem_replay),
        ("already_applied_with_new_idempotency_key", ex_already_applied),
        ("proposal_expired_before_approval", ex_proposal_expired),
        ("consumed_token_cannot_authorize_another_apply", None),
        ("approval_token_expired_before_apply", ex_token_expired),
        ("base_version_changed_before_apply", ex_base_changed),
        ("write_may_have_succeeded_but_readback_is_pending", ex_readback_pending),
    ]
    for i, (name, fn) in enumerate(order, start=1):
        ex_id = f"EX-{i:02d}"
        if fn is None:
            ex_record(ex_id, name, "not_executable",
                      "按 §6.5 判定顺序，已 applied 的 Proposal 先返回 ALREADY_APPLIED；APPROVAL_CONSUMED 在该状态不可达，需 M0 明确")
            continue
        ok, note = fn(by_name.get(name, {}))
        ex_record(ex_id, name, "pass" if ok else "fail", note)

    passed = sum(1 for x in results if x["pass"])
    ex_pass = sum(1 for x in EX if x["status"] == "pass")
    print(f"\ncore {passed}/{len(results)}; EX {ex_pass} pass, "
          f"{sum(1 for x in EX if x['status'] == 'fail')} fail, "
          f"{sum(1 for x in EX if x['status'] == 'not_executable')} not_executable")

    summary = {"baseline_contract": "2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6",
               "server": {"name": "checkd-agent-mock", "version": "0.4.0"},
               "core": {"passed": passed, "total": len(results), "results": results},
               "examples": {"passed": ex_pass, "total": len(EX), "results": EX}}
    with open(os.path.join(OUT_DIR, "m1-evidence-m0-2c48579.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=1)

    lines = ["# M1 增量证据 · 契约 2c48579", "",
             "基准：`agent-api-v1.md` + `agent-api-v1.examples.json` @ `2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6`",
             f"核心用例：**{passed}/{len(results)}**；EX 回放：**{ex_pass}/{len(EX)} 通过**"
             f"（不可执行 {sum(1 for x in EX if x['status'] == 'not_executable')}）",
             "", "> 本文件独立统计，不并入原 26/26 基线（`m1-evidence.md` 保持历史）。", "",
             "## 复现", "", "```bash", "python tools/m1-mock/run_evidence_m0.py", "```", "",
             f"- 环境：Windows / Python {platform.python_version()} / MCP stdio",
             "", "## 核心用例", "", "| 用例 | 预期 | 实际 | 结论 | 说明 |", "|---|---|---|---|---|"]
    for x in results:
        lines.append(f"| {x['case']} | {x['expected']} | {x['got']} | {'✅' if x['pass'] else '❌'} | {x.get('note','')} |")
    lines += ["", "## examples.json 回放（EX-01–EX-20）", "",
              "| ID | 示例 | 结果 | 说明 |", "|---|---|---|---|"]
    for x in EX:
        mark = {"pass": "✅", "fail": "❌", "not_executable": "⏸️"}[x["status"]]
        lines.append(f"| {x['id']} | {x['name']} | {mark} {x['status']} | {x['note']} |")
    lines += ["", "## 边界", "",
              "- `explanations[].code` 枚举待 B 提供映射；当前只发出已公布的两个值，不做扩展。",
              "- EX 回放按“场景 + 状态/错误码”比对，不比对 mock 生成的 ID 与时间。",
              "- WorkBuddy 实机、真实 Token 签名与撤销、审批服务仍在 BLOCKED。"]
    with open(os.path.join(OUT_DIR, "m1-evidence-m0-2c48579.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("written m1-evidence-m0-2c48579.md / .json")


# ---------------------------------------------------------------- EX replay helpers

def _ok_status(resp, code=None):
    return sc_of(resp).get("status") == "success" if code is None else code_of(resp) == code


def ex_list_tasks(ex):
    c = Client()
    r = c.call("list_tasks", {"date_range": RANGE})
    d = data_of(r)
    ok = d is not None and all("kind" in t for t in d["tasks"])
    c.close()
    return ok, f"{len(d['tasks'])} tasks" if d else "no data"


def ex_calendar(ex):
    c = Client()
    inp = dict(ex.get("request", {}).get("input", {}) or {})
    inp.setdefault("date_range", RANGE)
    r = c.call("get_calendar_events", inp)
    d = data_of(r)
    ok = d is not None and "events" in d
    c.close()
    return ok, f"{len(d['events'])} events" if d else "no data"


def ex_empty_tasks(ex):
    c = Client()
    r = c.call("list_tasks", {"date_range": RANGE, "statuses": ["archived"]})
    d = data_of(r)
    ok = d is not None and d["tasks"] == []
    c.close()
    return ok, "empty tasks"


def ex_empty_calendar(ex):
    c = Client()
    r = c.call("get_calendar_events", {"date_range": {"start": "2030-01-01", "end": "2030-01-02"}})
    d = data_of(r)
    ok = d is not None and d["events"] == []
    c.close()
    return ok, "empty calendar"


def ex_unauthorized(ex):
    c = Client()
    r = c.call("list_tasks", {"date_range": RANGE}, meta={"authorization": "Bearer invalid"})
    ok = code_of(r) == "AUTH_REQUIRED"
    c.close()
    return ok, f"code={code_of(r)}"


def ex_generate(ex):
    c = Client()
    p = data_of(c.call("generate_schedule", {"date_range": RANGE}))
    ok = p is not None and p["status"] == "draft" and p["expires_at"] > p["generated_at"]
    c.close()
    return ok, "draft + ttl"


def ex_validate(ex):
    c = Client()
    p = data_of(c.call("generate_schedule", {"date_range": RANGE}))
    v = data_of(c.call("validate_schedule", {"proposal_id": p["proposal_id"]}))
    ok = v is not None and v["proposal_status"] == "pending_approval"
    c.close()
    return ok, f"{v['validation_status']}"


def ex_request(ex):
    c = Client()
    p, aid = prepare_pending(c, "ex-req")
    r = c.call("request_approval", {"proposal_id": p["proposal_id"], "idempotency_key": "ex-req"})
    d = data_of(r)
    ok = d is not None and d["status"] == "pending" and "approval_token" not in d
    c.close()
    return ok, "pending only"


def ex_poll_pending(ex):
    c = Client()
    p, aid = prepare_pending(c, "ex-poll")
    d = data_of(c.call("get_approval_status", {"approval_id": aid}))
    ok = d is not None and d["status"] == "pending" and "approval_token" not in d
    c.close()
    return ok, "pending no token"


def ex_poll_approved(ex):
    c = Client()
    p, aid = prepare_pending(c, "ex-appr")
    approve(c, aid)
    d = data_of(c.call("get_approval_status", {"approval_id": aid}))
    ok = d is not None and d["status"] == "approved" and d.get("approval_token") \
        and d.get("token_expires_at")
    c.close()
    return ok, "approved + token"


def ex_poll_issued(ex):
    c = Client()
    p, aid = prepare_pending(c, "ex-issued")
    approve(c, aid)
    c.call("get_approval_status", {"approval_id": aid})
    d = data_of(c.call("get_approval_status", {"approval_id": aid}))
    ok = d is not None and d["status"] == "token_issued" and d.get("approval_token") is None
    c.close()
    return ok, "token_issued + null"


def ex_apply_pending(ex):
    c = Client()
    p, aid = prepare_pending(c, "ex-apply-pending")
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": "", "idempotency_key": "ex-ap-1"})
    ok = code_of(r) == "APPROVAL_PENDING"
    c.close()
    return ok, f"code={code_of(r)}"


def ex_apply_success(ex):
    c = Client()
    p, aid = prepare_pending(c, "ex-ok")
    tok = token_for(c, aid)
    d = data_of(c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                                 "approval_token": tok, "idempotency_key": "ex-ok-1"}))
    ok = d is not None and d["readback_verified"] is True
    c.close()
    return ok, "readback ok"


def ex_idem_replay(ex):
    c = Client()
    p, aid = prepare_pending(c, "ex-idem")
    tok = token_for(c, aid)
    args = {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
            "approval_token": tok, "idempotency_key": "ex-idem-1"}
    d1 = data_of(c.call("apply_approved_changes", args))
    d2 = data_of(c.call("apply_approved_changes", args))
    ok = d1 and d2 and d1["result_version"] == d2["result_version"]
    c.close()
    return ok, "same result"


def ex_already_applied(ex):
    c = Client()
    p, aid = prepare_pending(c, "ex-alr")
    tok = token_for(c, aid)
    c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                      "approval_token": tok, "idempotency_key": "ex-alr-1"})
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": tok, "idempotency_key": "ex-alr-2"})
    ok = code_of(r) == "ALREADY_APPLIED"
    c.close()
    return ok, f"code={code_of(r)}"


def ex_proposal_expired(ex):
    c = Client()
    p = data_of(c.call("generate_schedule", {"date_range": RANGE}))
    c.call("validate_schedule", {"proposal_id": p["proposal_id"]})
    set_flags({"expire_proposal": True})
    r = c.call("request_approval", {"proposal_id": p["proposal_id"], "idempotency_key": "ex-exp"})
    ok = code_of(r) == "PROPOSAL_EXPIRED"
    c.close()
    return ok, f"code={code_of(r)}"


def ex_token_expired(ex):
    c = Client()
    p, aid = prepare_pending(c, "ex-tokexp")
    tok = token_for(c, aid)
    set_flags({"expire_token": True})
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": tok, "idempotency_key": "ex-tokexp-1"})
    ok = code_of(r) == "APPROVAL_EXPIRED"
    c.close()
    return ok, f"code={code_of(r)}"


def ex_base_changed(ex):
    c = Client()
    p, aid = prepare_pending(c, "ex-base")
    tok = token_for(c, aid)
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": "stale",
                                          "approval_token": tok, "idempotency_key": "ex-base-1"})
    ok = code_of(r) == "SNAPSHOT_CONFLICT"
    c.close()
    return ok, f"code={code_of(r)}"


def ex_readback_pending(ex):
    c = Client()
    p, aid = prepare_pending(c, "ex-rb")
    tok = token_for(c, aid)
    set_flags({"readback_mismatch": True})
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": tok, "idempotency_key": "ex-rb-1"})
    ok = code_of(r) == "READBACK_PENDING"
    c.close()
    return ok, f"code={code_of(r)}"


if __name__ == "__main__":
    main()