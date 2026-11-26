"""Stage 04 migration 的权限静态检查。

为什么需要这个：2026-11-26 M0 在 PR #22 审查中发现，冻结契约写着
「behavior_events 只给 SELECT、事件只能走 append_behavior_event()」，
但 0001 migration 里仍然 `grant select, insert ... to authenticated` 且建了 insert 策略。
文档说一套、SQL 做一套——这类不一致没有任何运行时测试能发现（表还没建），只能靠静态检查。

本文件不连数据库，纯文本解析 migration，断言的是**源码级约束**。
真实库里权限是否真的生效，仍需执行后用 authenticated 角色实测（见 G2_ACCEPTANCE.md §六）。

跑法：python -m unittest test_migration_permissions -v
"""

import re
import unittest
from pathlib import Path

MIGRATIONS = Path(__file__).resolve().parents[2] / "supabase" / "migrations"

GUARDED_TABLES = ("behavior_events", "preference_profiles")
WRITE_PRIVS = ("insert", "update", "delete", "truncate", "references", "trigger")


def read_sql(name_glob: str) -> str:
    files = sorted(MIGRATIONS.glob(name_glob))
    if not files:
        raise FileNotFoundError(f"no migration matched {name_glob} under {MIGRATIONS}")
    return "\n".join(f.read_text(encoding="utf-8") for f in files)


def strip_comments(sql: str) -> str:
    """去掉 -- 行注释，避免注释里的示例语句被当成真语句。"""
    return "\n".join(line.split("--", 1)[0] for line in sql.splitlines())


def parse_grants(sql: str) -> list[tuple[str, str, str]]:
    """返回 [(privs, table, roles)]。"""
    return re.findall(
        r"grant\s+([a-z]+(?:\s*,\s*[a-z]+)*)\s+on\s+public\.(\w+)\s+to\s+([a-z]+(?:\s*,\s*[a-z]+)*)",
        sql,
        flags=re.I,
    )


def parse_policies(sql: str) -> list[tuple[str, str, str]]:
    """返回 [(policy_name, table, command)]。"""
    return re.findall(
        r"create\s+policy\s+(\w+)\s+on\s+public\.(\w+)\s+for\s+(select|insert|update|delete)",
        sql,
        flags=re.I,
    )


def write_privs_for(sql: str, table: str, role: str = "authenticated") -> set[str]:
    """某个角色在某张表上拿到的写权限集合；空集 = 正确。"""
    out: set[str] = set()
    for privs, t, roles in parse_grants(sql):
        if t.lower() != table or role not in roles.lower():
            continue
        out |= {p.strip().lower() for p in privs.split(",")} & set(WRITE_PRIVS)
    return out


def non_select_policies_for(sql: str, table: str) -> list[tuple[str, str]]:
    return [(n, c) for n, t, c in parse_policies(sql)
            if t.lower() == table and c.lower() != "select"]


class TestCheckerItself(unittest.TestCase):
    """反向验证：检查器必须能抓出已知的坏样本，否则「全绿」毫无意义。"""

    BAD_GRANT = "grant select, insert on public.behavior_events to authenticated;"
    BAD_POLICY = ("create policy behavior_events_owner_insert on public.behavior_events "
                  "for insert to authenticated with check (auth.uid() = user_id);")

    def test_detects_table_level_insert_grant(self):
        self.assertEqual(write_privs_for(self.BAD_GRANT, "behavior_events"), {"insert"})

    def test_detects_write_policy(self):
        self.assertEqual(non_select_policies_for(self.BAD_POLICY, "behavior_events"),
                         [("behavior_events_owner_insert", "insert")])

    def test_ignores_harmless_select_only(self):
        clean = "grant select on public.behavior_events to authenticated;"
        self.assertEqual(write_privs_for(clean, "behavior_events"), set())
        self.assertEqual(non_select_policies_for(clean, "behavior_events"), [])

    def test_drop_policy_alone_is_not_a_policy(self):
        """只写 drop policy 是清理动作，不能被算成在建策略。"""
        sql = "drop policy if exists behavior_events_owner_insert on public.behavior_events;"
        self.assertEqual(non_select_policies_for(sql, "behavior_events"), [])


class TestNoClientWritePrivilege(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = strip_comments(read_sql("20261126*_stage04_*.sql"))
        cls.grants = parse_grants(cls.sql)

    def test_grants_were_found(self):
        """先确认正则真的抓到了东西，否则后面全绿也没有意义。"""
        tables = {t for _, t, _ in self.grants}
        for table in GUARDED_TABLES:
            self.assertIn(table, tables, f"{table} 上没有任何 grant 语句被解析到")

    def test_no_write_privilege_on_guarded_tables(self):
        """authenticated 不得拿到任何表级写权限。"""
        for table in GUARDED_TABLES:
            bad = write_privs_for(self.sql, table)
            self.assertFalse(bad, f"{table} 对 authenticated 授了写权限 {bad}")

    def test_select_is_granted(self):
        """只读必须可用，否则 RLS 策略没有意义。"""
        for table in GUARDED_TABLES:
            ok = any(
                table == t and "select" in {p.strip().lower() for p in privs.split(",")}
                and "authenticated" in roles.lower()
                for privs, t, roles in self.grants
            )
            self.assertTrue(ok, f"{table} 没有把 SELECT 授给 authenticated")


class TestNoWritePolicy(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = strip_comments(read_sql("20261126*_stage04_*.sql"))
        cls.policies = parse_policies(cls.sql)

    def test_policies_were_found(self):
        self.assertTrue(self.policies, "没有解析到任何 create policy")

    def test_only_select_policies_exist(self):
        """写策略与收回表级写权限是矛盾的：留着会让人以为能直写。"""
        for name, table, cmd in self.policies:
            self.assertIn(cmd.lower(), ("select",),
                          f"{table} 上仍有 {cmd} 策略 {name}")

    def test_stale_write_policies_are_dropped(self):
        """迁移必须能清理历史上建过的写策略，保证可重跑且不留残。"""
        for table in GUARDED_TABLES:
            pat = rf"drop\s+policy\s+if\s+exists\s+\w+\s+on\s+public\.{table}"
            self.assertRegex(self.sql, pat,
                             f"{table} 缺少 drop policy if exists 清理语句")


class TestFunctionHardening(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = strip_comments(read_sql("20261126*_stage04_*.sql"))
        # 每个函数的完整文本（含签名，因为 security definer / search_path 写在签名里）
        cls.functions = []
        for m in re.finditer(r"create\s+or\s+replace\s+function\s+(public\.\w+)\s*\(",
                             cls.sql, flags=re.I):
            as_pos = cls.sql.find("as $$", m.end())
            if as_pos == -1:
                continue
            end = cls.sql.find("$$;", as_pos + 4)
            if end == -1:
                continue
            cls.functions.append((m.group(1), cls.sql[m.start():end]))

    def test_functions_were_found(self):
        names = {n for n, _ in self.functions}
        for expected in ("public.append_behavior_event",
                         "public.list_behavior_events",
                         "public.checkd_context_snapshot",
                         "public.upsert_preference_profile",
                         "public.get_preference_profile"):
            self.assertIn(expected, names, f"没解析到函数 {expected}")

    def test_every_function_is_security_definer_with_empty_search_path(self):
        """definer 函数不固定 search_path，等于把函数体内的名字解析交给调用方。"""
        for name, text in self.functions:
            lowered = text.lower()
            self.assertIn("security definer", lowered, f"{name} 不是 security definer")
            self.assertIn("set search_path = ''", lowered,
                          f"{name} 没有 set search_path = ''")
            # 声明顺序：security definer 必须出现在 as $$ 之前
            self.assertLess(lowered.index("security definer"), lowered.index("as $$"),
                            f"{name} 的 security definer 位置异常")

    def test_write_functions_are_executable_only_by_authenticated(self):
        """anon / public 不得能调写函数。"""
        for func in ("append_behavior_event", "upsert_preference_profile"):
            pat = (rf"grant\s+execute\s+on\s+function\s+public\.{func}\([^)]*\)\s+to\s+([a-z]+)")
            roles = [m.lower() for m in re.findall(pat, self.sql, flags=re.I)]
            self.assertTrue(roles, f"{func} 没有 grant execute 语句")
            self.assertEqual(set(roles), {"authenticated"},
                             f"{func} 的 EXECUTE 授给了 {roles}，只应给 authenticated")

    def test_append_event_checks_task_ownership(self):
        """事件写入必须校验 task_id 归属——这正是禁止直写表的理由。"""
        body = next(t for n, t in self.functions if n == "public.append_behavior_event")
        self.assertIn("TASK_NOT_OWNED", body)
        self.assertIn("auth.uid()", body)


if __name__ == "__main__":
    unittest.main()
