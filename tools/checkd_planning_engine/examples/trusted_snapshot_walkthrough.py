#!/usr/bin/env python3
"""Reproducible local demo of sync-aware snapshots and atomic approval tests."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from checkd_planning_engine.trusted_snapshot_store import LocalSyncPending, TrustedSnapshotStore
from checkd_planning_engine.workflow_store import LocalTestPrincipal, SnapshotConflict


NOW = datetime(2026, 11, 15, 2, tzinfo=timezone.utc)
PRINCIPAL = LocalTestPrincipal(
    "demo-user", frozenset({"snapshot:write", "snapshot:read", "planning:read",
                             "proposal:write", "proposal:read", "approval:write",
                             "proposal:apply"}),
)


def main() -> None:
    with tempfile.TemporaryDirectory() as directory:
        store = TrustedSnapshotStore(Path(directory) / "trusted-demo.sqlite")
        try:
            original = {"tasks": [{"task_id": "task-demo", "planned_date": None,
                                   "deadline_date": "2026-11-20"}],
                        "courses": [{"course_id": "course-demo", "weekday": 1}]}
            store.seed_cloud_snapshot(PRINCIPAL, original, now=NOW)
            store.register_device(PRINCIPAL, "device-demo", downloaded_revision=1)

            store.mark_local_change(PRINCIPAL, "device-demo")
            provisional = store.create_snapshot(PRINCIPAL, "device-demo", now=NOW)
            try:
                store.create_proposal(PRINCIPAL, provisional["snapshot_id"],
                    changes=[{"task_id": "task-demo", "planned_date": "2026-11-16"}], now=NOW)
                dirty_rejected = False
            except LocalSyncPending:
                dirty_rejected = True

            store.acknowledge_upload(PRINCIPAL, "device-demo", uploaded_revision=1,
                                     payload=original, now=NOW + timedelta(seconds=1))
            current = store.create_snapshot(PRINCIPAL, "device-demo", now=NOW + timedelta(seconds=2))
            stale_proposal = store.create_proposal(PRINCIPAL, current["snapshot_id"],
                changes=[{"task_id": "task-demo", "planned_date": "2026-11-16"}],
                now=NOW + timedelta(seconds=2))
            stale_approval = store.approve(PRINCIPAL, stale_proposal["proposal_id"],
                                           now=NOW + timedelta(seconds=2))
            store.mutate_cloud(PRINCIPAL, {"courses": [{"course_id": "course-demo", "weekday": 2}]},
                               now=NOW + timedelta(seconds=3))
            try:
                store.apply_approved_changes(PRINCIPAL, stale_proposal["proposal_id"],
                    approval_token=stale_approval["approval_token"], idempotency_key="stale-apply",
                    now=NOW + timedelta(seconds=4))
                stale_rejected = False
            except SnapshotConflict:
                stale_rejected = True

            store.acknowledge_download(PRINCIPAL, "device-demo")
            fresh = store.create_snapshot(PRINCIPAL, "device-demo", now=NOW + timedelta(seconds=5))
            fresh_proposal = store.create_proposal(PRINCIPAL, fresh["snapshot_id"],
                changes=[{"task_id": "task-demo", "planned_date": "2026-11-16"}],
                now=NOW + timedelta(seconds=5))
            approval = store.approve(PRINCIPAL, fresh_proposal["proposal_id"],
                                     now=NOW + timedelta(seconds=5))
            applied = store.apply_approved_changes(PRINCIPAL, fresh_proposal["proposal_id"],
                approval_token=approval["approval_token"], idempotency_key="fresh-apply",
                now=NOW + timedelta(seconds=6))
            print(json.dumps({
                "dirty_local_snapshot": {"sync_state": provisional["sync_state"],
                                         "displayable_provisional": provisional["provisional"],
                                         "proposal_rejected": dirty_rejected},
                "server_version_change_during_approval": {"proposal_status":
                    store.get_proposal(PRINCIPAL, stale_proposal["proposal_id"])["status"],
                    "apply_rejected": stale_rejected},
                "fresh_proposal": {"status": applied["status"],
                                   "readback_verified": applied["readback_verified"],
                                   "business_write_count": store.business_write_count(PRINCIPAL)},
                "execution_scope": "local temporary SQLite only; not CheckD, Supabase, OAuth, or production",
            }, ensure_ascii=False, indent=2))
        finally:
            store.close()


if __name__ == "__main__":
    main()
