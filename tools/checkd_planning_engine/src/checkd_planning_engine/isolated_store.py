"""Local prototype for principal-scoped private workspaces and durable events.

The caller must obtain `subject` from a verified auth adapter. Tool payloads do
not accept user_id; this module intentionally has no owner-account fallback.
"""
from __future__ import annotations

import json
import sqlite3
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path


class AccessDenied(Exception): pass


class IsolatedStore:
    def __init__(self, path: str | Path):
        self.db=sqlite3.connect(str(path), timeout=10, isolation_level=None)
        self.db.row_factory=sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript("""
        CREATE TABLE IF NOT EXISTS workspace_data(user_id TEXT NOT NULL, kind TEXT NOT NULL, item_key TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(user_id,kind,item_key));
        CREATE TABLE IF NOT EXISTS agent_events(event_id TEXT PRIMARY KEY,user_id TEXT NOT NULL,dedupe_key TEXT NOT NULL,payload TEXT NOT NULL,status TEXT NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,available_at TEXT NOT NULL,last_error TEXT,UNIQUE(user_id,dedupe_key));
        CREATE INDEX IF NOT EXISTS events_ready ON agent_events(status,available_at);
        CREATE TABLE IF NOT EXISTS event_results(event_id TEXT PRIMARY KEY,user_id TEXT NOT NULL,result TEXT NOT NULL);
        """)

    @staticmethod
    def principal(subject: str | None, *, verified: bool) -> str:
        if not verified or not subject: raise AccessDenied("verified identity required")
        return subject

    def put_private(self, subject: str | None, *, verified: bool, kind: str, key: str, value: dict):
        user=self.principal(subject,verified=verified)
        if kind not in {"task","plan","risk","preference","memory","approval","notification","idempotency"}:
            raise ValueError("unsupported workspace kind")
        self.db.execute("INSERT INTO workspace_data VALUES(?,?,?,?) ON CONFLICT(user_id,kind,item_key) DO UPDATE SET payload=excluded.payload",
            (user,kind,key,json.dumps(value,sort_keys=True)))

    def get_private(self, subject: str | None, *, verified: bool, kind: str, key: str) -> dict | None:
        user=self.principal(subject,verified=verified)
        row=self.db.execute("SELECT payload FROM workspace_data WHERE user_id=? AND kind=? AND item_key=?",(user,kind,key)).fetchone()
        return json.loads(row[0]) if row else None

    def enqueue(self, subject: str | None, *, verified: bool, dedupe_key: str, payload: dict, now: datetime | None=None) -> str:
        user=self.principal(subject,verified=verified); now=(now or datetime.now(timezone.utc)).astimezone(timezone.utc)
        event_id=str(uuid.uuid4())
        self.db.execute("INSERT OR IGNORE INTO agent_events(event_id,user_id,dedupe_key,payload,status,available_at) VALUES(?,?,?,?,?,?)",
            (event_id,user,dedupe_key,json.dumps(payload,sort_keys=True),"pending",now.isoformat()))
        row=self.db.execute("SELECT event_id FROM agent_events WHERE user_id=? AND dedupe_key=?",(user,dedupe_key)).fetchone()
        return row[0]

    def claim(self, worker: str, *, now: datetime | None=None, lease: timedelta=timedelta(minutes=2)) -> dict | None:
        now=(now or datetime.now(timezone.utc)).astimezone(timezone.utc)
        self.db.execute("BEGIN IMMEDIATE")
        try:
            row=self.db.execute("SELECT event_id,user_id,payload,attempts FROM agent_events WHERE status IN ('pending','retry') AND available_at<=? ORDER BY available_at,event_id LIMIT 1",(now.isoformat(),)).fetchone()
            if not row: self.db.execute("COMMIT"); return None
            self.db.execute("UPDATE agent_events SET status='processing',attempts=attempts+1,available_at=? WHERE event_id=?",((now+lease).isoformat(),row['event_id']))
            self.db.execute("COMMIT")
            return {"event_id":row['event_id'],"user_id":row['user_id'],"payload":json.loads(row['payload']),"attempts":row['attempts']+1,"worker":worker}
        except Exception:
            self.db.execute("ROLLBACK"); raise

    def recover_expired(self, *, now: datetime | None=None) -> int:
        now=(now or datetime.now(timezone.utc)).astimezone(timezone.utc).isoformat()
        cur=self.db.execute("UPDATE agent_events SET status='retry',available_at=? WHERE status='processing' AND available_at<=?",(now,now))
        return cur.rowcount

    def fail(self,event_id:str, error_code:str, *, now:datetime|None=None, max_attempts:int=5):
        row=self.db.execute("SELECT attempts FROM agent_events WHERE event_id=?",(event_id,)).fetchone()
        if not row: raise KeyError(event_id)
        status='failed' if row[0]>=max_attempts else 'retry'
        now=(now or datetime.now(timezone.utc)).astimezone(timezone.utc)
        delay=min(3600,2**row[0])
        self.db.execute("UPDATE agent_events SET status=?,last_error=?,available_at=? WHERE event_id=?",(status,error_code,(now+timedelta(seconds=delay)).isoformat(),event_id))

    def complete(self,event_id:str, *, verified_user_id:str, result:dict):
        self.db.execute("BEGIN IMMEDIATE")
        try:
            row=self.db.execute("SELECT user_id,status FROM agent_events WHERE event_id=?",(event_id,)).fetchone()
            if not row or row['user_id']!=verified_user_id: raise AccessDenied("event owner mismatch")
            if row['status']!='processing': raise ValueError("event is not processing")
            self.db.execute("INSERT OR REPLACE INTO event_results VALUES(?,?,?)",(event_id,verified_user_id,json.dumps(result,sort_keys=True)))
            self.db.execute("UPDATE agent_events SET status='done',last_error=NULL WHERE event_id=?",(event_id,))
            self.db.execute("COMMIT")
        except Exception:
            self.db.execute("ROLLBACK"); raise

    def close(self): self.db.close()
