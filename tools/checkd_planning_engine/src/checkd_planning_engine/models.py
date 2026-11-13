from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo


@dataclass(frozen=True)
class Task:
    task_id: str
    remaining_seconds: int
    deadline: datetime | date
    earliest_start: datetime
    splittable: bool = True
    minimum_block_minutes: int = 30
    effort_confidence: float | None = None


@dataclass(frozen=True)
class Block:
    starts_at: datetime
    ends_at: datetime
    task_id: str | None = None
    kind: str = "busy"

    @property
    def seconds(self) -> int:
        return int((self.ends_at - self.starts_at).total_seconds())


@dataclass(frozen=True)
class PlanningInput:
    now: datetime
    horizon_end: datetime
    timezone: str = "Asia/Shanghai"
    tasks: tuple[Task, ...] = ()
    fixed_blocks: tuple[Block, ...] = ()
    unavailable: tuple[Block, ...] = ()
    existing_blocks: tuple[Block, ...] = ()
    slot_minutes: int = 15
    preferences: dict = field(default_factory=dict)


def deadline_instant(value: datetime | date, timezone: str) -> datetime:
    zone = ZoneInfo(timezone)
    if isinstance(value, datetime):
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("deadline datetime must include a UTC offset")
        return value.astimezone(zone)
    # Date-only deadline is inclusive through its local calendar date.
    return datetime.combine(value + timedelta(days=1), time.min, zone)
