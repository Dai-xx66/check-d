#!/usr/bin/env python3
"""验收证据索引自检。

只依赖标准库。校验 docs/contest/evidence-index.md：

1. 65 个证据 ID 是否齐全（9 场景 / 13 边界 / 15 拆解 / 23 契约 / 5 本轮增量）
2. 结果列是否只用允许的枚举（未测 / PASS / FAIL / BLOCKED / 部分）
3. 任何非「未测」的行，证据位置是否非空——防止填了结论却没有证据
4. 文末统计表的合计与明细是否自洽
5. 是否出现「基本通过」「差不多」这类模糊结论

用法:
    python tools/m3-checks/check_evidence_index.py
    python tools/m3-checks/check_evidence_index.py --verbose

退出码: 0 全部通过 / 1 存在问题
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
INDEX = REPO / "docs/contest/evidence-index.md"

ALLOWED_RESULTS = {"未测", "PASS", "FAIL", "BLOCKED", "部分"}
ALLOWED_LEVELS = {"E0", "E1", "E2", "E3"}
VAGUE = ["基本通过", "差不多", "大概通过", "应该没问题", "已优化"]
RESULT_RE = re.compile(r"^(未测|PASS|FAIL|BLOCKED|部分)(?:\((E[0-3])\))?$")

EXPECTED_IDS: list[str] = []
for scenario in ("A", "B", "C"):
    for run in (1, 2, 3):
        EXPECTED_IDS.append(f"EV-S-{scenario}{run}")
EXPECTED_IDS += [f"EV-E{i:02d}" for i in range(1, 14)]
EXPECTED_IDS += [f"EV-DA{i:02d}" for i in range(1, 16)]
EXPECTED_IDS += [
    "EV-T01", "EV-T02", "EV-T03-a", "EV-T03-b", "EV-T04", "EV-T04-b",
    "EV-T05", "EV-T06", "EV-T07", "EV-T08", "EV-T09", "EV-T10", "EV-T11",
    "EV-T12", "EV-T12-b", "EV-T15", "EV-T16", "EV-T17", "EV-T18", "EV-T19",
    "EV-T20", "EV-T21", "EV-T22",
    # 2026-10-31 本轮增量（M0 契约调整后，见矩阵 §3B）
    "EV-R1", "EV-X1", "EV-G1", "EV-G2", "EV-G3", "EV-G4", "EV-G5", "EV-S1",
    # A 侧 EX-01–EX-20 回放，C 独立复核（见 docs/contest/ex-replay-evidence.md）
] + [f"EV-EX{i:02d}" for i in range(1, 21)]

failures: list[str] = []
checks = 0


def check(cond: bool, msg: str) -> bool:
    global checks
    checks += 1
    if not cond:
        failures.append(msg)
    return cond


def parse_rows(text: str) -> list[list[str]]:
    rows = []
    for line in text.splitlines():
        if not line.startswith("| EV-"):
            continue
        cells = [c.strip() for c in line.split("|")[1:-1]]
        rows.append(cells)
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description="校验验收证据索引")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    if not INDEX.exists():
        print(f"FATAL 找不到 {INDEX}")
        return 1

    text = INDEX.read_text(encoding="utf-8")
    rows = parse_rows(text)

    ids = [r[0] for r in rows]
    check(len(ids) == len(set(ids)), f"证据 ID 重复：{[i for i in ids if ids.count(i) > 1]}")

    missing = [i for i in EXPECTED_IDS if i not in ids]
    extra = [i for i in ids if i not in EXPECTED_IDS]
    check(not missing, f"缺少证据行 {len(missing)} 条：{missing}")
    check(not extra, f"出现未定义的证据 ID：{extra}")
    check(len(rows) == len(EXPECTED_IDS), f"行数应为 {len(EXPECTED_IDS)}，实际 {len(rows)}")

    tested = 0
    for cells in rows:
        rid = cells[0]
        # 最后一列为结果，倒数第二列为证据位置
        result = cells[-1].replace("*", "").strip()
        evidence = cells[-2].strip() if len(cells) >= 2 else ""
        m = RESULT_RE.match(result)
        check(bool(m), f"{rid} 结果「{result}」不在允许枚举内（允许：未测/PASS/FAIL/BLOCKED/部分，非未测须带级别如 PASS(E1)）")
        if m:
            verdict, level = m.group(1), m.group(2)
            check(verdict in ALLOWED_RESULTS, f"{rid} 结论枚举非法：{verdict}")
            if level:
                check(level in ALLOWED_LEVELS, f"{rid} 证据级别非法：{level}")
            if verdict != "未测":
                check(bool(level), f"{rid} 结论「{verdict}」未标证据级别（E0–E3），不接受")
                tested += 1
                check(bool(evidence), f"{rid} 已给结论「{result}」但证据位置为空")
                check(len(evidence) > 3, f"{rid} 证据位置过短：{evidence}")
        for word in VAGUE:
            check(word not in " ".join(cells), f"{rid} 出现模糊结论「{word}」，不接受")

    # 统计表自洽
    m = re.search(r"\|\s*\*\*合计\*\*\s*\|\s*\*\*(\d+)\*\*\s*\|\s*\*\*(\d+)\*\*\s*\|\s*\*\*(\d+)\*\*", text)
    if m:
        total, done, pending = (int(g) for g in m.groups())
        check(total == len(EXPECTED_IDS), f"统计表合计 {total}，实际应有 {len(EXPECTED_IDS)}")
        check(done == tested, f"统计表已取证 {done}，实际非「未测」行 {tested}")
        check(done + pending == total, f"统计表分项不自洽：{done}+{pending}≠{total}")
    else:
        check(False, "未找到统计表「合计」行")

    print(f"== 证据索引自检 ==")
    print(f"  文件：{INDEX.relative_to(REPO)}")
    print(f"  证据行：{len(rows)}（期望 {len(EXPECTED_IDS)}）")
    print(f"  已取证：{tested} / 未测：{len(rows) - tested}")
    if args.verbose:
        print(f"  允许的结果枚举：{sorted(ALLOWED_RESULTS)}")
    print(f"\n共执行 {checks} 项检查，失败 {len(failures)} 项")
    for item in failures:
        print(f"  FAIL {item}")
    if failures:
        return 1
    print("全部通过 ✓")
    return 0


if __name__ == "__main__":
    sys.exit(main())
