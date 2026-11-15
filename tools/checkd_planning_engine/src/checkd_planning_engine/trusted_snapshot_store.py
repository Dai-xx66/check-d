"""Isolated SQLite model of server-owned snapshots and atomic approvals.

This is a local test prototype. Its principals and token authority are not
OAuth, Supabase Auth, or a production database. It never connects remotely.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from hashlib import sha256
import json
from pathlib import Path
import secrets
import sqlite3
from typing import Any

from .workflow_store import (
    AccessDenied, AlreadyApplied, IdempotencyConflict, InvalidTransition,
    LocalTestPrincipal, NotFound, ProposalExpired, ReadbackPending,
    SnapshotConflict, _json, _principal, _stamp,
)


class LocalSyncPending(Exception):
    code = "LOCAL_SYNC_PENDING"


class TrustedSnapshotStore:
    """A server-side consistency and approval prototype backed by a temp/local DB."""

    def __init__(self, path: str | Path, *, snapshot_ttl: timedelta = timedelta(minutes=15),
                 approval_ttl: timedelta = timedelta(minutes=5)):
        self.db = sqlite3.connect(str(path), timeout=30, isolation_level=None,
                                  check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA foreign_keys=ON")
        self.snapshot_ttl = snapshot_ttl
        self.approval_ttl = approval_ttl
        self.db.executescript("""
        CREATE TABLE IF NOT EXISTS cloud_state(
          user_id TEXT PRIMARY KEY, revision INTEGER NOT NULL, payload TEXT NOT NULL,
          updated_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS device_watermarks(
          user_id TEXT NOT NULL, device_id TEXT NOT NULL,
          local_revision INTEGER NOT NULL, uploaded_revision INTEGER NOT NULL,
          downloaded_revision INTEGER NOT NULL,
          PRIMARY KEY(user_id,device_id));
        CREATE TABLE IF NOT EXISTS planning_snapshots(
          snapshot_id TEXT PRIMARY KEY,user_id TEXT NOT NULL,version TEXT NOT NULL,
          cloud_revision INTEGER NOT NULL,payload TEXT NOT NULL,digest TEXT NOT NULL,
          sync_state TEXT NOT NULL,provisional INTEGER NOT NULL,created_at TEXT NOT NULL,
          expires_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS planning_proposals(
          proposal_id TEXT PRIMARY KEY,user_id TEXT NOT NULL,snapshot_id TEXT NOT NULL,
          base_version TEXT NOT NULL,changes_digest TEXT NOT NULL,changes_json TEXT NOT NULL,
          status TEXT NOT NULL,expires_at TEXT NOT NULL,created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY(snapshot_id) REFERENCES planning_snapshots(snapshot_id));
        CREATE TABLE IF NOT EXISTS planning_approvals(
          approval_id TEXT PRIMARY KEY,user_id TEXT NOT NULL,proposal_id TEXT NOT NULL,
          token_hash TEXT NOT NULL,status TEXT NOT NULL,expires_at TEXT NOT NULL,
          created_at TEXT NOT NULL,consumed_at TEXT,
          FOREIGN KEY(proposal_id) REFERENCES planning_proposals(proposal_id));
        CREATE UNIQUE INDEX IF NOT EXISTS one_active_token_per_proposal
          ON planning_approvals(user_id,proposal_id) WHERE status='active';
        CREATE TABLE IF NOT EXISTS planning_idempotency(
          user_id TEXT NOT NULL,tool TEXT NOT NULL,idem_key TEXT NOT NULL,
          request_digest TEXT NOT NULL,status TEXT NOT NULL,result_json TEXT,
          created_at TEXT NOT NULL,updated_at TEXT NOT NULL,
          PRIMARY KEY(user_id,tool,idem_key));
        CREATE TABLE IF NOT EXISTS applied_changes(
          user_id TEXT NOT NULL,proposal_id TEXT NOT NULL,task_id TEXT NOT NULL,
          planned_date TEXT NOT NULL,base_version TEXT NOT NULL,applied_version TEXT NOT NULL,
          PRIMARY KEY(user_id,proposal_id,task_id));
        CREATE TABLE IF NOT EXISTS planning_audit(
          audit_id INTEGER PRIMARY KEY AUTOINCREMENT,user_id TEXT NOT NULL,
          resource_type TEXT NOT NULL,resource_id TEXT NOT NULL,action TEXT NOT NULL,
          occurred_at TEXT NOT NULL,details_json TEXT NOT NULL);
        """)

    @staticmethod
    def _require(principal: object, scope: str) -> LocalTestPrincipal:
        return _principal(principal, scope)

    def seed_cloud_snapshot(self, principal: object, payload: dict[str, Any], *,
                            now: datetime) -> str:
        """Test fixture setup representing rows already committed to a server DB."""
        user = self._require(principal, "snapshot:write").subject
        if "user_id" in payload or "subject_ref" in payload:
            raise ValueError("cloud data fixture must not carry client-selected ownership")
        normalized = json.loads(_json(payload))
        if not isinstance(normalized.get("tasks", []), list):
            raise ValueError("tasks must be a list")
        row = self.db.execute("SELECT revision FROM cloud_state WHERE user_id=?", (user,)).fetchone()
        revision = (row["revision"] + 1) if row else 1
        self.db.execute(
            "INSERT INTO cloud_state VALUES(?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET revision=excluded.revision,payload=excluded.payload,updated_at=excluded.updated_at",
            (user, revision, _json(normalized), _stamp(now)),
        )
        return self._cloud_version(revision, normalized)

    def register_device(self, principal: object, device_id: str, *,
                        downloaded_revision: int = 0) -> None:
        user = self._require(principal, "snapshot:write").subject
        if not device_id.strip() or downloaded_revision < 0:
            raise ValueError("valid device_id and revision required")
        self.db.execute(
            "INSERT OR IGNORE INTO device_watermarks VALUES(?,?,0,0,?)",
            (user, device_id, downloaded_revision),
        )

    def mark_local_change(self, principal: object, device_id: str) -> int:
        user = self._require(principal, "snapshot:write").subject
        cursor = self.db.execute(
            "UPDATE device_watermarks SET local_revision=local_revision+1 WHERE user_id=? AND device_id=?",
            (user, device_id),
        )
        if cursor.rowcount != 1:
            raise NotFound("device unavailable")
        return self.db.execute(
            "SELECT local_revision FROM device_watermarks WHERE user_id=? AND device_id=?",
            (user, device_id),
        ).fetchone()["local_revision"]

    def acknowledge_upload(self, principal: object, device_id: str, *,
                           uploaded_revision: int, payload: dict[str, Any], now: datetime) -> str:
        user = self._require(principal, "snapshot:write").subject
        self.db.execute("BEGIN IMMEDIATE")
        try:
            device = self._device(user, device_id)
            if uploaded_revision != device["local_revision"]:
                raise SnapshotConflict("upload does not cover current local revision")
            version = self.seed_cloud_snapshot(principal, payload, now=now)
            revision = self.db.execute(
                "SELECT revision FROM cloud_state WHERE user_id=?", (user,)
            ).fetchone()["revision"]
            self.db.execute(
                "UPDATE device_watermarks SET uploaded_revision=?,downloaded_revision=? WHERE user_id=? AND device_id=?",
                (uploaded_revision, revision, user, device_id),
            )
            self.db.execute("COMMIT")
            return version
        except Exception:
            if self.db.in_transaction:
                self.db.execute("ROLLBACK")
            raise

    def mutate_cloud(self, principal: object, mutation: dict[str, Any], *, now: datetime) -> str:
        """Test-only external server mutation to model another device/service."""
        user = self._require(principal, "snapshot:write").subject
        current = self._cloud(user)
        current.update(json.loads(_json(mutation)))
        return self.seed_cloud_snapshot(principal, current, now=now)

    def acknowledge_download(self, principal: object, device_id: str) -> int:
        user = self._require(principal, "snapshot:write").subject
        cloud = self.db.execute("SELECT revision FROM cloud_state WHERE user_id=?", (user,)).fetchone()
        if cloud is None:
            raise NotFound("cloud snapshot unavailable")
        cursor = self.db.execute(
            "UPDATE device_watermarks SET downloaded_revision=? WHERE user_id=? AND device_id=?",
            (cloud["revision"], user, device_id),
        )
        if cursor.rowcount != 1:
            raise NotFound("device unavailable")
        return cloud["revision"]

    def create_snapshot(self, principal: object, device_id: str, *, now: datetime) -> dict[str, Any]:
        import uuid
        user = self._require(principal, "planning:read").subject
        self.db.execute("BEGIN")
        try:
            cloud = self.db.execute("SELECT * FROM cloud_state WHERE user_id=?", (user,)).fetchone()
            if cloud is None:
                raise NotFound("cloud snapshot unavailable")
            device = self._device(user, device_id)
            payload = json.loads(cloud["payload"])
            version = self._cloud_version(cloud["revision"], payload)
            digest = sha256(_json(payload).encode()).hexdigest()
            dirty = device["local_revision"] > device["uploaded_revision"]
            download_lag = device["downloaded_revision"] < cloud["revision"]
            sync_state = "pending_local_changes" if dirty else "cloud_lagging" if download_lag else "current"
            provisional = dirty or download_lag
            snapshot_id = str(uuid.uuid4())
            expires = _stamp(now + self.snapshot_ttl)
            self.db.execute(
                "INSERT INTO planning_snapshots VALUES(?,?,?,?,?,?,?,?,?,?)",
                (snapshot_id,user,version,cloud["revision"],_json(payload),digest,
                 sync_state,int(provisional),_stamp(now),expires),
            )
            self.db.execute("COMMIT")
            return {
                "snapshot_id": snapshot_id, "subject_ref": user,
                "snapshot_version": version, "server_revision": cloud["revision"],
                "snapshot_digest": digest, "captured_at": _stamp(now),
                "expires_at": expires, "sync_state": sync_state,
                "provisional": provisional, "approval_eligible": not provisional,
                "data": payload,
            }
        except Exception:
            if self.db.in_transaction:
                self.db.execute("ROLLBACK")
            raise

    def create_proposal(self, principal: object, snapshot_id: str, *,
                        changes: list[dict[str, str]], now: datetime,
                        proposal_ttl: timedelta = timedelta(minutes=30)) -> dict[str, Any]:
        import uuid
        user = self._require(principal, "proposal:write").subject
        self.db.execute("BEGIN IMMEDIATE")
        try:
            snapshot = self._snapshot(user, snapshot_id)
            if now >= datetime.fromisoformat(snapshot["expires_at"]):
                raise ProposalExpired("snapshot expired")
            if snapshot["provisional"]:
                raise LocalSyncPending("snapshot has pending local or cloud synchronization")
            self._assert_current(user, snapshot["version"], device_id=None)
            validated = self._validate_changes(json.loads(snapshot["payload"]), changes)
            proposal_id = str(uuid.uuid4())
            expires = _stamp(min(now + proposal_ttl, now + timedelta(minutes=30)))
            self.db.execute(
                "INSERT INTO planning_proposals VALUES(?,?,?,?,?,?,'proposed',?,?,?)",
                (proposal_id,user,snapshot_id,snapshot["version"],
                 sha256(_json(validated).encode()).hexdigest(),_json(validated),expires,
                 _stamp(now),_stamp(now)),
            )
            self._audit(user,"proposal",proposal_id,"proposed",now,{"base_version":snapshot["version"]})
            self.db.execute("COMMIT")
            return self.get_proposal(principal, proposal_id)
        except Exception:
            if self.db.in_transaction:
                self.db.execute("ROLLBACK")
            raise

    def approve(self, principal: object, proposal_id: str, *, now: datetime) -> dict[str, Any]:
        import uuid
        user = self._require(principal, "approval:write").subject
        token = secrets.token_urlsafe(32)
        approval_id = str(uuid.uuid4())
        self.db.execute("BEGIN IMMEDIATE")
        try:
            proposal = self._proposal(user, proposal_id)
            if proposal["status"] != "proposed":
                raise InvalidTransition("proposal not approvable")
            try:
                self._assert_proposal_live(user, proposal, now)
            except ProposalExpired:
                self.db.execute("UPDATE planning_proposals SET status='expired',updated_at=? WHERE user_id=? AND proposal_id=?",
                                (_stamp(now),user,proposal_id))
                self.db.execute("COMMIT")
                raise
            snapshot = self._snapshot(user, proposal["snapshot_id"])
            try:
                self._assert_current(user, proposal["base_version"], device_id=None)
            except SnapshotConflict:
                self.db.execute("UPDATE planning_proposals SET status='superseded',updated_at=? WHERE user_id=? AND proposal_id=?",
                                (_stamp(now),user,proposal_id))
                self.db.execute("COMMIT")
                raise
            expires = _stamp(min(now + self.approval_ttl, datetime.fromisoformat(proposal["expires_at"])))
            self.db.execute(
                "INSERT INTO planning_approvals VALUES(?,?,?,?, 'active',?,?,NULL)",
                (approval_id,user,proposal_id,sha256(token.encode()).hexdigest(),expires,_stamp(now)),
            )
            self.db.execute(
                "UPDATE planning_proposals SET status='approved',updated_at=? WHERE user_id=? AND proposal_id=? AND status='proposed'",
                (_stamp(now),user,proposal_id),
            )
            self._audit(user,"proposal",proposal_id,"approved",now,{"approval_id":approval_id})
            self.db.execute("COMMIT")
            return {"approval_id":approval_id,"approval_token":token,
                    "expires_at":expires,"status":"approved"}
        except Exception:
            if self.db.in_transaction:
                self.db.execute("ROLLBACK")
            raise

    def apply_approved_changes(self, principal: object, proposal_id: str, *,
                               approval_token: str, idempotency_key: str,
                               now: datetime, fail_before_commit: bool = False,
                               readback_outcome: str = "consistent") -> dict[str, Any]:
        """Applies only the allowlisted test mutation, atomically in this SQLite DB."""
        user = self._require(principal, "proposal:apply").subject
        token_hash = sha256(approval_token.encode()).hexdigest()
        self.db.execute("BEGIN IMMEDIATE")
        try:
            idem = self.db.execute(
                "SELECT * FROM planning_idempotency WHERE user_id=? AND tool='apply' AND idem_key=?",
                (user,idempotency_key),
            ).fetchone()
            digest = sha256(_json({"proposal_id":proposal_id,"approval_hash":token_hash}).encode()).hexdigest()
            if idem:
                if idem["request_digest"] != digest:
                    raise IdempotencyConflict("idempotency key reused with different request")
                result = json.loads(idem["result_json"] or "{}")
                self.db.execute("COMMIT")
                return {"replayed":True,**result}
            proposal = self._proposal(user,proposal_id)
            if proposal["status"] == "applied":
                raise AlreadyApplied("proposal already applied")
            if proposal["status"] == "readback_pending":
                raise ReadbackPending("readback only; applying again is forbidden")
            if proposal["status"] != "approved":
                raise InvalidTransition("proposal is not approved")
            try:
                self._assert_proposal_live(user,proposal,now)
            except ProposalExpired:
                self.db.execute("UPDATE planning_proposals SET status='expired',updated_at=? WHERE user_id=? AND proposal_id=?",
                                (_stamp(now),user,proposal_id))
                self.db.execute("COMMIT")
                raise
            try:
                self._assert_current(user,proposal["base_version"],device_id=None)
            except SnapshotConflict:
                self.db.execute("UPDATE planning_proposals SET status='superseded',updated_at=? WHERE user_id=? AND proposal_id=?",
                                (_stamp(now),user,proposal_id))
                self.db.execute("COMMIT")
                raise
            approval = self.db.execute(
                "SELECT * FROM planning_approvals WHERE user_id=? AND proposal_id=? AND token_hash=?",
                (user,proposal_id,token_hash),
            ).fetchone()
            if approval is None:
                raise NotFound("approval unavailable")
            if now >= datetime.fromisoformat(approval["expires_at"]):
                self.db.execute("UPDATE planning_approvals SET status='expired' WHERE approval_id=?",(approval["approval_id"],))
                self.db.execute("UPDATE planning_proposals SET status='superseded',updated_at=? WHERE user_id=? AND proposal_id=?",
                                (_stamp(now),user,proposal_id))
                self.db.execute("COMMIT")
                raise ProposalExpired("approval token expired")
            if approval["status"] != "active":
                raise AccessDenied("approval token is not active")
            snapshot = self._snapshot(user,proposal["snapshot_id"])
            changes = json.loads(proposal["changes_json"])
            payload = self._cloud(user)
            new_payload = self._apply_changes(payload, changes)
            current = self.db.execute("SELECT * FROM cloud_state WHERE user_id=?",(user,)).fetchone()
            applied_revision = current["revision"] + 1
            applied_version = self._cloud_version(applied_revision,new_payload)
            timestamp = _stamp(now)
            self.db.execute("UPDATE planning_approvals SET status='consumed',consumed_at=? WHERE approval_id=? AND status='active'",
                            (timestamp,approval["approval_id"]))
            self.db.execute("UPDATE planning_proposals SET status='applying',updated_at=? WHERE user_id=? AND proposal_id=?",
                            (timestamp,user,proposal_id))
            self.db.execute("INSERT INTO planning_idempotency VALUES(?,?,?,?,'in_progress',NULL,?,?)",
                            (user,"apply",idempotency_key,digest,timestamp,timestamp))
            self.db.execute("UPDATE cloud_state SET revision=?,payload=?,updated_at=? WHERE user_id=?",
                            (applied_revision,_json(new_payload),timestamp,user))
            for change in changes:
                self.db.execute("INSERT INTO applied_changes VALUES(?,?,?,?,?,?)",
                                (user,proposal_id,change["task_id"],change["planned_date"],proposal["base_version"],applied_version))
            self.db.execute("UPDATE planning_proposals SET status='readback_pending',updated_at=? WHERE user_id=? AND proposal_id=?",
                            (timestamp,user,proposal_id))
            pending_result = {"proposal_id":proposal_id,"status":"readback_pending",
                              "operation":"readback_only","business_write_performed":True,
                              "applied_version":applied_version,"readback_verified":None}
            self.db.execute("UPDATE planning_idempotency SET status='readback_pending',result_json=?,updated_at=? WHERE user_id=? AND tool='apply' AND idem_key=?",
                            (_json(pending_result),timestamp,user,idempotency_key))
            self._audit(user,"proposal",proposal_id,"business_write_committed",now,
                        {"base_version":proposal["base_version"],"applied_version":applied_version})
            if fail_before_commit:
                raise RuntimeError("injected transaction failure")
            self.db.execute("COMMIT")
        except Exception:
            if self.db.in_transaction:
                self.db.execute("ROLLBACK")
            raise
        return self.reconcile_readback(
            principal,proposal_id,idempotency_key=idempotency_key,
            outcome=readback_outcome,now=now,
        )

    def reconcile_readback(self, principal: object, proposal_id: str, *,
                           idempotency_key: str, outcome: str, now: datetime) -> dict[str, Any]:
        if outcome not in {"consistent","mismatch","unknown"}:
            raise ValueError("invalid readback outcome")
        user = self._require(principal,"proposal:apply").subject
        self.db.execute("BEGIN IMMEDIATE")
        try:
            proposal = self._proposal(user,proposal_id)
            idem = self.db.execute(
                "SELECT * FROM planning_idempotency WHERE user_id=? AND tool='apply' AND idem_key=?",
                (user,idempotency_key),
            ).fetchone()
            if proposal["status"] != "readback_pending" or idem is None or idem["status"] != "readback_pending":
                raise InvalidTransition("matching readback-pending apply required")
            if json.loads(idem["result_json"] or "{}").get("proposal_id") != proposal_id:
                raise InvalidTransition("idempotency record belongs to another proposal")
            if outcome == "consistent":
                snapshot = self._snapshot(user,proposal["snapshot_id"])
                changes = json.loads(proposal["changes_json"])
                observed = self._cloud(user)
                expected = self._apply_changes(json.loads(snapshot["payload"]),changes)
                consistent = all(
                    self._read_planned_date(observed, change["task_id"]) ==
                    self._read_planned_date(expected, change["task_id"])
                    for change in changes
                )
                outcome = "consistent" if consistent else "mismatch"
            status = {"consistent":"applied","mismatch":"failed","unknown":"readback_pending"}[outcome]
            verified = True if outcome == "consistent" else False if outcome == "mismatch" else None
            result = {
                **json.loads(idem["result_json"] or "{}"), "status":status,
                "operation":"readback_only", "business_write_performed":False,
                "readback_verified":verified,
                "error_code":"READBACK_MISMATCH" if outcome == "mismatch" else
                    "READBACK_PENDING" if outcome == "unknown" else None,
            }
            timestamp = _stamp(now)
            self.db.execute("UPDATE planning_proposals SET status=?,updated_at=? WHERE user_id=? AND proposal_id=?",
                            (status,timestamp,user,proposal_id))
            self.db.execute("UPDATE planning_idempotency SET status=?,result_json=?,updated_at=? WHERE user_id=? AND tool='apply' AND idem_key=?",
                            (status,_json(result),timestamp,user,idempotency_key))
            self._audit(user,"proposal",proposal_id,f"readback_{outcome}",now,{"readback_verified":verified})
            self.db.execute("COMMIT")
            return result
        except Exception:
            if self.db.in_transaction:
                self.db.execute("ROLLBACK")
            raise

    def get_proposal(self, principal: object, proposal_id: str) -> dict[str, Any]:
        user = self._require(principal,"proposal:read").subject
        row = self._proposal(user,proposal_id)
        return {**dict(row),"changes":json.loads(row["changes_json"])}

    def business_write_count(self, principal: object) -> int:
        user = self._require(principal,"snapshot:read").subject
        return self.db.execute("SELECT COUNT(*) FROM applied_changes WHERE user_id=?",(user,)).fetchone()[0]

    def cloud_payload(self, principal: object) -> dict[str, Any]:
        user = self._require(principal,"snapshot:read").subject
        return self._cloud(user)

    def _cloud(self, user: str) -> dict[str, Any]:
        row = self.db.execute("SELECT payload FROM cloud_state WHERE user_id=?",(user,)).fetchone()
        if row is None:
            raise NotFound("cloud snapshot unavailable")
        return json.loads(row["payload"])

    def _device(self, user: str, device_id: str) -> sqlite3.Row:
        row = self.db.execute("SELECT * FROM device_watermarks WHERE user_id=? AND device_id=?",
                              (user,device_id)).fetchone()
        if row is None:
            raise NotFound("device unavailable")
        return row

    def _assert_current(self, user: str, base_version: str, device_id: str | None) -> None:
        cloud_row = self.db.execute("SELECT * FROM cloud_state WHERE user_id=?",(user,)).fetchone()
        if cloud_row is None:
            raise NotFound("cloud snapshot unavailable")
        payload=json.loads(cloud_row["payload"])
        if self._cloud_version(cloud_row["revision"],payload) != base_version:
            self.db.execute("UPDATE planning_proposals SET status='superseded' WHERE user_id=? AND base_version=? AND status IN ('proposed','approved')",
                            (user,base_version))
            raise SnapshotConflict("server snapshot version changed")
        devices = self.db.execute("SELECT * FROM device_watermarks WHERE user_id=?",(user,)).fetchall()
        if any(row["local_revision"] > row["uploaded_revision"] for row in devices):
            raise LocalSyncPending("a device has unuploaded local changes")
        if any(row["downloaded_revision"] < cloud_row["revision"] for row in devices):
            raise LocalSyncPending("a device has not acknowledged the current cloud revision")

    @staticmethod
    def _cloud_version(revision: int, payload: dict[str, Any]) -> str:
        digest=sha256(_json(payload).encode()).hexdigest()
        return f"server-v{revision}:{digest}"

    @staticmethod
    def _validate_changes(payload: dict[str, Any], changes: list[dict[str, str]]) -> list[dict[str, str]]:
        if not isinstance(changes,list) or not changes:
            raise ValueError("at least one change is required")
        tasks={task["task_id"]:task for task in payload.get("tasks",[])}
        normalized=[]
        seen=set()
        for change in changes:
            if set(change)!={"task_id","planned_date"}:
                raise ValueError("only task planned_date changes are allowed")
            task_id=change["task_id"]
            day=change["planned_date"]
            if task_id not in tasks:
                raise NotFound("task not found")
            if task_id in seen:
                raise ValueError("duplicate task change")
            datetime.strptime(day,"%Y-%m-%d")
            seen.add(task_id)
            normalized.append({"task_id":task_id,"planned_date":day})
        return sorted(normalized,key=lambda item:item["task_id"])

    @staticmethod
    def _apply_changes(payload: dict[str, Any], changes: list[dict[str, str]]) -> dict[str, Any]:
        updated=json.loads(_json(payload))
        tasks={task["task_id"]:task for task in updated.get("tasks",[])}
        for change in changes:
            if change["task_id"] not in tasks:
                raise NotFound("task not found")
            tasks[change["task_id"]]["planned_date"]=change["planned_date"]
        return updated

    @staticmethod
    def _read_planned_date(payload: dict[str, Any], task_id: str) -> str | None:
        return next((task.get("planned_date") for task in payload.get("tasks",[])
                     if task.get("task_id")==task_id),None)

    def _snapshot(self, user: str, snapshot_id: str) -> sqlite3.Row:
        row=self.db.execute("SELECT * FROM planning_snapshots WHERE user_id=? AND snapshot_id=?",
                            (user,snapshot_id)).fetchone()
        if row is None:
            raise NotFound("snapshot unavailable")
        return row

    def _proposal(self, user: str, proposal_id: str) -> sqlite3.Row:
        row=self.db.execute("SELECT * FROM planning_proposals WHERE user_id=? AND proposal_id=?",
                            (user,proposal_id)).fetchone()
        if row is None:
            raise NotFound("proposal unavailable")
        return row

    def _assert_proposal_live(self, user: str, proposal: sqlite3.Row, now: datetime) -> None:
        if now >= datetime.fromisoformat(proposal["expires_at"]):
            raise ProposalExpired("proposal expired")
        snapshot=self._snapshot(user,proposal["snapshot_id"])
        if now >= datetime.fromisoformat(snapshot["expires_at"]):
            raise ProposalExpired("snapshot expired")

    def _audit(self,user: str,resource_type: str,resource_id: str,action: str,
               now: datetime,details: dict[str,Any]) -> None:
        self.db.execute("INSERT INTO planning_audit(user_id,resource_type,resource_id,action,occurred_at,details_json) VALUES(?,?,?,?,?,?)",
                        (user,resource_type,resource_id,action,_stamp(now),_json(details)))

    def close(self) -> None:
        self.db.close()
