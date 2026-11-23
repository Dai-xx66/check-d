#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""B-rail readiness probe: run the full decompose->approve->apply chain against
M1's mock server over MCP stdio, and record what READBACK_PENDING actually
returns (field name + value) plus the server-side write counter.

Read-only with respect to the repo: everything happens in a temp dir.
"""
import json
import os
import subprocess
import sys
import tempfile
import uuid

SERVER = os.path.abspath(sys.argv[1])
TMP = tempfile.mkdtemp(prefix="bprobe_")
APPROVAL_FILE = os.path.join(TMP, "approvals.json")
FLAGS_FILE = os.path.join(TMP, "flags.json")
with open(APPROVAL_FILE, "w", encoding="utf-8") as f:
    json.dump({}, f)
with open(FLAGS_FILE, "w", encoding="utf-8") as f:
    json.dump({}, f)

ENV = dict(os.environ)
ENV.update({"PYTHONIOENCODING": "utf-8", "CHECKD_TOKEN": "demo-token-alice",
            "MOCK_APPROVAL_FILE": APPROVAL_FILE, "MOCK_TEST_FLAGS": FLAGS_FILE})

p = subprocess.Popen([sys.executable, SERVER], stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=ENV,
                     text=True, encoding="utf-8", bufsize=1)
_id = [0]


def rpc(method, params=None, notify=False):
    if notify:
        p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": method, "params": params or {}},
                                 ensure_ascii=False) + "\n")
        p.stdin.flush()
        return None
    _id[0] += 1
    mid = _id[0]
    p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": mid, "method": method,
                              "params": params or {}}, ensure_ascii=False) + "\n")
    p.stdin.flush()
    while True:
        line = p.stdout.readline()
        if not line:
            raise RuntimeError("server closed stdout")
        msg = json.loads(line)
        if msg.get("id") == mid:
            return msg


def call(tool, inp):
    r = rpc("tools/call", {"name": tool, "arguments": {
        "api_version": "checkd.agent.v1",
        "request_id": "req_" + uuid.uuid4().hex[:12],
        "timezone": "Asia/Shanghai",
        "input": inp,
    }})
    res = r.get("result", {})
    payload = res.get("structuredContent") or res
    text = None
    for c in res.get("content", []) or []:
        if c.get("type") == "text":
            text = c.get("text")
    if text:
        try:
            parsed = json.loads(text)
            if isinstance(parsed, dict) and parsed.get("status") == "success":
                return parsed.get("data", {}), text
            if isinstance(parsed, dict) and parsed.get("error"):
                return {"error": parsed["error"]}, text
            return parsed, text
        except Exception:
            pass
    return payload, text


def flags(**kw):
    cur = json.load(open(FLAGS_FILE, encoding="utf-8"))
    cur.update(kw)
    json.dump(cur, open(FLAGS_FILE, "w", encoding="utf-8"), ensure_ascii=False)
    return cur


def writes():
    return json.load(open(FLAGS_FILE, encoding="utf-8")).get("writes", 0)


rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                   "clientInfo": {"name": "m3-b-rail-probe", "version": "0.1"}})
rpc("notifications/initialized", notify=True)

DR = {"start": "2026-10-29", "end": "2026-11-02"}
print("### step1 list_tasks")
r, _ = call("list_tasks", {"date_range": DR})
print("  tasks:", len(r.get("tasks", [])) if "error" not in r else r)

print("### step2 generate_schedule")
gen, _ = call("generate_schedule", {"date_range": DR})
if "error" in gen:
    print("  ERROR", gen)
    sys.exit(1)
pid, base = gen["proposal_id"], gen["base_version"]
print("  proposal_id=%s status=%s changes=%d unplanned=%d"
      % (pid, gen.get("status"), len(gen.get("changes", [])), len(gen.get("unplanned_tasks", []))))

print("### step3 validate_schedule")
val, _ = call("validate_schedule", {"proposal_id": pid})
print("  valid=%s violations=%s" % (val.get("valid"), json.dumps(val.get("violations"), ensure_ascii=False)[:200]))

print("### step4 request_approval")
ap, _ = call("request_approval", {"proposal_id": pid, "idempotency_key": "idem-appr-1"})
aid = ap.get("approval_id")
print("  approval_id=%s status=%s" % (aid, ap.get("status")))

# external approval page simulation
apv = json.load(open(APPROVAL_FILE, encoding="utf-8"))
apv[aid] = {"status": "approved"}
json.dump(apv, open(APPROVAL_FILE, "w", encoding="utf-8"), ensure_ascii=False)

print("### step5 get_approval_status -> token")
st, _ = call("get_approval_status", {"approval_id": aid})
token = st.get("approval_token")
print("  status=%s token_issued=%s" % (st.get("status"), bool(token)))

print("### step6 apply with simulate_applying_crash (Proposal really applying)")
w0 = writes()
flags(simulate_applying_crash=True)
res, text = call("apply_approved_changes", {"proposal_id": pid, "base_version": base,
                                            "approval_token": token,
                                            "idempotency_key": "idem-apply-crash"})
err = res.get("error") if isinstance(res, dict) else None
print("  raw:", json.dumps(res, ensure_ascii=False)[:600])
if err:
    print("  code=%s retryable=%s details=%s"
          % (err.get("code"), err.get("retryable"), json.dumps(err.get("details"), ensure_ascii=False)))
print("  writes_delta:", writes() - w0)

print("### step7 same key retry (idempotent in-progress)")
res2, _ = call("apply_approved_changes", {"proposal_id": pid, "base_version": base,
                                          "approval_token": token,
                                          "idempotency_key": "idem-apply-crash"})
e2 = res2.get("error") if isinstance(res2, dict) else None
if e2:
    print("  code=%s retryable=%s details=%s"
          % (e2.get("code"), e2.get("retryable"), json.dumps(e2.get("details"), ensure_ascii=False)))
else:
    print("  raw:", json.dumps(res2, ensure_ascii=False)[:400])

print("### step8 same key again (should converge or stay pending)")
res3, _ = call("apply_approved_changes", {"proposal_id": pid, "base_version": base,
                                          "approval_token": token,
                                          "idempotency_key": "idem-apply-crash"})
e3 = res3.get("error") if isinstance(res3, dict) else None
print("  code=%s details=%s" % ((e3 or {}).get("code"), json.dumps((e3 or {}).get("details"), ensure_ascii=False)))

p.terminate()
try:
    tail = p.communicate(timeout=5)[1]
except Exception:
    tail = ""
if tail:
    print("### stderr tail")
    print(tail[-400:])
print("### files:", TMP)
