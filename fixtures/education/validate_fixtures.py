#!/usr/bin/env python3
"""教育场景 fixture 自检脚本。

只依赖 Python 标准库，不需要 Flutter SDK。
用于 CI 或在任何机器上快速确认 fixtures/education/ 下的数据是否自洽、是否含隐私信息。

用法:
    python fixtures/education/validate_fixtures.py
    python fixtures/education/validate_fixtures.py --scenario A
    python fixtures/education/validate_fixtures.py --privacy
    python fixtures/education/validate_fixtures.py --verbose

退出码: 0 全部通过 / 1 存在失败项
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

FIXTURE_DIR = Path(__file__).resolve().parent
DAY_MINUTES = 1440
HARDNESS = {"hard", "soft"}
ITEM_TYPES = {"recurring", "one_time", "course"}
ACTIONS = {"none", "skip", "reschedule", "retarget", "reminder", "courseChange", "extraCourse"}

SCENARIO_FILES = {
    "A": "scenario_a_study_plan.json",
    "B": "scenario_b_report_breakdown.json",
    "C": "scenario_c_meeting_replan.json",
}

PII_PATTERNS = [
    ("手机号", re.compile(r"(?<!\d)1[3-9]\d{9}(?!\d)")),
    ("身份证号", re.compile(r"(?<!\d)\d{17}[\dXx](?!\d)")),
    ("邮箱", re.compile(r"[\w.+-]+@[\w-]+\.[\w.]{2,}")),
    ("学号(10-12位连续数字)", re.compile(r"(?<!\d)\d{10,12}(?!\d)")),
]

failures: list[str] = []
checks = 0


def check(cond: bool, message: str) -> bool:
    global checks
    checks += 1
    if not cond:
        failures.append(message)
    return cond


def load(name: str) -> dict[str, Any]:
    path = FIXTURE_DIR / name
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def in_range(minute: int, upper_inclusive: bool = False) -> bool:
    return 0 <= minute <= (DAY_MINUTES if upper_inclusive else DAY_MINUTES - 1)


def expand_weekdays(course: dict[str, Any]) -> list[int]:
    days = course.get("weekdays")
    return days if isinstance(days, list) else []


def hard_blocks_for_offset(data: dict[str, Any], offset: int, target_weekday: int | None) -> list[dict[str, Any]]:
    """收集某天所有 hard 块：课程（按 weekday）+ 固定事件。"""
    blocks: list[dict[str, Any]] = []
    if target_weekday is not None:
        for course in data.get("courses", []):
            if target_weekday in expand_weekdays(course):
                blocks.append(
                    {
                        "id": course["id"],
                        "name": course["name"],
                        "start": course["start_minute"],
                        "end": course["end_minute"],
                        "kind": "course",
                    }
                )
    for event in data.get("fixed_events", []):
        if event.get("day_offset") == offset:
            blocks.append(
                {
                    "id": event["id"],
                    "name": event["name"],
                    "start": event["start_minute"],
                    "end": event["end_minute"],
                    "kind": "fixed_event",
                }
            )
    return blocks


def overlaps(a_start: int, a_end: int, b_start: int, b_end: int) -> bool:
    return a_start < b_end and b_start < a_end


def validate_common(data: dict[str, Any], label: str) -> None:
    for key in ("fixture_version", "scenario_id", "title", "timezone", "anchor", "prompt", "expectations"):
        check(key in data, f"{label}: 缺少必需字段 {key}")
    check(data.get("timezone") == "Asia/Shanghai", f"{label}: timezone 必须为 Asia/Shanghai")
    check(bool(data.get("prompt", "").strip()), f"{label}: prompt 不能为空")

    ids: list[str] = []
    for group in ("courses", "tasks", "fixed_events"):
        for item in data.get(group, []):
            ids.append(item.get("id", ""))
    dup = {i for i in ids if ids.count(i) > 1}
    check(not dup, f"{label}: id 重复 {sorted(dup)}")

    # override 引用的是已有实体，只校验指向存在，不参与 id 唯一性
    entity_ids = set(ids)
    for override in data.get("existing_overrides", []):
        check(override.get("item_id") in entity_ids,
              f"{label}: override 引用了不存在的实体 {override.get('item_id')}")

    for item in data.get("courses", []):
        check(bool(item.get("name")), f"{label}: 课程 {item.get('id')} 缺少 name")
        check(bool(expand_weekdays(item)), f"{label}: 课程 {item.get('id')} weekdays 为空")
        for day in expand_weekdays(item):
            check(1 <= day <= 7, f"{label}: 课程 {item.get('id')} weekday {day} 越界（应为 1-7）")
        start, end = item.get("start_minute", -1), item.get("end_minute", -1)
        check(in_range(start) and in_range(end), f"{label}: 课程 {item.get('id')} 分钟越界")
        check(0 <= start < end <= DAY_MINUTES, f"{label}: 课程 {item.get('id')} 需满足 start < end")
        check(item.get("hardness", "hard") in HARDNESS, f"{label}: 课程 {item.get('id')} hardness 非法")

    for task in data.get("tasks", []):
        check(bool(task.get("name")), f"{label}: 任务 {task.get('id')} 缺少 name")
        check(task.get("hardness") in HARDNESS, f"{label}: 任务 {task.get('id')} hardness 非法")
        deadline = task.get("deadline")
        if deadline:
            check(
                isinstance(deadline.get("day_offset"), int) and in_range(deadline.get("minute_of_day", -1)),
                f"{label}: 任务 {task.get('id')} deadline 非法",
            )

    for event in data.get("fixed_events", []):
        check(isinstance(event.get("day_offset"), int), f"{label}: 事件 {event.get('id')} 缺少 day_offset")
        start, end = event.get("start_minute", -1), event.get("end_minute", -1)
        check(0 <= start < end <= DAY_MINUTES, f"{label}: 事件 {event.get('id')} 需满足 start < end")
        check(event.get("hardness", "hard") == "hard", f"{label}: 事件 {event.get('id')} 应为 hard")

    for override in data.get("existing_overrides", []):
        check(override.get("item_type") in ITEM_TYPES, f"{label}: override item_type 非法 {override.get('item_type')}")
        check(override.get("action") in ACTIONS, f"{label}: override action 非法 {override.get('action')}")
        start, end = override.get("planned_start_minute", -1), override.get("planned_end_minute", -1)
        check(0 <= start < end <= DAY_MINUTES, f"{label}: override {override.get('item_id')} 需满足 start < end")

    # 同一 weekday 上课程之间不得互相重叠
    week_map: dict[int, list[dict[str, Any]]] = {}
    for course in data.get("courses", []):
        for day in expand_weekdays(course):
            week_map.setdefault(day, []).append(course)
    for day, courses in week_map.items():
        for i in range(len(courses)):
            for j in range(i + 1, len(courses)):
                a, b = courses[i], courses[j]
                check(
                    not overlaps(a["start_minute"], a["end_minute"], b["start_minute"], b["end_minute"]),
                    f"{label}: 周{day} 课程 {a['id']} 与 {b['id']} 时间冲突",
                )

    # 断言必须可读且带 check 表达式
    assertions = data.get("expectations", {}).get("assertions", [])
    check(len(assertions) >= 3, f"{label}: 至少需要 3 条断言，当前 {len(assertions)}")
    for item in assertions:
        check(bool(item.get("id")) and bool(item.get("desc")) and bool(item.get("check")),
              f"{label}: 断言 {item.get('id')} 字段不完整")


def validate_scenario_a(data: dict[str, Any]) -> None:
    label = "场景A"
    validate_common(data, label)
    offset = data["anchor"]["target_offset"]
    task_ids = {t["id"] for t in data.get("tasks", [])}

    # 已存在 override 必须指向真实任务
    for override in data.get("existing_overrides", []):
        check(override["item_id"] in task_ids, f"{label}: override 引用了不存在的任务 {override['item_id']}")

    # 以「明天」为基准做一次冲突检查（weekday 取决于实际运行日期，这里用固定映射示例 weekday=5 周五）
    for weekday in range(1, 8):
        blocks = hard_blocks_for_offset(data, offset, weekday)
        for override in data.get("existing_overrides", []):
            if override["day_offset"] != offset:
                continue
            for block in blocks:
                check(
                    not overlaps(override["planned_start_minute"], override["planned_end_minute"],
                                 block["start"], block["end"]),
                    f"{label}: 周{weekday} 已排块 {override['item_id']} 与 hard 块 {block['id']} 重叠（数据本身有问题）",
                )

    # 主角任务应在某天有可排时长
    vocab = next((t for t in data["tasks"] if t["id"] == "task-eng-vocab"), None)
    check(vocab is not None, f"{label}: 缺少主角任务 task-eng-vocab")
    if vocab:
        check(vocab.get("target_duration_minutes", 0) >= 15, f"{label}: 词汇复习目标时长过短")


def validate_scenario_b(data: dict[str, Any]) -> None:
    label = "场景B"
    validate_common(data, label)
    subtasks = data.get("expected_breakdown", {}).get("subtasks", [])
    parent = next((t for t in data["tasks"] if t["id"] == "task-research-report"), None)
    check(parent is not None, f"{label}: 缺少父任务 task-research-report")
    if parent:
        total = sum(s.get("estimated_minutes", 0) for s in subtasks)
        check(total == parent.get("estimated_minutes"),
              f"{label}: 子任务合计 {total} 应等于父任务预估 {parent.get('estimated_minutes')}")
        check(len(subtasks) >= 4, f"{label}: 子任务数量应 >= 4，当前 {len(subtasks)}")

    # 依赖必须指向已存在的子任务，且不得成环
    sub_ids = {s["id"] for s in subtasks}
    for sub in subtasks:
        for dep in sub.get("depends_on", []):
            check(dep in sub_ids, f"{label}: 子任务 {sub['id']} 依赖不存在的 {dep}")
            check(dep != sub["id"], f"{label}: 子任务 {sub['id']} 不能依赖自己")

    # 可用时长核算
    window = data.get("study_windows", {})
    offsets = window.get("applies_to_day_offsets", [])
    window_minutes = window.get("end_minute", 0) - window.get("start_minute", 0)
    total_window = window_minutes * len(offsets)
    hard_minutes = 0
    for event in data.get("fixed_events", []):
        if event.get("day_offset") in offsets:
            s = max(event["start_minute"], window.get("start_minute", 0))
            e = min(event["end_minute"], window.get("end_minute", 0))
            if e > s:
                hard_minutes += e - s
    available = total_window - hard_minutes
    declared = data.get("expectations", {}).get("free_minutes_by_window", {})
    if declared:
        check(declared.get("total_study_minutes") == total_window,
              f"{label}: total_study_minutes 应为 {total_window}，声明为 {declared.get('total_study_minutes')}")
        check(declared.get("hard_block_minutes") == hard_minutes,
              f"{label}: hard_block_minutes 应为 {hard_minutes}，声明为 {declared.get('hard_block_minutes')}")
        check(declared.get("available_minutes") == available,
              f"{label}: available_minutes 应为 {available}，声明为 {declared.get('available_minutes')}")
        shortfall = max(0, parent.get("estimated_minutes", 0) - available) if parent else 0
        check(declared.get("shortfall_minutes") == shortfall,
              f"{label}: shortfall_minutes 应为 {shortfall}，声明为 {declared.get('shortfall_minutes')}")
        check(shortfall == 60, f"{label}: 本场景设计上的缺口应为 60 分钟，实际 {shortfall}")


def validate_scenario_c(data: dict[str, Any]) -> None:
    label = "场景C"
    validate_common(data, label)
    offset = data["anchor"]["target_offset"]
    meeting = next((e for e in data["fixed_events"] if e.get("is_new_in_this_scenario")), None)
    check(meeting is not None, f"{label}: 缺少本次新增的会议事件")

    if meeting:
        overlapping, untouched = [], []
        for override in data.get("existing_overrides", []):
            if override["day_offset"] != offset:
                continue
            if overlaps(override["planned_start_minute"], override["planned_end_minute"],
                        meeting["start_minute"], meeting["end_minute"]):
                overlapping.append(override)
            else:
                untouched.append(override)
        check(len(overlapping) == 1,
              f"{label}: 设计中应恰好 1 个软块与会议重叠，实际 {len(overlapping)}")
        if overlapping:
            check(overlapping[0]["item_id"] == "task-calc-homework",
                  f"{label}: 重叠块应为 task-calc-homework，实际 {overlapping[0]['item_id']}")
        check(len(untouched) == 3, f"{label}: 应恰好 3 个软块不受影响，实际 {len(untouched)}")

        # 会议不得与课程冲突（否则就变成 E06 边界用例了）
        for weekday in range(1, 8):
            for block in hard_blocks_for_offset(data, offset, weekday):
                if block["kind"] != "course":
                    continue
                check(not overlaps(meeting["start_minute"], meeting["end_minute"], block["start"], block["end"]),
                      f"{label}: 周{weekday} 会议与课程 {block['id']} 冲突（应以 E06 覆盖，不应出现在主场景）")

    expected = data.get("expectations", {}).get("expected_state_after_approval", {})
    check(expected.get("moved_soft_blocks") == 1, f"{label}: moved_soft_blocks 应为 1")
    check(expected.get("moved_hard_blocks") == 0, f"{label}: moved_hard_blocks 应为 0")


def validate_boundary_cases() -> None:
    label = "边界用例"
    data = load("boundary_cases.json")
    cases = data.get("cases", [])
    check(len(cases) >= 10, f"{label}: 至少 10 条，当前 {len(cases)}")
    ids = [c.get("id") for c in cases]
    check(len(ids) == len(set(ids)), f"{label}: 用例 id 重复")
    for case in cases:
        for key in ("id", "name", "category", "severity", "prompt", "expected_behavior", "must_not", "verify"):
            check(key in case, f"{label}: {case.get('id')} 缺少字段 {key}")
        check(case.get("severity") in {"P0", "P1", "P2"}, f"{label}: {case.get('id')} severity 非法")
        check(isinstance(case.get("must_not"), list) and case["must_not"], f"{label}: {case.get('id')} must_not 不能为空")
        fixture = case.get("inject", {}).get("fixture")
        if fixture and fixture != "任意场景":
            check(fixture in SCENARIO_FILES.values() or fixture in {"scenario_a_study_plan", "scenario_b_report_breakdown", "scenario_c_meeting_replan"},
                  f"{label}: {case.get('id')} 引用了不存在的 fixture {fixture}")


def validate_privacy(verbose: bool) -> None:
    label = "隐私扫描"
    scanned = 0
    for path in sorted(FIXTURE_DIR.glob("*.json")) + sorted(FIXTURE_DIR.glob("*.md")):
        scanned += 1
        text = path.read_text(encoding="utf-8")
        for name, pattern in PII_PATTERNS:
            for match in pattern.finditer(text):
                snippet = match.group(0)
                # 允许时间/日期中的长数字串被误报时人工复核，这里直接报出
                failures.append(f"{label}: {path.name} 命中疑似{name}「{snippet}」")
                checks += 1
    print(f"  扫描文件 {scanned} 个，PII 规则 {len(PII_PATTERNS)} 条")
    if verbose:
        print(f"  规则: {[n for n, _ in PII_PATTERNS]}")


def main() -> int:
    parser = argparse.ArgumentParser(description="校验教育场景 fixtures")
    parser.add_argument("--scenario", choices=["A", "B", "C", "all"], default="all")
    parser.add_argument("--privacy", action="store_true", help="同时执行隐私扫描")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    print("== CheckD 教育场景 fixture 校验 ==")
    targets = SCENARIO_FILES if args.scenario == "all" else {args.scenario: SCENARIO_FILES[args.scenario]}

    for key, filename in targets.items():
        print(f"[{key}] {filename}")
        data = load(filename)
        if key == "A":
            validate_scenario_a(data)
        elif key == "B":
            validate_scenario_b(data)
        elif key == "C":
            validate_scenario_c(data)

    print("[E] boundary_cases.json")
    validate_boundary_cases()

    if args.privacy:
        print("[P] 隐私扫描")
        validate_privacy(args.verbose)

    print(f"\n共执行 {checks} 项检查，失败 {len(failures)} 项")
    if failures:
        for item in failures:
            print(f"  FAIL {item}")
        return 1
    print("全部通过 ✓")
    return 0


if __name__ == "__main__":
    sys.exit(main())
