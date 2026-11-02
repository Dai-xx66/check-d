#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""M3 / C 侧：独立核验 M1 证据 JSON（不采信其 pass 标志，只核事实字段）。

口径（2026-11-02 修订，M0 12:54Z 邮件指出的两处漏洞已封）
    上一版允许从 expected/got/note 文本回退提取 `proposal_status`，且零写入
    判定靠文本里是否出现"零写入"字样——两者都会让 raw 缺字段的条目被误判为
    "字段齐全"。本版起**只认 raw**，文本一律不参与取值：

      A 类（硬缺口，记「未测」，不得升 E1）
        code ∈ {READBACK_PENDING, READBACK_MISMATCH} 的条目，必须同时具备
        `raw.proposal_status`（取值合法）、`raw.writes_delta`（int）、
        `raw.retryable`（**严格布尔**，且与契约示例一致）、`raw.details`（非空数组）。
        类型不对（如 retryable="false" 字符串、writes_delta="0" 字符串）一律记未测，
        不做 bool()/int() 之类的转换——转换会把 "false" 变成 True，属漏判。

      B 类（零写入类的软缺口，单列，不混进 A 类计数）
        code ∈ ZERO_WRITE_CODES 但非 A 类的条目，必须给 `raw.writes_delta`（int=0）；
        缺失只影响该条的"零写入"结论，不影响 READBACK_* 行为判定。

      C 类（冲突，exit 1）
        越界错误码 / proposal_status 取值非法 / writes_delta≠0 / retryable 与
        契约示例相反 / writes_delta 用字符串冒充整数。

用法
    python tools/m3-checks/verify_m1_evidence.py --evidence 36ab22e:docs/contracts/reviews/m1-evidence-c53b1a9.json --contract c9dda83
    python tools/m3-checks/verify_m1_evidence.py --evidence <本地文件> --contract HEAD

退出码
    0 = 没有越界/冲突（可能仍有「未测」条目，按类分别计数）
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
# 契约示例 #21/#31/#34：PENDING 必须可重试，MISMATCH 是终态、不可重试
READBACK_RETRYABLE = {
    "READBACK_PENDING": True,
    "READBACK_MISMATCH": False,
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

    conflicts, needs_a, needs_b, notes = [], [], [], []
    self_pass = 0
    for sec, name, flags, text, raw in rows:
        ok = all(str(f).lower() in ("true", "pass") for f in flags) if flags else False
        self_pass += 1 if ok else 0

        # 该条涉及哪些错误码：raw.code 优先（机器可读），文本只用于识别"这条在讲什么码"
        found = set(re.findall(r"\b([A-Z][A-Z_]{4,})\b", text))
        raw_code = str(raw.get("code") or "").strip()
        if raw_code:
            found.add(raw_code)
        bad = {c for c in found if c not in codes and c not in NON_ERROR_CODES}
        if bad:
            conflicts.append("%s: 出现契约外错误码 %s" % (name, sorted(bad)))

        hit_readback = sorted(found & set(READBACK_PS))
        hit_zero = sorted(found & ZERO_WRITE_CODES)

        # ---- A 类：READBACK_* 四个字段必须全在 raw 里（文本一律不参与取值）----
        for code in hit_readback:
            allowed = READBACK_PS[code]
            ps = raw.get("proposal_status")
            if ps is None:
                needs_a.append("%s: %s 缺 raw.proposal_status（§4.1 强制；不接受文本回退）"
                               % (name, code))
            elif ps not in allowed:
                conflicts.append("%s: %s 的 proposal_status=%s 非法（允许 %s）"
                                 % (name, code, ps, "/".join(sorted(allowed))))

            retry = raw.get("retryable")
            if retry is None:
                needs_a.append("%s: %s 缺 raw.retryable（契约示例要求 %s）"
                               % (name, code, READBACK_RETRYABLE[code]))
            elif not isinstance(retry, bool):
                # 严格布尔：字符串 "false" / 0 / 1 一律记未测，不做 bool() 转换
                # （转换会把 "false" 变成 True，是 M0 2026-11-02T15:27Z 指出的漏判）
                needs_a.append("%s: %s 的 raw.retryable=%r 是 %s，契约要求 JSON 布尔"
                               % (name, code, retry, type(retry).__name__))
            elif retry is not READBACK_RETRYABLE[code]:
                conflicts.append("%s: %s 的 retryable=%s，与契约示例相反（应为 %s）"
                                 % (name, code, retry, READBACK_RETRYABLE[code]))

            det = raw.get("details")
            if not isinstance(det, list) or not det:
                needs_a.append("%s: %s 缺 raw.details（须为响应原样、非空数组）" % (name, code))
            elif not any(str((d or {}).get("field")) == "proposal_status" for d in det):
                notes.append("%s: %s 的 details 无 proposal_status 条目（%s）"
                             % (name, code, [str((d or {}).get("field")) for d in det]))

        # ---- B 类：零写入类必须有整数计数器（区分 bool 与 int；不接受字符串）----
        if hit_zero:
            wd = raw.get("writes_delta")
            if isinstance(wd, bool) or not isinstance(wd, int):
                needs_b.append("%s: %s 未给 raw.writes_delta 整数（实得 %r；不接受文案或字符串）"
                               % (name, "/".join(hit_zero), wd))
            elif wd != 0:
                conflicts.append("%s: writes_delta=%s ≠ 0" % (name, wd))

        if "->" in str(raw.get("got", "")) or re.search(r"[A-Z_]{5,}\s*->\s*[A-Z_]{5,}", text):
            notes.append("%s: 结果含 '->' 序列，需说明是两步语义还是修复前后（否则不可当单次判定）" % name)

        if "differ" in str(raw.get("note", "")) + text or "differs" in text:
            notes.append("%s: 自述与示例存在差异（fixture/字段），该条不能作为严格一致性证据" % name)

        # second_apply_executed 在契约里是布尔（§4.1 示例 #21），字符串 "false" 不等于 false
        sae = raw.get("second_apply_executed")
        if sae is not None and not isinstance(sae, bool):
            notes.append("%s: raw.second_apply_executed=%r 是 %s，契约示例为布尔"
                         % (name, sae, type(sae).__name__))

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
    print("未测 A（READBACK_* 缺必填 raw 字段）: %d" % len(needs_a))
    for c in needs_a:
        print("  ? %s" % c)
    print("未测 B（零写入类缺计数器，不影响 READBACK_* 行为判定）: %d" % len(needs_b))
    for c in needs_b:
        print("  ? %s" % c)
    print("需说明: %d" % len(notes))
    for c in notes:
        print("  ! %s" % c)
    return 1 if conflicts else 0


if __name__ == "__main__":
    sys.exit(main())
