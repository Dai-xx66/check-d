from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta


@dataclass(frozen=True)
class Preference:
    key: str
    value: object
    provenance: str  # explicit | inferred | user_confirmed
    hard_constraint: bool = False

    def __post_init__(self):
        if self.provenance not in {"explicit", "inferred", "user_confirmed"}:
            raise ValueError("invalid preference provenance")
        if self.provenance == "inferred" and self.hard_constraint:
            raise ValueError("inferred preference cannot become a hard constraint")


STYLES={"gentle":"可以稍作调整，我们先看看剩余空间。",
        "balanced":"当前安排有一定风险，建议重新检查可用时间。",
        "direct":"按现有数据，这项安排可能无法按期完成。"}


def render_risk(risk: dict, style: str) -> dict:
    if style not in STYLES: raise ValueError("unknown style")
    return {"facts":risk,"message":STYLES[style]}


@dataclass
class InterventionPolicy:
    cooldown: timedelta = timedelta(hours=12)
    daily_limit: int = 3
    last_sent: dict[str,datetime] = field(default_factory=dict)
    sent_today: dict[str,int] = field(default_factory=dict)
    ignored: set[str] = field(default_factory=set)

    def should_notify(self, user_id: str, risk_key: str, now: datetime) -> bool:
        if risk_key in self.ignored or self.sent_today.get(user_id,0)>=self.daily_limit: return False
        prior=self.last_sent.get(risk_key)
        return prior is None or now-prior>=self.cooldown

    def record(self,user_id:str,risk_key:str,now:datetime):
        self.last_sent[risk_key]=now; self.sent_today[user_id]=self.sent_today.get(user_id,0)+1
