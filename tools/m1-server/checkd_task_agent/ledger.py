from __future__ import annotations

import json
import os
import secrets
import sqlite3
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

from .models import AgentError, TaskDraft


class _ClosingConnection(sqlite3.Connection):
    def __exit__(self, exc_type, exc_value, traceback):
        try:
            return super().__exit__(exc_type, exc_value, traceback)
        finally:
            self.close()


@dataclass(frozen=True, slots=True)
class ConfirmationRecord:
    confirmation_id: str
    idempotency_key: str
    draft: TaskDraft
    digest: str
    confirmation_code: str
    status: str
    expires_at: datetime
    task_id: str | None
    result: dict[str, object] | None
    lease_owner: str | None
    lease_expires_at: datetime | None

    @property
    def confirmation_phrase(self) -> str:
        return f"确认 {self.confirmation_code}"


@dataclass(frozen=True, slots=True)
class UpdateConfirmationRecord:
    confirmation_id: str
    idempotency_key: str
    task_id: str
    changes: dict[str, object]
    original_snapshot: dict[str, object]
    digest: str
    confirmation_code: str
    status: str
    expires_at: datetime
    result: dict[str, object] | None
    lease_owner: str | None
    lease_expires_at: datetime | None

    @property
    def confirmation_phrase(self) -> str:
        return f"确认 {self.confirmation_code}"


class ConfirmationLedger:
    def __init__(self, path: str | Path) -> None:
        self.path = str(path)
        Path(self.path).expanduser().parent.mkdir(parents=True, exist_ok=True)
        self.path = str(Path(self.path).expanduser())
        self._initialize()
        try:
            os.chmod(self.path, 0o600)
        except OSError:
            # Some container/Windows filesystems do not implement POSIX modes.
            pass

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(
            self.path,
            timeout=5,
            isolation_level=None,
            factory=_ClosingConnection,
        )
        connection.row_factory = sqlite3.Row
        return connection

    def _initialize(self) -> None:
        with self._connect() as connection:
            connection.execute("PRAGMA journal_mode=WAL")
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS task_confirmations (
                    confirmation_id TEXT PRIMARY KEY,
                    idempotency_key TEXT NOT NULL UNIQUE,
                    payload_json TEXT NOT NULL,
                    payload_digest TEXT NOT NULL,
                    confirmation_code TEXT NOT NULL,
                    status TEXT NOT NULL,
                    expires_at TEXT NOT NULL,
                    task_id TEXT,
                    result_json TEXT,
                    error_code TEXT,
                    lease_owner TEXT,
                    lease_expires_at TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """
            )
            columns = {
                row["name"]
                for row in connection.execute("PRAGMA table_info(task_confirmations)")
            }
            if "lease_owner" not in columns:
                connection.execute(
                    "ALTER TABLE task_confirmations ADD COLUMN lease_owner TEXT"
                )
            if "lease_expires_at" not in columns:
                connection.execute(
                    "ALTER TABLE task_confirmations ADD COLUMN lease_expires_at TEXT"
                )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS task_update_confirmations (
                    confirmation_id TEXT PRIMARY KEY,
                    idempotency_key TEXT NOT NULL UNIQUE,
                    task_id TEXT NOT NULL,
                    changes_json TEXT NOT NULL,
                    original_snapshot_json TEXT NOT NULL,
                    payload_digest TEXT NOT NULL,
                    confirmation_code TEXT NOT NULL,
                    status TEXT NOT NULL,
                    expires_at TEXT NOT NULL,
                    result_json TEXT,
                    error_code TEXT,
                    lease_owner TEXT,
                    lease_expires_at TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """
            )

            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS task_update_write_receipts (
                    confirmation_id TEXT NOT NULL,
                    component TEXT NOT NULL CHECK(component IN ('task', 'reminder')),
                    version TEXT NOT NULL,
                    PRIMARY KEY (confirmation_id, component),
                    FOREIGN KEY (confirmation_id)
                        REFERENCES task_update_confirmations(confirmation_id)
                )
                """
            )

    def prepare(
        self,
        draft: TaskDraft,
        idempotency_key: str,
        *,
        now: datetime,
        ttl: timedelta,
    ) -> ConfirmationRecord:
        key = idempotency_key.strip()
        if not key or len(key) > 128:
            raise AgentError("INVALID_IDEMPOTENCY_KEY", "idempotency_key 必须为 1–128 个字符。")
        normalized = draft.validated()
        digest = normalized.digest()
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT * FROM task_confirmations WHERE idempotency_key = ?", (key,)
            ).fetchone()
            if row is not None:
                record = self._record(row)
                if record.digest != digest:
                    connection.execute("ROLLBACK")
                    raise AgentError(
                        "IDEMPOTENCY_CONFLICT",
                        "同一 idempotency_key 已用于不同的任务内容。",
                    )
                connection.execute("COMMIT")
                return record
            confirmation_id = str(uuid.uuid4())
            code = f"{secrets.randbelow(1_000_000):06d}"
            expires_at = now.astimezone(timezone.utc) + ttl
            timestamp = now.astimezone(timezone.utc).isoformat()
            connection.execute(
                """
                INSERT INTO task_confirmations (
                    confirmation_id, idempotency_key, payload_json,
                    payload_digest, confirmation_code, status, expires_at,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, 'pending', ?, ?, ?)
                """,
                (
                    confirmation_id,
                    key,
                    normalized.canonical_json(),
                    digest,
                    code,
                    expires_at.isoformat(),
                    timestamp,
                    timestamp,
                ),
            )
            row = connection.execute(
                "SELECT * FROM task_confirmations WHERE confirmation_id = ?",
                (confirmation_id,),
            ).fetchone()
            connection.execute("COMMIT")
            assert row is not None
            return self._record(row)

    def claim(
        self,
        confirmation_id: str,
        confirmation_text: str,
        *,
        now: datetime,
        lease_owner: str,
        lease_ttl: timedelta,
    ) -> ConfirmationRecord:
        if not lease_owner:
            raise ValueError("lease_owner must not be empty")
        now_utc = now.astimezone(timezone.utc)
        lease_expires_at = now_utc + lease_ttl
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT * FROM task_confirmations WHERE confirmation_id = ?",
                (confirmation_id,),
            ).fetchone()
            if row is None:
                connection.execute("ROLLBACK")
                raise AgentError("CONFIRMATION_NOT_FOUND", "确认请求不存在。")
            record = self._record(row)
            if record.status == "completed":
                connection.execute("COMMIT")
                return record
            if record.status == "cancelled":
                connection.execute("ROLLBACK")
                raise AgentError("CONFIRMATION_CANCELLED", "该任务创建已取消。")
            if record.status == "failed":
                connection.execute("ROLLBACK")
                raise AgentError("CREATION_FAILED", "该确认已终止，请重新准备任务。")
            if record.expires_at <= now_utc:
                connection.execute(
                    "UPDATE task_confirmations SET status='expired', updated_at=? WHERE confirmation_id=?",
                    (now_utc.isoformat(), confirmation_id),
                )
                connection.execute("COMMIT")
                raise AgentError("CONFIRMATION_EXPIRED", "确认已过期，请重新准备任务。")
            if record.status == "expired":
                connection.execute("ROLLBACK")
                raise AgentError("CONFIRMATION_EXPIRED", "确认已过期，请重新准备任务。")
            if confirmation_text.strip() != record.confirmation_phrase:
                connection.execute("ROLLBACK")
                raise AgentError(
                    "EXPLICIT_CONFIRMATION_REQUIRED",
                    f"请用户本人回复完整确认短语：{record.confirmation_phrase}",
                )
            if record.status == "creating":
                if (
                    record.lease_expires_at is not None
                    and record.lease_expires_at > now_utc
                ):
                    connection.execute("ROLLBACK")
                    raise AgentError(
                        "IDEMPOTENCY_IN_PROGRESS",
                        "该任务正在创建。",
                        retryable=True,
                    )
            if record.status not in {"pending", "retryable"}:
                if record.status != "creating":
                    connection.execute("ROLLBACK")
                    raise AgentError("INVALID_CONFIRMATION_STATE", "确认状态不允许创建。")
            connection.execute(
                """
                UPDATE task_confirmations
                SET status='creating', lease_owner=?, lease_expires_at=?, updated_at=?
                WHERE confirmation_id=?
                """,
                (
                    lease_owner,
                    lease_expires_at.isoformat(),
                    now_utc.isoformat(),
                    confirmation_id,
                ),
            )
            row = connection.execute(
                "SELECT * FROM task_confirmations WHERE confirmation_id = ?",
                (confirmation_id,),
            ).fetchone()
            connection.execute("COMMIT")
            assert row is not None
            return self._record(row)

    def assign_task_id(
        self,
        confirmation_id: str,
        task_id: str,
        *,
        now: datetime,
        lease_owner: str,
    ) -> None:
        with self._connect() as connection:
            cursor = connection.execute(
                """
                UPDATE task_confirmations SET task_id=?, updated_at=?
                WHERE confirmation_id=? AND status='creating' AND lease_owner=?
                """,
                (
                    task_id,
                    now.astimezone(timezone.utc).isoformat(),
                    confirmation_id,
                    lease_owner,
                ),
            )
            if cursor.rowcount != 1:
                raise AgentError("LEASE_LOST", "创建租约已失效，请重试。", retryable=True)

    def complete(
        self,
        confirmation_id: str,
        result: dict[str, object],
        *,
        now: datetime,
        lease_owner: str,
    ) -> ConfirmationRecord:
        with self._connect() as connection:
            cursor = connection.execute(
                """
                UPDATE task_confirmations
                SET status='completed', result_json=?, error_code=NULL,
                    lease_owner=NULL, lease_expires_at=NULL, updated_at=?
                WHERE confirmation_id=? AND status='creating' AND lease_owner=?
                """,
                (
                    json.dumps(result, ensure_ascii=False, sort_keys=True),
                    now.astimezone(timezone.utc).isoformat(),
                    confirmation_id,
                    lease_owner,
                ),
            )
            if cursor.rowcount != 1:
                raise AgentError("LEASE_LOST", "创建租约已失效，请重试。", retryable=True)
            row = connection.execute(
                "SELECT * FROM task_confirmations WHERE confirmation_id=?",
                (confirmation_id,),
            ).fetchone()
            assert row is not None
            return self._record(row)

    def fail(
        self,
        confirmation_id: str,
        error: AgentError,
        *,
        now: datetime,
        lease_owner: str,
    ) -> None:
        status = "retryable" if error.retryable else "failed"
        with self._connect() as connection:
            connection.execute(
                """
                UPDATE task_confirmations
                SET status=?, error_code=?, lease_owner=NULL,
                    lease_expires_at=NULL, updated_at=?
                WHERE confirmation_id=? AND status='creating' AND lease_owner=?
                """,
                (
                    status,
                    error.code,
                    now.astimezone(timezone.utc).isoformat(),
                    confirmation_id,
                    lease_owner,
                ),
            )

    def cancel(self, confirmation_id: str, *, now: datetime) -> ConfirmationRecord:
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT * FROM task_confirmations WHERE confirmation_id=?",
                (confirmation_id,),
            ).fetchone()
            if row is None:
                connection.execute("ROLLBACK")
                raise AgentError("CONFIRMATION_NOT_FOUND", "确认请求不存在。")
            record = self._record(row)
            if record.status == "completed":
                connection.execute("ROLLBACK")
                raise AgentError("ALREADY_CREATED", "任务已创建，不能通过取消删除。")
            if record.status == "creating":
                connection.execute("ROLLBACK")
                raise AgentError("IDEMPOTENCY_IN_PROGRESS", "任务正在创建，无法取消。", retryable=True)
            connection.execute(
                "UPDATE task_confirmations SET status='cancelled', updated_at=? WHERE confirmation_id=?",
                (now.astimezone(timezone.utc).isoformat(), confirmation_id),
            )
            row = connection.execute(
                "SELECT * FROM task_confirmations WHERE confirmation_id=?",
                (confirmation_id,),
            ).fetchone()
            connection.execute("COMMIT")
            assert row is not None
            return self._record(row)

    def find_prepared_update(
        self,
        idempotency_key: str,
        task_id: str,
        changes: dict[str, object],
    ) -> UpdateConfirmationRecord | None:
        key = idempotency_key.strip()
        if not key or len(key) > 128:
            raise AgentError("INVALID_IDEMPOTENCY_KEY", "idempotency_key 必须为 1–128 个字符。")
        with self._connect() as connection:
            return self._existing_update(connection, key, task_id, changes)

    def _existing_update(
        self,
        connection: sqlite3.Connection,
        key: str,
        task_id: str,
        changes: dict[str, object],
    ) -> UpdateConfirmationRecord | None:
        row = connection.execute(
            "SELECT * FROM task_update_confirmations WHERE idempotency_key=?", (key,)
        ).fetchone()
        if row is None:
            return None
        record = self._update_record(row)
        if record.task_id != task_id or record.changes != changes:
            raise AgentError("IDEMPOTENCY_CONFLICT", "同一 idempotency_key 已用于不同的修改内容。")
        return record

    def prepare_update(
        self,
        *,
        task_id: str,
        changes: dict[str, object],
        original_snapshot: dict[str, object],
        digest: str,
        idempotency_key: str,
        now: datetime,
        ttl: timedelta,
    ) -> UpdateConfirmationRecord:
        key = idempotency_key.strip()
        if not key or len(key) > 128:
            raise AgentError("INVALID_IDEMPOTENCY_KEY", "idempotency_key 必须为 1–128 个字符。")
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            existing = self._existing_update(connection, key, task_id, changes)
            if existing is not None:
                connection.execute("COMMIT")
                return existing
            confirmation_id = str(uuid.uuid4())
            code = f"{secrets.randbelow(1_000_000):06d}"
            expires_at = now.astimezone(timezone.utc) + ttl
            timestamp = now.astimezone(timezone.utc).isoformat()
            connection.execute(
                """
                INSERT INTO task_update_confirmations (
                    confirmation_id,idempotency_key,task_id,changes_json,
                    original_snapshot_json,payload_digest,confirmation_code,status,
                    expires_at,created_at,updated_at
                ) VALUES (?,?,?,?,?,?,?,'pending',?,?,?)
                """,
                (
                    confirmation_id,
                    key,
                    task_id,
                    json.dumps(changes, ensure_ascii=False, sort_keys=True),
                    json.dumps(original_snapshot, ensure_ascii=False, sort_keys=True),
                    digest,
                    code,
                    expires_at.isoformat(),
                    timestamp,
                    timestamp,
                ),
            )
            row = connection.execute(
                "SELECT * FROM task_update_confirmations WHERE confirmation_id=?", (confirmation_id,)
            ).fetchone()
            connection.execute("COMMIT")
            assert row is not None
            return self._update_record(row)

    def claim_update(
        self,
        confirmation_id: str,
        confirmation_text: str,
        *,
        now: datetime,
        lease_owner: str,
        lease_ttl: timedelta,
    ) -> UpdateConfirmationRecord:
        if not lease_owner:
            raise ValueError("lease_owner must not be empty")
        now_utc = now.astimezone(timezone.utc)
        lease_expires_at = now_utc + lease_ttl
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT * FROM task_update_confirmations WHERE confirmation_id=?", (confirmation_id,)
            ).fetchone()
            if row is None:
                connection.execute("ROLLBACK")
                raise AgentError("UPDATE_CONFIRMATION_NOT_FOUND", "修改确认请求不存在。")
            record = self._update_record(row)
            if record.status == "completed":
                connection.execute("COMMIT")
                return record
            if record.status == "cancelled":
                connection.execute("ROLLBACK")
                raise AgentError("UPDATE_CONFIRMATION_CANCELLED", "该修改已取消。")
            if record.status == "failed":
                connection.execute("ROLLBACK")
                raise AgentError("UPDATE_FAILED", "该修改已终止，请重新准备。")
            if record.expires_at <= now_utc:
                connection.execute(
                    "UPDATE task_update_confirmations SET status='expired',updated_at=? WHERE confirmation_id=?",
                    (now_utc.isoformat(), confirmation_id),
                )
                connection.execute("COMMIT")
                raise AgentError("UPDATE_CONFIRMATION_EXPIRED", "修改确认已过期，请重新准备。")
            if confirmation_text.strip() != record.confirmation_phrase:
                connection.execute("ROLLBACK")
                raise AgentError(
                    "EXPLICIT_CONFIRMATION_REQUIRED",
                    f"请用户本人回复完整确认短语：{record.confirmation_phrase}",
                )
            if record.status == "creating" and record.lease_expires_at is not None and record.lease_expires_at > now_utc:
                connection.execute("ROLLBACK")
                raise AgentError("IDEMPOTENCY_IN_PROGRESS", "该修改正在执行。", retryable=True)
            if record.status not in {"pending", "retryable", "creating"}:
                connection.execute("ROLLBACK")
                raise AgentError("INVALID_UPDATE_STATE", "修改状态不允许执行。")
            connection.execute(
                """
                UPDATE task_update_confirmations
                SET status='creating',lease_owner=?,lease_expires_at=?,updated_at=?
                WHERE confirmation_id=?
                """,
                (lease_owner, lease_expires_at.isoformat(), now_utc.isoformat(), confirmation_id),
            )
            row = connection.execute(
                "SELECT * FROM task_update_confirmations WHERE confirmation_id=?", (confirmation_id,)
            ).fetchone()
            connection.execute("COMMIT")
            assert row is not None
            return self._update_record(row)

    def update_write_receipts(self, confirmation_id: str) -> dict[str, str]:
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT component, version FROM task_update_write_receipts WHERE confirmation_id=?",
                (confirmation_id,),
            )
            return {row["component"]: row["version"] for row in rows}

    def record_update_write(
        self,
        confirmation_id: str,
        component: str,
        version: str,
        *,
        now: datetime,
        lease_owner: str,
    ) -> None:
        with self._connect() as connection:
            cursor = connection.execute(
                """
                INSERT INTO task_update_write_receipts (confirmation_id, component, version)
                SELECT confirmation_id, ?, ? FROM task_update_confirmations
                WHERE confirmation_id=? AND status='creating' AND lease_owner=?
                    AND lease_expires_at>?
                """,
                (component, version, confirmation_id, lease_owner, now.astimezone(timezone.utc).isoformat()),
            )
            if cursor.rowcount != 1:
                raise AgentError("LEASE_LOST", "修改租约已失效，请重新读取并核对任务。")

    def complete_update(
        self,
        confirmation_id: str,
        result: dict[str, object],
        *,
        now: datetime,
        lease_owner: str,
    ) -> UpdateConfirmationRecord:
        with self._connect() as connection:
            cursor = connection.execute(
                """
                UPDATE task_update_confirmations
                SET status='completed',result_json=?,error_code=NULL,
                    lease_owner=NULL,lease_expires_at=NULL,updated_at=?
                WHERE confirmation_id=? AND status='creating' AND lease_owner=?
                """,
                (json.dumps(result, ensure_ascii=False, sort_keys=True), now.astimezone(timezone.utc).isoformat(), confirmation_id, lease_owner),
            )
            if cursor.rowcount != 1:
                raise AgentError("LEASE_LOST", "修改租约已失效，请重试。", retryable=True)
            row = connection.execute(
                "SELECT * FROM task_update_confirmations WHERE confirmation_id=?", (confirmation_id,)
            ).fetchone()
            assert row is not None
            return self._update_record(row)

    def fail_update(
        self,
        confirmation_id: str,
        error: AgentError,
        *,
        now: datetime,
        lease_owner: str,
    ) -> None:
        status = "retryable" if error.retryable else "failed"
        with self._connect() as connection:
            connection.execute(
                """
                UPDATE task_update_confirmations
                SET status=?,error_code=?,lease_owner=NULL,lease_expires_at=NULL,updated_at=?
                WHERE confirmation_id=? AND status='creating' AND lease_owner=?
                """,
                (status, error.code, now.astimezone(timezone.utc).isoformat(), confirmation_id, lease_owner),
            )

    def cancel_update(self, confirmation_id: str, *, now: datetime) -> UpdateConfirmationRecord:
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT * FROM task_update_confirmations WHERE confirmation_id=?", (confirmation_id,)
            ).fetchone()
            if row is None:
                connection.execute("ROLLBACK")
                raise AgentError("UPDATE_CONFIRMATION_NOT_FOUND", "修改确认请求不存在。")
            record = self._update_record(row)
            if record.status == "completed":
                connection.execute("ROLLBACK")
                raise AgentError("ALREADY_UPDATED", "修改已执行，不能通过取消撤销。")
            if record.status == "creating":
                connection.execute("ROLLBACK")
                raise AgentError("IDEMPOTENCY_IN_PROGRESS", "修改正在执行，无法取消。", retryable=True)
            connection.execute(
                "UPDATE task_update_confirmations SET status='cancelled',updated_at=? WHERE confirmation_id=?",
                (now.astimezone(timezone.utc).isoformat(), confirmation_id),
            )
            row = connection.execute(
                "SELECT * FROM task_update_confirmations WHERE confirmation_id=?", (confirmation_id,)
            ).fetchone()
            connection.execute("COMMIT")
            assert row is not None
            return self._update_record(row)

    def _record(self, row: sqlite3.Row) -> ConfirmationRecord:
        return ConfirmationRecord(
            confirmation_id=row["confirmation_id"],
            idempotency_key=row["idempotency_key"],
            draft=TaskDraft.from_json(row["payload_json"]),
            digest=row["payload_digest"],
            confirmation_code=row["confirmation_code"],
            status=row["status"],
            expires_at=datetime.fromisoformat(row["expires_at"]),
            task_id=row["task_id"],
            result=json.loads(row["result_json"]) if row["result_json"] else None,
            lease_owner=row["lease_owner"],
            lease_expires_at=(
                datetime.fromisoformat(row["lease_expires_at"])
                if row["lease_expires_at"]
                else None
            ),
        )

    def _update_record(self, row: sqlite3.Row) -> UpdateConfirmationRecord:
        return UpdateConfirmationRecord(
            confirmation_id=row["confirmation_id"],
            idempotency_key=row["idempotency_key"],
            task_id=row["task_id"],
            changes=json.loads(row["changes_json"]),
            original_snapshot=json.loads(row["original_snapshot_json"]),
            digest=row["payload_digest"],
            confirmation_code=row["confirmation_code"],
            status=row["status"],
            expires_at=datetime.fromisoformat(row["expires_at"]),
            result=json.loads(row["result_json"]) if row["result_json"] else None,
            lease_owner=row["lease_owner"],
            lease_expires_at=(
                datetime.fromisoformat(row["lease_expires_at"])
                if row["lease_expires_at"] else None
            ),
        )
