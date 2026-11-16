from __future__ import annotations

import re
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from .models import AgentError, DEFAULT_TIMEZONE


_DAY_OFFSETS = {"今天": 0, "明天": 1, "后天": 2}
_CHINESE_NUMBERS = {
    "零": 0,
    "一": 1,
    "二": 2,
    "两": 2,
    "三": 3,
    "四": 4,
    "五": 5,
    "六": 6,
    "七": 7,
    "八": 8,
    "九": 9,
    "十": 10,
}


def resolve_deadline(
    text: str,
    *,
    now: datetime,
    timezone: str = DEFAULT_TIMEZONE,
) -> dict[str, str]:
    value = text.strip()
    if not value:
        raise AgentError("DEADLINE_REQUIRED", "请提供截止日期或时间。")
    try:
        zone = ZoneInfo(timezone)
    except ZoneInfoNotFoundError as error:
        raise AgentError("INVALID_TIMEZONE", "不支持的 IANA 时区。") from error
    if now.tzinfo is None or now.utcoffset() is None:
        raise ValueError("now must be offset-aware")

    iso = _resolve_iso(value, zone)
    if iso is not None:
        return iso

    local_now = now.astimezone(zone)
    target_date: date | None = None
    remainder = value
    for label, offset in _DAY_OFFSETS.items():
        if label in remainder:
            target_date = local_now.date() + timedelta(days=offset)
            remainder = remainder.replace(label, "", 1).strip()
            break
    if target_date is None:
        explicit = re.search(r"(?P<date>\d{4}-\d{2}-\d{2})", remainder)
        if explicit:
            try:
                target_date = date.fromisoformat(explicit.group("date"))
            except ValueError as error:
                raise AgentError("INVALID_DATE", "日期必须为有效的 YYYY-MM-DD。") from error
            remainder = (remainder[: explicit.start()] + remainder[explicit.end() :]).strip()
    if target_date is None:
        raise AgentError(
            "AMBIGUOUS_DEADLINE",
            "无法确定日期，请使用“明天”“后天”或 YYYY-MM-DD。",
        )

    time_value = _parse_time(remainder)
    if time_value is None:
        return {"deadline_date": target_date.isoformat(), "timezone": timezone}
    hour, minute = time_value
    target = datetime(
        target_date.year,
        target_date.month,
        target_date.day,
        hour,
        minute,
        tzinfo=zone,
    )
    return {"deadline_at": target.isoformat(), "timezone": timezone}


def _resolve_iso(value: str, zone: ZoneInfo) -> dict[str, str] | None:
    try:
        parsed_date = date.fromisoformat(value)
        return {"deadline_date": parsed_date.isoformat(), "timezone": zone.key}
    except ValueError:
        pass
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise AgentError("TIMEZONE_REQUIRED", "精确时间必须带 UTC 偏移。")
    return {"deadline_at": parsed.isoformat(), "timezone": zone.key}


def _parse_time(value: str) -> tuple[int, int] | None:
    compact = re.sub(r"\s+", "", value)
    if not compact:
        return None
    colon = re.search(r"(?<!\d)(?P<hour>\d{1,2}):(?P<minute>\d{2})(?!\d)", compact)
    period = _period(compact)
    if colon:
        hour = int(colon.group("hour"))
        minute = int(colon.group("minute"))
        return _normalize_time(hour, minute, period)
    point = re.search(
        r"(?P<hour>\d{1,2}|[零一二两三四五六七八九十]{1,3})点(?:(?P<half>半)|(?P<minute>\d{1,2})分?)?",
        compact,
    )
    if not point:
        raise AgentError(
            "AMBIGUOUS_TIME",
            "无法确定具体时间，请使用 24 小时制，例如 20:00。",
        )
    hour_text = point.group("hour")
    hour = int(hour_text) if hour_text.isdigit() else _chinese_number(hour_text)
    minute = 30 if point.group("half") else int(point.group("minute") or 0)
    return _normalize_time(hour, minute, period)


def _period(value: str) -> str | None:
    for label in ("凌晨", "早上", "上午", "中午", "下午", "晚上"):
        if label in value:
            return label
    return None


def _normalize_time(hour: int, minute: int, period: str | None) -> tuple[int, int]:
    if period in {"下午", "晚上"} and 1 <= hour <= 11:
        hour += 12
    elif period == "中午" and 1 <= hour <= 10:
        hour += 12
    elif period in {"凌晨", "早上", "上午"} and hour == 12:
        hour = 0
    if not 0 <= hour <= 23 or not 0 <= minute <= 59:
        raise AgentError("INVALID_TIME", "时间必须在 00:00 到 23:59 之间。")
    return hour, minute


def _chinese_number(value: str) -> int:
    if value in _CHINESE_NUMBERS:
        return _CHINESE_NUMBERS[value]
    if value.startswith("十"):
        return 10 + (_CHINESE_NUMBERS.get(value[1:], 0) if len(value) > 1 else 0)
    if "十" in value:
        left, right = value.split("十", 1)
        return _CHINESE_NUMBERS[left] * 10 + (_CHINESE_NUMBERS.get(right, 0) if right else 0)
    raise AgentError("INVALID_TIME", "无法识别中文时间。")
