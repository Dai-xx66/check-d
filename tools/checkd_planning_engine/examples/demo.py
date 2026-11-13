from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo
from checkd_planning_engine import PlanningInput, Task, simulate_delay, generate_schedule

z=ZoneInfo('Asia/Shanghai'); now=datetime(2026,11,14,9,tzinfo=z); end=datetime(2026,11,14,18,tzinfo=z)
def make(seconds): return PlanningInput(now,end,tasks=(Task('report',seconds,date(2026,11,14),now),))
for label, value, delay in [
    ('normal',make(3600),None),
    ('delay_still_feasible',make(3600),now+timedelta(hours=2)),
    ('delay_not_found_within_horizon',make(5*3600),now+timedelta(hours=6)),
]:
    result=generate_schedule(value) if delay is None else simulate_delay(value,'report',delay)
    print(label, result)
