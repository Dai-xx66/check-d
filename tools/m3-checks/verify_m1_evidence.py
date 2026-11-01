#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""M3 / C 侧：独立核验 M1 证据 JSON（不采信其 pass 标志，只核事实字段）。

用途
    队友提交的 evidence JSON 里每条结果都自带 `pass: true`，但**自述通过不算证据**。
    本脚本只做三件事：
      1. 把结果里出现的错误码逐个对照契约 §4.1 的 21 码闭集（越界即报）。
      2. 对 `READBACK_*` 结果，检查是否记录了 `proposal_status` 且取值合法
         （c9dda83 起 §4.1 强制要求，缺了就无法判定，记 NEEDS_EVIDENCE）。
      3. 对声称零写入的结果，检查是否给出 `writes_delta`（没给就只是口头声明）。

用法
    python tools/m3-checks/verify_m1_evidence.py --evidence 36ab22e:docs/contracts/reviews/m1-evidence-c53b1a9.json --contract c9dda83
    python tools/m3-checks/verify_m1_evidence.py --evidence <本地文件> --contract HEAD

退出码
    0 = 没有越界/冲突（可能仍有 NEEDS_EVIDENCE）
    1 = 存在越界或与契约冲突
    2 = 输入无法读取

注意
    本脚本**不执行**任何 mock，只核「记录是否足以支撑其结论」。
    「证据不足」不等于「结论错误」，但按 C 侧纪律不得升级为 E1。
"""

import argparse
import json
import re
import subprocess
import sys

READBACK_PS = {
    "READBACK_PENDING": {"applying", "readback_pending"},
    "READBACK_MISMATCH": {"failed"},
}
ZERO_WRITE_CODES = {
    "READBACK_PENDING", "READBACK_MISMATCH", "ALREADY_APPLIED",
    "APPROVAL_EXPIRED", "APPROVAL_CONSUMED", "APPROVAL_UNTRUSTED",
    "IDEMPOTENCY_IN_PROGRESS", "IDEMPOTENCY_CONFLICT", "NOT_FOUND",
}
# 这些大写标识不是错误码（explanations / violations / reason_code / duration_source 闭集），
# 不能拿去做 §4.1 的越界判定，否则会把 C2 这类枚举用例误报成"契约外错误码"。
NON_ERROR_CODES = {
    "SCHEDULED", "ESTIMATED_DURATION", "ALREADY_DONE_TODAY", "FIXED_BLOCKS_OVERLAP",
    "NO_AVAILABILITY_WINDOW", "AVAILABILITY_SATURATED", "PRESERVED_FIXED_EVENTS",
    "PLANNED_BEFORE_AVAILABLE_FROM", "PLANNED_AFTER_DATE_ONLY_DEADLINE",
    "BLOCK_AFTER_EXACT_DEADLINE", "BLOCK_TIME_INVALID", "FIXED_EVENT_CONFLICT",
    "MULTIPLE_CHANGES_FOR_ONE_TIME_TASK", "MULTIPLE_BLOCKS_FOR_RECURRING_TASK_DAY",
    "WINDOW_INSUFFICIENT", "PAST_DEADLINE", "OVERLAPS_FIXED", "NO_AVAILABILITY",
    "TASK_TARGET", "SCHEDULER_ESTIMATE",
}


def git(*args):
    return subprocess.run(["git"] + list(args), capture_output=True, check=False).stdout.decode("utf-8")


def load_evidence(spec):
    if re.match(r"^[0-9a-f]{7,40}:", spec):
        ref, path = spec.split(":", 1)
        raw = git("show", "%s:%s" % (ref, path))
    else:
        raw = open(spec, encoding="utf-8").read()
    if not raw.strip():
        print("FATAL: 读不到证据文件 %s" % spec)
        sys.exit(2)
    return json.loads(raw)


def contract_codes(sha):
    md = git("show", "%s:docs/contracts/agent-api-v1.md" % sha)
    if not md.strip():
        print("FATAL: 读不到契约 %s" % sha)
        sys.exit(2)
    return {c for c, _ in re.findall(r"^\| `([A-Z][A-Z_]+)` \| (\d{3}) \|", md, re.M)}


def norm(r):
    """把 core / examples 两种不同结构的条目统一成 (case, pass_flags, text, raw)。"""
    name = r.get("case") or r.get("name") or r.get("id") or "?"
    flags = [r[k] for k in ("pass", "status") if k in r]
    text = " ".join(str(r.get(k, "")) for k in ("expected", "got", "note"))
    return name, flags, text, (r.get("raw") or {})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--evidence", required=True, help="<ref>:<path> 或本地文件")
    ap.add_argument("--contract", default="HEAD", help="契约所在提交，默认 HEAD")
    a = ap.parse_args()

    ev = load_evidence(a.evidence)
    codes = contract_codes(a.contract)
    rows = []
    for sec in ("core", "examples"):
        for r in (ev.get(sec) or {}).get("results") or []:
            rows.append((sec,) + norm(r))

    conflicts, needs, notes = [], [], []
    self_pass = 0
    for sec, name, flags, text, raw in rows:
        ok = all(str(f).lower() in ("true", "pass") for f in flags) if flags else False
        self_pass += 1 if ok else 0

        found = set(re.findall(r"\b([A-Z][A-Z_]{4,})\b", text))
        bad = {c for c in found if c not in codes and c not in NON_ERROR_CODES}
        if bad:
            conflicts.append("%s: 出现契约外错误码 %s" % (name, sorted(bad)))

        for code, allowed in READBACK_PS.items():
            if code in found:
                ps = raw.get("proposal_status")
                if ps is None:
                    m = re.search(r"proposal_status[\"']?\s*[:=]\s*[\"']?(\w+)", text)
                    ps = m.group(1) if m else None
                if ps is None:
                    needs.append("%s: %s 未记录 proposal_status（§4.1 强制，无法判定）" % (name, code))
                elif ps not in allowed:
                    conflicts.append("%s: %s 的 proposal_status=%s 非法（允许 %s）"
                                     % (name, code, ps, "/".join(sorted(allowed))))

        # 只在用例**明确声称零写入**时才要求计数器；否则不把"没写计数"当作缺陷
        claims_zero = bool(re.search(r"零写入|writes\s*=\s*0|writes 0", text)) or (
            "writes_delta" in raw and raw.get("writes_delta") is not None)
        if claims_zero:
            if "writes_delta" not in raw and not re.search(r"writes?[_ ]?delta\s*=\s*0", text):
                needs.append("%s: 声称零写入但未给 writes_delta（raw 无计数）" % name)
            elif raw.get("writes_delta") not in (None, 0):
                conflicts.append("%s: writes_delta=%s ≠ 0" % (name, raw.get("writes_delta")))

        if "->" in str(raw.get("got", "")) or re.search(r"[A-Z_]{5,}\s*->\s*[A-Z_]{5,}", text):
            notes.append("%s: 结果含 '->' 序列，需说明是两步语义还是修复前后（否则不可当单次判定）" % name)

        if "differ" in str(raw.get("note", "")) + text or "differs" in text:
            notes.append("%s: 自述与示例存在差异（fixture/字段），该条不能作为严格一致性证据" % name)

    print("证据文件: %s" % a.evidence)
    print("契约基准: %s（%d 个错误码）" % (a.contract, len(codes)))
    print("结果条目: %d（core %s + examples %s）"
          % (len(rows), len((ev.get("core") or {}).get("results") or []),
             len((ev.get("examples") or {}).get("results") or [])))
    print("自述通过: %d / %d" % (self_pass, len(rows)))
    print()
    print("契约冲突: %d" % len(conflicts))
    for c in conflicts:
        print("  ✗ %s" % c)
    print("证据不足: %d" % len(needs))
    for c in needs:
        print("  ? %s" % c)
    print("需说明: %d" % len(notes))
    for c in notes:
        print("  ! %s" % c)
    return 1 if conflicts else 0


if __name__ == "__main__":
    sys.exit(main())
