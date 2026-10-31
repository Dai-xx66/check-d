#!/usr/bin/env python3
"""M1 evidence aligned to contract c53b1a9 (separate from earlier baselines).

Writes docs/contracts/reviews/m1-evidence-c53b1a9.md/.json.
Covers: schema/envelope, explanations closed set, R1, X1, ordering, EX-17
(APPROVAL_UNTRUSTED vs APPROVAL_CONSUMED), idempotency-in-progress,
EX-01..EX-20 replay with raw response records and write counters.
"""
import json
import os
import platform
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(HERE, "tool_server.py")
OUT_DIR = os.path.abspath(os.path.join(HERE, "..", "..", "docs", "contracts", "reviews"))
EXAMPLES = os.environ.get("CHECKD_EXAMPLES") or os.path.abspath(
    os.path.join(HERE, "..", "..", "docs", "contracts", "agent-api-v1.examples.json"))

RANGE = {"start": "2026-10-29", "end": "2026-10-31"}
ENV = {"api_version": "checkd.agent.v1", "timezone": "Asia/Shanghai"}
FLAGS_FILE = os.path.join(tempfile.gettempdir(), "checkd_c53_flags.json")

EXPLANATION_CODES = {"SCHEDULED", "ESTIMATED_DURATION", "ALREADY_DONE_TODAY",
                     "FIXED_BLOCKS_OVERLAP", "NO_AVAILABILITY_WINDOW",
                     "AVAILABILITY_SATURATED", "PRESERVED_FIXED_EVENTS"}


def set_flags(data):
    with open(FLAGS_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)


def writes():
    try:
        return json.load(open(FLAGS_FILE, encoding="utf-8")).get("writes", 0)
    except Exception:
        return 0


class Client:
    def __init__(self):
        self.approvals = os.path.join(tempfile.gettempdir(), f"c53_appr_{os.getpid()}_{id(self)}.json")
        set_flags({})
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
        args["request_id"] = inp.get("request_id") or f"req_{name}_{self.n + 1}"
        args["input"] = {k: v for k, v in inp.items() if k != "request_id"}
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


def sc(resp):
    return resp["result"].get("structuredContent", {})


def data(resp):
    return sc(resp).get("data")


def code(resp):
    e = sc(resp).get("error")
    return e.get("code") if isinstance(e, dict) else None


def approve(client, aid):
    recs = json.load(open(client.approvals, encoding="utf-8"))
    recs[aid]["status"] = "approved"
    json.dump(recs, open(client.approvals, "w", encoding="utf-8"), ensure_ascii=False)


def pending(client, key):
    p = data(client.call("generate_schedule", {"date_range": RANGE}))
    client.call("validate_schedule", {"proposal_id": p["proposal_id"]})
    r = data(client.call("request_approval", {"proposal_id": p["proposal_id"], "idempotency_key": key}))
    return p, r["approval_id"]


def token(client, aid):
    approve(client, aid)
    return data(client.call("get_approval_status", {"approval_id": aid}))["approval_token"]


results, ex = [], []


def rec(case, ok, expected, got, note="", raw=None):
    results.append({"case": case, "expected": expected, "got": got, "pass": bool(ok),
                    "note": note, "raw": raw or {}})
    print(f"[{'PASS' if ok else 'FAIL'}] {case}: {got}")


def main():
    examples = json.load(open(EXAMPLES, encoding="utf-8"))
    names = [t if isinstance(t, str) else t.get("name") for t in examples["tools"]]

    c = Client()
    tl = c.rpc("tools/list")
    tools = tl["result"]["tools"]
    rec("C1 tools/list 与 examples 的 7 工具一致",
        set(t["name"] for t in tools) == set(names) and len(tools) == len(names), names,
        [t["name"] for t in tools], raw={"count": len(tools)})

    p = data(c.call("generate_schedule", {"date_range": RANGE}))
    codes = [x["code"] for x in p["explanations"]]
    rec("C2 explanations 属七码闭集",
        set(codes) <= EXPLANATION_CODES and codes, sorted(EXPLANATION_CODES), codes)
    rec("C3 响应信封字段",
        {"api_version", "request_id", "trace_id", "status", "data"} <= set(sc(c.call("list_tasks", {"date_range": RANGE}))),
        "envelope", sorted(sc(c.call("list_tasks", {"date_range": RANGE}))))
    c.close()

    # R1 with write counters
    c = Client()
    p, aid = pending(c, "r1k1")
    t1 = token(c, aid)
    w0 = writes()
    set_flags({"expire_token": True})
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": t1, "idempotency_key": "r1a1"})
    rec("R1-1 Token 过期 → APPROVAL_EXPIRED 且零写入",
        code(r) == "APPROVAL_EXPIRED" and writes() == w0, "APPROVAL_EXPIRED, writes 0",
        f"{code(r)}, writes={writes()-w0}", raw={"writes_delta": writes() - w0})
    r = c.call("request_approval", {"proposal_id": p["proposal_id"], "idempotency_key": "r1k2"})
    aid2 = data(r)["approval_id"]
    rec("R1-2 旧 Approval 终结后新 approval_id", aid2 != aid, "new id", f"{aid}->{aid2}")
    t2 = token(c, aid2)
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": t2, "idempotency_key": "r1a2"})
    rec("R1-3 新 Token 成功应用", data(r) is not None, "success", code(r) or "success",
        raw={"applied": len(data(r)["applied_changes"]) if data(r) else 0})
    c.close()

    # X1 with counters
    c = Client()
    p, aid = pending(c, "x1k1")
    t = token(c, aid)
    set_flags({"readback_mismatch": True})
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": t, "idempotency_key": "x1a1"})
    rec("X1-a 首次写入 → READBACK_PENDING", code(r) == "READBACK_PENDING", "READBACK_PENDING", code(r))
    w_before = writes()
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": t, "idempotency_key": "x1a2"})
    rec("X1-1 新幂等键 → READBACK_PENDING 且零写入",
        code(r) == "READBACK_PENDING" and writes() == w_before, "READBACK_PENDING, writes 0",
        f"{code(r)}, writes={writes()-w_before}", raw={"writes_delta": writes() - w_before})
    c.close()

    # T1 cross-proposal token
    c = Client()
    p1, a1 = pending(c, "t1k1")
    t1 = token(c, a1)
    p2 = data(c.call("generate_schedule", {"date_range": RANGE}))
    c.call("validate_schedule", {"proposal_id": p2["proposal_id"]})
    r = c.call("apply_approved_changes", {"proposal_id": p2["proposal_id"], "base_version": p2["base_version"],
                                          "approval_token": t1, "idempotency_key": "t1a1"})
    rec("T1 跨 Proposal 错绑 Token → APPROVAL_UNTRUSTED", code(r) == "APPROVAL_UNTRUSTED",
        "APPROVAL_UNTRUSTED", code(r))
    c.close()

    # T2 failed + consumed -> APPROVAL_CONSUMED (reachable)
    c = Client()
    p, aid = pending(c, "t2k1")
    t = token(c, aid)
    set_flags({"fail_after_consume": True})
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": t, "idempotency_key": "t2a1"})
    first = code(r)
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": t, "idempotency_key": "t2a2"})
    rec("T2 failed+已消费 → APPROVAL_CONSUMED",
        code(r) == "APPROVAL_CONSUMED", "APPROVAL_CONSUMED", f"{first} -> {code(r)}")
    c.close()

    # T3 applying + same key -> IDEMPOTENCY_IN_PROGRESS
    c = Client()
    p, aid = pending(c, "t3k1")
    t = token(c, aid)
    set_flags({"simulate_applying_crash": True})
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": t, "idempotency_key": "t3a1"})
    first = code(r)
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": t, "idempotency_key": "t3a1"})
    e = sc(r).get("error") or {}
    rec("T3 applying 同键 → IDEMPOTENCY_IN_PROGRESS(retryable)",
        code(r) == "IDEMPOTENCY_IN_PROGRESS" and e.get("retryable") is True,
        "IDEMPOTENCY_IN_PROGRESS retryable", f"{first} -> {code(r)} retryable={e.get('retryable')}")
    c.close()

    # ORD
    c = Client()
    p, aid = pending(c, "ordk")
    t = token(c, aid)
    c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                      "approval_token": t, "idempotency_key": "orda1"})
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": t, "idempotency_key": "orda2"})
    rec("ORD-1 已应用 + 新键 → ALREADY_APPLIED", code(r) == "ALREADY_APPLIED", "ALREADY_APPLIED", code(r))
    c.close()

    # EX replay (first 20 by name mapping)
    mapping = {e["name"]: e for e in examples["examples"]}
    order = EX_ORDER
    for i, (name, fn) in enumerate(order, start=1):
        ex_id = f"EX-{i:02d}"
        if fn is None:
            ex.append({"id": ex_id, "name": name, "status": "not_executable",
                       "note": "requires state not modelled in mock", "raw": {}})
            continue
        ok, note, raw = fn(mapping.get(name, {}))
        ex.append({"id": ex_id, "name": name, "status": "pass" if ok else "fail",
                   "note": note, "raw": raw})
        print(f"[{'PASS' if ok else 'FAIL'}] {ex_id} {name}: {note}")

    passed = sum(1 for x in results if x["pass"])
    exp = sum(1 for x in ex if x["status"] == "pass")
    summary = {"contract": "c53b1a91c17cd9acdee6d3937c093fcf97515ba0",
               "core": {"passed": passed, "total": len(results), "results": results},
               "examples": {"passed": exp, "total": len(ex), "results": ex}}
    os.makedirs(OUT_DIR, exist_ok=True)
    json.dump(summary, open(os.path.join(OUT_DIR, "m1-evidence-c53b1a9.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)

    lines = ["# M1 证据 · 契约 c53b1a9", "",
             "基准：`c53b1a91c17cd9acdee6d3937c093fcf97515ba0`（PR #4）",
             f"核心 {passed}/{len(results)}；EX {exp}/{len(ex)}；环境 Windows / Python {platform.python_version()} / MCP stdio",
             "", "> 与 2c48579 及 26/26 证据分开统计；WorkBuddy 实机另见 `m1-workbuddy-live.md`。", "",
             "## 核心", "", "| 用例 | 预期 | 实际 | 结论 | 说明 |", "|---|---|---|---|---|"]
    for x in results:
        lines.append(f"| {x['case']} | {x['expected']} | {x['got']} | {'✅' if x['pass'] else '❌'} | {x['note']} |")
    lines += ["", "## examples 回放", "", "| ID | 名称 | 结果 | 说明 |", "|---|---|---|---|"]
    for x in ex:
        mark = {"pass": "✅", "fail": "❌", "not_executable": "⏸️"}[x["status"]]
        lines.append(f"| {x['id']} | {x['name']} | {mark} {x['status']} | {x['note']} |")
    open(os.path.join(OUT_DIR, "m1-evidence-c53b1a9.md"), "w", encoding="utf-8").write("\n".join(lines))
    print(f"core {passed}/{len(results)}; EX {exp}/{len(ex)}")


def _ok(r):
    return sc(r).get("status") == "success"


def ex_list_tasks(ex):
    c = Client()
    inp = dict(ex.get("request", {}).get("input", {}) or {})
    inp.setdefault("date_range", RANGE)
    r = c.call("list_tasks", inp)
    d = data(r)
    expected = ex.get("response", {}).get("data", {})
    keys = sorted(d.keys()) if d else []
    exp_keys = sorted(expected.keys())
    ok = keys == exp_keys and isinstance(d.get("tasks"), list)
    c.close()
    return ok, f"keys match={keys == exp_keys}; mock tasks={len(d['tasks']) if d else 0} vs example={len(expected.get('tasks', []))} (fixture differs)", {"keys": keys, "expected_keys": exp_keys}


def ex_calendar(ex):
    c = Client()
    inp = dict(ex.get("request", {}).get("input", {}) or {})
    inp.setdefault("date_range", RANGE)
    r = c.call("get_calendar_events", inp)
    d = data(r)
    expected = ex.get("response", {}).get("data", {})
    ok = d is not None and sorted(d.keys()) == sorted(expected.keys())
    c.close()
    return ok, f"keys={sorted(d.keys()) if d else None} events={len(d['events']) if d else 0}", {"keys": sorted(d.keys()) if d else []}


def ex_empty_tasks(ex):
    c = Client()
    r = c.call("list_tasks", {"date_range": RANGE, "statuses": ["archived"]})
    ok = _ok(r) and data(r)["tasks"] == []
    c.close()
    return ok, "empty tasks", {}


def ex_empty_calendar(ex):
    c = Client()
    r = c.call("get_calendar_events", {"date_range": {"start": "2030-01-01", "end": "2030-01-02"}})
    ok = _ok(r) and data(r)["events"] == []
    c.close()
    return ok, "empty calendar", {}


def ex_unauthorized(ex):
    c = Client()
    r = c.call("list_tasks", {"date_range": RANGE}, meta={"authorization": "Bearer invalid"})
    ok = code(r) == "AUTH_REQUIRED"
    c.close()
    return ok, f"code={code(r)}", {"code": code(r)}


def ex_generate(ex):
    c = Client()
    p = data(c.call("generate_schedule", {"date_range": RANGE}))
    ok = p is not None and p["status"] == "draft"
    c.close()
    return ok, "draft", {"keys": sorted(p.keys()) if p else []}


def ex_validate(ex):
    c = Client()
    p = data(c.call("generate_schedule", {"date_range": RANGE}))
    v = data(c.call("validate_schedule", {"proposal_id": p["proposal_id"]}))
    ok = v is not None and v["proposal_status"] == "pending_approval"
    c.close()
    return ok, v["validation_status"] if v else "none", {}


def ex_request(ex):
    c = Client()
    p, aid = pending(c, "exreq")
    d = data(c.call("request_approval", {"proposal_id": p["proposal_id"], "idempotency_key": "exreq"}))
    ok = d["status"] == "pending" and "approval_token" not in d
    c.close()
    return ok, "pending only", {"approval_id": d.get("approval_id")}


def ex_poll_pending(ex):
    c = Client()
    p, aid = pending(c, "expoll")
    d = data(c.call("get_approval_status", {"approval_id": aid}))
    ok = d["status"] == "pending" and "approval_token" not in d
    c.close()
    return ok, "pending", {"status": d.get("status")}


def ex_poll_approved(ex):
    c = Client()
    p, aid = pending(c, "exappr")
    approve(c, aid)
    d = data(c.call("get_approval_status", {"approval_id": aid}))
    ok = d["status"] == "approved" and bool(d.get("approval_token")) and bool(d.get("token_expires_at"))
    c.close()
    return ok, "approved+token", {"status": d.get("status"), "has_token": bool(d.get("approval_token"))}


def ex_poll_issued(ex):
    c = Client()
    p, aid = pending(c, "exissued")
    approve(c, aid)
    c.call("get_approval_status", {"approval_id": aid})
    d = data(c.call("get_approval_status", {"approval_id": aid}))
    ok = d["status"] == "token_issued" and d.get("approval_token") is None
    c.close()
    return ok, "token_issued", {"status": d.get("status")}


def ex_apply_pending(ex):
    c = Client()
    p, aid = pending(c, "exap")
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": "", "idempotency_key": "exap1"})
    ok = code(r) == "APPROVAL_PENDING"
    c.close()
    return ok, f"code={code(r)}", {"code": code(r)}


def ex_apply_success(ex):
    c = Client()
    p, aid = pending(c, "exok")
    t = token(c, aid)
    d = data(c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                               "approval_token": t, "idempotency_key": "exok1"}))
    ok = d is not None and d["readback_verified"] is True
    c.close()
    return ok, "readback ok", {"changes": len(d["applied_changes"]) if d else 0}


def ex_idem_replay(ex):
    c = Client()
    p, aid = pending(c, "exidem")
    t = token(c, aid)
    args = {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
            "approval_token": t, "idempotency_key": "exidem1"}
    d1 = data(c.call("apply_approved_changes", args))
    d2 = data(c.call("apply_approved_changes", args))
    ok = d1 and d2 and d1["result_version"] == d2["result_version"]
    c.close()
    return ok, "same result", {"result_version": d1.get("result_version") if d1 else None}


def ex_already_applied(ex):
    c = Client()
    p, aid = pending(c, "exalr")
    t = token(c, aid)
    c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                      "approval_token": t, "idempotency_key": "exalr1"})
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": t, "idempotency_key": "exalr2"})
    ok = code(r) == "ALREADY_APPLIED"
    c.close()
    return ok, f"code={code(r)}", {"code": code(r)}


def ex_proposal_expired(ex):
    c = Client()
    p = data(c.call("generate_schedule", {"date_range": RANGE}))
    c.call("validate_schedule", {"proposal_id": p["proposal_id"]})
    set_flags({"expire_proposal": True})
    r = c.call("request_approval", {"proposal_id": p["proposal_id"], "idempotency_key": "exexp"})
    ok = code(r) == "PROPOSAL_EXPIRED"
    c.close()
    return ok, f"code={code(r)}", {"code": code(r)}


def ex_consumed(ex):
    c = Client()
    p, aid = pending(c, "excons")
    t = token(c, aid)
    set_flags({"fail_after_consume": True})
    c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                      "approval_token": t, "idempotency_key": "excons1"})
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": t, "idempotency_key": "excons2"})
    ok = code(r) == "APPROVAL_CONSUMED"
    c.close()
    return ok, f"code={code(r)}", {"code": code(r)}


def ex_token_expired(ex):
    c = Client()
    p, aid = pending(c, "extok")
    t = token(c, aid)
    set_flags({"expire_token": True})
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": t, "idempotency_key": "extok1"})
    ok = code(r) == "APPROVAL_EXPIRED"
    c.close()
    return ok, f"code={code(r)}", {"code": code(r)}


def ex_base_changed(ex):
    c = Client()
    p, aid = pending(c, "exbase")
    t = token(c, aid)
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": "stale",
                                          "approval_token": t, "idempotency_key": "exbase1"})
    ok = code(r) == "SNAPSHOT_CONFLICT"
    c.close()
    return ok, f"code={code(r)}", {"code": code(r)}


def ex_readback(ex):
    c = Client()
    p, aid = pending(c, "exrb")
    t = token(c, aid)
    set_flags({"readback_mismatch": True})
    r = c.call("apply_approved_changes", {"proposal_id": p["proposal_id"], "base_version": p["base_version"],
                                          "approval_token": t, "idempotency_key": "exrb1"})
    ok = code(r) == "READBACK_PENDING"
    c.close()
    return ok, f"code={code(r)}", {"code": code(r)}


EX_ORDER = [
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
    ("consumed_token_cannot_authorize_another_apply", ex_consumed),
    ("approval_token_expired_before_apply", ex_token_expired),
    ("base_version_changed_before_apply", ex_base_changed),
    ("write_may_have_succeeded_but_readback_is_pending", ex_readback),
]

if __name__ == "__main__":
    main()