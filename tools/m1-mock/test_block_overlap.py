#!/usr/bin/env python3
"""P1 regression tests: proposal blocks must not overlap.

Covers M0's acceptance requirements (2026-11-03 mail):
  T1  normal generation -> blocks pairwise disjoint, no task dropped,
      fixed-event conflict check still effective
  T2  injected overlapping blocks (bypassing generation) ->
      validate_schedule must reject the proposal

Run:
  cd /e/DSHWP/SmallCompetition/work/repo/check-d
  PYTHONIOENCODING=utf-8 python tools/m1-mock/test_block_overlap.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import run_evidence_c53 as ev  # noqa: E402  (MCP stdio client)
import tool_server as ts  # noqa: E402  (unit-level checks)

# M3's original 彩排 window; no preferences.
WINDOW = {"start": "2026-10-29", "end": "2026-11-01"}

failures = []


def check(name, cond, detail=""):
    if cond:
        print("  [PASS] %s%s" % (name, ("  " + detail) if detail else ""))
    else:
        print("  [FAIL] %s%s" % (name, ("  " + detail) if detail else ""))
        failures.append(name)


def envelope(rpc_resp):
    return json.loads(rpc_resp["result"]["content"][0]["text"])


def data(rpc_resp):
    env = envelope(rpc_resp)
    if env.get("status") != "success":
        raise SystemExit("call failed: %s" % json.dumps(env, ensure_ascii=False)[:400])
    return env["data"]


def count_overlaps(blocks):
    """Independent of server code on purpose: sort and compare. Returns pairs."""
    rows = sorted((b["start_at"], b["end_at"], b["block_id"], b["task_id"]) for b in blocks)
    pairs = []
    for i in range(len(rows)):
        for j in range(i + 1, len(rows)):
            if rows[j][0] >= rows[i][1]:
                break
            pairs.append((rows[i][2], rows[j][2]))
    return pairs


def t1_normal_generation():
    print("T1 正常生成：blocks 两两不重叠 + 固定事件冲突检查仍有效")
    c = ev.Client()
    try:
        p = data(c.call("generate_schedule", {"date_range": WINDOW}))
        blocks = p["blocks"]
        pairs = count_overlaps(blocks)
        check("T1.1 块间重叠为 0", len(pairs) == 0,
              "blocks=%d overlaps=%d" % (len(blocks), len(pairs)))
        check("T1.2 无任务被挤掉", len(p["unplanned_tasks"]) == 0,
              "unplanned=%s" % [u["task_id"] for u in p["unplanned_tasks"]])
        v = data(c.call("validate_schedule", {"proposal_id": p["proposal_id"]}))
        check("T1.3 校验结论为 valid 且无 violation",
              v["validation_status"] == "valid" and v["violations"] == [],
              "status=%s violations=%s" % (v["validation_status"], v["violations"]))
    finally:
        c.p.kill()

    # T1.4 固定事件冲突检测未被削弱（单元级，构造块 vs 固定事件重叠）
    proposal = {"blocks": [{"block_id": "b_x", "task_id": "t_x", "task_kind": "one_time",
                            "start_at": "2026-10-29T09:00:00+08:00",
                            "end_at": "2026-10-29T10:00:00+08:00"}],
                "changes": []}
    events = [{"event_id": "ev_1", "fixed": True, "date": "2026-10-29",
               "start_at": "2026-10-29T09:30:00+08:00",
               "end_at": "2026-10-29T10:30:00+08:00"}]
    violations = ts.check_hard_constraints(proposal, events)
    codes = [x["code"] for x in violations]
    check("T1.4 固定事件冲突仍报 FIXED_EVENT_CONFLICT",
          "FIXED_EVENT_CONFLICT" in codes, "codes=%s" % codes)


def t2_injected_overlap_must_be_rejected():
    print("T2 注入重叠 blocks（绕过生成阶段）：validate 必须拒绝")
    c = ev.Client()
    try:
        ev.set_flags({"inject_overlapping_blocks": True})
        p = data(c.call("generate_schedule", {"date_range": WINDOW}))
        pairs = count_overlaps(p["blocks"])
        check("T2.1 注入生效（提案内确实重叠）", len(pairs) > 0,
              "overlap_pairs=%d" % len(pairs))

        r = c.call("validate_schedule", {"proposal_id": p["proposal_id"]})
        check("T2.2 validate 以 error 拒绝该提案",
              r["result"].get("isError") is True)
        env = envelope(r)
        err = env.get("error") or (env.get("data") or {}).get("error") or {}
        check("T2.3 错误码为 PROPOSAL_INVALID", err.get("code") == "PROPOSAL_INVALID",
              "code=%s" % err.get("code"))
        details = err.get("details") or []
        ids = sorted({i for d in details for i in d.get("block_ids", [])})
        check("T2.4 details 给出 reason 与涉及的 block_id",
              bool(details) and all(d.get("reason") == "BLOCK_OVERLAP" for d in details)
              and len(ids) >= 2,
              "reason=%s block_ids=%s" % (
                  sorted({d.get("reason") for d in details}), ids))
    finally:
        c.p.kill()


def main():
    print("=" * 72)
    print("P1 回归：提案块间重叠（mock vs c9dda83）")
    print("=" * 72)
    t1_normal_generation()
    t2_injected_overlap_must_be_rejected()
    print("-" * 72)
    if failures:
        print("结论：%d 项未通过 -> %s" % (len(failures), failures))
        return 1
    print("结论：全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
