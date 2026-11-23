#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Second B-rail probe: the readback_mismatch path (proposal -> readback_pending)
and the pre-existing pending-proposal path. Records error.details verbatim."""
import json
import os
import subprocess
import sys
import tempfile
import uuid

SERVER = os.path.abspath(sys.argv[1])
TMP = tempfile.mkdtemp(prefix="bprobe2_")
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
            raise RuntimeError("closed")
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
                return d.get("data", {}), d
            return {"error": d.get("error")}, d
    return {}, {}


def setflag(**kw):
    cur = json.load(open(FLAGS_FILE))
    cur.update(kw)
    json.dump(cur, open(FLAGS_FILE, "w"), ensure_ascii=False)


def writes():
    return json.load(open(FLAGS_FILE)).get("writes", 0)


rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                   "clientInfo": {"name": "m3-probe2", "version": "0.1"}})
rpc("notifications/initialized", notify=True)
DR = {"start": "2026-10-29", "end": "2026-11-02"}


def make_approved_proposal():
    gen, _ = call("generate_schedule", {"date_range": DR})
    pid, base = gen["proposal_id"], gen["base_version"]
    call("validate_schedule", {"proposal_id": pid})
    ap, _ = call("request_approval", {"proposal_id": pid, "idempotency_key": "k-appr-" + pid})
    aid = ap["approval_id"]
    apv = json.load(open(APPROVAL_FILE))
    apv[aid] = {"status": "approved"}
    json.dump(apv, open(APPROVAL_FILE, "w"), ensure_ascii=False)
    st, _ = call("get_approval_status", {"approval_id": aid})
    return pid, base, st.get("approval_token")


print("=== case A: readback_mismatch flag (write ok, readback not converged) ===")
pid, base, tok = make_approved_proposal()
w0 = writes()
setflag(readback_mismatch=True)
r, env = call("apply_approved_changes", {"proposal_id": pid, "base_version": base,
                                         "approval_token": tok, "idempotency_key": "k-apply-a"})
err = r.get("error") or {}
print("  status=", env.get("status"), "code=", err.get("code"), "retryable=", err.get("retryable"))
print("  details=", json.dumps(err.get("details"), ensure_ascii=False))
print("  writes_delta=", writes() - w0)

print("=== case B: pre-existing pending proposal, same key retry (new key) ===")
r2, env2 = call("apply_approved_changes", {"proposal_id": pid, "base_version": base,
                                           "approval_token": tok, "idempotency_key": "k-apply-a2"})
e2 = r2.get("error") or {}
print("  code=", e2.get("code"), "retryable=", e2.get("retryable"))
print("  details=", json.dumps(e2.get("details"), ensure_ascii=False))
print("  message=", e2.get("message"))

print("=== case C: same key retry on that proposal (idempotent replay) ===")
r3, env3 = call("apply_approved_changes", {"proposal_id": pid, "base_version": base,
                                           "approval_token": tok, "idempotency_key": "k-apply-a"})
if "error" in r3:
    e3 = r3["error"]
    print("  code=", e3.get("code"), "details=", json.dumps(e3.get("details"), ensure_ascii=False))
else:
    print("  success payload keys:", list(r3.keys()))

print("=== case D: proposal_status after the above (re-read via list_tasks not applicable) ===")
print("  (proposal state only visible through apply responses in this mock)")

p.terminate()
try:
    tail = p.communicate(timeout=5)[1]
except Exception:
    tail = ""
if tail:
    print("stderr tail:", tail[-300:])
print("tmp:", TMP)
