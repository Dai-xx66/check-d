"""Local SQLite prototype for leased events, private state, risks and approvals.

This store is for isolated tests and single-process prototyping only. Its
LocalTestPrincipal is not OAuth, and this SQLite file is not a cloud worker DB.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from hashlib import sha256
import json
from pathlib import Path
import secrets
import sqlite3
from zoneinfo import ZoneInfo


class WorkflowError(Exception):
    code = "WORKFLOW_ERROR"


class AccessDenied(WorkflowError):
    code = "AUTH_REQUIRED"


class NotFound(WorkflowError):
    code = "NOT_FOUND"


class SnapshotConflict(WorkflowError):
    code = "SNAPSHOT_CONFLICT"


class ProposalExpired(WorkflowError):
    code = "PROPOSAL_EXPIRED"


class ApprovalConsumed(WorkflowError):
    code = "APPROVAL_CONSUMED"


class IdempotencyConflict(WorkflowError):
    code = "IDEMPOTENCY_CONFLICT"


class InvalidTransition(WorkflowError):
    code = "INVALID_STATE"


class AlreadyApplied(WorkflowError):
    code = "ALREADY_APPLIED"


class ReadbackPending(WorkflowError):
    code = "READBACK_PENDING"


@dataclass(frozen=True)
class LocalTestPrincipal:
    """Explicit test seam. Never accept this as an HTTP credential."""
    subject: str
    scopes: frozenset[str]
    issuer: str = "local-test-only"
    session_id: str = "test-session"


@dataclass(frozen=True)
class LocalTestHumanConfirmation:
    """Test-only stand-in for a separately verified human confirmation."""
    subject: str
    proposal_id: str
    changes_digest: str
    confirmation_id: str
    issuer: str = "local-test-only"


def _principal(value: object, scope: str) -> LocalTestPrincipal:
    if (not isinstance(value, LocalTestPrincipal) or value.issuer != "local-test-only"
            or not value.subject or scope not in value.scopes):
        raise AccessDenied("verified principal and scope required")
    return value


def _stamp(value: datetime | None = None) -> str:
    value = value or datetime.now(timezone.utc)
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("timestamp must include timezone")
    return value.astimezone(timezone.utc).isoformat()


def _json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _digest(value: object) -> str:
    return sha256(_json(value).encode("utf-8")).hexdigest()


class PlanningWorkflowStore:
    def __init__(self, path: str | Path):
        self.db = sqlite3.connect(str(path), timeout=15, isolation_level=None)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA foreign_keys=ON")
        self.db.executescript("""
        CREATE TABLE IF NOT EXISTS agent_events(
          event_id TEXT PRIMARY KEY,user_id TEXT NOT NULL,event_type TEXT NOT NULL,
          dedupe_key TEXT NOT NULL,payload TEXT NOT NULL,status TEXT NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0,available_at TEXT NOT NULL,
          lease_owner TEXT,lease_expires_at TEXT,final_result TEXT,error_code TEXT,
          created_at TEXT NOT NULL,updated_at TEXT NOT NULL,
          UNIQUE(user_id,dedupe_key));
        CREATE INDEX IF NOT EXISTS agent_events_ready ON agent_events(status,available_at);
        CREATE TABLE IF NOT EXISTS private_workspace(
          user_id TEXT NOT NULL,kind TEXT NOT NULL,item_key TEXT NOT NULL,payload TEXT NOT NULL,
          updated_at TEXT NOT NULL,PRIMARY KEY(user_id,kind,item_key));
        CREATE TABLE IF NOT EXISTS plan_proposals(
          proposal_id TEXT PRIMARY KEY,user_id TEXT NOT NULL,base_version TEXT NOT NULL,
          rules_version TEXT NOT NULL,changes_digest TEXT NOT NULL,changes_json TEXT NOT NULL,
          status TEXT NOT NULL,expires_at TEXT NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS proposals_owner ON plan_proposals(user_id,status);
        CREATE TABLE IF NOT EXISTS approvals(
          approval_id TEXT PRIMARY KEY,proposal_id TEXT NOT NULL,user_id TEXT NOT NULL,
          token_hash TEXT NOT NULL,status TEXT NOT NULL,expires_at TEXT NOT NULL,
          created_at TEXT NOT NULL,consumed_at TEXT,
          FOREIGN KEY(proposal_id) REFERENCES plan_proposals(proposal_id));
        CREATE UNIQUE INDEX IF NOT EXISTS one_active_approval_per_proposal
          ON approvals(user_id,proposal_id) WHERE status='active';
        CREATE TABLE IF NOT EXISTS workflow_idempotency(
          user_id TEXT NOT NULL,tool TEXT NOT NULL,idem_key TEXT NOT NULL,
          request_digest TEXT NOT NULL,status TEXT NOT NULL,result_json TEXT,
          created_at TEXT NOT NULL,updated_at TEXT NOT NULL,
          PRIMARY KEY(user_id,tool,idem_key));
        CREATE TABLE IF NOT EXISTS risk_states(
          user_id TEXT NOT NULL,risk_key TEXT NOT NULL,version TEXT NOT NULL,
          fingerprint TEXT NOT NULL,severity TEXT NOT NULL,status TEXT NOT NULL,
          payload TEXT NOT NULL,evaluated_at TEXT NOT NULL,last_notified_at TEXT,
          PRIMARY KEY(user_id,risk_key));
        CREATE TABLE IF NOT EXISTS notification_outbox(
          notification_id TEXT PRIMARY KEY,user_id TEXT NOT NULL,dedupe_key TEXT NOT NULL,
          payload TEXT NOT NULL,status TEXT NOT NULL,created_at TEXT NOT NULL,
          UNIQUE(user_id,dedupe_key));
        CREATE TABLE IF NOT EXISTS workflow_audit(
          audit_id TEXT PRIMARY KEY,user_id TEXT NOT NULL,resource_type TEXT NOT NULL,
          resource_id TEXT NOT NULL,action TEXT NOT NULL,details TEXT NOT NULL,created_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS revoked_test_sessions(
          user_id TEXT NOT NULL,session_id TEXT NOT NULL,revoked_at TEXT NOT NULL,
          PRIMARY KEY(user_id,session_id));
        """)

    def _principal(self, value: object, scope: str) -> LocalTestPrincipal:
        principal = _principal(value, scope)
        revoked = self.db.execute(
            "SELECT 1 FROM revoked_test_sessions WHERE user_id=? AND session_id=?",
            (principal.subject, principal.session_id),
        ).fetchone()
        if revoked:
            raise AccessDenied("authorization revoked")
        return principal

    def revoke_access(self, principal: object, *, now: datetime) -> None:
        if not isinstance(principal, LocalTestPrincipal) or principal.issuer != "local-test-only":
            raise AccessDenied("test principal required")
        self.db.execute("INSERT OR IGNORE INTO revoked_test_sessions VALUES(?,?,?)",
                        (principal.subject,principal.session_id,_stamp(now)))

    def _audit(self, user: str, kind: str, resource: str, action: str,
               details: dict, now: str) -> None:
        import uuid
        self.db.execute("INSERT INTO workflow_audit VALUES(?,?,?,?,?,?,?)",
                        (str(uuid.uuid4()), user, kind, resource, action, _json(details), now))

    # Durable events -----------------------------------------------------
    def enqueue_event(self, principal: object, *, event_type: str, dedupe_key: str,
                      payload: dict, now: datetime | None = None) -> str:
        import uuid
        user = self._principal(principal, "events:write").subject
        timestamp = _stamp(now)
        event_id = str(uuid.uuid4())
        self.db.execute("INSERT OR IGNORE INTO agent_events(event_id,user_id,event_type,dedupe_key,payload,status,available_at,created_at,updated_at) VALUES(?,?,?,?,?,'pending',?,?,?)",
                        (event_id,user,event_type,dedupe_key,_json(payload),timestamp,timestamp,timestamp))
        row = self.db.execute("SELECT event_id FROM agent_events WHERE user_id=? AND dedupe_key=?",
                              (user,dedupe_key)).fetchone()
        return row["event_id"]

    def claim_event(self, worker: str, *, now: datetime | None = None,
                    lease: timedelta = timedelta(minutes=2),
                    max_attempts: int = 5) -> dict | None:
        if not worker.strip() or lease.total_seconds() <= 0 or max_attempts < 1:
            raise ValueError("worker, positive lease, and max_attempts are required")
        timestamp = _stamp(now)
        expires = _stamp((now or datetime.now(timezone.utc)) + lease)
        self.db.execute("BEGIN IMMEDIATE")
        try:
            self.db.execute("UPDATE agent_events SET status='dead_letter',error_code='LEASE_EXPIRED_MAX_ATTEMPTS',lease_owner=NULL,lease_expires_at=NULL,updated_at=? WHERE status='processing' AND lease_expires_at<=? AND attempts>=?",
                            (timestamp,timestamp,max_attempts))
            self.db.execute("UPDATE agent_events SET status='retry',lease_owner=NULL,lease_expires_at=NULL,available_at=?,updated_at=? WHERE status='processing' AND lease_expires_at<=? AND attempts<?",
                            (timestamp,timestamp,timestamp,max_attempts))
            row = self.db.execute("SELECT * FROM agent_events WHERE status IN ('pending','retry') AND available_at<=? ORDER BY available_at,event_id LIMIT 1",
                                  (timestamp,)).fetchone()
            if row is None:
                self.db.execute("COMMIT")
                return None
            self.db.execute("UPDATE agent_events SET status='processing',attempts=attempts+1,lease_owner=?,lease_expires_at=?,updated_at=? WHERE event_id=?",
                            (worker,expires,timestamp,row["event_id"]))
            self.db.execute("COMMIT")
            return {"event_id": row["event_id"], "user_id": row["user_id"],
                    "event_type": row["event_type"], "payload": json.loads(row["payload"]),
                    "attempts": row["attempts"] + 1, "lease_owner": worker,
                    "lease_expires_at": expires}
        except Exception:
            self.db.execute("ROLLBACK")
            raise

    def complete_event(self, principal: object, event_id: str, *, worker: str,
                       result: dict, now: datetime | None = None) -> None:
        user = self._principal(principal, "events:write").subject
        timestamp = _stamp(now)
        cur = self.db.execute("UPDATE agent_events SET status='done',final_result=?,lease_owner=NULL,lease_expires_at=NULL,error_code=NULL,updated_at=? WHERE event_id=? AND user_id=? AND status='processing' AND lease_owner=? AND lease_expires_at>?",
                              (_json(result),timestamp,event_id,user,worker,timestamp))
        if cur.rowcount != 1:
            raise NotFound("event unavailable")

    def fail_event(self, principal: object, event_id: str, *, worker: str,
                   error_code: str, now: datetime | None = None,
                   max_attempts: int = 5) -> None:
        if max_attempts < 1:
            raise ValueError("max_attempts must be positive")
        user = self._principal(principal, "events:write").subject
        timestamp = _stamp(now)
        row = self.db.execute("SELECT attempts FROM agent_events WHERE event_id=? AND user_id=? AND status='processing' AND lease_owner=? AND lease_expires_at>?",
                              (event_id,user,worker,timestamp)).fetchone()
        if row is None:
            raise NotFound("event unavailable")
        attempts = row["attempts"]
        status = "dead_letter" if attempts >= max_attempts else "retry"
        delay = min(3600, 2 ** attempts)
        available = _stamp((now or datetime.now(timezone.utc)) + timedelta(seconds=delay))
        self.db.execute("UPDATE agent_events SET status=?,error_code=?,available_at=?,lease_owner=NULL,lease_expires_at=NULL,updated_at=? WHERE event_id=? AND user_id=?",
                        (status,error_code,available,timestamp,event_id,user))

    # Principal-scoped private workspace --------------------------------
    def put_private(self, principal: object, *, kind: str, key: str,
                    value: dict, now: datetime | None = None) -> None:
        user = self._principal(principal, "workspace:write").subject
        if kind not in {
            "task", "course", "plan", "plan_version", "time_block", "timer",
            "risk", "preference", "memory", "approval", "notification",
            "idempotency",
        }:
            raise ValueError("unsupported private data kind")
        timestamp = _stamp(now)
        self.db.execute("INSERT INTO private_workspace VALUES(?,?,?,?,?) ON CONFLICT(user_id,kind,item_key) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at",
                        (user,kind,key,_json(value),timestamp))

    def get_private(self, principal: object, *, kind: str, key: str) -> dict | None:
        user = self._principal(principal, "workspace:read").subject
        row = self.db.execute("SELECT payload FROM private_workspace WHERE user_id=? AND kind=? AND item_key=?",
                              (user,kind,key)).fetchone()
        return json.loads(row["payload"]) if row else None

    # Risk lifecycle and durable notification to-do ----------------------
    def update_risks(self, principal: object, *, version: str, risks: list[dict],
                     now: datetime, cooldown: timedelta = timedelta(hours=12),
                     daily_limit: int = 3,
                     timezone_name: str = "Asia/Shanghai") -> dict:
        user = self._principal(principal, "risk:write").subject
        timestamp = _stamp(now)
        active = {risk["risk_key"]: risk for risk in risks}
        created_notifications = 0
        self.db.execute("BEGIN IMMEDIATE")
        try:
            old = self.db.execute("SELECT risk_key FROM risk_states WHERE user_id=? AND status='active'",
                                  (user,)).fetchall()
            for row in old:
                if row["risk_key"] not in active:
                    self.db.execute("UPDATE risk_states SET status='resolved',version=?,evaluated_at=? WHERE user_id=? AND risk_key=?",
                                    (version,timestamp,user,row["risk_key"]))
            local_day = now.astimezone(ZoneInfo(timezone_name)).date()
            day_start = datetime.combine(local_day, datetime.min.time(), ZoneInfo(timezone_name))
            day_end = day_start + timedelta(days=1)
            sent_today = self.db.execute(
                "SELECT COUNT(*) FROM notification_outbox WHERE user_id=? AND created_at>=? AND created_at<?",
                (user, _stamp(day_start), _stamp(day_end)),
            ).fetchone()[0]
            for key, risk in active.items():
                fingerprint = _digest({"severity": risk.get("severity"), "risk_type": risk.get("risk_type"),
                                       "evidence": risk.get("evidence")})
                prior = self.db.execute("SELECT * FROM risk_states WHERE user_id=? AND risk_key=?",
                                        (user,key)).fetchone()
                last_notified = prior["last_notified_at"] if prior and prior["fingerprint"] == fingerprint else None
                changed = prior is None or prior["status"] != "active" or prior["fingerprint"] != fingerprint
                if prior and prior["status"] == "active" and prior["fingerprint"] == fingerprint:
                    changed = (last_notified is None or
                               now.astimezone(timezone.utc)-datetime.fromisoformat(last_notified) >= cooldown)
                self.db.execute("INSERT INTO risk_states VALUES(?,?,?,?,?,'active',?,?,?) ON CONFLICT(user_id,risk_key) DO UPDATE SET version=excluded.version,fingerprint=excluded.fingerprint,severity=excluded.severity,status='active',payload=excluded.payload,evaluated_at=excluded.evaluated_at",
                                (user,key,version,fingerprint,risk.get("severity","medium"),_json(risk),timestamp,last_notified))
                if changed and sent_today + created_notifications < daily_limit:
                    bucket = int(now.astimezone(timezone.utc).timestamp() // max(1,int(cooldown.total_seconds())))
                    dedupe = f"{key}:{fingerprint}:{bucket}"
                    import uuid
                    cur = self.db.execute("INSERT OR IGNORE INTO notification_outbox VALUES(?,?,?,?,'pending',?)",
                                          (str(uuid.uuid4()),user,dedupe,_json({"risk_key":key,"version":version,"risk":risk}),timestamp))
                    if cur.rowcount:
                        created_notifications += 1
                        self.db.execute("UPDATE risk_states SET last_notified_at=? WHERE user_id=? AND risk_key=?",
                                        (timestamp,user,key))
            self.db.execute("COMMIT")
        except Exception:
            self.db.execute("ROLLBACK")
            raise
        return {"active_count": len(active), "notifications_queued": created_notifications,
                "resolved_count": sum(1 for row in old if row["risk_key"] not in active)}

    def list_pending_notifications(self, principal: object, *, limit: int = 100) -> list[dict]:
        user = self._principal(principal, "risk:read").subject
        rows = self.db.execute("SELECT payload,created_at FROM notification_outbox WHERE user_id=? AND status='pending' ORDER BY created_at LIMIT ?",
                               (user,max(1,min(limit,100)))).fetchall()
        return [{"payload":json.loads(row["payload"]),"created_at":row["created_at"]} for row in rows]

    # Proposal and one-time approval state machine -----------------------
    def create_draft(self, principal: object, *, proposal_id: str, base_version: str,
                     rules_version: str, changes: list[dict], expires_at: datetime,
                     idempotency_key: str, now: datetime) -> dict:
        user = self._principal(principal, "proposal:write").subject
        timestamp = _stamp(now); expiration = _stamp(expires_at)
        if expires_at <= now: raise ProposalExpired("proposal expiry must be in future")
        digest = _digest(changes)
        request_digest = _digest({"base_version":base_version,"rules_version":rules_version,"changes":changes})
        self.db.execute("BEGIN IMMEDIATE")
        try:
            idem = self.db.execute("SELECT * FROM workflow_idempotency WHERE user_id=? AND tool='create_proposal' AND idem_key=?",
                                   (user,idempotency_key)).fetchone()
            if idem:
                if idem["request_digest"] != request_digest: raise IdempotencyConflict("key reused with different proposal")
                row = self.db.execute("SELECT * FROM plan_proposals WHERE user_id=? AND proposal_id=?",
                                      (user,json.loads(idem["result_json"])["proposal_id"])).fetchone()
                self.db.execute("COMMIT")
                return dict(row)
            self.db.execute("INSERT INTO plan_proposals VALUES(?,?,?,?,?,?,'draft',?,?,?)",
                            (proposal_id,user,base_version,rules_version,digest,_json(changes),expiration,timestamp,timestamp))
            self.db.execute("INSERT INTO workflow_idempotency VALUES(?,?,?,?,'created',?,?,?)",
                            (user,"create_proposal",idempotency_key,request_digest,_json({"proposal_id":proposal_id}),timestamp,timestamp))
            self._audit(user,"proposal",proposal_id,"draft_created",{"base_version":base_version,"rules_version":rules_version},timestamp)
            self.db.execute("COMMIT")
            return self.get_proposal(principal,proposal_id)
        except Exception:
            self.db.execute("ROLLBACK")
            raise

    def propose(self, principal: object, proposal_id: str, *, current_version: str,
                now: datetime) -> dict:
        user = self._principal(principal, "proposal:write").subject
        timestamp = _stamp(now)
        row = self._owned_proposal(user,proposal_id)
        if row["status"] != "draft": raise InvalidTransition("proposal is not draft")
        if now >= datetime.fromisoformat(row["expires_at"]):
            self._set_proposal(user,proposal_id,"superseded",timestamp,"expired")
            raise ProposalExpired("proposal expired")
        if current_version != row["base_version"]:
            self._set_proposal(user,proposal_id,"superseded",timestamp,"version_changed")
            raise SnapshotConflict("proposal basis changed")
        self._set_proposal(user,proposal_id,"proposed",timestamp,"proposed")
        return self.get_proposal(principal,proposal_id)

    def approve(self, principal: object, proposal_id: str, *, confirmation: object,
                current_version: str,
                now: datetime, token_ttl: timedelta = timedelta(minutes=5)) -> dict:
        user = self._principal(principal, "approval:write").subject
        import uuid
        token = secrets.token_urlsafe(32)
        approval_id = str(uuid.uuid4())
        timestamp = _stamp(now)
        self.db.execute("BEGIN IMMEDIATE")
        try:
            row = self._owned_proposal(user,proposal_id)
            if (not isinstance(confirmation, LocalTestHumanConfirmation)
                    or confirmation.issuer != "local-test-only"
                    or confirmation.subject != user
                    or confirmation.proposal_id != proposal_id
                    or confirmation.changes_digest != row["changes_digest"]
                    or not confirmation.confirmation_id.strip()):
                raise AccessDenied("matching explicit test confirmation required")
            if row["status"] != "proposed": raise InvalidTransition("proposal is not approvable")
            if now >= datetime.fromisoformat(row["expires_at"]):
                self._set_proposal(user,proposal_id,"superseded",timestamp,"expired")
                self.db.execute("COMMIT")
                raise ProposalExpired("proposal expired")
            if current_version != row["base_version"]:
                self._set_proposal(user,proposal_id,"superseded",timestamp,"version_changed")
                self.db.execute("COMMIT")
                raise SnapshotConflict("proposal basis changed")
            expires = min(now+token_ttl,datetime.fromisoformat(row["expires_at"]))
            self.db.execute("INSERT INTO approvals VALUES(?,?,?,?, 'active',?,?,NULL)",
                            (approval_id,proposal_id,user,sha256(token.encode()).hexdigest(),_stamp(expires),timestamp))
            self._set_proposal(user,proposal_id,"approved",timestamp,"approved")
            self._audit(user,"approval",approval_id,"approved",{"proposal_id":proposal_id,"expires_at":_stamp(expires),"confirmation_id":confirmation.confirmation_id},timestamp)
            self.db.execute("COMMIT")
            return {"approval_id":approval_id,"approval_token":token,"expires_at":_stamp(expires),"status":"approved"}
        except Exception:
            if self.db.in_transaction:
                self.db.execute("ROLLBACK")
            raise

    def reject(self, principal: object, proposal_id: str, *, now: datetime) -> dict:
        user = self._principal(principal,"approval:write").subject
        row = self._owned_proposal(user,proposal_id)
        if row["status"] not in {"draft","proposed"}: raise InvalidTransition("proposal cannot be rejected")
        self._set_proposal(user,proposal_id,"rejected",_stamp(now),"rejected")
        return self.get_proposal(principal,proposal_id)

    def begin_apply(self, principal: object, proposal_id: str, *, approval_token: str,
                    idempotency_key: str, current_version: str,
                    now: datetime) -> dict:
        user = self._principal(principal,"proposal:apply").subject
        digest = _digest({"proposal_id":proposal_id,"approval_token_hash":sha256(approval_token.encode()).hexdigest()})
        timestamp = _stamp(now)
        self.db.execute("BEGIN IMMEDIATE")
        try:
            idem = self.db.execute("SELECT * FROM workflow_idempotency WHERE user_id=? AND tool='apply_proposal' AND idem_key=?",
                                   (user,idempotency_key)).fetchone()
            if idem:
                if idem["request_digest"] != digest: raise IdempotencyConflict("key reused with different apply")
                result = json.loads(idem["result_json"] or "{}")
                self.db.execute("COMMIT")
                return {"replayed":True,**result}
            proposal = self._owned_proposal(user,proposal_id)
            if proposal["status"] == "applied": raise AlreadyApplied("already applied")
            if proposal["status"] == "applying":
                consumed = self.db.execute("SELECT 1 FROM approvals WHERE user_id=? AND proposal_id=? AND token_hash=? AND status='consumed'",
                                           (user,proposal_id,sha256(approval_token.encode()).hexdigest())).fetchone()
                if consumed: raise ApprovalConsumed("approval already consumed")
                raise InvalidTransition("proposal is already applying")
            if proposal["status"] == "readback_pending":
                raise ReadbackPending("apply outcome is uncertain; readback only")
            if proposal["status"] in {"failed","rejected","superseded"}:
                raise InvalidTransition("proposal is terminal or in progress")
            if now >= datetime.fromisoformat(proposal["expires_at"]):
                self._set_proposal(user,proposal_id,"superseded",timestamp,"expired")
                self.db.execute("COMMIT")
                raise ProposalExpired("proposal expired")
            if current_version != proposal["base_version"]:
                self._set_proposal(user,proposal_id,"superseded",timestamp,"version_changed")
                self.db.execute("COMMIT")
                raise SnapshotConflict("proposal basis changed")
            token_hash = sha256(approval_token.encode()).hexdigest()
            approval = self.db.execute("SELECT * FROM approvals WHERE user_id=? AND proposal_id=? AND token_hash=?",
                                       (user,proposal_id,token_hash)).fetchone()
            if approval is None: raise NotFound("approval unavailable")
            if now >= datetime.fromisoformat(approval["expires_at"]):
                self.db.execute("UPDATE approvals SET status='expired' WHERE approval_id=?",(approval["approval_id"],))
                self._set_proposal(user,proposal_id,"superseded",timestamp,"approval_expired")
                self.db.execute("COMMIT")
                raise ProposalExpired("approval token expired")
            if approval["status"] != "active": raise ApprovalConsumed("approval already consumed")
            self.db.execute("UPDATE approvals SET status='consumed',consumed_at=? WHERE approval_id=? AND status='active'",
                            (timestamp,approval["approval_id"]))
            self._set_proposal(user,proposal_id,"applying",timestamp,"apply_started")
            result = {"proposal_id":proposal_id,"status":"applying","business_write_performed":False}
            self.db.execute("INSERT INTO workflow_idempotency VALUES(?,?,?,?,'in_progress',?,?,?)",
                            (user,"apply_proposal",idempotency_key,digest,_json(result),timestamp,timestamp))
            self._audit(user,"proposal",proposal_id,"apply_started",{"approval_id":approval["approval_id"],"idempotency_key_hash":_digest(idempotency_key)},timestamp)
            self.db.execute("COMMIT")
            return {"replayed":False,**result}
        except Exception:
            if self.db.in_transaction:
                self.db.execute("ROLLBACK")
            raise

    def finish_apply(self, principal: object, proposal_id: str, *, idempotency_key: str,
                     readback_verified: bool | None, result: dict, now: datetime) -> dict:
        user = self._principal(principal,"proposal:apply").subject
        timestamp = _stamp(now)
        self.db.execute("BEGIN IMMEDIATE")
        try:
            proposal = self._owned_proposal(user,proposal_id)
            if proposal["status"] != "applying": raise InvalidTransition("proposal is not applying")
            idem = self.db.execute(
                "SELECT * FROM workflow_idempotency WHERE user_id=? AND tool='apply_proposal' AND idem_key=?",
                (user, idempotency_key),
            ).fetchone()
            if idem is None or idem["status"] != "in_progress":
                raise InvalidTransition("matching in-progress apply record required")
            if json.loads(idem["result_json"] or "{}").get("proposal_id") != proposal_id:
                raise InvalidTransition("idempotency record belongs to another proposal")
            status = ("applied" if readback_verified is True else
                      "failed" if readback_verified is False else "readback_pending")
            action = ("readback_verified" if readback_verified is True else
                      "readback_mismatch" if readback_verified is False else "readback_uncertain")
            self._set_proposal(user,proposal_id,status,timestamp,action)
            final = {"proposal_id":proposal_id,"status":status,
                     "readback_verified":readback_verified,"business_write_performed":False,
                     "operation":"readback_only",
                     "result":result if readback_verified is True else
                         {"error":"READBACK_MISMATCH"} if readback_verified is False else
                         {"error":"READBACK_PENDING"}}
            self.db.execute("UPDATE workflow_idempotency SET status=?,result_json=?,updated_at=? WHERE user_id=? AND tool='apply_proposal' AND idem_key=?",
                            (status,_json(final),timestamp,user,idempotency_key))
            self._audit(user,"proposal",proposal_id,status,{"readback_verified":readback_verified},timestamp)
            self.db.execute("COMMIT")
            return final
        except Exception:
            self.db.execute("ROLLBACK")
            raise

    def reconcile_readback(self, principal: object, proposal_id: str, *,
                           idempotency_key: str, outcome: str, result: dict,
                           now: datetime) -> dict:
        """Converge uncertain local apply state by readback only; never writes business data."""
        if outcome not in {"consistent", "mismatch", "unknown"}:
            raise ValueError("outcome must be consistent, mismatch, or unknown")
        user = self._principal(principal,"proposal:apply").subject
        timestamp = _stamp(now)
        self.db.execute("BEGIN IMMEDIATE")
        try:
            proposal = self._owned_proposal(user,proposal_id)
            idem = self.db.execute(
                "SELECT * FROM workflow_idempotency WHERE user_id=? AND tool='apply_proposal' AND idem_key=?",
                (user,idempotency_key),
            ).fetchone()
            if proposal["status"] != "readback_pending" or idem is None or idem["status"] != "readback_pending":
                raise InvalidTransition("matching readback-pending apply required")
            if json.loads(idem["result_json"] or "{}").get("proposal_id") != proposal_id:
                raise InvalidTransition("idempotency record belongs to another proposal")
            status = {"consistent":"applied","mismatch":"failed","unknown":"readback_pending"}[outcome]
            final = {
                "proposal_id": proposal_id, "status": status,
                "readback_verified": outcome == "consistent" if outcome != "unknown" else None,
                "business_write_performed": False, "operation": "readback_only",
                "result": result if outcome == "consistent" else
                    {"error":"READBACK_MISMATCH"} if outcome == "mismatch" else
                    {"error":"READBACK_PENDING"},
            }
            self._set_proposal(user,proposal_id,status,timestamp,f"readback_{outcome}")
            self.db.execute("UPDATE workflow_idempotency SET status=?,result_json=?,updated_at=? WHERE user_id=? AND tool='apply_proposal' AND idem_key=?",
                            (status,_json(final),timestamp,user,idempotency_key))
            self.db.execute("COMMIT")
            return final
        except Exception:
            self.db.execute("ROLLBACK")
            raise

    def get_proposal(self, principal: object, proposal_id: str) -> dict:
        user = self._principal(principal,"proposal:read").subject
        row = self._owned_proposal(user,proposal_id)
        return {**dict(row),"changes":json.loads(row["changes_json"])}

    def _owned_proposal(self, user: str, proposal_id: str) -> sqlite3.Row:
        row = self.db.execute("SELECT * FROM plan_proposals WHERE user_id=? AND proposal_id=?",
                              (user,proposal_id)).fetchone()
        if row is None: raise NotFound("proposal unavailable")
        return row

    def _set_proposal(self, user: str, proposal_id: str, status: str,
                      timestamp: str, action: str) -> None:
        self.db.execute("UPDATE plan_proposals SET status=?,updated_at=? WHERE user_id=? AND proposal_id=?",
                        (status,timestamp,user,proposal_id))
        self._audit(user,"proposal",proposal_id,action,{},timestamp)

    def close(self) -> None:
        self.db.close()
