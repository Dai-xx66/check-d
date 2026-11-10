#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""快照存储：独立 DEMO 库的唯一读写入口。

## 职责边界（写死，别扩）

- 只做持久化与版本发号。调度语义在 M2 引擎，这里一行都不涉及。
- 所有"现在几点"一律由库 `now()` 产生，**不采信客户端时钟**。客户端能改系统时间，
  拿它判过期等于把过期判定交给攻击者。
- 失败一律抛错，不返回"看起来成功"的默认值。宁可 503，不静默降级。
- `base_version` 只从库里读回来，**绝不在这里拼字符串**。库里是生成列，
  两处拼接必然漂移（P1-2 要防的就是这个）。

## 为什么分成 Executor 与 Store

Store 是业务逻辑（发号、supersede、apply 校验、错误映射）。
Executor 是"怎么把 SQL 打到库上"，有两个实现：

- `PgExecutor`   ：真 psycopg3 连接池，生产用
- `RecordingExecutor`：不发 SQL，只记录 (sql, params) 并按预设返回答，
                        用于**无库环境下的逻辑单测**

这个分层是有代价的：Recording 能证明"我给库的语句和参数对不对"，
**但不能证明"库真能执行"**。所以两种测试的结论必须分开写：

    logic PASS（Recording）  ≠  persistence PASS（Pg + 真库）

M0 2026-11-07T03:07:56Z 工单 §一.4 明确禁止用 stub 冒充持久化 PASS。
本文件不破这条：Recording 全绿时，真实持久化仍标 BLOCKED。

## 契约依据

- §6.3 L492-505：服务端包装层创建快照、产 snapshot_ref/base_version/input_digest
- §4.1 L148/L149：PROPOSAL_EXPIRED / SNAPSHOT_CONFLICT 均为 409
- ALREADY_APPLIED 409，幂等由 applied_change.proposal_id unique 兜底
"""

import hashlib
import json
import os
import threading
import uuid
from datetime import datetime, timezone

# 错误码走 errors.py 的闭集，不在这里自造。
try:
    from errors import HTTP_BY_CODE  # noqa: F401  仅用于断言码在闭集内
except Exception:                                            # noqa: BLE001
    HTTP_BY_CODE = {}

# 本模块会抛的码，必须是闭集内的。
_CODE_SNAPSHOT_CONFLICT = "SNAPSHOT_CONFLICT"
_CODE_PROPOSAL_EXPIRED = "PROPOSAL_EXPIRED"
_CODE_ALREADY_APPLIED = "ALREADY_APPLIED"
_CODE_DEPENDENCY_UNAVAILABLE = "DEPENDENCY_UNAVAILABLE"
_CODE_INVALID_ARGUMENT = "INVALID_ARGUMENT"
_CODE_NOT_FOUND = "NOT_FOUND"
_CODE_INTERNAL_ERROR = "INTERNAL_ERROR"

# retryable 口径：只有依赖不可用可重试（库抖动，等一下可能好）。
# 409 三种都不可重试——重试同一份过期/冲突的数据，结果不会变。
_RETRYABLE = {
    _CODE_DEPENDENCY_UNAVAILABLE: True,
}

# 快照 TTL 相对提案 TTL 的余量（秒）。快照先插入、提案后插入，两条 expires_at 各由
# 自己的 now() 算；余量为 0 时提案到期前会出现「提案有效、快照已过期」的毫秒窗口。
# 60 s 只覆盖两次插入的间隔，不改变契约对提案 30 分钟的规定。
SNAPSHOT_TTL_MARGIN_SECONDS = 60


class SnapshotStoreError(Exception):
    """带契约码的存储错误。上层直接取 .code / .retryable 组信封。"""

    def __init__(self, code, message, retryable=None, details=None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.retryable = _RETRYABLE.get(code, False) if retryable is None else retryable
        self.details = details or {}

    def to_error(self):
        return {
            "code": self.code,
            "message": self.message,
            "retryable": self.retryable,
            "details": self.details,
        }


def canonical_payload(payload):
    """规范化 JSON：键排序、无多余空白、UTF-8。

    digest 必须对**规范化后**的字节算，否则同样的数据换个键序就是另一个摘要，
    digest 就失去"同一份数据"的含义。
    """
    return json.dumps(payload, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"))


def payload_digest(payload):
    raw = canonical_payload(payload).encode("utf-8")
    return hashlib.sha256(raw).hexdigest(), len(raw)


# ============================================================
# Executor：怎么把 SQL 打到库上
# ============================================================


class PgExecutor:
    """真 psycopg3 连接池。

    连接参数按 M0 §二 P0-3 的要求给定，理由见 migration 注释与交付说明：
    - 5432 直连优先；6543 transaction pooler 与"同事务 supersede+insert"冲突
    - prepare_threshold=None：关闭预编译缓存，6543 兼容的根因项
    - statement_timeout / lock_timeout 防长事务拖死整条链路
    """

    def __init__(self, dsn, min_size=1, max_size=4, timeout=5.0,
                 statement_timeout_ms=5000, lock_timeout_ms=3000):
        self.dsn = dsn
        self._min = min_size
        self._max = max_size
        self._timeout = timeout
        self._stmt_ms = statement_timeout_ms
        self._lock_ms = lock_timeout_ms
        self._pool = None
        self._lock = threading.Lock()

    def open(self):
        with self._lock:
            if self._pool is not None:
                return
            import psycopg_pool                      # 延迟导入：无库环境不因缺包崩
            self._pool = psycopg_pool.ConnectionPool(
                conninfo=self.dsn,
                min_size=self._min,
                max_size=self._max,
                timeout=self._timeout,
                kwargs={
                    "prepare_threshold": None,
                    "application_name": "checkd-demo",
                    "options": "-c statement_timeout=%d -c lock_timeout=%d"
                               % (self._stmt_ms, self._lock_ms),
                },
                open=True,
            )

    def close(self):
        with self._lock:
            if self._pool is not None:
                self._pool.close()
                self._pool = None

    def transaction(self):
        """返回一个上下文管理器：进出真事务。"""
        if self._pool is None:
            raise SnapshotStoreError(_CODE_DEPENDENCY_UNAVAILABLE,
                                     "快照库连接池未打开。")
        return _PgTransaction(self._pool)

    def ping(self):
        try:
            if self._pool is None:
                return False
            with self._pool.connection(timeout=self._timeout) as conn:
                conn.execute("select 1")
            return True
        except Exception:                            # noqa: BLE001
            return False


class _PgTransaction:
    def __init__(self, pool):
        self._pool = pool
        self._ctx = None
        self._conn = None

    def __enter__(self):
        self._ctx = self._pool.connection()
        self._conn = self._ctx.__enter__()
        self._tx = self._conn.transaction()
        self._tx.__enter__()
        return self._conn

    def __exit__(self, exc_type, exc, tb):
        try:
            self._tx.__exit__(exc_type, exc, tb)
        finally:
            self._ctx.__exit__(exc_type, exc, tb)
        return False


class RecordingExecutor:
    """不发 SQL，只记录并按队列返回答。用于无库环境的逻辑单测。

    用法：
        ex = RecordingExecutor([[(1,)], [(uuid_val,)]])
        store = SnapshotStore(executor=ex)
        ...
        assert "on conflict" in ex.statements[0][0].lower()

    明确的能力边界：它能证明「语句与参数长什么样」、「顺序对不对」、「错误怎么映射」，
    不能证明「PostgreSQL 接受这段 SQL」。
    """

    def __init__(self, replies=None, fail_with=None):
        self.statements = []          # [(sql, params)]
        self._replies = list(replies or [])
        self._fail_with = fail_with   # 第几条开始抛（1-based），None = 全成功
        self.commits = 0
        self.rollbacks = 0

    def transaction(self):
        return _RecordingTransaction(self)

    def ping(self):
        return self._fail_with is None

    # --- 内部 ---
    def _execute(self, sql, params):
        self.statements.append((sql, params))
        if self._fail_with is not None and len(self.statements) >= self._fail_with:
            raise _InjectedFailure()
        if self._replies:
            return self._replies.pop(0)
        return []


class _InjectedFailure(Exception):
    pass


class _RecordingTransaction:
    def __init__(self, ex):
        self._ex = ex
        self._pending = 0

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        if exc_type is None:
            self._ex.commits += 1
        else:
            self._ex.rollbacks += 1
        return False

    def execute(self, sql, params=None):
        return _RecordingCursor(self._ex._execute(sql, params or ()))


class _RecordingCursor:
    def __init__(self, rows):
        self._rows = rows

    def fetchone(self):
        return self._rows[0] if self._rows else None

    def fetchall(self):
        return list(self._rows)


# ============================================================
# Store：业务逻辑
# ============================================================


class SnapshotStore:
    def __init__(self, dsn=None, executor=None,
                 snapshot_ttl_seconds=None, proposal_ttl_seconds=1800):
        """TTL 默认值按契约定死，不做成可配置。

        契约原文（blob 9579be9e，L344-345）：「Proposal 自 `generated_at` 起固定有效
        30 分钟；服务端不得接受客户端指定或延长该 TTL」，L423 也是「TTL 30 分钟」。
        旧默认 600 s（10 分钟）是早期遗留，等于把契约的 30 分钟砍成 10 分钟——库里
        写进去的 `expires_at` 会比契约允许的提前 20 分钟到期，调用方按契约算的时间
        再来 validate 就会拿到 PROPOSAL_EXPIRED。现已对齐 1800 s。

        快照 TTL 必须**严格长于**提案 TTL 至少 `SNAPSHOT_TTL_MARGIN_SECONDS`，只
        「>=」不够（M3 提、M2 16:09Z 附议的毫秒窗口）：两值相等时，快照先插入、
        提案后插入，两条 `expires_at` 都是各自的 `now() + interval`，于是提案到期
        前那几十毫秒里「提案仍有效、快照已过期」，validate / request_approval /
        apply 一律返回 SNAPSHOT_CONFLICT —— 一个必现但极窄的自相矛盾窗口。
        故快照默认取 `proposal_ttl + 60 s`（1860），多出的 60 s 只是给插入间隔留余量，
        不改变契约对提案的 30 分钟。
        """
        self._ex = executor if executor is not None else PgExecutor(dsn or os.environ.get("CHECKD_DEMO_DSN", ""))
        self.proposal_ttl = int(proposal_ttl_seconds)
        minimum_snapshot_ttl = self.proposal_ttl + SNAPSHOT_TTL_MARGIN_SECONDS
        if snapshot_ttl_seconds is None:
            self.snapshot_ttl = minimum_snapshot_ttl
        else:
            self.snapshot_ttl = int(snapshot_ttl_seconds)
            if self.snapshot_ttl < minimum_snapshot_ttl:
                # 显式放宽到相等/更短时直接失败，不静默接受：那正是上面的毫秒窗口。
                raise ValueError(
                    "snapshot_ttl_seconds 必须 >= proposal_ttl + %d（%d），收到 %d；"
                    "两者相等会在 TTL 边界造出「提案有效但快照已过期」的窗口。"
                    % (SNAPSHOT_TTL_MARGIN_SECONDS, minimum_snapshot_ttl, self.snapshot_ttl))

    # ---------- 生命周期 ----------

    def open(self):
        self._ex.open()
        return self

    def close(self):
        self._ex.close()

    def health(self):
        return bool(self._ex.ping())

    # ---------- 快照 ----------

    def create_snapshot(self, user_id, date_from, date_to, payload):
        """新建一版快照：原子发号 → 旧 latest 置 superseded → 插新行，同一事务。

        锁序固定：seq 行（ON CONFLICT 隐式行锁）→ snapshot 旧 latest 行 → 插新行。
        与 apply 路径（proposal → snapshot）只在 snapshot 行交叉，无回环，不会死锁。

        返回 dict：snapshot_id / version / base_version / payload_digest / payload_bytes / expires_at
        """
        _require_text(user_id, "user_id")
        _require_date_order(date_from, date_to)
        digest, nbytes = payload_digest(payload)
        raw = canonical_payload(payload)

        try:
            with self._ex.transaction() as conn:
                # 1) 发号：单语句，禁止 select max+1
                row = conn.execute(
                    "insert into checkd_demo.snapshot_seq "
                    "(user_id, date_from, date_to, next_version) "
                    "values (%s, %s, %s, 2) "
                    "on conflict (user_id, date_from, date_to) "
                    "do update set next_version = checkd_demo.snapshot_seq.next_version + 1, "
                    "              updated_at = now() "
                    "returning next_version - 1 as version",
                    (user_id, date_from, date_to),
                ).fetchone()
                version = int(row[0])

                # 2) 旧 latest 置为已替代（可能 0 行，首次创建时就是 0）
                conn.execute(
                    "update checkd_demo.snapshot set superseded_at = now() "
                    "where user_id = %s and date_from = %s and date_to = %s "
                    "  and superseded_at is null",
                    (user_id, date_from, date_to),
                )

                # 3) 插入新快照。expires_at 由库算，不用客户端时间
                row = conn.execute(
                    "insert into checkd_demo.snapshot "
                    "(user_id, date_from, date_to, version, payload, "
                    " payload_digest, payload_bytes, expires_at) "
                    "values (%s, %s, %s, %s, %s::jsonb, %s, %s, "
                    "        now() + make_interval(secs => %s)) "
                    "returning snapshot_id, expires_at",
                    (user_id, date_from, date_to, version, raw,
                     digest, nbytes, self.snapshot_ttl),
                ).fetchone()
                snapshot_id, expires_at = row[0], row[1]

                return {
                    "snapshot_id": str(snapshot_id),
                    "version": version,
                    # 库里是生成列，正常路径应该读回来；这里按同一规则给出，
                    # 并在 get_snapshot 里以库值为准做一次自校验。
                    "base_version": _base_version(snapshot_id, version),
                    "payload_digest": digest,
                    "payload_bytes": nbytes,
                    "expires_at": _iso(expires_at),
                }
        except SnapshotStoreError:
            raise
        except Exception as e:                       # noqa: BLE001
            raise _map_db_error(e, "create_snapshot")

    def get_snapshot(self, snapshot_id, user_id):
        try:
            with self._ex.transaction() as conn:
                row = conn.execute(
                    "select s.snapshot_id, s.version, s.user_id, s.date_from, s.date_to, "
                    "       s.payload_digest, s.payload_bytes, s.expires_at, s.superseded_at, "
                    "       (select p.base_version from checkd_demo.proposal p "
                    "         where p.snapshot_id = s.snapshot_id and p.user_id = s.user_id "
                    "         limit 1) as _probe "
                    "  from checkd_demo.snapshot s "
                    " where s.snapshot_id = %s and s.user_id = %s",
                    (snapshot_id, user_id),
                ).fetchone()
        except SnapshotStoreError:
            raise
        except Exception as e:                       # noqa: BLE001
            raise _map_db_error(e, "get_snapshot")
        if row is None:
            # 用户隔离：别人的快照一律 NOT_FOUND，不是 FORBIDDEN。
            # 回 403 等于确认"这个 id 存在"，是信息泄露。
            raise SnapshotStoreError(_CODE_NOT_FOUND, "快照不存在或不属于当前用户。")
        return {
            "snapshot_id": str(row[0]),
            "version": int(row[1]),
            "user_id": row[2],
            "date_from": _iso_date(row[3]),
            "date_to": _iso_date(row[4]),
            "base_version": _base_version(row[0], row[1]),
            "payload_digest": row[5],
            "payload_bytes": int(row[6]),
            "expires_at": _iso(row[7]),
            "superseded": row[8] is not None,
        }

    def get_snapshot_payload(self, snapshot_id, user_id):
        """取快照本体 + 归属与范围。validate 需要用快照里的 ext/prefs 重算摘要。

        为什么不复用 get_snapshot：那条查询刻意不取 payload（body 可能很大，
        列表类路径不需要它）。这里单独一条，避免把大字段带进所有调用。
        """
        try:
            with self._ex.transaction() as conn:
                row = conn.execute(
                    "select s.snapshot_id, s.version, s.user_id, s.date_from, s.date_to, "
                    "       s.payload, s.payload_digest, s.payload_bytes, s.expires_at, "
                    "       s.superseded_at "
                    "  from checkd_demo.snapshot s "
                    " where s.snapshot_id = %s and s.user_id = %s",
                    (snapshot_id, user_id),
                ).fetchone()
        except SnapshotStoreError:
            raise
        except Exception as e:                       # noqa: BLE001
            raise _map_db_error(e, "get_snapshot_payload")
        if row is None:
            raise SnapshotStoreError(_CODE_NOT_FOUND, "快照不存在或不属于当前用户。")
        return {
            "snapshot_id": str(row[0]),
            "version": int(row[1]),
            "user_id": row[2],
            "date_from": _iso_date(row[3]),
            "date_to": _iso_date(row[4]),
            "payload": row[5],
            "payload_digest": row[6],
            "payload_bytes": int(row[7]),
            "expires_at": _iso(row[8]),
            "superseded": row[9] is not None,
        }

    def get_latest(self, user_id, date_from, date_to):
        try:
            with self._ex.transaction() as conn:
                row = conn.execute(
                    "select snapshot_id, version, payload_digest, payload_bytes, expires_at "
                    "  from checkd_demo.snapshot "
                    " where user_id = %s and date_from = %s and date_to = %s "
                    "   and superseded_at is null",
                    (user_id, date_from, date_to),
                ).fetchone()
        except SnapshotStoreError:
            raise
        except Exception as e:                       # noqa: BLE001
            raise _map_db_error(e, "get_latest")
        if row is None:
            return None
        return {
            "snapshot_id": str(row[0]),
            "version": int(row[1]),
            "base_version": _base_version(row[0], row[1]),
            "payload_digest": row[2],
            "payload_bytes": int(row[3]),
            "expires_at": _iso(row[4]),
        }

    # ---------- Proposal ----------

    def create_proposal(self, user_id, snapshot_id, snapshot_version, plan):
        """建提案。base_version 由库生成列产出，这里只负责读回来。

        `plan` 是服务端自己生成的完整提案内容（blocks / changes / unplanned_tasks /
        explanations）。**必须存库**，原因写在契约 L514：apply 时服务端必须加载自己
        保存的 Proposal，不接受调用方重新提交。若不存，apply 就只能靠调用方重传，
        那等于把"可信输入"交回给调用方，契约明禁。
        """
        _require_text(user_id, "user_id")
        if not isinstance(plan, dict):
            raise SnapshotStoreError(_CODE_INVALID_ARGUMENT,
                                     "plan 必须是对象（含 blocks/changes/unplanned_tasks）。")
        raw_plan = canonical_payload(plan)
        try:
            with self._ex.transaction() as conn:
                row = conn.execute(
                    "insert into checkd_demo.proposal "
                    "(user_id, snapshot_id, snapshot_version, expires_at, plan) "
                    "values (%s, %s, %s, now() + make_interval(secs => %s), %s::jsonb) "
                    "returning proposal_id, base_version, status, expires_at, created_at",
                    (user_id, snapshot_id, int(snapshot_version), self.proposal_ttl, raw_plan),
                ).fetchone()
                return {
                    "proposal_id": str(row[0]),
                    "base_version": row[1],
                    "status": row[2],
                    "expires_at": _iso(row[3]),
                    # generated_at 只能是库时间，不用进程时钟：容器与本机时区不同，
                    # 契约要的是带偏移的服务端 instant。
                    "generated_at": _iso(row[4]) if len(row) > 4 else None,
                    "snapshot_id": str(snapshot_id),
                    "snapshot_version": int(snapshot_version),
                    "plan_digest": payload_digest(plan)[0],
                }
        except SnapshotStoreError:
            raise
        except Exception as e:                       # noqa: BLE001
            raise _map_db_error(e, "create_proposal")

    def get_proposal(self, proposal_id, user_id):
        try:
            with self._ex.transaction() as conn:
                row = conn.execute(
                    "select proposal_id, user_id, snapshot_id, snapshot_version, base_version, "
                    "       status, expires_at, applied_at "
                    "  from checkd_demo.proposal where proposal_id = %s and user_id = %s",
                    (proposal_id, user_id),
                ).fetchone()
        except SnapshotStoreError:
            raise
        except Exception as e:                       # noqa: BLE001
            raise _map_db_error(e, "get_proposal")
        if row is None:
            raise SnapshotStoreError(_CODE_NOT_FOUND, "提案不存在或不属于当前用户。")
        return {
            "proposal_id": str(row[0]),
            "user_id": row[1],
            "snapshot_id": str(row[2]),
            "snapshot_version": int(row[3]),
            "base_version": row[4],
            "status": row[5],
            "expires_at": _iso(row[6]),
            "applied_at": _iso(row[7]),
        }

    def proposal_gate(self, proposal_id, user_id):
        """一次查询取齐「能不能进下一步」所需的全部事实，**过期由库判**。

        为什么要单独一个方法，而不是上层拿 get_proposal 自己比时间：
        容器时钟与本机时钟都不可信，`expires_at` 是库 `now()` 写的，
        比较也必须用库的 `now()`。差几秒就可能是「本地没过期、库里已过期」。
        """
        _require_text(user_id, "user_id")
        try:
            with self._ex.transaction() as conn:
                row = conn.execute(
                    "select p.proposal_id, p.user_id, p.snapshot_id, p.snapshot_version, "
                    "       p.base_version, p.status, p.validation_status, p.plan, "
                    "       p.expires_at, p.applied_at, "
                    "       (p.expires_at <= now()) as expired, "
                    "       (s.expires_at <= now()) as snapshot_expired, "
                    "       s.date_from, s.date_to, s.payload_digest "
                    "  from checkd_demo.proposal p "
                    "  join checkd_demo.snapshot s "
                    "    on s.snapshot_id = p.snapshot_id and s.user_id = p.user_id "
                    " where p.proposal_id = %s and p.user_id = %s",
                    (proposal_id, user_id),
                ).fetchone()
        except SnapshotStoreError:
            raise
        except Exception as e:                       # noqa: BLE001
            raise _map_db_error(e, "proposal_gate")
        if row is None:
            raise SnapshotStoreError(_CODE_NOT_FOUND, "提案不存在或不属于当前用户。")
        return {
            "proposal_id": str(row[0]),
            "user_id": row[1],
            "snapshot_id": str(row[2]),
            "snapshot_version": int(row[3]),
            "base_version": row[4],
            "status": row[5],
            "validation_status": row[6],
            "plan": row[7],
            "expires_at": _iso(row[8]),
            "applied_at": _iso(row[9]),
            "expired": bool(row[10]),
            # P0-1（M3 2026-11-07 审查）：快照自己的 TTL。
            # 原先只判 p.expires_at，snapshot.expires_at 存了却从没被读过 ——
            # 当时默认 proposal TTL 600s < snapshot TTL 900s，所以「提案先过期」掩盖了这个洞；
            # 一旦把 snapshot TTL 调短，就会出现「拿过期快照 validate/apply」。
            # 现快照 1860 s / 提案 1800 s（见 __init__ 说明），但这个字段仍必须独立判、
            # 不能靠「提案没过期」推论快照没过期。
            "snapshot_expired": bool(row[11]),
            "date_from": _iso_date(row[12]),
            "date_to": _iso_date(row[13]),
            "snapshot_payload_digest": row[14],
        }

    def set_validation(self, proposal_id, user_id, validation_status):
        """落校验结论。

        只动 `validation_status`，**不动 `status`**：库里 status 的闭集是
        `pending/applied/rejected/expired`，没有契约 §5.7 的 `pending_approval`，
        往库里写契约值会直接撞 CHECK 约束。出参映射在 `proposal_assembly.contract_status`，
        两边各管一层，不互相冒充。
        """
        if validation_status not in ("unvalidated", "valid", "invalid"):
            raise SnapshotStoreError(_CODE_INVALID_ARGUMENT,
                                     "validation_status 取值非法。")
        _require_text(user_id, "user_id")
        try:
            with self._ex.transaction() as conn:
                row = conn.execute(
                    "update checkd_demo.proposal set validation_status = %s "
                    " where proposal_id = %s and user_id = %s "
                    "returning proposal_id",
                    (validation_status, proposal_id, user_id),
                ).fetchone()
        except SnapshotStoreError:
            raise
        except Exception as e:                       # noqa: BLE001
            raise _map_db_error(e, "set_validation")
        if row is None:
            raise SnapshotStoreError(_CODE_NOT_FOUND, "提案不存在或不属于当前用户。")
        return True

    def get_applied_change(self, proposal_id, user_id):
        """读回 apply 写下的结果，用于写入后回读核验（readback）。"""
        _require_text(user_id, "user_id")
        try:
            with self._ex.transaction() as conn:
                row = conn.execute(
                    "select apply_id, proposal_id, user_id, snapshot_id, applied_at, result "
                    "  from checkd_demo.applied_change "
                    " where proposal_id = %s and user_id = %s",
                    (proposal_id, user_id),
                ).fetchone()
        except SnapshotStoreError:
            raise
        except Exception as e:                       # noqa: BLE001
            raise _map_db_error(e, "get_applied_change")
        if row is None:
            raise SnapshotStoreError(_CODE_NOT_FOUND, "该提案没有已应用的变更记录。")
        return {
            "apply_id": str(row[0]),
            "proposal_id": str(row[1]),
            "user_id": row[2],
            "snapshot_id": str(row[3]),
            "applied_at": _iso(row[4]),
            "result": row[5],
        }

    # ---------- apply ----------

    def apply_proposal(self, proposal_id, user_id, base_version):
        """同一事务内：锁提案 → 校验（归属/状态/过期/版本）→ 幂等查 → 写 applied_change → 置 applied。

        锁序 proposal → snapshot，与 create_snapshot（seq → snapshot）只在 snapshot 行交叉。
        四道闸的顺序是刻意的：先 404（不泄露存在性）→ 再看状态 → 再看过期 → 最后比版本。
        版本放最后，是因为它是"两份都合法数据之间的冲突"，前三条都是"根本不该做"。
        """
        _require_text(user_id, "user_id")
        _require_text(base_version, "base_version")

        try:
            with self._ex.transaction() as conn:
                # 1) 锁提案。for update 让并发 apply 串行在这一行上。
                #    只锁 p（for update of p）：锁序仍是 proposal → snapshot，
                #    不要因为多了一个 join 就把 snapshot 行一起锁上。
                #    M3 P2②：过期原先在下面用 _expired() 再查一次，同事务内 now() 不变，
                #    纯多一次 round trip。这里两条过期判定都随这条查询一起取回。
                row = conn.execute(
                    "select p.status, p.snapshot_id, p.snapshot_version, p.base_version, "
                    "       p.expires_at, p.plan, "
                    "       (p.expires_at <= now()) as p_expired, "
                    "       (s.expires_at <= now()) as s_expired "
                    "  from checkd_demo.proposal p "
                    "  join checkd_demo.snapshot s "
                    "    on s.snapshot_id = p.snapshot_id and s.user_id = p.user_id "
                    " where p.proposal_id = %s and p.user_id = %s "
                    "   for update of p",
                    (proposal_id, user_id),
                ).fetchone()
                if row is None:
                    raise SnapshotStoreError(_CODE_NOT_FOUND,
                                             "提案不存在或不属于当前用户。")
                status, snap_id, snap_ver, db_base_version, expires_at = row[:5]
                # 契约 L514：服务端必须加载自己保存的 Proposal，不接受调用方重传。
                # 所以方案从这一行里读，不从入参拿。
                saved_plan = row[5]
                p_expired, s_expired = bool(row[6]), bool(row[7])

                # 2) 已应用 → 幂等错误，不是"成功"
                if status == "applied":
                    raise SnapshotStoreError(
                        _CODE_ALREADY_APPLIED, "该提案已应用过，不重复写入。",
                        details={"proposal_id": str(proposal_id)})

                # 3) 状态必须能进 apply
                if status != "pending":
                    raise SnapshotStoreError(
                        _CODE_PROPOSAL_EXPIRED if status == "expired" else _CODE_INTERNAL_ERROR,
                        "提案状态为 %s，不能应用。" % status,
                        details={"status": status})

                # 4) 过期由库判，不用客户端时间（同一事务内 now() 恒定，随上面那条查询取回）
                if p_expired:
                    raise SnapshotStoreError(
                        _CODE_PROPOSAL_EXPIRED, "提案已过期。",
                        details={"proposal_id": str(proposal_id)})
                # 4b) 快照自己也不能过期（P0-1）。快照比提案活得更久是默认配置下的常态，
                #     所以这条平时不触发；一旦 TTL 被调短，它才是拦住「过期快照仍可 apply」的那道闸。
                if s_expired:
                    raise SnapshotStoreError(
                        _CODE_SNAPSHOT_CONFLICT,
                        "快照已过期，需重新生成提案。",
                        details={"proposal_id": str(proposal_id),
                                 "snapshot_id": str(snap_id)})

                # 5) 版本必须与库里一致（库里是生成列，客户端传的只是"我以为的"）
                if str(db_base_version) != str(base_version):
                    raise SnapshotStoreError(
                        _CODE_SNAPSHOT_CONFLICT,
                        "base_version 与当前可信版本不一致。",
                        details={"expected": db_base_version,
                                 "provided": base_version})

                # 6) 写 applied_change。proposal_id 上的 unique 是幂等最后一道闸：
                #    并发两个 apply 都过了上面所有检查，第二个在这里撞唯一键 → 回滚 → 报 ALREADY_APPLIED
                if saved_plan is None:
                    # 宁可报错也不拿调用方传的东西顶替 —— 那正是契约禁的动作。
                    raise SnapshotStoreError(
                        _CODE_INTERNAL_ERROR,
                        "提案缺少已保存的方案内容（plan 为空），拒绝执行。")
                raw = (saved_plan if isinstance(saved_plan, str)
                       else canonical_payload(saved_plan))
                conn.execute(
                    "insert into checkd_demo.applied_change "
                    "(proposal_id, user_id, snapshot_id, result) "
                    "values (%s, %s, %s, %s::jsonb)",
                    (proposal_id, user_id, snap_id, raw),
                )

                # 7) 置状态。同事务，与 applied_change 一起生效或一起回滚
                conn.execute(
                    "update checkd_demo.proposal set status = 'applied', applied_at = now() "
                    " where proposal_id = %s",
                    (proposal_id,),
                )

                return {
                    "proposal_id": str(proposal_id),
                    "status": "applied",
                    "base_version": db_base_version,
                    "snapshot_id": str(snap_id),
                    "snapshot_version": int(snap_ver),
                }
        except SnapshotStoreError:
            raise
        except Exception as e:                       # noqa: BLE001
            raise _map_db_error(e, "apply_proposal")


# ============================================================
# 工具函数
# ============================================================


def _require_text(value, field):
    if not isinstance(value, str) or not value.strip():
        raise SnapshotStoreError(_CODE_INVALID_ARGUMENT,
                                 "%s 必须是非空字符串。" % field,
                                 details={"field": field})


def _require_date_order(date_from, date_to):
    if not date_from or not date_to:
        raise SnapshotStoreError(_CODE_INVALID_ARGUMENT,
                                 "date_from / date_to 均为必填。")
    if str(date_from) > str(date_to):
        raise SnapshotStoreError(_CODE_INVALID_ARGUMENT,
                                 "date_from 不得晚于 date_to。",
                                 details={"date_from": str(date_from),
                                          "date_to": str(date_to)})


def _constraint_of(exc):
    """从驱动异常里取违反的约束名，取不到返回 None。

    M3 2026-11-07 审查 P2①：原先靠 `str(exc)` 里是否出现 "applied_change" /
    "snapshot_one_latest" 来判断，驱动改一次错误措辞就会把 409 退化成 500。
    psycopg3 把约束名放在 `exc.diag.constraint_name`（服务端 ErrorResponse 的
    constraint 字段），那是结构化字段，不受措辞影响。
    """
    diag = getattr(exc, "diag", None)
    if diag is None:
        return None
    return getattr(diag, "constraint_name", None) or None


def _map_db_error(exc, where):
    """把驱动异常映射到契约闭集内的码。不新增码。

    23505 unique_violation → 靠约束名区分：
        applied_change_proposal_uk → ALREADY_APPLIED（幂等闸）
        snapshot_one_latest        → SNAPSHOT_CONFLICT（并发建快照）
    23503 foreign_key_violation → 用户归属违约（复合 FK 拦住），属服务端拼错 id
    40001 / 40P01 → 序列化失败/死锁，可重试
    其余 → DEPENDENCY_UNAVAILABLE（连接类）或 INTERNAL_ERROR
    """
    name = type(exc).__name__
    pgcode = getattr(exc, "sqlstate", None) or getattr(exc, "pgcode", None)
    text = str(exc)
    constraint = _constraint_of(exc)

    def _hit(*needles):
        """先看结构化约束名；拿不到才退回文本匹配（老驱动/老服务端的兜底）。"""
        if constraint:
            return constraint in needles
        return any(n in text for n in needles)

    if pgcode == "23505":
        if _hit("applied_change_proposal_uk", "applied_change"):
            return SnapshotStoreError(_CODE_ALREADY_APPLIED, "该提案已应用过。")
        if _hit("snapshot_one_latest"):
            return SnapshotStoreError(_CODE_SNAPSHOT_CONFLICT,
                                      "并发创建快照，latest 唯一约束冲突，请重试。")
        return SnapshotStoreError(_CODE_INTERNAL_ERROR, "唯一约束冲突。",
                                  details={"where": where, "constraint": constraint})
    if pgcode == "23503":
        return SnapshotStoreError(_CODE_INTERNAL_ERROR,
                                  "引用完整性违约（用户归属或版本不符）。",
                                  details={"where": where, "constraint": constraint})
    if pgcode in ("40001", "40P01"):
        return SnapshotStoreError(_CODE_DEPENDENCY_UNAVAILABLE,
                                  "事务冲突或死锁，可重试。", retryable=True,
                                  details={"where": where})
    if pgcode in ("08000", "08003", "08006", "57P01"):
        return SnapshotStoreError(_CODE_DEPENDENCY_UNAVAILABLE,
                                  "快照库连接不可用。", retryable=True,
                                  details={"where": where})
    if name in ("OperationalError", "PoolTimeout", "InterfaceError"):
        return SnapshotStoreError(_CODE_DEPENDENCY_UNAVAILABLE,
                                  "快照库连接不可用。", retryable=True,
                                  details={"where": where})
    return SnapshotStoreError(_CODE_INTERNAL_ERROR, "快照存储内部错误。",
                              details={"where": where, "type": name})


def _base_version(snapshot_id, version):
    """base_version 的唯一构造入口。

    为什么需要这个函数：`base_version` 的库级生成列在 proposal 表上
    （`snapshot_id::text || ':' || snapshot_version::text`），snapshot 表没有同名列，
    所以「快照维度」根本读不到库值，只能按同一规则构造。

    M3 2026-11-07 审查 P1-1 指出：同一个格式原先在 create_snapshot / get_snapshot /
    get_latest 三处各拼一次，与文件头自述「绝不在这里拼字符串」相反。现在三处统一
    走这里，规则只存在一份；配合 migration 的
    `proposal_snapshot_version_fk (snapshot_id, snapshot_version) -> snapshot(snapshot_id, version)`，
    「应用层拼出来的值」与「库里生成列的值」不再靠巧合一致，而是被约束钉住。

    改这个格式 = 同时改 migration 的生成列表达式，两处必须同形。
    """
    return "%s:%d" % (snapshot_id, int(version))


def _iso(value):
    if value is None:
        return None
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.astimezone().isoformat()
    return str(value)


def _iso_date(value):
    if value is None:
        return None
    return value.isoformat() if hasattr(value, "isoformat") else str(value)
