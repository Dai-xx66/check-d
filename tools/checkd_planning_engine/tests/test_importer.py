import unittest
from datetime import date
from checkd_planning_engine.importer import assert_snapshot_current, import_snapshot
from checkd_planning_engine.engine import generate_schedule

BASE={"subject_ref":"anon-A","source":"redacted_fixture","captured_at":"2026-11-14T00:00:00Z","version":"v1","sync_state":"pending_local_changes","timezone":"Asia/Shanghai","now":"2026-11-14T09:00:00+08:00","horizon_end":"2026-11-14T18:00:00+08:00","tasks":[{"task_id":"t1","remaining_seconds":None,"deadline_date":"2026-11-14","earliest_start":"2026-11-14T09:00:00+08:00"}],"course_occurrences":[{"starts_at":"2026-11-14T10:00:00+08:00","ends_at":"2026-11-14T11:00:00+08:00","kind":"course"}],"occupied_blocks":[]}
class ImportTests(unittest.TestCase):
 def test_pending_sync_retains_snapshot_and_unknown_effort(self):
  snap=import_snapshot(BASE)
  self.assertTrue(snap.provisional); self.assertFalse(snap.effort_known); self.assertEqual(snap.version,'v1')
  self.assertTrue(snap.planning_input.tasks[0].deadline==date(2026,11,14))
 def test_user_id_spoofing_rejected_and_digest_changes(self):
  bad=dict(BASE,user_id='victim')
  with self.assertRaises(ValueError): import_snapshot(bad)
  changed=dict(BASE,version='v2'); self.assertNotEqual(import_snapshot(BASE).digest,import_snapshot(changed).digest)
 def test_resolved_occurrence_is_used_as_block(self):
  snap=import_snapshot(BASE); result=generate_schedule(snap.planning_input)
  self.assertFalse(any('10:00:00' in b['starts_at'] for b in result.blocks))
 def test_provisional_or_changed_version_cannot_reuse_proposal(self):
  snap=import_snapshot(BASE)
  with self.assertRaises(RuntimeError): assert_snapshot_current(snap,subject_ref='anon-A',version='v1',sync_state='current')
  current=dict(BASE,sync_state='current'); fresh=import_snapshot(current)
  with self.assertRaises(RuntimeError): assert_snapshot_current(fresh,subject_ref='anon-A',version='v2',sync_state='current')
if __name__=='__main__': unittest.main()
