import tempfile, unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from checkd_planning_engine.isolated_store import IsolatedStore, AccessDenied

NOW=datetime(2026,11,14,tzinfo=timezone.utc)
class StoreTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory(); self.store=IsolatedStore(Path(self.tmp.name)/'events.db')
 def tearDown(self): self.store.close(); self.tmp.cleanup()
 def test_user_scope_and_unknown_identity_denied(self):
  self.store.put_private('A',verified=True,kind='task',key='same',value={'name':'A'})
  self.store.put_private('B',verified=True,kind='task',key='same',value={'name':'B'})
  self.assertEqual(self.store.get_private('A',verified=True,kind='task',key='same')['name'],'A')
  self.assertIsNone(self.store.get_private('A',verified=True,kind='task',key='B-only'))
  with self.assertRaises(AccessDenied): self.store.get_private(None,verified=False,kind='task',key='same')
 def test_event_dedupe_scoped_to_user(self):
  a=self.store.enqueue('A',verified=True,dedupe_key='k',payload={'n':1},now=NOW)
  self.assertEqual(a,self.store.enqueue('A',verified=True,dedupe_key='k',payload={'n':2},now=NOW))
  b=self.store.enqueue('B',verified=True,dedupe_key='k',payload={'n':1},now=NOW)
  self.assertNotEqual(a,b)
 def test_restart_recovers_expired_processing_event(self):
  event=self.store.enqueue('A',verified=True,dedupe_key='k',payload={},now=NOW)
  self.assertEqual(self.store.claim('w',now=NOW)['event_id'],event)
  self.store.close(); self.store=IsolatedStore(Path(self.tmp.name)/'events.db')
  self.assertEqual(self.store.recover_expired(now=NOW+timedelta(minutes=3)),1)
  self.assertEqual(self.store.claim('w2',now=NOW+timedelta(minutes=3))['event_id'],event)
 def test_fail_retry_and_complete_owner_check(self):
  event=self.store.enqueue('A',verified=True,dedupe_key='k',payload={},now=NOW)
  self.store.claim('w',now=NOW)
  with self.assertRaises(AccessDenied): self.store.complete(event,verified_user_id='B',result={})
  self.store.fail(event,'TEMP',now=NOW)
  self.assertEqual(self.store.claim('w',now=NOW+timedelta(seconds=3))['event_id'],event)
  self.store.complete(event,verified_user_id='A',result={'ok':True})
  self.assertIsNone(self.store.claim('w',now=NOW+timedelta(days=1)))
 def test_unverified_enqueue_rejected(self):
  with self.assertRaises(AccessDenied): self.store.enqueue('A',verified=False,dedupe_key='x',payload={})
 def test_concurrent_users_claim_distinct_events(self):
  a=self.store.enqueue('A',verified=True,dedupe_key='same',payload={'u':'A'},now=NOW)
  b=self.store.enqueue('B',verified=True,dedupe_key='same',payload={'u':'B'},now=NOW)
  claimed={self.store.claim('w1',now=NOW)['event_id'],self.store.claim('w2',now=NOW)['event_id']}
  self.assertEqual(claimed,{a,b})
 def test_duplicate_completion_cannot_reexecute(self):
  event=self.store.enqueue('A',verified=True,dedupe_key='x',payload={},now=NOW); self.store.claim('w',now=NOW)
  self.store.complete(event,verified_user_id='A',result={'ok':1})
  with self.assertRaises(ValueError): self.store.complete(event,verified_user_id='A',result={'ok':2})

if __name__=='__main__': unittest.main()
