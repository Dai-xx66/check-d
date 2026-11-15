from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta


@dataclass(frozen=True)
class Preference:
    key: str
    value: object
    provenance: str  # explicit | inferred | user_confirmed | default | contextual
    hard_constraint: bool = False
    category: str = "default"  # hard_rule | default | contextual | leisure_balance

    def __post_init__(self):
        if self.provenance not in {"explicit", "inferred", "user_confirmed", "default", "contextual"}:
            raise ValueError("invalid preference provenance")
        if self.category not in {"hard_rule", "default", "contextual", "leisure_balance"}:
            raise ValueError("invalid preference category")
        if self.hard_constraint and not (self.provenance in {"explicit", "user_confirmed"} and self.category == "hard_rule"):
            raise ValueError("only explicit or confirmed hard rules may constrain planning")


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
    last_sent: dict[tuple[str,str],datetime] = field(default_factory=dict)
    sent_today: dict[tuple[str,str],int] = field(default_factory=dict)
    ignored: set[tuple[str,str]] = field(default_factory=set)
    rest_until: dict[str,datetime] = field(default_factory=dict)

    def should_notify(self, user_id: str, risk_key: str, now: datetime) -> bool:
        local_day = now.date().isoformat()
        if (user_id,risk_key) in self.ignored or self.sent_today.get((user_id,local_day),0)>=self.daily_limit: return False
        if self.rest_until.get(user_id) and now < self.rest_until[user_id]: return False
        prior=self.last_sent.get((user_id,risk_key))
        return prior is None or now-prior>=self.cooldown

    def record(self,user_id:str,risk_key:str,now:datetime):
        local_day = now.date().isoformat()
        self.last_sent[(user_id,risk_key)]=now
        key = (user_id,local_day)
        self.sent_today[key]=self.sent_today.get(key,0)+1

    def choose_rest(self,user_id:str,until:datetime):
        self.rest_until[user_id]=until

    def ignore(self,user_id:str,risk_key:str):
        self.ignored.add((user_id,risk_key))

    def unignore(self,user_id:str,risk_key:str):
        self.ignored.discard((user_id,risk_key))
