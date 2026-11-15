import tempfile
from concurrent.futures import ThreadPoolExecutor
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from checkd_planning_engine.workflow_store import (
    AccessDenied, AlreadyApplied, ApprovalConsumed, IdempotencyConflict,
    InvalidTransition, LocalTestHumanConfirmation, LocalTestPrincipal, NotFound, PlanningWorkflowStore,
    ProposalExpired, ReadbackPending, SnapshotConflict,
)

NOW = datetime(2026, 11, 14, 1, tzinfo=timezone.utc)
SCOPES = frozenset({"events:write", "workspace:read", "workspace:write",
                    "risk:read", "risk:write", "proposal:read", "proposal:write",
                    "approval:write", "proposal:apply"})


class WorkflowStoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "workflow.db"
        self.store = PlanningWorkflowStore(self.path)
        self.a = LocalTestPrincipal("user-a", SCOPES)
        self.b = LocalTestPrincipal("user-b", SCOPES)

    def tearDown(self):
        self.store.close()
        self.tmp.cleanup()

    def test_identity_scope_and_user_isolated_idempotency(self):
        with self.assertRaises(AccessDenied):
            self.store.enqueue_event("user-a", event_type="x", dedupe_key="k", payload={}, now=NOW)
        a = self.store.enqueue_event(self.a, event_type="a", dedupe_key="same", payload={"owner":"A"}, now=NOW)
        self.assertEqual(self.store.enqueue_event(self.a, event_type="a", dedupe_key="same", payload={}, now=NOW), a)
        b = self.store.enqueue_event(self.b, event_type="b", dedupe_key="same", payload={"owner":"B"}, now=NOW)
        self.assertNotEqual(a, b)

    def test_event_lease_expiry_retry_and_fencing(self):
        event = self.store.enqueue_event(self.a, event_type="risk_scan", dedupe_key="r1", payload={}, now=NOW)
        claim = self.store.claim_event("worker-a", now=NOW, lease=timedelta(seconds=5))
        self.assertEqual(claim["event_id"], event)
        with self.assertRaises(NotFound):
            self.store.complete_event(self.b, event, worker="worker-a", result={}, now=NOW+timedelta(seconds=1))
        self.store.close()
        self.store = PlanningWorkflowStore(self.path)
        recovered = self.store.claim_event("worker-b", now=NOW+timedelta(seconds=6))
        self.assertEqual(recovered["event_id"], event)
        with self.assertRaises(NotFound):
            self.store.complete_event(self.a, event, worker="worker-a", result={}, now=NOW+timedelta(seconds=7))
        self.store.complete_event(self.a, event, worker="worker-b", result={"ok":True}, now=NOW+timedelta(seconds=8))

    def test_event_failure_backoff_and_same_user_queue(self):
        event = self.store.enqueue_event(self.a, event_type="scan", dedupe_key="one", payload={}, now=NOW)
        self.store.claim_event("worker", now=NOW)
        self.store.fail_event(self.a, event, worker="worker", error_code="TEMPORARY", now=NOW)
        self.assertIsNone(self.store.claim_event("other", now=NOW+timedelta(seconds=1)))
        self.assertIsNotNone(self.store.claim_event("other", now=NOW+timedelta(seconds=3)))

    def test_crashed_event_reaches_dead_letter_after_attempt_limit(self):
        event = self.store.enqueue_event(self.a,event_type="scan",dedupe_key="crash",payload={},now=NOW)
        self.store.claim_event("crashing-worker",now=NOW,lease=timedelta(seconds=1),max_attempts=1)
        self.assertIsNone(self.store.claim_event("replacement",now=NOW+timedelta(seconds=1),max_attempts=1))
        row = self.store.db.execute("SELECT status,error_code FROM agent_events WHERE event_id=?",(event,)).fetchone()
        self.assertEqual(row["status"],"dead_letter")
        self.assertEqual(row["error_code"],"LEASE_EXPIRED_MAX_ATTEMPTS")

    def test_private_workspace_isolation_survives_restart(self):
        self.store.put_private(self.a, kind="memory", key="pref", value={"mode":"quiet"}, now=NOW)
        self.store.put_private(self.a, kind="course", key="course-1", value={"private":True}, now=NOW)
        self.assertIsNone(self.store.get_private(self.b, kind="memory", key="pref"))
        self.assertIsNone(self.store.get_private(self.b, kind="course", key="course-1"))
        self.store.close()
        self.store = PlanningWorkflowStore(self.path)
        self.assertEqual(self.store.get_private(self.a, kind="memory", key="pref"), {"mode":"quiet"})

    def test_revoked_test_session_fails_closed(self):
        self.store.put_private(self.a, kind="preference", key="mode", value={"x":1}, now=NOW)
        self.store.revoke_access(self.a, now=NOW+timedelta(minutes=1))
        with self.assertRaises(AccessDenied):
            self.store.get_private(self.a, kind="preference", key="mode")

    def test_two_users_can_claim_independent_events_concurrently(self):
        event_a = self.store.enqueue_event(self.a,event_type="scan",dedupe_key="a",payload={},now=NOW)
        event_b = self.store.enqueue_event(self.b,event_type="scan",dedupe_key="b",payload={},now=NOW)
        def claim(worker):
            other = PlanningWorkflowStore(self.path)
            try:
                return other.claim_event(worker,now=NOW)["event_id"]
            finally:
                other.close()
        with ThreadPoolExecutor(max_workers=2) as pool:
            claimed = set(pool.map(claim,["worker-a","worker-b"]))
        self.assertEqual(claimed,{event_a,event_b})

    def test_same_user_events_are_claimed_once_under_concurrency(self):
        events = {
            self.store.enqueue_event(self.a,event_type="scan",dedupe_key=f"same-{index}",payload={},now=NOW)
            for index in range(2)
        }
        def claim(worker):
            other = PlanningWorkflowStore(self.path)
            try:
                return other.claim_event(worker,now=NOW)["event_id"]
            finally:
                other.close()
        with ThreadPoolExecutor(max_workers=2) as pool:
            claimed = set(pool.map(claim,["same-worker-a","same-worker-b"]))
        self.assertEqual(claimed,events)

    def test_risk_version_update_resolution_and_notification_dedupe(self):
        risk = {"risk_key":"risk-1", "risk_type":"buffer_low", "severity":"high",
                "evidence":{"slack_seconds":120}, "recommendation":"review"}
        first = self.store.update_risks(self.a, version="v1", risks=[risk], now=NOW)
        again = self.store.update_risks(self.a, version="v1", risks=[risk], now=NOW+timedelta(minutes=1))
        self.assertEqual(first["notifications_queued"], 1)
        self.assertEqual(again["notifications_queued"], 0)
        changed = dict(risk, severity="critical")
        changed["evidence"] = {"slack_seconds":0}
        updated = self.store.update_risks(self.a, version="v2", risks=[changed], now=NOW+timedelta(minutes=2))
        self.assertEqual(updated["notifications_queued"], 1)
        self.assertEqual(len(self.store.list_pending_notifications(self.a)), 2)
        resolved = self.store.update_risks(self.a, version="v3", risks=[], now=NOW+timedelta(minutes=3))
        self.assertEqual(resolved["resolved_count"], 1)
        self.assertEqual(len(self.store.list_pending_notifications(self.b)), 0)

    def test_daily_notification_cap_uses_shanghai_calendar_day(self):
        risk = {"risk_key":"risk-day", "risk_type":"buffer_low", "severity":"medium", "evidence":{}}
        # 16:00 UTC is midnight on the next Shanghai calendar day.
        at = datetime(2026, 11, 14, 16, tzinfo=timezone.utc)
        self.assertEqual(self.store.update_risks(self.a,version="v1",risks=[risk],now=at,daily_limit=1)["notifications_queued"],1)
        changed = dict(risk, severity="high")
        changed["evidence"] = {"changed":True}
        self.assertEqual(self.store.update_risks(self.a,version="v2",risks=[changed],now=at+timedelta(minutes=1),daily_limit=1)["notifications_queued"],0)
        self.assertEqual(self.store.update_risks(self.a,version="v3",risks=[changed],now=at+timedelta(days=1),daily_limit=1)["notifications_queued"],1)

    def test_same_risk_realert_after_cooldown(self):
        risk = {"risk_key":"risk-cooldown", "risk_type":"buffer_low", "severity":"medium", "evidence":{}}
        self.assertEqual(self.store.update_risks(self.a,version="v1",risks=[risk],now=NOW)["notifications_queued"],1)
        self.assertEqual(self.store.update_risks(self.a,version="v2",risks=[risk],now=NOW+timedelta(hours=1))["notifications_queued"],0)
        self.assertEqual(self.store.update_risks(self.a,version="v3",risks=[risk],now=NOW+timedelta(hours=13))["notifications_queued"],1)

    def _proposal(self, proposal_id="p1", *, key="proposal-key", now=NOW):
        draft = self.store.create_draft(self.a, proposal_id=proposal_id, base_version="v1",
            rules_version="rules-1", changes=[{"task_id":"t1","planned_date":"2026-11-14"}],
            expires_at=now+timedelta(minutes=30), idempotency_key=key, now=now)
        return self.store.propose(self.a,proposal_id,current_version="v1",now=now)

    def _confirmation(self, principal, proposal_id):
        row = self.store.get_proposal(principal, proposal_id)
        return LocalTestHumanConfirmation(
            subject=principal.subject, proposal_id=proposal_id,
            changes_digest=row["changes_digest"], confirmation_id=f"confirm-{proposal_id}",
        )

    def test_approval_apply_replay_readback_and_cross_user_denial(self):
        self._proposal()
        with self.assertRaises(NotFound):
            self.store.get_proposal(self.b,"p1")
        approval = self.store.approve(self.a,"p1",confirmation=self._confirmation(self.a,"p1"),current_version="v1",now=NOW)
        with self.assertRaises(NotFound):
            self.store.begin_apply(self.b,"p1",approval_token=approval["approval_token"],
                idempotency_key="k",current_version="v1",now=NOW)
        self.store.create_draft(self.b,proposal_id="p-b",base_version="vb",rules_version="r1",
            changes=[{"task_id":"tb"}],expires_at=NOW+timedelta(minutes=20),idempotency_key="same-key",now=NOW)
        self.store.propose(self.b,"p-b",current_version="vb",now=NOW)
        with self.assertRaises(NotFound):
            self.store.begin_apply(self.b,"p-b",approval_token=approval["approval_token"],
                idempotency_key="cross-proposal",current_version="vb",now=NOW)
        first = self.store.begin_apply(self.a,"p1",approval_token=approval["approval_token"],
            idempotency_key="apply-k",current_version="v1",now=NOW)
        self.assertFalse(first["business_write_performed"])
        replay = self.store.begin_apply(self.a,"p1",approval_token=approval["approval_token"],
            idempotency_key="apply-k",current_version="v1",now=NOW+timedelta(seconds=1))
        self.assertTrue(replay["replayed"])
        with self.assertRaises(IdempotencyConflict):
            self.store.begin_apply(self.a,"p1",approval_token="different",
                idempotency_key="apply-k",current_version="v1",now=NOW)
        final = self.store.finish_apply(self.a,"p1",idempotency_key="apply-k",
            readback_verified=True,result={"verified":True},now=NOW+timedelta(seconds=2))
        self.assertEqual(final["status"],"applied")
        with self.assertRaises(AlreadyApplied):
            self.store.begin_apply(self.a,"p1",approval_token=approval["approval_token"],
                idempotency_key="apply-k-new",current_version="v1",now=NOW+timedelta(seconds=3))

    def test_approval_requires_matching_explicit_confirmation(self):
        self._proposal()
        with self.assertRaises(AccessDenied):
            self.store.approve(self.a,"p1",confirmation=None,current_version="v1",now=NOW)
        wrong = LocalTestHumanConfirmation(
            subject=self.a.subject, proposal_id="other-proposal",
            changes_digest=self._confirmation(self.a,"p1").changes_digest,
            confirmation_id="fake-confirmation",
        )
        with self.assertRaises(AccessDenied):
            self.store.approve(self.a,"p1",confirmation=wrong,current_version="v1",now=NOW)
        approval = self.store.approve(self.a,"p1",confirmation=self._confirmation(self.a,"p1"),
            current_version="v1",now=NOW)
        self.assertEqual(approval["status"],"approved")

    def test_failed_readback_is_terminal_and_token_consumed(self):
        self._proposal()
        approval = self.store.approve(self.a,"p1",confirmation=self._confirmation(self.a,"p1"),current_version="v1",now=NOW)
        self.store.begin_apply(self.a,"p1",approval_token=approval["approval_token"],
            idempotency_key="k",current_version="v1",now=NOW)
        final = self.store.finish_apply(self.a,"p1",idempotency_key="k",
            readback_verified=False,result={},now=NOW+timedelta(seconds=1))
        self.assertEqual(final["status"],"failed")
        with self.assertRaises(InvalidTransition):
            self.store.begin_apply(self.a,"p1",approval_token=approval["approval_token"],
                idempotency_key="k2",current_version="v1",now=NOW+timedelta(seconds=2))

    def test_uncertain_readback_recovers_without_second_apply(self):
        self._proposal()
        approval = self.store.approve(self.a,"p1",confirmation=self._confirmation(self.a,"p1"),
            current_version="v1",now=NOW)
        self.store.begin_apply(self.a,"p1",approval_token=approval["approval_token"],
            idempotency_key="k",current_version="v1",now=NOW)
        pending = self.store.finish_apply(self.a,"p1",idempotency_key="k",
            readback_verified=None,result={},now=NOW+timedelta(seconds=1))
        self.assertEqual(pending["status"],"readback_pending")
        self.assertEqual(pending["operation"],"readback_only")
        self.assertFalse(pending["business_write_performed"])
        with self.assertRaises(ReadbackPending):
            self.store.begin_apply(self.a,"p1",approval_token=approval["approval_token"],
                idempotency_key="new-key",current_version="v1",now=NOW+timedelta(seconds=2))
        still_pending = self.store.reconcile_readback(self.a,"p1",idempotency_key="k",
            outcome="unknown",result={},now=NOW+timedelta(seconds=3))
        self.assertEqual(still_pending["status"],"readback_pending")
        applied = self.store.reconcile_readback(self.a,"p1",idempotency_key="k",
            outcome="consistent",result={"verified":True},now=NOW+timedelta(seconds=4))
        self.assertEqual(applied["status"],"applied")
        self.assertEqual(applied["operation"],"readback_only")
        self.assertFalse(applied["business_write_performed"])
        replay = self.store.begin_apply(self.a,"p1",approval_token=approval["approval_token"],
            idempotency_key="k",current_version="v1",now=NOW+timedelta(seconds=5))
        self.assertTrue(replay["replayed"])
        self.assertEqual(replay["status"],"applied")

    def test_finish_apply_requires_matching_in_progress_idempotency_record(self):
        self._proposal()
        approval = self.store.approve(self.a,"p1",confirmation=self._confirmation(self.a,"p1"),current_version="v1",now=NOW)
        self.store.begin_apply(self.a,"p1",approval_token=approval["approval_token"],
            idempotency_key="k",current_version="v1",now=NOW)
        with self.assertRaises(InvalidTransition):
            self.store.finish_apply(self.a,"p1",idempotency_key="wrong-key",
                readback_verified=True,result={},now=NOW+timedelta(seconds=1))
        self.assertEqual(self.store.get_proposal(self.a,"p1")["status"],"applying")
        self.assertEqual(self.store.finish_apply(self.a,"p1",idempotency_key="k",
            readback_verified=True,result={},now=NOW+timedelta(seconds=2))["status"],"applied")

    def test_expired_approval_and_version_conflict(self):
        self._proposal()
        approval = self.store.approve(self.a,"p1",confirmation=self._confirmation(self.a,"p1"),current_version="v1",now=NOW,token_ttl=timedelta(seconds=5))
        with self.assertRaises(ProposalExpired):
            self.store.begin_apply(self.a,"p1",approval_token=approval["approval_token"],
                idempotency_key="expired",current_version="v1",now=NOW+timedelta(seconds=5))
        self.assertEqual(self.store.get_proposal(self.a,"p1")["status"],"superseded")

        self._proposal("p2",key="proposal-key-2")
        with self.assertRaises(SnapshotConflict):
            self.store.approve(self.a,"p2",confirmation=self._confirmation(self.a,"p2"),current_version="changed",now=NOW)
        self.assertEqual(self.store.get_proposal(self.a,"p2")["status"],"superseded")

    def test_proposal_idempotency_and_rejected_state(self):
        draft = self.store.create_draft(self.a,proposal_id="p1",base_version="v1",rules_version="r1",
            changes=[],expires_at=NOW+timedelta(minutes=5),idempotency_key="key",now=NOW)
        same = self.store.create_draft(self.a,proposal_id="ignored",base_version="v1",rules_version="r1",
            changes=[],expires_at=NOW+timedelta(minutes=5),idempotency_key="key",now=NOW)
        self.assertEqual(draft["proposal_id"],same["proposal_id"])
        with self.assertRaises(IdempotencyConflict):
            self.store.create_draft(self.a,proposal_id="p2",base_version="v1",rules_version="r1",
                changes=[{"x":1}],expires_at=NOW+timedelta(minutes=5),idempotency_key="key",now=NOW)
        rejected = self.store.reject(self.a,"p1",now=NOW)
        self.assertEqual(rejected["status"],"rejected")
        own = self.store.create_draft(self.b,proposal_id="b-proposal",base_version="v1",rules_version="r1",
            changes=[],expires_at=NOW+timedelta(minutes=5),idempotency_key="key",now=NOW)
        self.assertEqual(own["proposal_id"],"b-proposal")


if __name__ == "__main__":
    unittest.main()
