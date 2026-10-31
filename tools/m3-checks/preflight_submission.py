#!/usr/bin/env python3
"""提交材料预检（匿名 / 隐私 / 密钥 / 占位符）。

只扫「将来会交出去的材料」，不扫内部说明文档——内部文档引用赛题原名是正常的，
提交材料里出现学校/学院/姓名则是**一票否决**（方案原件附件一原文）。

用法:
    python tools/m3-checks/preflight_submission.py
    python tools/m3-checks/preflight_submission.py --all    # 连 evidence/ 一起扫
    python tools/m3-checks/preflight_submission.py --verbose

退出码: 0 无问题 / 1 存在命中
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

# 会进入提交包的文件（随材料增加而扩充）
SUBMIT_FILES = [
    "docs/contest/submission-outline.md",
    "docs/contest/demo-script.md",
    "docs/contest/oss-disclosure.md",
]

RULES: list[tuple[str, re.Pattern[str]]] = [
    ("学校/学院名", re.compile(r"广州航海学院|人工智能学院|[\u4e00-\u9fa5]{2,6}大学|[\u4e00-\u9fa5]{2,6}学院")),
    ("手机号", re.compile(r"(?<!\d)1[3-9]\d{9}(?!\d)")),
    ("身份证号", re.compile(r"(?<!\d)\d{17}[\dXx](?!\d)")),
    ("邮箱", re.compile(r"[\w.+-]+@[\w-]+\.[\w.]{2,}")),
    ("学号(10-12位连续数字)", re.compile(r"(?<!\d)\d{10,12}(?!\d)")),
    ("身份字段", re.compile(r"(姓名|学生姓名|指导教师|任课教师|学号|班级)\s*[:：]\s*\S")),
    ("API 密钥", re.compile(r"sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}")),
    ("密钥赋值", re.compile(r"(api[_-]?key|secret|password|token)\s*[:=]\s*['\"]?[A-Za-z0-9._\-]{8,}", re.I)),
    ("Bearer 串", re.compile(r"Bearer\s+[A-Za-z0-9._\-]{20,}")),
    ("真实用户路径", re.compile(r"[A-Za-z]:\\Users\\(?!<|Xxx|xxx|user|User)")),
]

ALLOW = [
    "X老师", "学生A", "学生B", "教学楼A-301",
    "`C:\\Users\\`",  # 文档里"禁止出现该路径"的说明本身不算违规
]

PLACEHOLDER = re.compile(r"__|\bTODO\b|待补|待填")


def scan(path: Path, verbose: bool) -> list[str]:
    issues: list[str] = []
    if not path.exists():
        return [f"文件不存在：{path.relative_to(REPO) if path.is_absolute() else path}"]
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    for lineno, line in enumerate(lines, start=1):
        stripped = line
        for allowed in ALLOW:
            stripped = stripped.replace(allowed, "")
        for name, pattern in RULES:
            for match in pattern.finditer(stripped):
                issues.append(f"{path.name}:{lineno} 命中「{name}」→ {match.group(0)[:40]}")
                if verbose:
                    print(f"    {name}: {line.strip()[:80]}")
    return issues


def main() -> int:
    parser = argparse.ArgumentParser(description="提交材料预检")
    parser.add_argument("--all", action="store_true", help="同时扫描 evidence/ 下所有文本文件")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    targets = [REPO / f for f in SUBMIT_FILES]
    if args.all:
        ev = REPO / "evidence"
        if ev.exists():
            targets += [p for p in ev.rglob("*") if p.suffix in {".md", ".json", ".txt", ".csv"}]

    print("== 提交材料预检 ==")
    issues: list[str] = []
    placeholders = 0
    for path in targets:
        found = scan(path, args.verbose)
        issues += found
        if path.exists():
            ph = len(PLACEHOLDER.findall(path.read_text(encoding="utf-8", errors="replace")))
            placeholders += ph
            print(f"  {path.name}: {'OK' if not found else f'{len(found)} 处问题'}，占位符 {ph} 处")

    print(f"\n扫描 {len(targets)} 个文件，规则 {len(RULES)} 条")
    if placeholders:
        print(f"提示：仍有 {placeholders} 处占位符（__ / 待补），提交前必须填完或删句")
    if issues:
        print(f"\n命中 {len(issues)} 处：")
        for item in issues:
            print(f"  FAIL {item}")
        return 1
    print("无匿名/隐私/密钥问题 ✓")
    return 0


if __name__ == "__main__":
    sys.exit(main())
