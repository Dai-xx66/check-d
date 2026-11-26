#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""静态校验：REAL-READ 用到的每一列，都必须在 Supabase migration 里真实存在。

为什么要有这个文件
------------------
`test_real_read.py` 用的是假 PostgREST，它**不校验列名**。
所以「列名写错」这类错误在 270 个测试全绿的情况下也照旧存在，
一到真实库上就是 400（`column xxx does not exist`），
表现却是「整个 list_tasks 失败」，很容易被误诊成权限或令牌问题。

真实案例（2026-11-09 发现）：`task_schedules` 表建表时就没有 `deleted_at` 列，
但查询里带了 `deleted_at=is.null`。静态核对一次就抓到了。

这个文件不连网、不需要凭证，纯读仓库里的 SQL 文件。
"""

import glob
import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
# 同目录下要导入 test_real_end_to_end 的夹具；两种跑法（`discover -s tests` 与
# `python -m unittest tests.xxx`）下 top_level 不同，所以把 tests 目录本身也放进路径。
sys.path.insert(0, HERE)

import real_read as rr  # noqa: E402


REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
MIGRATION_GLOB = os.path.join(REPO_ROOT, "supabase", "migrations", "*.sql")


# --------------------------------------------------------------------------
# 从 migration 里抽表结构（不做完整 SQL 解析，只覆盖本仓库实际用到的写法）
# --------------------------------------------------------------------------

_CREATE_RE = re.compile(
    r"create\s+table\s+(?:if\s+not\s+exists\s+)?public\.(\w+)\s*\((.*?)\n\);",
    re.S | re.I,
)
_ALTER_RE = re.compile(
    r"alter\s+table\s+(?:if\s+exists\s+)?public\.(\w+)\s+([\s\S]{0,600}?);",
    re.I,
)
_ADD_COL_RE = re.compile(
    r"add\s+column\s+(?:if\s+not\s+exists\s+)?(\w+)", re.I
)
_NOT_A_COLUMN = {
    "constraint", "check", "unique", "primary", "foreign", "exclude", "like",
}


def load_table_columns():
    """返回 {表名: {列名, ...}}，合并 create table 与后续 add column。"""
    cols = {}
    for path in sorted(glob.glob(MIGRATION_GLOB)):
        with open(path, encoding="utf-8") as fh:
            sql = fh.read()

        for m in _CREATE_RE.finditer(sql):
            table, body = m.group(1), m.group(2)
            bucket = cols.setdefault(table, set())
            for raw in body.split("\n"):
                line = raw.strip()
                if not line or line.startswith("--"):
                    continue
                token = line.split()[0].strip(",")
                if token.lower() in _NOT_A_COLUMN:
                    continue
                if re.fullmatch(r"[a-z_][a-z0-9_]*", token):
                    bucket.add(token)

        for m in _ALTER_RE.finditer(sql):
            table, body = m.group(1), m.group(2)
            bucket = cols.setdefault(table, set())
            for mm in _ADD_COL_RE.finditer(body):
                bucket.add(mm.group(1))

    return cols


# --------------------------------------------------------------------------
# 被测清单
# --------------------------------------------------------------------------
# 第一项是 real_read 里的列白名单常量；
# 第二项是查询里额外出现在 filters 中的列（例如 `deleted_at=is.null`、`status=in.`）。
# **改 real_read 的 filters，必须同步改这里**，否则这个测试就失去了守门作用。

QUERIED = {
    "tasks": (rr.TASK_COLUMNS, ("status", "deleted_at")),
    "one_time_reminders": (rr.TASK_REMINDER_COLUMNS, ()),
    "long_term_tasks": (rr.TASK_LONG_TERM_COLUMNS, ()),
    "task_schedules": (rr.TASK_SCHEDULE_COLUMNS, ()),
    "courses": (rr.COURSE_COLUMNS, ("deleted_at",)),
    "course_schedule_rules": (rr.COURSE_RULE_COLUMNS, ("deleted_at",)),
    "daily_item_overrides": (rr.OVERRIDE_COLUMNS, ("deleted_at",)),
    "semesters": (rr.SEMESTER_COLUMNS, ("deleted_at",)),
}


class SchemaColumnsExist(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not glob.glob(MIGRATION_GLOB):
            raise unittest.SkipTest(
                "仓库里没有 supabase/migrations，跳过静态列校验（不是失败）。"
            )
        cls.schema = load_table_columns()

    def test_schema_parsed_all_tables(self):
        """自检：migration 里应当能解析出 28 张表（数量变了说明解析或迁移有变动）。"""
        self.assertGreaterEqual(
            len(self.schema), 20,
            "只解析出 %d 张表，SQL 写法可能变了，先修解析再信结论" % len(self.schema),
        )

    def test_every_queried_table_exists(self):
        for table in QUERIED:
            with self.subTest(table=table):
                self.assertIn(table, self.schema, "表 %s 在 migration 里不存在" % table)

    def test_whitelist_columns_exist(self):
        """列白名单里的每一列都必须真实存在。"""
        for table, (columns, _filters) in QUERIED.items():
            have = self.schema.get(table, set())
            for col in columns:
                with self.subTest(table=table, column=col):
                    self.assertIn(
                        col, have,
                        "%s.%s 不存在（白名单写错，真实库会 400）" % (table, col),
                    )

    def test_filter_columns_exist(self):
        """filters 里用到的列（如 deleted_at）也必须真实存在。

        这就是 `task_schedules` 那个 bug 的守门点：
        该表没有 deleted_at，一旦有人再给它加上 `deleted_at=is.null`，
        必须同步改 QUERIED，而改了这里就会红。
        """
        for table, (_columns, filter_columns) in QUERIED.items():
            have = self.schema.get(table, set())
            for col in filter_columns:
                with self.subTest(table=table, column=col):
                    self.assertIn(
                        col, have,
                        "%s 用 %s 过滤，但该表没有这一列" % (table, col),
                    )

    def test_task_schedules_has_no_deleted_at(self):
        """反向断言：把「task_schedules 没有软删除列」这个事实本身钉住。

        它不是风格问题——带 `deleted_at=is.null` 会让整条 list_tasks 挂掉。
        哪天表结构真加了这一列，这个测试会红，提醒把过滤加回来。
        """
        self.assertNotIn("deleted_at", self.schema.get("task_schedules", set()))


class FixturesUseRealColumnNames(unittest.TestCase):
    """端到端测试用的构造行，必须只用**真实列名**。

    M0 2026-11-10 要求「至少完成真实结构 fixtures 的端到端无凭证测试」。
    「真实结构」不能靠我口头保证——这份测试把它变成可核的：
    逐字段断言 fixture 的每个键都在 migration 里存在。

    注意区分两件事：
    - 本测试证明 **fixture 的字段名与真实 schema 一致**；
    - 它**不证明** fixture 的行内容是真实数据。行内容是手写构造的，
      真实读取仍然只能由 M0 配短期授权后单独验证。
    """

    @classmethod
    def setUpClass(cls):
        if not glob.glob(MIGRATION_GLOB):
            raise unittest.SkipTest("仓库里没有 supabase/migrations，跳过。")
        cls.schema = load_table_columns()

    def test_every_fixture_field_is_a_real_column(self):
        import test_real_end_to_end as e2e

        checked = 0
        for table, rows in e2e._ROUTE.items():
            have = self.schema.get(table, set())
            self.assertTrue(have, "表 %s 不在 migration 里" % table)
            for row in rows:
                for key in row:
                    checked += 1
                    with self.subTest(table=table, field=key):
                        self.assertIn(
                            key, have,
                            "fixture 字段 %s.%s 不是真实列名（真实库会 400）"
                            % (table, key),
                        )
        # 夹具被清空时不要让这个测试变成空转
        self.assertGreater(checked, 40, "只核了 %d 个字段，夹具可能被清空了" % checked)

    def test_fixtures_cover_the_tables_this_layer_reads(self):
        """夹具必须覆盖本层真正读的七张表，否则端到端测的是半条链路。"""
        import test_real_end_to_end as e2e

        self.assertEqual(
            set(e2e._ROUTE), set(QUERIED),
            "夹具覆盖的表与本层实际查询的表不一致",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
