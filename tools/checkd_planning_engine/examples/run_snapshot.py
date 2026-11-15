#!/usr/bin/env python3
"""Read normalized Flutter snapshot JSON from stdin and emit planning-only results."""
from __future__ import annotations
import json, sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
from checkd_planning_engine.engine import generate_schedule, simulate_delay
from checkd_planning_engine.importer import import_snapshot

payload=json.load(sys.stdin)
snapshot=import_snapshot(payload)
result=generate_schedule(snapshot.planning_input)
output={"snapshot_version":snapshot.version,"snapshot_digest":snapshot.digest,
 "provisional":snapshot.provisional,"execution_eligible":False,
 "outcome":("unknown_due_to_missing_data" if snapshot.unknown_effort_task_ids or
   snapshot.missing_deadline_task_ids or snapshot.existing_plan_needing_effort_task_ids or
   payload.get("unmodeled_recurring_occurrence_ids",[]) else
   "found_feasible" if result.feasible else "no_solution_found"),
 "unknown_effort_task_ids":list(snapshot.unknown_effort_task_ids),
 "missing_deadline_task_ids":list(snapshot.missing_deadline_task_ids),
 "existing_plan_task_ids":list(snapshot.existing_plan_task_ids),
 "existing_plan_needing_effort_task_ids":list(snapshot.existing_plan_needing_effort_task_ids),
 "schedule":{"feasible":result.feasible,"status":result.status,"blocks":result.blocks,
   "unplanned_tasks":result.unplanned_tasks,"optimality_proven":result.optimality_proven,
   "limitation":result.limitation}}
delay=payload.get('delay_scenario')
if delay:
 from datetime import datetime
 output['delay_analysis']=simulate_delay(snapshot.planning_input,delay['task_id'],datetime.fromisoformat(delay['delay_until']))
print(json.dumps(output,ensure_ascii=False))
