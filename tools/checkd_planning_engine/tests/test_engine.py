import unittest
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo
from checkd_planning_engine import Block, PlanningInput, Task, generate_schedule, simulate_delay
from checkd_planning_engine.engine import calculate_availability
from checkd_planning_engine.risk import evaluate_risks
from checkd_planning_engine.preferences import Preference, InterventionPolicy, render_risk

Z=ZoneInfo('Asia/Shanghai')
NOW=datetime(2026,11,14,9,tzinfo=Z)

class EngineTests(unittest.TestCase):
 def make(self, deadline=date(2026,11,14), effort=3600, blocks=(), task_extra=None):
  task=Task('a',effort,deadline,NOW,**(task_extra or {}))
  return PlanningInput(NOW,datetime(2026,11,14,18,tzinfo=Z),tasks=(task,),fixed_blocks=tuple(blocks))
 def test_normal_plan_and_date_only_deadline(self):
  result=generate_schedule(self.make())
  self.assertTrue(result.feasible); self.assertEqual(result.blocks[0]['starts_at'],NOW.isoformat())
  self.assertFalse(result.optimality_proven)
 def test_course_blocks_are_respected(self):
  course=Block(NOW,NOW+timedelta(hours=2),kind='course')
  result=generate_schedule(self.make(blocks=(course,)))
  self.assertEqual(result.blocks[0]['starts_at'],(NOW+timedelta(hours=2)).isoformat())
 def test_non_splittable_requires_contiguous_slots(self):
  busy=Block(NOW+timedelta(minutes=30),NOW+timedelta(minutes=45))
  result=generate_schedule(self.make(effort=10*3600,blocks=(busy,),task_extra={'splittable':False,'minimum_block_minutes':60}))
  self.assertFalse(result.feasible)
  self.assertIn('not a proof',result.limitation)
 def test_splittable_respects_minimum_chunk(self):
  busy=Block(NOW+timedelta(minutes=30),NOW+timedelta(minutes=60))
  result=generate_schedule(self.make(effort=3600,blocks=(busy,),task_extra={'minimum_block_minutes':45}))
  self.assertTrue(result.feasible)
 def test_delay_still_feasible(self):
  result=simulate_delay(self.make(), 'a', NOW+timedelta(hours=1))
  self.assertTrue(result['before_feasible']); self.assertTrue(result['after_feasible'])
  self.assertLess(result['after_slack_seconds'],result['before_slack_seconds'])
 def test_delay_not_found_within_horizon(self):
  result=simulate_delay(self.make(effort=4*3600), 'a', NOW+timedelta(hours=7))
  self.assertFalse(result['after_feasible'])
 def test_multiple_tasks_compete_edf_order_is_stable(self):
  a=Task('later',3600,date(2026,11,14),NOW); b=Task('sooner',3600,NOW+timedelta(hours=2),NOW)
  v=PlanningInput(NOW,datetime(2026,11,14,12,tzinfo=Z),tasks=(a,b))
  r=generate_schedule(v); self.assertEqual(r.blocks[0]['task_id'],'sooner')
 def test_fragmented_windows_do_not_claim_contiguous_fit(self):
  busy=tuple(Block(NOW+timedelta(minutes=m),NOW+timedelta(minutes=m+15)) for m in (30,90,150))
  v=self.make(effort=10*3600,blocks=busy,task_extra={'splittable':False})
  self.assertFalse(generate_schedule(v).feasible)
 def test_cross_day_slots_keep_offset_and_deadline(self):
  late=datetime(2026,11,14,23,30,tzinfo=Z); due=datetime(2026,11,15,1,tzinfo=Z)
  v=PlanningInput(late,datetime(2026,11,15,2,tzinfo=Z),tasks=(Task('overnight',3600,due,late),))
  r=generate_schedule(v); self.assertTrue(r.feasible); self.assertIn('+08:00',r.blocks[0]['starts_at'])
 def test_expired_deadline_and_exact_deadline(self):
  old=generate_schedule(self.make(deadline=date(2026,11,13)))
  exact=generate_schedule(self.make(deadline=NOW+timedelta(hours=1)))
  self.assertFalse(old.feasible); self.assertTrue(exact.feasible)
 def test_invalid_timezone_and_zero_slot(self):
  v=self.make(); bad=PlanningInput(v.now,v.horizon_end,'No/Such',v.tasks)
  with self.assertRaises(Exception): generate_schedule(bad)
  self.assertEqual(calculate_availability(PlanningInput(NOW,NOW, tasks=v.tasks)),[])

class PolicyTests(unittest.TestCase):
 def test_risk_key_stable_and_style_facts_same(self):
  risk=evaluate_risks([{'task_id':'a','remaining_seconds':300,'available_capacity_seconds':100}],evaluated_at=NOW)
  self.assertEqual(risk[0]['risk_key'],evaluate_risks([{'task_id':'a','remaining_seconds':300,'available_capacity_seconds':100}],evaluated_at=NOW)[0]['risk_key'])
  for style in ('gentle','balanced','direct'):
   self.assertEqual(render_risk(risk[0],style)['facts'],risk[0])
 def test_inferred_preference_cannot_be_hard(self):
  with self.assertRaises(ValueError): Preference('study_time','morning','inferred',True)
 def test_intervention_cooldown_and_ignore(self):
  p=InterventionPolicy(); self.assertTrue(p.should_notify('u','r',NOW)); p.record('u','r',NOW)
  self.assertFalse(p.should_notify('u','r',NOW+timedelta(hours=1)))
  p.ignored.add('r'); self.assertFalse(p.should_notify('u','r',NOW+timedelta(days=2)))

if __name__=='__main__': unittest.main()
