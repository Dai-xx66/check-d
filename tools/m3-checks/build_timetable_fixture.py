#!/usr/bin/env python3
"""把真实课表转成脱敏 fixture。

用途：规划要求「1 份真实课表，脱敏后入库」（docs/submission/needs-evidence-pack.md §4）。
本脚本做三件事：删除身份列、把教师/教室/课名替换为占位、按现有 fixture 字段输出。

输入 CSV（UTF-8，首行表头，中英文列名都认）：
    course,weekday,start_time,end_time,classroom,teacher
    高等数学A(2024级),1,08:00,09:40,B6-705,张伟

输出：
    fixtures/education/scenario_d_real_timetable.json

用法:
    python tools/m3-checks/build_timetable_fixture.py 课表.csv
    python tools/m3-checks/build_timetable_fixture.py 课表.csv --out /tmp/x.json
    python tools/m3-checks/build_timetable_fixture.py --demo      # 用内置样本自测，不写仓库

注意：--demo 的输出只是自测，不得当作真实课表提交。
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO / "fixtures/education/scenario_d_real_timetable.json"

ALIASES = {
    "course": ["course", "课程", "课程名称", "课名"],
    "weekday": ["weekday", "星期", "周几"],
    "start_time": ["start_time", "开始", "开始时间", "上课时间"],
    "end_time": ["end_time", "结束", "结束时间", "下课时间"],
    "classroom": ["classroom", "教室", "地点", "上课地点"],
    "teacher": ["teacher", "教师", "老师", "任课教师"],
}
DROP_COLUMNS = ["name", "姓名", "student_id", "学号", "class", "班级", "学院", "college"]

PII_PATTERNS = [
    ("手机号", re.compile(r"(?<!\d)1[3-9]\d{9}(?!\d)")),
    ("身份证号", re.compile(r"(?<!\d)\d{17}[\dXx](?!\d)")),
    ("邮箱", re.compile(r"[\w.+-]+@[\w-]+\.[\w.]{2,}")),
    ("学号(10-12位连续数字)", re.compile(r"(?<!\d)\d{10,12}(?!\d)")),
]

DEMO_ROWS = [
    ["高等数学A(2024级)", "1", "08:00", "09:40", "B6-705", "张伟"],
    ["大学英语（2）", "2", "10:00", "11:40", "外语楼205", "李娜"],
    ["数据结构A", "3", "14:00", "15:40", "B6-301", "王强"],
    ["大学物理实验", "4", "19:00", "20:40", "实验楼A-102", "赵敏"],
]


def normalize_header(row: list[str]) -> dict[str, int]:
    header = {h.strip().lower(): i for i, h in enumerate(row)}
    mapping: dict[str, int] = {}
    for key, names in ALIASES.items():
        for name in names:
            if name.lower() in header:
                mapping[key] = header[name.lower()]
                break
    return mapping


def to_minutes(text: str) -> int:
    text = text.strip().replace("：", ":")
    m = re.match(r"^(\d{1,2}):(\d{2})$", text)
    if not m:
        raise ValueError(f"时间格式无法解析：{text}（应为 HH:MM）")
    hour, minute = int(m.group(1)), int(m.group(2))
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        raise ValueError(f"时间越界：{text}")
    return hour * 60 + minute


def clean_course_name(raw: str) -> str:
    name = raw.strip()
    name = re.sub(r"[（(][^）)]*[）)]", "", name)      # 去括号内容：等级、课号、年份
    name = re.sub(r"[A-Za-z]?\d+级", "", name)
    name = re.sub(r"(?<=[\u4e00-\u9fa5])[A-Za-z]$", "", name)  # 末尾单字母等级：高等数学A → 高等数学
    name = re.sub(r"\s+", "", name)
    return name or "课程"


def build(rows: list[list[str]], meta_source: str) -> dict:
    if not rows:
        raise ValueError("CSV 为空")
    mapping = normalize_header(rows[0])
    missing = [k for k in ALIASES if k not in mapping]
    if missing:
        raise ValueError(f"缺少必需列：{missing}；表头实际为 {rows[0]}")

    courses = []
    seen_names: dict[str, int] = {}
    for idx, row in enumerate(rows[1:], start=1):
        if not any(cell.strip() for cell in row):
            continue
        course = clean_course_name(row[mapping["course"]])
        weekday = int(str(row[mapping["weekday"]]).strip())
        start = to_minutes(row[mapping["start_time"]])
        end = to_minutes(row[mapping["end_time"]])
        if not 1 <= weekday <= 7:
            raise ValueError(f"第 {idx} 行 weekday={weekday} 越界（应为 1–7）")
        if not start < end:
            raise ValueError(f"第 {idx} 行开始时间不早于结束时间")

        seen_names[course] = seen_names.get(course, 0) + 1
        suffix = f"-{seen_names[course]}" if seen_names[course] > 1 else ""
        courses.append({
            "id": f"course-d{idx:02d}{suffix}",
            "name": course,
            "weekdays": [weekday],
            "start_minute": start,
            "end_minute": end,
            "classroom": f"教学楼{'ABCD'[(idx - 1) % 4]}-{100 + idx}",
            "teacher": "X老师",
            "hardness": "hard",
        })

    return {
        "fixture_version": "1.0",
        "scenario_id": "scenario_d_real_timetable",
        "owner_module": "M3",
        "timezone": "Asia/Shanghai",
        "meta": {
            "source": meta_source,
            "privacy": "课程名已通用化（去括号/等级/课号），教师统一为 X老师，教室替换为占位，未保留姓名与学号",
            "note": "真实课表脱敏产物。字段与 scenario_a/b/c 的 courses 对齐，可直接用于排程输入。",
        },
        "courses": courses,
    }


def privacy_scan(text: str) -> list[str]:
    hits = []
    for name, pattern in PII_PATTERNS:
        for match in pattern.finditer(text):
            hits.append(f"疑似{name}「{match.group(0)}」")
    return hits


def write_out(data: dict, out: Path) -> None:
    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    hits = privacy_scan(text)
    if hits:
        raise SystemExit(f"隐私扫描未通过：{hits}")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8")
    print(f"已写入 {out}")
    print(f"  课程 {len(data['courses'])} 条，隐私扫描 0 命中")


def main() -> int:
    parser = argparse.ArgumentParser(description="真实课表脱敏为 fixture")
    parser.add_argument("csv_path", nargs="?", help="课表 CSV 路径")
    parser.add_argument("--out", default=str(DEFAULT_OUT), help="输出 JSON 路径")
    parser.add_argument("--demo", action="store_true", help="用内置样本自测，不写仓库")
    parser.add_argument("--source", default="真实课表（已脱敏）", help="meta.source 描述")
    args = parser.parse_args()

    if args.demo:
        data = build([["course", "weekday", "start_time", "end_time", "classroom", "teacher"]] + DEMO_ROWS,
                     "内置样本（自测用，非真实课表）")
        with tempfile.TemporaryDirectory() as tmp:
            write_out(data, Path(tmp) / "demo.json")
        names = [c["name"] for c in data["courses"]]
        print(f"  脱敏后课名：{names}")
        assert all("(" not in n and "（" not in n for n in names), "课名仍有括号"
        assert all(c["teacher"] == "X老师" for c in data["courses"]), "教师未替换"
        print("  自测通过 ✓")
        return 0

    if not args.csv_path:
        parser.error("需要 CSV 路径，或用 --demo 自测")
    path = Path(args.csv_path)
    if not path.exists():
        print(f"FATAL 找不到 {path}")
        return 1
    with path.open("r", encoding="utf-8-sig", newline="") as fh:
        rows = list(csv.reader(fh))
    try:
        data = build(rows, args.source)
    except ValueError as exc:
        print(f"FATAL {exc}")
        return 1
    write_out(data, Path(args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
