#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""B-rail contract gate: decide pass/fail for the four M0-mandated Mock fixes.

Runs four READBACK_PENDING scenarios in one MCP stdio session and asserts:

  G1  details 条目字段名必须是 `proposal_status`（不是 `proposal.status`）
  G2  值必须来自真实 Proposal 状态：applying 分支 → applying
  G3  值必须来自真实 Proposal 状态：readback_pending 分支 → readback_pending
  G4  retryable 必须为 true（契约 #21/#31/#34）
  G5  details 必须含 business_write_count_delta；写前路径必须为 0
  G6  写前路径不得触发第二次 apply（服务端写入计数增量 = 0）

Exit code 0 = 全部通过（可以开录）；1 = 至少一项不通过（镜头 6 保持 BLOCKED）。

Read-only w.r.t. the repo: approval store and flag file live in a temp dir.
"""
import json
import os
import subprocess
import sys
import tempfile
import uuid

SERVER = os.path.abspath(sys.argv[1])
TMP = tempfile.mkdtemp(prefix="brail_gate_")
APPROVAL_FILE = os.path.join(TMP, "approvals.json")
FLAGS_FILE = os.path.join(TMP, "flags.json")
json.dump({}, open(APPROVAL_FILE, "w"))
json.dump({}, open(FLAGS_FILE, "w"))

ENV = dict(os.environ)
ENV.update({"PYTHONIOENCODING": "utf-8", "CHECKD_TOKEN": "demo-token-alice",
            "MOCK_APPROVAL_FILE": APPROVAL_FILE, "MOCK_TEST_FLAGS": FLAGS_FILE})
p = subprocess.Popen([sys.executable, SERVER], stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=ENV,
                     text=True, encoding="utf-8", bufsize=1)
_id = [0]


def rpc(method, params=None, notify=False):
    if notify:
        p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": method, "params": params or {}}) + "\n")
        p.stdin.flush()
        return None
    _id[0] += 1
    mid = _id[0]
    p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": mid, "method": method,
                              "params": params or {}}) + "\n")
    p.stdin.flush()
    while True:
        line = p.stdout.readline()
        if not line:
            raise RuntimeError("server closed stdout")
        m = json.loads(line)
        if m.get("id") == mid:
            return m


def call(tool, inp):
    r = rpc("tools/call", {"name": tool, "arguments": {
        "api_version": "checkd.agent.v1", "request_id": "req_" + uuid.uuid4().hex[:12],
        "timezone": "Asia/Shanghai", "input": inp}})
    res = r.get("result", {})
    for c in res.get("content", []) or []:
        if c.get("type") == "text":
            d = json.loads(c["text"])
            if d.get("status") == "success":
                return d.get("data", {})
            return {"error": d.get("error")}
    return {}


def setflag(**kw):
    cur = json.load(open(FLAGS_FILE))
    cur.update(kw)
    json.dump(cur, open(FLAGS_FILE, "w"), ensure_ascii=False)


def writes():
    return json.load(open(FLAGS_FILE)).get("writes", 0)


rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                   "clientInfo": {"name": "brail-gate", "version": "1.0"}})
rpc("notifications/initialized", notify=True)
DR = {"start": "2026-10-29", "end": "2026-11-02"}


def approved_proposal():
    gen = call("generate_schedule", {"date_range": DR})
    pid, base = gen["proposal_id"], gen["base_version"]
    call("validate_schedule", {"proposal_id": pid})
    ap = call("request_approval", {"proposal_id": pid, "idempotency_key": "k-appr-" + pid})
    aid = ap["approval_id"]
    apv = json.load(open(APPROVAL_FILE))
    apv[aid] = {"status": "approved"}
    json.dump(apv, open(APPROVAL_FILE, "w"), ensure_ascii=False)
    st = call("get_approval_status", {"approval_id": aid})
    return pid, base, st.get("approval_token")


def details_map(err):
    out = {}
    for d in err.get("details") or []:
        if isinstance(d, dict) and "field" in d:
            out[d["field"]] = d.get("reason")
    return out


cases = {}

# --- case 1: crash after consume -> Proposal really applying (contract #31 shape)
pid1, base1, tok1 = approved_proposal()
w0 = writes()
setflag(simulate_applying_crash=True)
r = call("apply_approved_changes", {"proposal_id": pid1, "base_version": base1,
                                    "approval_token": tok1, "idempotency_key": "gate-crash"})
cases["crash_applying"] = {"error": r.get("error"), "writes_delta": writes() - w0}

# --- case 2: readback not converged -> Proposal really readback_pending
pid2, base2, tok2 = approved_proposal()
w1 = writes()
setflag(readback_mismatch=True)
r = call("apply_approved_changes", {"proposal_id": pid2, "base_version": base2,
                                    "approval_token": tok2, "idempotency_key": "gate-mismatch"})
cases["mismatch_readback_pending"] = {"error": r.get("error"), "writes_delta": writes() - w1}

# --- case 3: pre-existing readback_pending + NEW key (contract #21 shape)
w2 = writes()
r = call("apply_approved_changes", {"proposal_id": pid2, "base_version": base2,
                                    "approval_token": tok2, "idempotency_key": "gate-pending-newkey"})
cases["pending_newkey"] = {"error": r.get("error"), "writes_delta": writes() - w2}

# --- case 4: pre-existing applying + NEW key (contract #31 shape, the hardcoded case)
w3 = writes()
r = call("apply_approved_changes", {"proposal_id": pid1, "base_version": base1,
                                    "approval_token": tok1, "idempotency_key": "gate-applying-newkey"})
cases["applying_newkey"] = {"error": r.get("error"), "writes_delta": writes() - w3}

p.terminate()
try:
    p.communicate(timeout=5)
except Exception:
    pass

# ------------------------------------------------------------------ assertions
results = []


def check(gid, desc, ok, detail):
    results.append((gid, desc, ok, detail))


def err_of(k):
    return cases[k]["error"] or {}


empty_details = []
for k, label in (("crash_applying", "崩溃后 applying"),
                 ("mismatch_readback_pending", "回读未收敛"),
                 ("pending_newkey", "预存 readback_pending + 新键"),
                 ("applying_newkey", "预存 applying + 新键")):
    e = err_of(k)
    if not e:
        check("G0", label + " 是否返回 READBACK_PENDING", False, "未返回错误：" + json.dumps(cases[k])[:200])
    elif not (e.get("details") or []):
        empty_details.append(k)
check("G0", "四条 READBACK_PENDING 的 details 均非空",
      not empty_details,
      "details 为空：%s（缺 proposal_status 与 business_write_count_delta）"
      % json.dumps(empty_details, ensure_ascii=False))

e1, e2, e3, e4 = (err_of("crash_applying"), err_of("mismatch_readback_pending"),
                  err_of("pending_newkey"), err_of("applying_newkey"))

# G1 字段名：只在 details 非空的响应上判（details 为空由 G0 负责，避免同一根因重复计分）
bad_names = sorted({f for e in (e1, e2, e3, e4) for f in details_map(e)
                    if f in ("proposal.status", "proposal_status", "status")})
nonempty = [e for e in (e1, e2, e3, e4) if e and (e.get("details") or [])]
check("G1", "details 使用 proposal_status 字段名",
      bool(nonempty) and all("proposal_status" in details_map(e) for e in nonempty)
      and not any("proposal.status" in details_map(e) for e in (e1, e2, e3, e4)),
      "非空 details 条数=%d；实测字段名：%s"
      % (len(nonempty), json.dumps(bad_names, ensure_ascii=False)))

# G2/G3 值必须反映真实状态
def reason_of(e):
    d = details_map(e)
    return d.get("proposal_status") or d.get("proposal.status")


check("G2", "applying 路径的 proposal_status = applying",
      reason_of(e1) == "applying" and reason_of(e4) == "applying",
      "crash=%r / preexisting=%r" % (reason_of(e1), reason_of(e4)))
check("G3", "readback_pending 路径的 proposal_status = readback_pending",
      reason_of(e2) == "readback_pending" and reason_of(e3) == "readback_pending",
      "mismatch=%r / preexisting=%r" % (reason_of(e2), reason_of(e3)))

# G4 retryable
check("G4", "四条 READBACK_PENDING 的 retryable 均为 true",
      all(e.get("retryable") is True for e in (e1, e2, e3, e4) if e),
      "实测：" + json.dumps([e.get("retryable") for e in (e1, e2, e3, e4)]))

# G5 business_write_count_delta 存在；写前路径必须为 0
has_delta = [("business_write_count_delta" in details_map(e)) for e in (e1, e3, e4) if e]
zero_delta = [details_map(e).get("business_write_count_delta") in ("0", 0)
              for e in (e1, e3, e4) if e]
check("G5", "写前路径含 business_write_count_delta=0",
      bool(has_delta) and all(has_delta) and all(zero_delta),
      "存在=%s 值=0:%s" % (has_delta, zero_delta))

# G6 写前路径不得发生第二次 apply
deltas = {k: cases[k]["writes_delta"] for k in ("crash_applying", "pending_newkey", "applying_newkey")}
check("G6", "写前路径服务端写入增量 = 0",
      all(v == 0 for v in deltas.values()),
      json.dumps(deltas, ensure_ascii=False))

print("=" * 72)
print("B 轨契约闸门（mock vs c9dda83）")
print("=" * 72)
for gid, desc, ok, detail in results:
    print("  [%s] %-4s %s" % ("PASS" if ok else "FAIL", gid, desc))
    if not ok:
        print("         实测：%s" % detail)
print("-" * 72)
failed = [r for r in results if not r[2]]
if failed:
    print("结论：%d/%d 项不通过 → 镜头 6 保持 BLOCKED，不得开录。" % (len(failed), len(results)))
    print("原始响应：")
    for k, v in cases.items():
        print("  %-26s %s" % (k, json.dumps(v, ensure_ascii=False)[:260]))
    print("tmp:", TMP)
    sys.exit(1)
print("结论：%d/%d 项全部通过 → B 轨可开录（仍须 4 条 MOCK 标识）。" % (len(results), len(results)))
print("tmp:", TMP)
sys.exit(0)
