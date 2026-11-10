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

# 窗口改成「相对明天」，不再写死 2026-10-29。
# 原因：写死日期会随时间腐烂——2026-11-10 之后整个窗口在过去，
# mock 会把所有任务判成「窗口在过去、未生成块」，T1/T2 全部失去意义。
from datetime import date as _date, timedelta as _timedelta  # noqa: E402

_D1 = _date.today() + _timedelta(days=1)
DAY1 = _D1.isoformat()                       # 窗口第一天（明天）
WINDOW = {"start": DAY1, "end": (_D1 + _timedelta(days=3)).isoformat()}

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
        # 逾期任务被摘出 blocks 是**正确**行为（M0 2026-11-05 P0-1/P0-2），不算「被挤掉」。
        # 内建夹具 t_1001 / t_1002 的截止写死在 2026-10-31 与 2026-11-02，随真实时间必然过期，
        # 所以这里按 reason_code 过滤，而不是硬要求 unplanned 为空——
        # 否则这条断言会随日历自己变红，与被测逻辑无关。
        blocked = [u for u in p["unplanned_tasks"]
                   if u.get("reason_code") != "UNSCHEDULABLE_OVERDUE"]
        outdated = [u["task_id"] for u in p["unplanned_tasks"]
                    if u.get("reason_code") == "UNSCHEDULABLE_OVERDUE"]
        check("T1.2 无任务被挤掉（逾期摘出不算）", len(blocked) == 0,
              "blocked=%s outdated=%s" % ([u["task_id"] for u in blocked], outdated))
        v = data(c.call("validate_schedule", {"proposal_id": p["proposal_id"]}))
        check("T1.3 校验结论为 valid 且无 violation",
              v["validation_status"] == "valid" and v["violations"] == [],
              "status=%s violations=%s" % (v["validation_status"], v["violations"]))
    finally:
        c.p.kill()

    # T1.4 固定事件冲突检测未被削弱（单元级，构造块 vs 固定事件重叠）
    proposal = {"blocks": [{"block_id": "b_x", "task_id": "t_x", "task_kind": "one_time",
                            "start_at": DAY1 + "T09:00:00+08:00",
                            "end_at": DAY1 + "T10:00:00+08:00"}],
                "changes": []}
    events = [{"event_id": "ev_1", "fixed": True, "date": DAY1,
               "start_at": DAY1 + "T09:30:00+08:00",
               "end_at": DAY1 + "T10:30:00+08:00"}]
    violations = ts.check_hard_constraints(proposal, events)
    codes = [x["code"] for x in violations]
    check("T1.4 固定事件冲突仍报 FIXED_EVENT_CONFLICT",
          "FIXED_EVENT_CONFLICT" in codes, "codes=%s" % codes)

    # T1.5 检测顺序（M0 要求 5）：同时存在块间重叠与固定事件冲突时，
    # FIXED_EVENT_CONFLICT 仍必须先于 BLOCK_OVERLAP 出现，不能被新码抢占。
    mixed = {"blocks": [
        {"block_id": "b_p", "task_id": "t_p", "task_kind": "one_time",
         "start_at": DAY1 + "T09:00:00+08:00", "end_at": DAY1 + "T10:00:00+08:00"},
        {"block_id": "b_q", "task_id": "t_q", "task_kind": "one_time",
         "start_at": DAY1 + "T09:30:00+08:00", "end_at": DAY1 + "T10:30:00+08:00"}],
        "changes": []}
    ev_ = [{"event_id": "ev_1", "fixed": True, "date": DAY1,
            "start_at": DAY1 + "T09:15:00+08:00",
            "end_at": DAY1 + "T09:45:00+08:00"}]
    mixed_codes = [x["code"] for x in ts.check_hard_constraints(mixed, ev_)]
    check("T1.5 混合场景下 FIXED_EVENT_CONFLICT 不被 BLOCK_OVERLAP 抢占",
          "FIXED_EVENT_CONFLICT" in mixed_codes and "BLOCK_OVERLAP" in mixed_codes
          and mixed_codes.index("FIXED_EVENT_CONFLICT") < mixed_codes.index("BLOCK_OVERLAP"),
          "codes=%s" % mixed_codes)


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
        env = envelope(r)
        check("T2.2 走正常校验响应，不是结构错误",
              env.get("status") == "success" and not r["result"].get("isError"),
              "status=%s" % env.get("status"))
        v = env.get("data") or {}
        check("T2.3 validation_status=invalid", v.get("validation_status") == "invalid",
              "validation_status=%s" % v.get("validation_status"))
        vs = v.get("violations") or []
        overlap = [x for x in vs if x.get("code") == "BLOCK_OVERLAP"]
        check("T2.4 violations 含 BLOCK_OVERLAP", len(overlap) == 1,
              "codes=%s" % [x.get("code") for x in vs])

        ids = sorted(overlap[0].get("related_block_ids") or []) if overlap else []
        expect = sorted({i for pr in pairs for i in pr})
        check("T2.5 related_block_ids 指向冲突双方",
              len(ids) == 2 and ids == expect,
              "related_block_ids=%s expect=%s" % (ids, expect))
        check("T2.6 带 message 与 related_task_ids",
              bool(overlap and overlap[0].get("message"))
              and bool(overlap and overlap[0].get("related_task_ids")),
              "message=%r related_task_ids=%s" % (
                  (overlap[0].get("message") or "")[:40] if overlap else None,
                  overlap[0].get("related_task_ids") if overlap else None))
    finally:
        c.p.kill()


def t3_window_in_the_past():
    """窗口整体在过去：不许产出任何块，但每个任务都要有「为什么没排」的出口。

    M2 2026-11-10T01:37 报的缺陷 1 就是这个：range=11-09、now=11-10 时，
    旧实现照排 11-09 08:00-09:00，把块排进了过去，而且那些块是可审批的。
    """
    print("T3 窗口整体在过去：不排块 + 每个任务都有未排出口")
    past_end = _date.today() - _timedelta(days=1)
    past_start = _date.today() - _timedelta(days=3)
    c = ev.Client()
    try:
        p = data(c.call("generate_schedule", {
            "date_range": {"start": past_start.isoformat(),
                           "end": past_end.isoformat()}}))
        check("T3.1 不产出任何块", len(p["blocks"]) == 0,
              "blocks=%d" % len(p["blocks"]))
        codes = {u.get("reason_code") for u in p["unplanned_tasks"]}
        check("T3.2 未排原因用闭集内的 NO_AVAILABILITY",
              codes == {"NO_AVAILABILITY"}, "codes=%s" % sorted(codes))
        check("T3.3 未排条数 = 全部 active 任务数",
              len(p["unplanned_tasks"]) > 0,
              "unplanned=%d" % len(p["unplanned_tasks"]))
        basis = (p["unplanned_tasks"][0].get("basis") or {}) if p["unplanned_tasks"] else {}
        check("T3.4 basis 写明窗口与今天",
              "window" in basis and "today" in basis,
              "basis_keys=%s" % sorted(basis))
    finally:
        c.p.kill()


def t4_recurring_target_not_floored():
    """周期任务有 duration_target 时，块长必须等于 target，**不 floor 到最小块**。

    M2 2026-11-10T03:07 用跨实现比对实测出来的那一处：target=600s、min_block=30，
    旧实现给 30 分钟块，他的 Dart 引擎给 10 分钟 + `task_target`。
    契约 `39f7f965` L288–293 写死 `duration_target_seconds` 优先，
    `max(minimum_block_minutes, 30)` 只是两者都没有时的兜底。
    """
    print("T4 周期任务时长：有 target 不 floor，无 target 才走兜底")
    prefs = {"day_start_minute": 480, "day_end_minute": 1320,
             "minimum_block_minutes": 30}

    def run(tasks):
        return ts.schedule({"range": [DAY1, DAY1], "tasks": tasks, "courses": [],
                            "external_fixed_events": [], "overrides": [],
                            "base_version": "x", "snapshot_ref": None}, prefs)[0]

    with_target = run([{"task_id": "t_tgt", "kind": "long_term", "status": "active",
                        "duration_target_seconds": 600, "name": "十分钟周期",
                        "recurrence": {"preset": "daily", "weekdays": [1, 2, 3, 4, 5]}}])
    check("T4.1 有 target 的周期任务块长 = target（600s）",
          bool(with_target) and with_target[0]["duration_seconds"] == 600,
          "dur=%s" % (with_target[0]["duration_seconds"] if with_target else None))
    check("T4.2 时长来源标 task_target",
          bool(with_target) and with_target[0]["duration_source"] == "task_target",
          "source=%s" % (with_target[0]["duration_source"] if with_target else None))

    no_target = run([{"task_id": "t_est", "kind": "long_term", "status": "active",
                      "duration_target_seconds": None, "name": "无目标周期",
                      "recurrence": {"preset": "daily", "weekdays": [1, 2, 3, 4, 5]}}])
    check("T4.3 无 target 走兜底 max(min_block, 30) = 1800s",
          bool(no_target) and no_target[0]["duration_seconds"] == 1800,
          "dur=%s" % (no_target[0]["duration_seconds"] if no_target else None))
    check("T4.4 兜底标记 scheduler_estimate",
          bool(no_target) and no_target[0]["duration_source"] == "scheduler_estimate",
          "source=%s" % (no_target[0]["duration_source"] if no_target else None))

    # 用户把最小块设得比 30 还小时，兜底仍应是 30 —— 契约写的是「两者取大」。
    small = ts.schedule({"range": [DAY1, DAY1], "tasks": [
        {"task_id": "t_small", "kind": "long_term", "status": "active",
         "duration_target_seconds": None, "name": "小最小块",
         "recurrence": {"preset": "daily", "weekdays": [1, 2, 3, 4, 5]}}],
        "courses": [], "external_fixed_events": [], "overrides": [],
        "base_version": "x", "snapshot_ref": None},
        {"day_start_minute": 480, "day_end_minute": 1320,
         "minimum_block_minutes": 10})[0]
    check("T4.5 min_block=10 时兜底仍是 30 分钟（两者取大）",
          bool(small) and small[0]["duration_seconds"] == 1800,
          "dur=%s" % (small[0]["duration_seconds"] if small else None))


def main():
    print("=" * 72)
    print("P1 回归：提案块间重叠（mock vs c9dda83）")
    print("=" * 72)
    t1_normal_generation()
    t2_injected_overlap_must_be_rejected()
    t3_window_in_the_past()
    t4_recurring_target_not_floored()
    print("-" * 72)
    if failures:
        print("结论：%d 项未通过 -> %s" % (len(failures), failures))
        return 1
    print("结论：全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
