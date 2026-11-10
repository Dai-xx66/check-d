#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""snapshot_store 逻辑单测（无库环境）。

## 这组测试能证明什么、不能证明什么

能证明：
- 发给库的语句文本与参数正确（单语句发号、无 select max+1、supersede 在 insert 之前）
- 事务边界正确（成功提交、失败回滚）
- 错误映射正确（23505/23503/连接类 → 契约闭集内的码，不新造码）
- 入参校验与用户隔离（别人的 id 一律 NOT_FOUND，不回 403）

**不能证明**：
- PostgreSQL 是否接受这些 SQL
- 唯一索引/复合外键在真实并发下是否真的拦住
- 持久化是否真的落盘

所以本文件全绿时，真实持久化仍标 BLOCKED（M0 §一.4）。
层级标注：LOCAL-LOGIC（非持久化）。

跑法：
    cd work/repo/check-d
    python -m unittest discover -s tools/m1-server/tests -v
"""

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))

import snapshot_store as ss  # noqa: E402


def _store(replies=None, fail_with=None):
    ex = ss.RecordingExecutor(replies=replies, fail_with=fail_with)
    return ss.SnapshotStore(executor=ex), ex


class TestPayloadDigest(unittest.TestCase):
    def test_digest_ignores_key_order(self):
        """规范化后键序无关，否则同一份数据换个写法就是另一个摘要。"""
        a = {"b": 1, "a": 2}
        b = {"a": 2, "b": 1}
        da, na = ss.payload_digest(a)
        db, nb = ss.payload_digest(b)
        self.assertEqual(da, db)
        self.assertEqual(na, nb)

    def test_digest_differs_on_value(self):
        da, _ = ss.payload_digest({"a": 1})
        db, _ = ss.payload_digest({"a": 2})
        self.assertNotEqual(da, db)

    def test_payload_bytes_is_utf8_length(self):
        _, n = ss.payload_digest({"k": "中文"})
        self.assertEqual(n, len('{"k":"中文"}'.encode("utf-8")))


class TestCreateSnapshot(unittest.TestCase):
    def test_version_sql_is_single_statement_no_select_max(self):
        """发号必须是单语句 ON CONFLICT，禁止 select max+1。"""
        store, ex = _store(replies=[[(1,)], [(None,)], [("uuid-1", "2026-11-07T12:00:00+08:00")]])
        store.create_snapshot("u1", "2026-11-07", "2026-11-20", {"tasks": []})
        first_sql = ex.statements[0][0].lower()
        self.assertIn("on conflict", first_sql)
        self.assertIn("returning next_version - 1", first_sql)
        self.assertNotIn("max(", first_sql)
        self.assertNotIn("max (", first_sql)

    def test_supersede_runs_before_insert(self):
        """顺序必须是：发号 → 旧 latest 置 superseded → 插新行。顺序错了会同时存在两个 latest。"""
        store, ex = _store(replies=[[(1,)], [(None,)], [("uuid-1", "2026-11-07T12:00:00+08:00")]])
        store.create_snapshot("u1", "2026-11-07", "2026-11-20", {"tasks": []})
        s0, s1, s2 = [x[0].lower() for x in ex.statements[:3]]
        self.assertIn("snapshot_seq", s0)
        self.assertIn("update checkd_demo.snapshot", s1)
        self.assertIn("superseded_at = now()", s1)
        self.assertIn("insert into checkd_demo.snapshot", s2)

    def test_ttl_passed_as_seconds_not_timestamp(self):
        """expires_at 由库 now() 算，客户端只传秒数——不采信客户端时钟。"""
        store, ex = _store(replies=[[(1,)], [(None,)], [("uuid-1", "2026-11-07T12:00:00+08:00")]])
        store.create_snapshot("u1", "2026-11-07", "2026-11-20", {"a": 1})
        insert_sql, insert_params = ex.statements[2]
        self.assertIn("now() + make_interval", insert_sql)
        self.assertIn(store.snapshot_ttl, insert_params)

    def test_rejects_reversed_date_range(self):
        store, ex = _store()
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            store.create_snapshot("u1", "2026-11-20", "2026-11-07", {})
        self.assertEqual(ctx.exception.code, "INVALID_ARGUMENT")
        self.assertEqual(ex.statements, [], "参数非法时不该打库")

    def test_rejects_empty_user(self):
        store, ex = _store()
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            store.create_snapshot("  ", "2026-11-07", "2026-11-20", {})
        self.assertEqual(ctx.exception.code, "INVALID_ARGUMENT")
        self.assertEqual(ex.statements, [])

    def test_returns_base_version_from_snapshot_and_version(self):
        store, ex = _store(replies=[[(3,)], [(None,)], [("snap-abc", "2026-11-07T12:00:00+08:00")]])
        out = store.create_snapshot("u1", "2026-11-07", "2026-11-20", {"a": 1})
        self.assertEqual(out["version"], 3)
        self.assertEqual(out["base_version"], "snap-abc:3")


class TestUserIsolation(unittest.TestCase):
    def test_other_users_snapshot_is_not_found_not_forbidden(self):
        """别人的 id 一律 404。回 403 等于确认"这个 id 存在"，是信息泄露。"""
        store, ex = _store(replies=[[]])
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            store.get_snapshot("snap-x", "someone-else")
        self.assertEqual(ctx.exception.code, "NOT_FOUND")

    def test_query_filters_by_user_id(self):
        store, ex = _store(replies=[[]])
        with self.assertRaises(ss.SnapshotStoreError):
            store.get_snapshot("snap-x", "u2")
        sql, params = ex.statements[0]
        self.assertIn("user_id = %s", sql)
        self.assertIn("u2", params)


class TestApplyProposal(unittest.TestCase):
    def _apply(self, replies, base_version="snap-1:2"):
        store, ex = _store(replies=replies)
        return store, ex, store.apply_proposal("prop-1", "u1", base_version)

    def test_already_applied_is_error_not_success(self):
        """已应用要报 ALREADY_APPLIED，不能当成功返回——重复写会污染结果。"""
        store, ex = _store(replies=[[("applied", "snap-1", 2, "snap-1:2", None, None, False, False)]])
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            store.apply_proposal("prop-1", "u1", "snap-1:2")
        self.assertEqual(ctx.exception.code, "ALREADY_APPLIED")
        self.assertEqual(ex.rollbacks, 1)
        self.assertEqual(ex.commits, 0)

    def test_version_mismatch_is_snapshot_conflict(self):
        store, ex = _store(replies=[[("pending", "snap-1", 2, "snap-1:3", None, None, False, False)]])
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            store.apply_proposal("prop-1", "u1", "snap-1:2")
        self.assertEqual(ctx.exception.code, "SNAPSHOT_CONFLICT")
        self.assertEqual(ex.rollbacks, 1)

    def test_expired_proposal_is_proposal_expired(self):
        store, ex = _store(replies=[
            [("pending", "snap-1", 2, "snap-1:2", None, {"blocks": []}, True, False)]])
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            store.apply_proposal("prop-1", "u1", "snap-1:2")
        self.assertEqual(ctx.exception.code, "PROPOSAL_EXPIRED")

    def test_expiry_checked_by_database_not_client(self):
        """过期判据必须是库的 now()，不是客户端传的时间。"""
        store, ex = _store(replies=[
            [("pending", "snap-1", 2, "snap-1:2", None, {"blocks": []}, False, False)]])
        store.apply_proposal("prop-1", "u1", "snap-1:2")
        head_sql = ex.statements[0][0].lower()
        self.assertIn("expires_at <= now()", head_sql)
        self.assertEqual(len([x for x in ex.statements if "expires_at <= now()" in x[0].lower()]), 1,
                         "过期判定应随首条查询一次取回，不能再单发一条（M3 P2②）")

    def test_proposal_locks_row_for_update(self):
        store, ex = _store(replies=[
            [("pending", "snap-1", 2, "snap-1:2", None, {"blocks": []}, False, False)]])
        store.apply_proposal("prop-1", "u1", "snap-1:2")
        lock_sql = ex.statements[0][0].lower()
        self.assertIn("for update", lock_sql)
        self.assertIn("for update of p", lock_sql,
                      "多 join 了 snapshot，锁必须显式限定在 proposal 行（锁序不能变）")

    def test_success_writes_applied_change_then_updates_status(self):
        store, ex = _store(replies=[
            [("pending", "snap-1", 2, "snap-1:2", None,
              {"blocks": [1], "changes": [2]}, False, False)],
            [],
            [],
        ])
        out = store.apply_proposal("prop-1", "u1", "snap-1:2")
        self.assertEqual(out["status"], "applied")
        self.assertEqual(ex.commits, 1)
        self.assertEqual(ex.rollbacks, 0)
        kinds = [s[0].lower() for s in ex.statements]
        self.assertIn("insert into checkd_demo.applied_change", kinds[1])
        self.assertIn("update checkd_demo.proposal set status = 'applied'", kinds[2])

    def test_missing_plan_refuses_instead_of_using_caller_input(self):
        """库里没有 plan 时必须拒，不能拿调用方的东西顶替（契约 L514）。"""
        store, ex = _store(replies=[
            [("pending", "snap-1", 2, "snap-1:2", None, None, False, False)],  # plan 为 NULL
        ])
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            store.apply_proposal("prop-1", "u1", "snap-1:2")
        self.assertEqual(ctx.exception.code, "INTERNAL_ERROR")
        kinds = [x[0].lower() for x in ex.statements]
        self.assertFalse(any("insert into checkd_demo.applied_change" in k for k in kinds),
                         "plan 缺失时不能写 applied_change")
        self.assertEqual(ex.commits, 0)

    def test_applied_record_uses_saved_plan(self):
        """写进 applied_change 的必须是库里的 plan，不是任何外部入参。"""
        saved = {"blocks": [{"task_id": "t_1"}], "changes": [], "unplanned_tasks": []}
        store, ex = _store(replies=[
            [("pending", "snap-1", 2, "snap-1:2", None, saved, False, False)],
            [],
            [],
        ])
        store.apply_proposal("prop-1", "u1", "snap-1:2")
        insert_stmt = [x for x in ex.statements if "insert into checkd_demo.applied_change" in x[0]][0]
        self.assertIn("t_1", str(insert_stmt[1]), "落库内容应来自库里的 plan")

    def test_select_reads_plan_column(self):
        """apply 的 select 必须把 plan 一起取出来，否则上面两条都无从谈起。"""
        store, ex = _store(replies=[
            [("pending", "snap-1", 2, "snap-1:2", None, {"blocks": []}, False, False)],
            [],
            [],
        ])
        store.apply_proposal("prop-1", "u1", "snap-1:2")
        head_sql = ex.statements[0][0].lower()
        self.assertIn("plan", head_sql)
        self.assertIn("for update", head_sql)

    def test_unknown_proposal_is_not_found(self):
        store, ex = _store(replies=[[]])
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            store.apply_proposal("prop-x", "u1", "snap-1:2")
        self.assertEqual(ctx.exception.code, "NOT_FOUND")
        self.assertEqual(ex.rollbacks, 1)


class TestErrorMapping(unittest.TestCase):
    class _PgErr(Exception):
        def __init__(self, sqlstate, text):
            super().__init__(text)
            self.sqlstate = sqlstate

    def test_unique_violation_on_applied_change_is_already_applied(self):
        err = ss._map_db_error(self._PgErr("23505", 'duplicate key "applied_change_proposal_key"'),
                               "apply_proposal")
        self.assertEqual(err.code, "ALREADY_APPLIED")
        self.assertFalse(err.retryable)

    def test_unique_violation_on_latest_index_is_snapshot_conflict(self):
        err = ss._map_db_error(self._PgErr("23505", 'duplicate key "snapshot_one_latest"'),
                               "create_snapshot")
        self.assertEqual(err.code, "SNAPSHOT_CONFLICT")

    def test_fk_violation_is_user_ownership_breach(self):
        err = ss._map_db_error(self._PgErr("23503", "violates foreign key"),
                               "create_proposal")
        self.assertEqual(err.code, "INTERNAL_ERROR")

    def test_connection_error_is_retryable_dependency_unavailable(self):
        err = ss._map_db_error(self._PgErr("08006", "connection failure"), "get_snapshot")
        self.assertEqual(err.code, "DEPENDENCY_UNAVAILABLE")
        self.assertTrue(err.retryable, "库抖动应可重试")

    def test_serialization_failure_is_retryable(self):
        err = ss._map_db_error(self._PgErr("40001", "could not serialize"), "apply_proposal")
        self.assertEqual(err.code, "DEPENDENCY_UNAVAILABLE")
        self.assertTrue(err.retryable)

    def test_conflict_codes_are_not_retryable(self):
        """409 三种都不可重试——重试同一份过期/冲突数据，结果不会变。"""
        for code, text in (("23505", "applied_change"), ("23505", "snapshot_one_latest")):
            err = ss._map_db_error(self._PgErr(code, text), "x")
            self.assertFalse(err.retryable, err.code)

    def test_only_known_codes(self):
        """不新造码：所有抛出的 code 必须在 errors.py 闭集内。"""
        allowed = set(ss._RETRYABLE) | {
            "SNAPSHOT_CONFLICT", "PROPOSAL_EXPIRED", "ALREADY_APPLIED",
            "INVALID_ARGUMENT", "NOT_FOUND", "INTERNAL_ERROR",
        }
        for state, text in (("23505", "applied_change"), ("23505", "snapshot_one_latest"),
                            ("23503", "fk"), ("08006", "conn"), ("40001", "ser"), ("XX000", "wtf")):
            err = ss._map_db_error(self._PgErr(state, text), "x")
            self.assertIn(err.code, allowed)


class TestProposalStoresPlan(unittest.TestCase):
    """契约 L514：apply 时服务端必须加载自己保存的 Proposal。
    所以要成立，create_proposal 必须把方案本身存进库，不能只存一个 id。"""

    def test_plan_is_persisted_not_just_referenced(self):
        # returning proposal_id, base_version, status, expires_at
        store, ex = _store(replies=[[("p-1", "s-1:3", "pending", "2026-11-07T10:00:00Z")]])
        out = store.create_proposal("u1", "s-1", 3, {"blocks": [], "changes": [], "unplanned_tasks": []})
        self.assertEqual(out["proposal_id"], "p-1")
        self.assertEqual(out["base_version"], "s-1:3")
        sql, params = ex.statements[0]
        self.assertIn("plan", sql)
        # plan 必须作为参数真正传下去，而不是写死在 SQL 里
        self.assertTrue(any("blocks" in str(p) for p in params), params)

    def test_plan_must_be_object(self):
        store, ex = _store(replies=[[("p-1", "s-1:3", "pending", "2026-11-07T10:00:00Z")]])
        for bad in (None, [], "x", 1):
            with self.assertRaises(ss.SnapshotStoreError) as ctx:
                store.create_proposal("u1", "s-1", 3, bad)
            self.assertEqual(ctx.exception.code, "INVALID_ARGUMENT")
        self.assertEqual(ex.statements, [], "参数不合法时不应该真的发 SQL")

    def test_plan_digest_ignores_key_order(self):
        store, ex = _store(replies=[[("p-1", "s-1:3", "pending", "2026-11-07T10:00:00Z")]])
        a = store.create_proposal("u1", "s-1", 3, {"blocks": [1], "changes": []})
        store2, ex2 = _store(replies=[[("p-1", "s-1:3", "pending", "2026-11-07T10:00:00Z")]])
        b = store2.create_proposal("u1", "s-1", 3, {"changes": [], "blocks": [1]})
        self.assertEqual(a["plan_digest"], b["plan_digest"])
        # 而真正不同的内容必须给出不同摘要，别把 digest 写成常量
        store3, _ = _store(replies=[[("p-1", "s-1:3", "pending", "2026-11-07T10:00:00Z")]])
        c = store3.create_proposal("u1", "s-1", 3, {"blocks": [2], "changes": []})
        self.assertNotEqual(a["plan_digest"], c["plan_digest"])


class TestTransactionSemantics(unittest.TestCase):
    def test_failure_rolls_back_and_does_not_commit(self):
        store, ex = _store(replies=[[(1,)], [(None,)], [("s", "e")]], fail_with=1)
        with self.assertRaises(ss.SnapshotStoreError):
            store.create_snapshot("u1", "2026-11-07", "2026-11-20", {})
        self.assertEqual(ex.commits, 0)
        self.assertGreaterEqual(ex.rollbacks, 1)



class TestSnapshotTTLInStore(unittest.TestCase):
    """P0-1：快照 TTL 是库里真实存的一列，必须在 store 层就判，不能指望上层记得判。

    两个入口：
      proposal_gate()  —— validate / request_approval 都从它取事实
      apply_proposal() —— 唯一写路径，自己也要闸一遍（绕过 tools 直接调 store 也拦得住）
    """

    def test_proposal_gate_selects_snapshot_expiry(self):
        row = ("prop-1", "u1", "snap-1", 2, "snap-1:2", "pending", "valid",
               {"blocks": []}, None, None, False, True, "2026-11-08", "2026-11-10", "dg")
        store, ex = _store(replies=[[row]])
        gate = store.proposal_gate("prop-1", "u1")
        sql = ex.statements[0][0].lower()
        self.assertIn("s.expires_at <= now()", sql,
                      "proposal_gate 必须把快照 TTL 一起判回来")
        self.assertTrue(gate["snapshot_expired"])
        self.assertFalse(gate["expired"], "两条 TTL 是独立字段，不能互相顶替")
        self.assertEqual(gate["date_from"], "2026-11-08")

    def test_apply_refuses_when_snapshot_expired(self):
        store, ex = _store(replies=[
            [("pending", "snap-1", 2, "snap-1:2", None, {"blocks": []}, False, True)]])
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            store.apply_proposal("prop-1", "u1", "snap-1:2")
        self.assertEqual(ctx.exception.code, "SNAPSHOT_CONFLICT")
        self.assertEqual(ex.commits, 0, "快照过期时不得提交任何写入")
        self.assertEqual(ex.rollbacks, 1)

    def test_apply_proposal_expiry_takes_precedence_over_snapshot(self):
        """两个都过期报 PROPOSAL_EXPIRED（提案先死），顺序稳定才好断言。"""
        store, ex = _store(replies=[
            [("pending", "snap-1", 2, "snap-1:2", None, {"blocks": []}, True, True)]])
        with self.assertRaises(ss.SnapshotStoreError) as ctx:
            store.apply_proposal("prop-1", "u1", "snap-1:2")
        self.assertEqual(ctx.exception.code, "PROPOSAL_EXPIRED")


class TestConstraintNameMapping(unittest.TestCase):
    """P2①：错误映射不能靠错误文案，要用 exc.diag.constraint_name。"""

    class _Err(Exception):
        def __init__(self, sqlstate, constraint=None, text="dup"):
            super().__init__(text)
            self.sqlstate = sqlstate

            class D:
                constraint_name = constraint
            self.diag = D()

    def test_uses_constraint_name_not_message_text(self):
        # 文案里故意不含 applied_change 字样，只有结构化约束名能认出来
        err = ss._map_db_error(
            self._Err("23505", "applied_change_proposal_uk", "duplicate key value"), "x")
        self.assertEqual(err.code, "ALREADY_APPLIED")

    def test_message_wording_change_does_not_degrade_to_500(self):
        err = ss._map_db_error(
            self._Err("23505", "snapshot_one_latest", "重新表述过的错误文案"), "x")
        self.assertEqual(err.code, "SNAPSHOT_CONFLICT",
                         "驱动改措辞不该把 409 退化成 500")

    def test_falls_back_to_text_when_diag_missing(self):
        class NoDiag(Exception):
            def __init__(self, sqlstate, text):
                super().__init__(text)
                self.sqlstate = sqlstate

        err = ss._map_db_error(NoDiag("23505", 'duplicate key "snapshot_one_latest"'), "x")
        self.assertEqual(err.code, "SNAPSHOT_CONFLICT")


class TestBaseVersionSingleSource(unittest.TestCase):
    """P1-1：base_version 的格式只许存在一个函数里。"""

    def test_format_matches_generated_column(self):
        self.assertEqual(ss._base_version("snap-1", 2), "snap-1:2")
        self.assertEqual(ss._base_version("11111111-1111-1111-1111-111111111111", 7),
                         "11111111-1111-1111-1111-111111111111:7")

    def test_no_inline_format_left_in_module(self):
        src = open(os.path.join(HERE, "..", "snapshot_store.py"), encoding="utf-8").read()
        # 全文件这个格式只许出现一次（就是 _base_version 里那行）。
        # 数出现次数，比"排除某几个函数"更难绕过。
        hits = [ln.strip() for ln in src.splitlines() if '"%s:%d"' in ln]
        self.assertEqual(len(hits), 1,
                         "base_version 格式必须只存在一处，实际 %d 处：%s" % (len(hits), hits))


class TestTTLContract(unittest.TestCase):
    """契约 L344-345 / L423：Proposal 固定有效 30 分钟，服务端不得延长。

    旧默认 600 s 把契约的 30 分钟砍成 10 分钟，且是「悄悄砍」——库里写进去的
    expires_at 比契约允许的早 20 分钟，调用方按契约算的时间再来会拿到
    PROPOSAL_EXPIRED。这类参数默认值没有任何测试盯着，改错了不会红，所以在这里钉住。
    """

    CONTRACT_PROPOSAL_TTL = 30 * 60

    def test_default_proposal_ttl_is_contract_30_minutes(self):
        store, _ = _store()
        self.assertEqual(store.proposal_ttl, self.CONTRACT_PROPOSAL_TTL,
                         "契约写死 30 分钟；改这个值必须先改契约")

    def test_snapshot_ttl_strictly_longer_than_proposal_ttl(self):
        """快照活得比提案短 = 契约给的权利被自家数据驳回。

        提案在 30 分钟有效期内，但绑定的快照 15 分钟就过期 → validate /
        request_approval / apply 全返回 SNAPSHOT_CONFLICT，用户拿着合规提案却走不下去。

        只判 `>=` 不够（M3 提、M2 2026-11-07T16:09Z 附议）：快照先插入、提案后插入，
        两条 `expires_at` 各由自己的 `now() + interval` 算；两值相等时，提案到期前
        那几十毫秒里「提案仍有效、快照已过期」，必现毫秒级 SNAPSHOT_CONFLICT。
        故这里要求严格长出余量，不是只要求不短。
        """
        store, ex = _store(replies=[[(1,)], [(None,)], [("uuid-1", "2026-11-07T12:00:00+08:00")]])
        margin = ss.SNAPSHOT_TTL_MARGIN_SECONDS
        self.assertEqual(store.snapshot_ttl, store.proposal_ttl + margin,
                         "快照 TTL 必须是提案 TTL + 余量")
        self.assertGreater(store.snapshot_ttl, store.proposal_ttl,
                           "两值相等会造出「提案有效但快照已过期」的毫秒窗口")
        # 余量要真的进 SQL：create_snapshot 的参数里是 1860，不是 1800。
        store.create_snapshot("u1", "2026-11-01", "2026-11-07", {"tasks": []})
        sql, params = ex.statements[-1]
        self.assertIn("now() + make_interval", sql)
        self.assertIn(store.snapshot_ttl, params)
        self.assertNotIn(store.proposal_ttl, params)

    def test_explicit_snapshot_ttl_equal_to_proposal_ttl_is_rejected(self):
        """显式把快照 TTL 设成与提案相等时必须失败，不许静默接受那个毫秒窗口。"""
        with self.assertRaises(ValueError):
            ss.SnapshotStore(
                executor=ss.RecordingExecutor(),
                snapshot_ttl_seconds=self.CONTRACT_PROPOSAL_TTL,
                proposal_ttl_seconds=self.CONTRACT_PROPOSAL_TTL)

    def test_create_proposal_passes_contract_ttl_to_sql(self):
        """默认值要真的进到 SQL 参数里，不能只停在对象属性上。"""
        store, ex = _store(replies=[[("p-1", "snap-1:1", "pending",
                                     "2026-11-07T12:30:00+08:00",
                                     "2026-11-07T12:00:00+08:00")]])
        store.create_proposal("u1", "snap-1", 1, {"blocks": [], "changes": []})
        sql, params = ex.statements[-1]
        self.assertIn("now() + make_interval", sql)
        self.assertIn(self.CONTRACT_PROPOSAL_TTL, params)


if __name__ == "__main__":
    unittest.main(verbosity=2)
