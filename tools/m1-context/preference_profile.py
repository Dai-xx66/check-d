"""PreferenceProfile 的 Python 参考实现。

用途：给 M2 客户端和 M0 适配层一个**可离线跑、与 SQL 同规则**的裁判，
避免两边对「每日偏好」「版本冲突」「超过 32 条」各写一套判断。

与 SQL 的关系：
  - 自定义错误码与 202611260003_stage04_preference_profiles.sql 完全同名；
  - 表约束类的错误在这里统一抛 code="CHECK_VIOLATION" + field，
    因为 SQL 侧那类没有自定义码（SQLSTATE 23514），别假装有。
  - SQL 里用咨询锁串行化同账号并发写入；这里用 apply_upsert() 的显式版本比较模拟同一语义，
    单线程下等价，多线程不等价（不要拿这个当并发正确性证明）。

不依赖第三方库。
"""

from __future__ import annotations

from typing import Any, Iterable

MAX_SLOTS = 32
FOCUS_MIN_RANGE = (5, 480)
BREAK_MIN_RANGE = (0, 120)
SCHEMA_VERSION = 1


class PreferenceError(ValueError):
    """带机器可读 code 的校验错误。code 与 SQL 侧 message 同名。"""

    def __init__(self, code: str, field: str | None = None, detail: Any = None):
        self.code = code
        self.field = field
        self.detail = detail
        super().__init__(f"{code}" + (f" ({field})" if field else ""))


def _as_int(value: Any, field: str, code: str = "INVALID_SLOT") -> int:
    if isinstance(value, bool):          # bool 是 int 子类，必须先排除
        raise PreferenceError(code, field)
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.strip() != "":
        try:
            return int(value)
        except ValueError:
            raise PreferenceError(code, field) from None
    raise PreferenceError(code, field)


def _is_daily(slot: dict[str, Any]) -> bool:
    """weekday 缺省或显式 null 都表示「每日默认」。"""
    if "weekday" not in slot:
        return True
    return slot["weekday"] is None


def normalize_slot(slot: Any) -> dict[str, Any]:
    """校验单条时段，返回统一形状 {weekday: int|None, start_minute, end_minute}。

    注意：这里只做**形状归一**，不做语义归一。
    「7 天各一条」与「一条 weekday=null」解析结果相同，但存储保持原样，不互转
    （互转会丢掉「用户明确逐日设置过」这个事实）。
    """
    if not isinstance(slot, dict):
        raise PreferenceError("INVALID_SLOT")
    if _is_daily(slot):
        weekday = None
    else:
        weekday = _as_int(slot["weekday"], "weekday", "INVALID_SLOT_RANGE")
        if weekday < 1 or weekday > 7:
            raise PreferenceError("INVALID_SLOT_RANGE", "weekday")

    start = _as_int(slot.get("start_minute"), "start_minute", "INVALID_SLOT_RANGE")
    end = _as_int(slot.get("end_minute"), "end_minute", "INVALID_SLOT_RANGE")
    if start < 0 or start > 1439 or end < 1 or end > 1440 or end <= start:
        raise PreferenceError("INVALID_SLOT_RANGE", "minutes")

    return {"weekday": weekday, "start_minute": start, "end_minute": end}


def validate_profile(profile: Any) -> dict[str, Any]:
    """校验一份写入载荷，返回规范化后的副本。校验顺序与 SQL 函数一致。"""
    if not isinstance(profile, dict):
        raise PreferenceError("INVALID_PROFILE")
    if profile.get("confirm") is not True:
        # 只有严格的 True 才算确认；"true" 字符串、1 都不算，避免客户端类型松散绕过。
        raise PreferenceError("CONFIRMATION_REQUIRED")

    raw_slots = profile.get("preferred_slots", [])
    if not isinstance(raw_slots, list):
        raise PreferenceError("INVALID_PREFERRED_SLOTS")
    if len(raw_slots) > MAX_SLOTS:
        # 硬失败，不截断：静默丢偏好比报错更糟。
        raise PreferenceError("TOO_MANY_SLOTS", detail=len(raw_slots))

    slots = [normalize_slot(s) for s in raw_slots]

    focus = profile.get("focus_minutes")
    if focus is not None:
        focus = _as_int(focus, "focus_minutes")
        lo, hi = FOCUS_MIN_RANGE
        if not (lo <= focus <= hi):
            raise PreferenceError("CHECK_VIOLATION", "focus_minutes")

    brk = profile.get("break_minutes")
    if brk is not None:
        brk = _as_int(brk, "break_minutes")
        lo, hi = BREAK_MIN_RANGE
        if not (lo <= brk <= hi):
            raise PreferenceError("CHECK_VIOLATION", "break_minutes")

    source = profile.get("source") or "explicit"
    if source not in ("explicit", "inferred"):
        raise PreferenceError("INVALID_SOURCE", "source")

    return {
        "preferred_slots": slots,
        "focus_minutes": focus,
        "break_minutes": brk,
        "source": source,
        # inferred 永远不带确认时间：未确认的行不许被当作偏好消费。
        "confirmed_at": "SET_BY_SERVER" if source == "explicit" else None,
        "schema_version": SCHEMA_VERSION,
    }


def slots_for_day(slots: Iterable[dict[str, Any]], weekday: int) -> list[dict[str, int]]:
    """解析某个 weekday（1=周一…7=周日）实际生效的时段。

    规则（冻结口径）：
      1. 存在 weekday == d 的条目 → **只用**这些条目，每日默认整条不生效（不是合并）。
      2. 否则用 weekday is null 的每日默认。
      3. 都没有 → 空列表（无偏好，不等于「全天可用」）。

    为什么是「覆盖」而不是「叠加」：叠加会让用户没法用一条显式设置排除某天的默认偏好，
    也没法表达「周末不要按工作日的偏好排」。
    """
    if weekday < 1 or weekday > 7:
        raise PreferenceError("INVALID_SLOT_RANGE", "weekday")
    explicit = [s for s in slots if s.get("weekday") == weekday]
    chosen = explicit if explicit else [s for s in slots if _is_daily(s)]
    return sorted(
        ({"start_minute": s["start_minute"], "end_minute": s["end_minute"]} for s in chosen),
        key=lambda s: s["start_minute"],
    )


def merge_segments(segments: Iterable[dict[str, int]]) -> list[dict[str, int]]:
    """合并重叠或首尾相接的段。消费侧算可用窗口前应调用，避免重复计算同一段时间。"""
    ordered = sorted(segments, key=lambda s: (s["start_minute"], s["end_minute"]))
    merged: list[dict[str, int]] = []
    for seg in ordered:
        if merged and seg["start_minute"] <= merged[-1]["end_minute"]:
            merged[-1]["end_minute"] = max(merged[-1]["end_minute"], seg["end_minute"])
        else:
            merged.append(dict(seg))
    return merged


def apply_upsert(current: dict[str, Any] | None,
                 profile: Any,
                 expected_version: int | None = None) -> dict[str, Any]:
    """模拟 SQL upsert_preference_profile 的版本语义。

    current 为 None 表示该账号还没有行。
    返回 {"status", "data_version", "schema_version", ...}。
    """
    data = validate_profile(profile)

    if current is None:
        if expected_version is not None and expected_version != 0:
            raise PreferenceError("VERSION_CONFLICT", "expected_version", detail=0)
        next_version = 1
    else:
        current_version = int(current.get("data_version", 0))
        if expected_version is not None and expected_version != current_version:
            raise PreferenceError("VERSION_CONFLICT", "expected_version",
                                  detail=current_version)
        next_version = current_version + 1

    return {
        "status": "ok" if data["source"] == "explicit" else "unconfirmed",
        "preferred_slots": data["preferred_slots"],
        "focus_minutes": data["focus_minutes"],
        "break_minutes": data["break_minutes"],
        "source": data["source"],
        "confirmed_at": "SET_BY_SERVER" if data["source"] == "explicit" else None,
        "schema_version": SCHEMA_VERSION,
        "data_version": next_version,
        "saved": True,
    }
