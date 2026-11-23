"""M3 独立复核：1baf95d 的块间重叠（生成侧 + 校验侧 + 顺序回归）。

不复用 M1 的 test_block_overlap.py 断言，自算重叠、自定期望值；
工具面走 MCP JSON-RPC，单元面直接 import tool_server 调用 check_hard_constraints。
"""
import json
import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from demo_driver import Driver  # noqa: E402

RANGE = {"start": "2026-10-29", "end": "2026-11-01"}
MEETING = {"external_event_id": "ext_meeting_1030",
           "title": "临时会议（外部日历）",
           "start_at": "2026-10-30T15:00:00+08:00",
           "end_at": "2026-10-30T16:30:00+08:00"}
PREFS = {"day_start_minute": 480, "day_end_minute": 1350, "minimum_block_minutes": 25}

CONTRACT_CODES = {
    "PLANNED_BEFORE_AVAILABLE_FROM", "PLANNED_AFTER_DATE_ONLY_DEADLINE",
    "BLOCK_AFTER_EXACT_DEADLINE", "BLOCK_TIME_INVALID", "FIXED_EVENT_CONFLICT",
    "MULTIPLE_CHANGES_FOR_ONE_TIME_TASK", "MULTIPLE_BLOCKS_FOR_RECURRING_TASK_DAY",
}
RULED_NEW = {"BLOCK_OVERLAP"}

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond), detail))
    print("  [%s] %s  %s" % ("PASS" if cond else "FAIL", name, detail))


def t(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def overlap_pairs(blocks):
    out = []
    for i in range(len(blocks)):
        for j in range(i + 1, len(blocks)):
            a, b = blocks[i], blocks[j]
            if t(a["start_at"]) < t(b["end_at"]) and t(b["start_at"]) < t(a["end_at"]):
                out.append((a["block_id"], b["block_id"]))
    return out


def envelope(box):
    """demo_driver.call 返回 structuredContent：{"status":..., "data":{...}}"""
    return box or {}


def main(mock_path):
    print("=" * 72)
    print("M3 独立复核 1baf95d：块间重叠")
    print("=" * 72)

    # ---------------------------------------------------------------- A 正常路径
    print("A 工具面：正常生成 + 校验")
    d = Driver(mock_path)
    try:
        _, box = d.call("generate_schedule",
                        {"date_range": RANGE, "external_fixed_events": [MEETING],
                         "preferences": PREFS})
        data = envelope(box).get("data") or {}
        blocks = data.get("blocks") or []
        pairs = overlap_pairs(blocks)
        print("    blocks=%d  分钟=%s  proposal=%s" % (
            len(blocks), sum(int((t(b["end_at"]) - t(b["start_at"])) // 60) for b in blocks),
            (data.get("proposal_id") or "")[:14]))
        for b in blocks:
            print("      %-8s %-20s %s → %s" % (b.get("block_id"), b.get("task_id"),
                                                b["start_at"], b["end_at"]))
        check("A1 块间重叠 = 0", len(pairs) == 0, "pairs=%d %s" % (len(pairs), pairs))
        check("A2 unplanned 为空", not (data.get("unplanned_tasks") or []),
              "n=%d" % len(data.get("unplanned_tasks") or []))

        pid = data["proposal_id"]
        _, vbox = d.call("validate_schedule", {"proposal_id": pid})
        vd = envelope(vbox).get("data") or {}
        codes = [v.get("code") for v in (vd.get("violations") or [])]
        check("A3 validation_status=valid", vd.get("validation_status") == "valid",
              "status=%s" % vd.get("validation_status"))
        check("A4 violations 为空（这次 0 是真的）", not codes, "codes=%s" % codes)
    finally:
        d.proc.kill()

    # ---------------------------------------------------------------- B 注入路径
    print("B 工具面：注入重叠 → 校验必须 invalid + BLOCK_OVERLAP")
    d = Driver(mock_path)
    try:
        with open(d.flags_file, "w", encoding="utf-8") as f:
            json.dump({"inject_overlapping_blocks": True}, f)
        _, box = d.call("generate_schedule",
                        {"date_range": RANGE, "external_fixed_events": [MEETING],
                         "preferences": PREFS})
        data = envelope(box).get("data") or {}
        blocks = data.get("blocks") or []
        pairs = overlap_pairs(blocks)
        check("B1 注入生效（提案内确实重叠）", len(pairs) > 0,
              "pairs=%d %s" % (len(pairs), pairs[:3]))
        _, vbox = d.call("validate_schedule", {"proposal_id": data["proposal_id"]})
        res = envelope(vbox)
        vd = res.get("data") or {}
        vs = vd.get("violations") or []
        codes = [v.get("code") for v in vs]
        check("B2 走正常校验响应，不是结构错误",
              res.get("status") == "success" and not res.get("isError"),
              "status=%s isError=%s" % (res.get("status"), res.get("isError")))
        check("B3 未出现 PROPOSAL_INVALID",
              "PROPOSAL_INVALID" not in json.dumps(res, ensure_ascii=False),
              "codes=%s" % codes)
        check("B4 validation_status=invalid",
              vd.get("validation_status") == "invalid",
              "status=%s" % vd.get("validation_status"))
        ov = [v for v in vs if v.get("code") == "BLOCK_OVERLAP"]
        check("B5 violations 含且仅含 1 条 BLOCK_OVERLAP", len(ov) == 1, "codes=%s" % codes)
        if ov:
            got = sorted(ov[0].get("related_block_ids") or [])
            expect = sorted({i for pr in pairs for i in pr})
            check("B6 related_block_ids 指向冲突双方", got == expect,
                  "got=%s expect=%s" % (got, expect))
            check("B7 带 message 与 related_task_ids",
                  bool(ov[0].get("message")) and bool(ov[0].get("related_task_ids")),
                  "tasks=%s" % ov[0].get("related_task_ids"))
        bad = [c for c in codes if c not in CONTRACT_CODES | RULED_NEW]
        check("B8 无契约外码", not bad, "bad=%s" % bad)
    finally:
        d.proc.kill()

    # ---------------------------------------------------------------- C 顺序回归（单元面）
    print("C 单元面：重叠 + 固定事件冲突共存时两条都要报")
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(mock_path))))
    import tool_server as ts  # noqa: E402

    proposal = {"blocks": [
        {"block_id": "b_1", "task_id": "t_1", "task_kind": "one_time",
         "start_at": "2026-10-29T09:00:00+08:00", "end_at": "2026-10-29T10:30:00+08:00"},
        {"block_id": "b_2", "task_id": "t_2", "task_kind": "one_time",
         "start_at": "2026-10-29T10:00:00+08:00", "end_at": "2026-10-29T11:00:00+08:00"},
    ], "changes": []}
    events = [{"event_id": "ev_1", "fixed": True, "date": "2026-10-29",
               "start_at": "2026-10-29T09:30:00+08:00",
               "end_at": "2026-10-29T09:45:00+08:00"}]
    vs = ts.check_hard_constraints(proposal, events)
    codes = [v.get("code") for v in vs]
    check("C1 同时报 BLOCK_OVERLAP 与 FIXED_EVENT_CONFLICT",
          "BLOCK_OVERLAP" in codes and "FIXED_EVENT_CONFLICT" in codes, "codes=%s" % codes)
    check("C2 块间检测未提前 return（块 vs 块只报一条）",
          codes.count("BLOCK_OVERLAP") == 1, "codes=%s" % codes)

    # ---------------------------------------------------------------- D 单块 vs 固定事件
    print("D 单元面：单块压固定事件只报 FIXED_EVENT_CONFLICT")
    p2 = {"blocks": [{"block_id": "b_x", "task_id": "t_x", "task_kind": "one_time",
                      "start_at": "2026-10-29T09:00:00+08:00",
                      "end_at": "2026-10-29T10:00:00+08:00"}], "changes": []}
    ev2 = [{"event_id": "ev_1", "fixed": True, "date": "2026-10-29",
            "start_at": "2026-10-29T09:30:00+08:00",
            "end_at": "2026-10-29T10:30:00+08:00"}]
    vs2 = ts.check_hard_constraints(p2, ev2)
    codes2 = [v.get("code") for v in vs2]
    check("D1 单块场景不误报 BLOCK_OVERLAP", "BLOCK_OVERLAP" not in codes2, "codes=%s" % codes2)
    check("D2 仍报 FIXED_EVENT_CONFLICT", "FIXED_EVENT_CONFLICT" in codes2, "codes=%s" % codes2)

    # ---------------------------------------------------------------- 汇总
    print("-" * 72)
    failed = [r for r in results if not r[1]]
    print("结论：%d/%d 通过，失败 %d" % (len(results) - len(failed), len(results), len(failed)))
    for name, _, detail in failed:
        print("  FAIL:", name, detail)
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
