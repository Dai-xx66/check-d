import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path

from checkd_planning_engine.trusted_snapshot_store import (
    LocalSyncPending, TrustedSnapshotStore,
)
from checkd_planning_engine.workflow_store import (
    AlreadyApplied, IdempotencyConflict, InvalidTransition, LocalTestPrincipal, NotFound,
    ReadbackPending, ProposalExpired, SnapshotConflict,
)

NOW = datetime(2026, 11, 15, 2, tzinfo=timezone.utc)
SCOPES = frozenset({"snapshot:write", "snapshot:read", "planning:read",
                    "proposal:write", "proposal:read", "approval:write",
                    "proposal:apply"})


class TrustedSnapshotStoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "trusted-snapshot.db"
        self.store = TrustedSnapshotStore(self.path)
        self.a = LocalTestPrincipal("user-a", SCOPES)
        self.b = LocalTestPrincipal("user-b", SCOPES)
        self._seed(self.a, "a")
        self._seed(self.b, "b")

    def tearDown(self):
        self.store.close()
        self.tmp.cleanup()

    def _payload(self, label):
        return {
            "tasks": [{"task_id": f"task-{label}", "planned_date": None,
                       "deadline_date": "2026-11-20"}],
            "courses": [{"course_id": f"course-{label}", "weekday": 1}],
        }

    def _seed(self, principal, label):
        self.store.seed_cloud_snapshot(principal, self._payload(label), now=NOW)
        self.store.register_device(principal, "device-1", downloaded_revision=1)

    def _snapshot(self, principal=None, *, device="device-1", now=NOW):
        return self.store.create_snapshot(principal or self.a, device, now=now)

    def _proposal(self, *, principal=None, now=NOW, label="a"):
        principal = principal or self.a
        snap = self._snapshot(principal, now=now)
        proposal = self.store.create_proposal(principal, snap["snapshot_id"],
            changes=[{"task_id":f"task-{label}","planned_date":"2026-11-16"}],now=now)
        return snap, proposal

    def test_local_pending_mutation_is_displayable_but_not_proposable(self):
        self.store.mark_local_change(self.a,"device-1")
        snapshot=self._snapshot()
        self.assertTrue(snapshot["provisional"])
        self.assertFalse(snapshot["approval_eligible"])
        self.assertEqual(snapshot["sync_state"],"pending_local_changes")
        with self.assertRaises(LocalSyncPending):
            self.store.create_proposal(self.a,snapshot["snapshot_id"],
                changes=[{"task_id":"task-a","planned_date":"2026-11-16"}],now=NOW)

    def test_cloud_lag_is_provisional_until_device_download_ack(self):
        self.store.mutate_cloud(self.a,{"courses":[{"course_id":"course-a","weekday":2}]},now=NOW+timedelta(seconds=1))
        snapshot=self._snapshot(now=NOW+timedelta(seconds=2))
        self.assertEqual(snapshot["sync_state"],"cloud_lagging")
        self.assertTrue(snapshot["provisional"])
        with self.assertRaises(LocalSyncPending):
            self.store.create_proposal(self.a,snapshot["snapshot_id"],
                changes=[{"task_id":"task-a","planned_date":"2026-11-16"}],now=NOW+timedelta(seconds=2))
        self.store.acknowledge_download(self.a,"device-1")
        current=self._snapshot(now=NOW+timedelta(seconds=3))
        self.assertEqual(current["sync_state"],"current")
        self.assertFalse(current["provisional"])

    def test_task_or_course_change_during_approval_invalidates_proposal(self):
        _,proposal=self._proposal()
        approval=self.store.approve(self.a,proposal["proposal_id"],now=NOW)
        self.store.mutate_cloud(self.a,{"courses":[{"course_id":"course-a","weekday":3}]},now=NOW+timedelta(seconds=1))
        before=self.store.cloud_payload(self.a)
        with self.assertRaises(SnapshotConflict):
            self.store.apply_approved_changes(self.a,proposal["proposal_id"],
                approval_token=approval["approval_token"],idempotency_key="apply-a",
                now=NOW+timedelta(seconds=2))
        self.assertEqual(self.store.business_write_count(self.a),0)
        self.assertEqual(self.store.cloud_payload(self.a),before)
        self.assertEqual(self.store.get_proposal(self.a,proposal["proposal_id"])["status"],"superseded")

    def test_expired_snapshot_cannot_create_proposal(self):
        snapshot=self._snapshot()
        with self.assertRaises(ProposalExpired):
            self.store.create_proposal(self.a,snapshot["snapshot_id"],
                changes=[{"task_id":"task-a","planned_date":"2026-11-16"}],
                now=NOW+timedelta(minutes=15))

    def test_expired_proposal_is_rejected_before_any_write(self):
        _,proposal=self._proposal()
        approval=self.store.approve(self.a,proposal["proposal_id"],now=NOW)
        self.assertGreater(len(approval["approval_token"]),20)
        before=self.store.cloud_payload(self.a)
        with self.assertRaises(ProposalExpired):
            self.store.apply_approved_changes(self.a,proposal["proposal_id"],
                approval_token=approval["approval_token"],idempotency_key="expired",
                now=NOW+timedelta(minutes=30))
        self.assertEqual(self.store.cloud_payload(self.a),before)
        self.assertEqual(self.store.business_write_count(self.a),0)
        self.assertEqual(self.store.get_proposal(self.a,proposal["proposal_id"])["status"],"expired")

    def test_expired_proposed_state_is_terminal_and_does_not_rewrite_applied(self):
        _,proposal=self._proposal()
        with self.assertRaises(ProposalExpired):
            self.store.approve(self.a,proposal["proposal_id"],now=NOW+timedelta(minutes=30))
        self.assertEqual(self.store.get_proposal(self.a,proposal["proposal_id"])["status"],"expired")

        _,applied_proposal=self._proposal(now=NOW+timedelta(seconds=1))
        approval=self.store.approve(self.a,applied_proposal["proposal_id"],now=NOW+timedelta(seconds=1))
        self.store.apply_approved_changes(self.a,applied_proposal["proposal_id"],
            approval_token=approval["approval_token"],idempotency_key="applied-before-expiry",
            now=NOW+timedelta(seconds=2))
        with self.assertRaises(InvalidTransition):
            self.store.approve(self.a,applied_proposal["proposal_id"],
                now=NOW+timedelta(minutes=31))
        self.assertEqual(self.store.get_proposal(self.a,applied_proposal["proposal_id"])["status"],"applied")

    def test_approval_token_rejected_for_other_user_without_data_change(self):
        _,proposal=self._proposal()
        approval=self.store.approve(self.a,proposal["proposal_id"],now=NOW)
        before=self.store.cloud_payload(self.b)
        with self.assertRaises(NotFound):
            self.store.apply_approved_changes(self.b,proposal["proposal_id"],
                approval_token=approval["approval_token"],idempotency_key="cross-user",now=NOW)
        self.assertEqual(self.store.cloud_payload(self.b),before)
        self.assertEqual(self.store.business_write_count(self.b),0)

    def test_transaction_failure_rolls_back_token_state_and_business_mutation(self):
        _,proposal=self._proposal()
        approval=self.store.approve(self.a,proposal["proposal_id"],now=NOW)
        before=self.store.cloud_payload(self.a)
        with self.assertRaises(RuntimeError):
            self.store.apply_approved_changes(self.a,proposal["proposal_id"],
                approval_token=approval["approval_token"],idempotency_key="recoverable",
                now=NOW+timedelta(seconds=1),fail_before_commit=True)
        self.assertEqual(self.store.cloud_payload(self.a),before)
        self.assertEqual(self.store.business_write_count(self.a),0)
        self.assertEqual(self.store.get_proposal(self.a,proposal["proposal_id"])["status"],"approved")
        applied=self.store.apply_approved_changes(self.a,proposal["proposal_id"],
            approval_token=approval["approval_token"],idempotency_key="recoverable",
            now=NOW+timedelta(seconds=2))
        self.assertEqual(applied["status"],"applied")
        self.assertEqual(self.store.business_write_count(self.a),1)

    def test_idempotent_apply_and_readback_mismatch(self):
        _,proposal=self._proposal()
        approval=self.store.approve(self.a,proposal["proposal_id"],now=NOW)
        result=self.store.apply_approved_changes(self.a,proposal["proposal_id"],
            approval_token=approval["approval_token"],idempotency_key="same",
            now=NOW+timedelta(seconds=1))
        self.assertTrue(result["readback_verified"])
        replay=self.store.apply_approved_changes(self.a,proposal["proposal_id"],
            approval_token=approval["approval_token"],idempotency_key="same",
            now=NOW+timedelta(seconds=2))
        self.assertTrue(replay["replayed"])
        self.assertEqual(self.store.business_write_count(self.a),1)

        self.store.acknowledge_download(self.a,"device-1")
        _,mismatch=self._proposal(now=NOW+timedelta(seconds=3))
        approval2=self.store.approve(self.a,mismatch["proposal_id"],now=NOW+timedelta(seconds=3))
        failed=self.store.apply_approved_changes(self.a,mismatch["proposal_id"],
            approval_token=approval2["approval_token"],idempotency_key="mismatch",
            now=NOW+timedelta(seconds=4),readback_outcome="mismatch")
        self.assertEqual(failed["status"],"failed")
        self.assertEqual(failed["error_code"],"READBACK_MISMATCH")
        self.assertEqual(self.store.business_write_count(self.a),2)

    def test_unknown_readback_is_readback_only_and_new_key_cannot_reapply(self):
        _,proposal=self._proposal()
        approval=self.store.approve(self.a,proposal["proposal_id"],now=NOW)
        pending=self.store.apply_approved_changes(self.a,proposal["proposal_id"],
            approval_token=approval["approval_token"],idempotency_key="pending",
            now=NOW+timedelta(seconds=1),readback_outcome="unknown")
        self.assertEqual(pending["status"],"readback_pending")
        self.assertEqual(pending["operation"],"readback_only")
        self.assertEqual(self.store.business_write_count(self.a),1)
        with self.assertRaises(ReadbackPending):
            self.store.apply_approved_changes(self.a,proposal["proposal_id"],
                approval_token=approval["approval_token"],idempotency_key="new-key",now=NOW+timedelta(seconds=2))
        applied=self.store.reconcile_readback(self.a,proposal["proposal_id"],
            idempotency_key="pending",outcome="consistent",now=NOW+timedelta(seconds=3))
        self.assertEqual(applied["status"],"applied")
        self.assertEqual(applied["operation"],"readback_only")
        self.assertEqual(self.store.business_write_count(self.a),1)

    def test_readback_pending_survives_store_restart_without_reapplying(self):
        _,proposal=self._proposal()
        approval=self.store.approve(self.a,proposal["proposal_id"],now=NOW)
        pending=self.store.apply_approved_changes(self.a,proposal["proposal_id"],
            approval_token=approval["approval_token"],idempotency_key="restart-pending",
            now=NOW+timedelta(seconds=1),readback_outcome="unknown")
        self.assertEqual(pending["status"],"readback_pending")
        self.assertEqual(self.store.business_write_count(self.a),1)
        self.store.close()
        self.store=TrustedSnapshotStore(self.path)

        recovered=self.store.reconcile_readback(self.a,proposal["proposal_id"],
            idempotency_key="restart-pending",outcome="consistent",now=NOW+timedelta(seconds=2))
        self.assertEqual(recovered["status"],"applied")
        self.assertEqual(recovered["operation"],"readback_only")
        self.assertEqual(self.store.business_write_count(self.a),1)

    def test_concurrent_proposals_from_same_version_only_one_can_apply(self):
        snap=self._snapshot()
        p1=self.store.create_proposal(self.a,snap["snapshot_id"],
            changes=[{"task_id":"task-a","planned_date":"2026-11-16"}],now=NOW)
        p2=self.store.create_proposal(self.a,snap["snapshot_id"],
            changes=[{"task_id":"task-a","planned_date":"2026-11-17"}],now=NOW)
        a1=self.store.approve(self.a,p1["proposal_id"],now=NOW)
        a2=self.store.approve(self.a,p2["proposal_id"],now=NOW)
        self.tokens={p1["proposal_id"]:a1["approval_token"],p2["proposal_id"]:a2["approval_token"]}
        def apply(store_path, proposal, token, key):
            store=TrustedSnapshotStore(store_path)
            try:
                return store.apply_approved_changes(self.a,proposal,approval_token=token,
                    idempotency_key=key,now=NOW+timedelta(seconds=1))["status"]
            finally:
                store.close()
        def safe_apply(proposal,token,key):
            try: return apply(self.path,proposal,token,key)
            except SnapshotConflict: return "snapshot_conflict"
        with ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(lambda args:safe_apply(*args),[
                (p1["proposal_id"],a1["approval_token"],"k1"),
                (p2["proposal_id"],a2["approval_token"],"k2"),
            ]))
        self.assertCountEqual(results,["applied","snapshot_conflict"])
        self.assertEqual(self.store.business_write_count(self.a),1)

    def test_other_user_cannot_read_or_mutate_snapshot(self):
        snapshot=self._snapshot(self.a)
        with self.assertRaises(NotFound):
            self.store.create_proposal(self.b,snapshot["snapshot_id"],
                changes=[{"task_id":"task-a","planned_date":"2026-11-16"}],now=NOW)
        self.assertEqual(self.store.business_write_count(self.a),0)


if __name__ == "__main__":
    unittest.main()
