#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""preflight_snapshot_db.py 只读模式的可执行断言。

对应 2026-11-07 M0 阻断件：旧版默认路径会 INSERT/DELETE，而邮件写的是「只读」。
这里不靠文档声称，靠可跑的断言：

  T1 语句守卫：写语句一律拒绝，只读语句一律放行，不误伤子串
  T2 RO_SQL 全表过守卫（模块里声明的每条只读查询都真的能过）
  T3 静态审计：源码里 `conn.execute(...)` 只允许出现在三个函数内
     （behavior_tests / apply_migration / prove_read_only），
     其余路径必须走 ro_exec —— 也就是说默认模式不存在写语句路径
  T4 进程级：不带 --i-have-m0-approval 时 --apply / --behavior-tests 一律 exit 3
  T5 进程级：无 DSN 时 exit 2 + BLOCKED，不出任何 PASS

只用标准库 unittest。

Run（仓库根）:
    python -m unittest discover -s tools/m1-server/tests -v
或:
    python tools/m1-server/tests/test_preflight_readonly.py
"""

import ast
import os
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.dirname(HERE)
SRC_FILE = os.path.join(SRC_DIR, "preflight_snapshot_db.py")

sys.path.insert(0, SRC_DIR)

import preflight_snapshot_db as pf  # noqa: E402

# 唯一允许直接 conn.execute 的函数：写路径 + 只读自证探针 + 守卫自身
WRITE_FUNCS = {"behavior_tests", "apply_migration", "prove_read_only", "ro_exec"}


class TestGuard(unittest.TestCase):
    def test_rejects_writes(self):
        bad = [
            "insert into checkd_demo.snapshot values (1)",
            "  INSERT INTO t VALUES (1)",
            "update checkd_demo.proposal set status='x'",
            "delete from checkd_demo.snapshot where user_id like 'preflight-%'",
            "create temp table t(x int)",
            "alter table t add column y int",
            "drop table t",
            "truncate t",
            "grant select on t to r",
            "copy t from stdin",
            "do $$ begin end $$",
            "set default_transaction_read_only = off",
            "with x as (delete from t returning *) select * from x",
            "/* hi */ insert into t values (1)",
            "",
        ]
        for sql in bad:
            ok, why = pf.is_read_only_sql(sql)
            self.assertFalse(ok, "应当拒绝：%r" % sql)
            self.assertTrue(why, "拒绝必须给原因：%r" % sql)

    def test_allows_reads(self):
        good = [
            "select 1",
            "  SELECT current_database()",
            "select current_setting('default_transaction_read_only')",
            "select has_table_privilege(%s, %s, %s)",
            "show default_transaction_read_only",
            "explain select 1",
            "with x as (select 1) select * from x",
            "select table_name from information_schema.tables where table_schema = %s",
        ]
        for sql in good:
            ok, why = pf.is_read_only_sql(sql)
            self.assertTrue(ok, "应当放行：%r（被拒原因 %s）" % (sql, why))

    def test_no_substring_false_positive(self):
        for sql in ("select current_setting('x')",
                    "select updated_at from t",
                    "select offset from t",
                    "select * from domains"):
            ok, why = pf.is_read_only_sql(sql)
            self.assertTrue(ok, "误拒：%r（%s）" % (sql, why))


class TestDeclaredQueries(unittest.TestCase):
    def test_all_ro_sql_pass_guard(self):
        self.assertTrue(pf.RO_SQL, "RO_SQL 不能为空")
        for name, sql in pf.RO_SQL.items():
            ok, why = pf.is_read_only_sql(sql)
            self.assertTrue(ok, "RO_SQL[%r] 过不了守卫：%s | %r" % (name, why, sql))

    def test_ro_exec_never_touches_connection_on_write(self):
        class Boom:
            called = 0

            def execute(self, *a, **k):
                Boom.called += 1
                raise AssertionError("守卫失效：写语句被送进数据库")

        with self.assertRaises(pf.ReadOnlyViolation):
            pf.ro_exec(Boom(), "delete from checkd_demo.snapshot")
        self.assertEqual(Boom.called, 0, "被拒语句不得触达连接对象")


class TestStaticAudit(unittest.TestCase):
    def test_no_conn_execute_outside_write_functions(self):
        tree = ast.parse(open(SRC_FILE, encoding="utf-8").read(), filename=SRC_FILE)
        offenders = []

        class V(ast.NodeVisitor):
            def __init__(self):
                self.stack = []

            def visit_FunctionDef(self, node):
                self.stack.append(node.name)
                self.generic_visit(node)
                self.stack.pop()

            def visit_Call(self, node):
                f = node.func
                if (isinstance(f, ast.Attribute) and f.attr == "execute"
                        and self.stack and self.stack[-1] not in WRITE_FUNCS):
                    offenders.append("%s() L%d" % (self.stack[-1], node.lineno))
                self.generic_visit(node)

        V().visit(tree)
        self.assertFalse(
            offenders,
            "这些函数在只读路径上直接调了 conn.execute，必须改走 ro_exec：%s"
            % offenders)

    def test_approval_gate_precedes_write_calls(self):
        src = open(SRC_FILE, encoding="utf-8").read()
        gate = src.index("if writes and not args.i_have_m0_approval")
        # 用 rindex：取调用处，不是 def 定义处
        self.assertLess(gate, src.rindex("            apply_migration(conn)"),
                        "approval 闸必须在 apply_migration 之前")
        self.assertLess(gate, src.rindex("                behavior_tests(conn)"),
                        "approval 闸必须在 behavior_tests 之前")

    def test_only_readonly_flag_adds_readonly_option(self):
        src = open(SRC_FILE, encoding="utf-8").read()
        self.assertIn("default_transaction_read_only=on", src)
        self.assertIn("if not writes:", src,
                      "只读连接选项必须受 writes 控制，写模式不能带上它")


class TestOutputPath(unittest.TestCase):
    """N1（M0 2026-11-07）：结果路径必须唯一、可预测，不随 cwd 或环境变。

    旧版先找 work/m1，找不到回退 cwd —— 同一脚本两个出口，M0 执行前不知道去哪取文件。
    """

    def test_default_out_is_fixed_repo_root(self):
        out = pf.default_out().replace("\\", "/")
        self.assertTrue(out.endswith("/preflight_snapshot_db_result.json"), out)
        self.assertNotIn("/work/m1/", out,
                         "不允许再按环境分叉出第二套路径（N1）")
        # 仓库根 = 含 tools/m1-server 的那一级
        repo_root = out.rsplit("/", 1)[0]
        self.assertTrue(os.path.isdir(os.path.join(repo_root, "tools", "m1-server")),
                        "结果文件必须落在仓库根：%s" % repo_root)

    def test_default_out_does_not_depend_on_cwd(self):
        before = pf.default_out()
        cwd = os.getcwd()
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            try:
                os.chdir(d)
                self.assertEqual(pf.default_out(), before,
                                 "换工作目录后结果路径变了，M0 就无法预测去哪取文件")
            finally:
                os.chdir(cwd)

    def test_gitignored(self):
        """M2 2026-11-07 P1：忽略规则必须真的作用到默认输出路径。

        旧断言只读 `tools/m1-server/.gitignore` 的文本就判绿 —— 但默认输出落在**仓库根**，
        git 的忽略匹配是「从文件所在目录向上」，子目录里的规则管不到仓库根的文件。
        那条断言因此是假绿：测试绿，跑一次 preflight 仍然脏工作区。
        现在改用 git 本人的判定（`git check-ignore`），并要求生效规则来自**仓库根**的 .gitignore。
        """
        out = pf.default_out()
        repo_root = os.path.dirname(out)
        name = os.path.basename(out)
        try:
            p = subprocess.run(["git", "-C", repo_root, "check-ignore", "-v", name],
                               capture_output=True, text=True)
        except (OSError, FileNotFoundError):
            self.skipTest("本机没有 git，无法验证真实忽略状态")
        if p.returncode not in (0, 1):
            self.skipTest("git check-ignore 不可用：%s" % (p.stderr or "").strip()[:200])
        self.assertEqual(
            p.returncode, 0,
            "默认输出文件未被 git 忽略，跑一次就脏工作区：%s" % out)
        src = p.stdout.split(":", 1)[0].strip()
        src_abs = src if os.path.isabs(src) else os.path.join(repo_root, src)
        self.assertEqual(
            os.path.normcase(os.path.abspath(src_abs)),
            os.path.normcase(os.path.abspath(os.path.join(repo_root, ".gitignore"))),
            "生效的忽略规则必须来自仓库根 .gitignore，实际来自：%s" % src)

    def test_default_out_independent_of_cwd(self):
        """N1（M0 2026-11-07）：结果路径不得随 cwd 变。

        旧版找不到 work/m1 就回退 os.getcwd()，同一个脚本换个目录跑就写到别处，
        与邮件承诺的路径不一致。这里把 cwd 换到临时目录，结果必须一模一样。
        """
        here = pf.default_out()
        old = os.getcwd()
        tmp = tempfile.mkdtemp(prefix="pf-cwd-")
        try:
            os.chdir(tmp)
            self.assertEqual(pf.default_out(), here,
                             "default_out() 跟随了 cwd，N1 未修复")
        finally:
            os.chdir(old)

    def test_no_cleanup_write_in_probe(self):
        """N3：只读探针失败后不得再执行任何清理写（旧版会 drop 掉探针表）。"""
        src = open(SRC_FILE, encoding="utf-8").read()
        fn = src[src.index("def prove_read_only"):]
        fn = fn[:fn.index("\ndef ", 1)] if "\ndef " in fn[1:] else fn
        self.assertNotIn("drop table", fn.lower(),
                         "prove_read_only 里出现了清理写（N3 回归）")

    def test_blocked_path_skips_schema_checks(self):
        """N2：只读证明失败要真的停，不是只记一行日志。"""
        src = open(SRC_FILE, encoding="utf-8").read()
        self.assertIn("if blocked:", src, "缺少 blocked 分支，N2 未修复")
        blocked_at = src.index("if blocked:")
        self.assertLess(blocked_at, src.rindex("check_schema(conn)"),
                        "check_schema 必须在 blocked 分支之后（即被跳过）")
        self.assertIn("return 4", src, "只读阻断必须用独立退出码 4")


class TestProcessBehaviour(unittest.TestCase):
    @staticmethod
    def _run(*argv):
        env = dict(os.environ)
        for k in ("CHECKD_DEMO_DSN", "DATABASE_URL"):
            env.pop(k, None)
        env["PYTHONIOENCODING"] = "utf-8"
        return subprocess.run([sys.executable, SRC_FILE] + list(argv),
                              capture_output=True, text=True, encoding="utf-8",
                              errors="replace", env=env, timeout=60)

    def test_refuse_apply_without_approval(self):
        r = self._run("--apply")
        self.assertEqual(r.returncode, 3, r.stdout + r.stderr)
        self.assertIn("REFUSED", r.stdout)

    def test_refuse_behavior_tests_without_approval(self):
        r = self._run("--behavior-tests")
        self.assertEqual(r.returncode, 3, r.stdout + r.stderr)
        self.assertIn("REFUSED", r.stdout)

    def test_blocked_without_dsn(self):
        r = self._run()
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertIn("BLOCKED", r.stdout)
        self.assertNotIn("合计", r.stdout, "没有库时不得出现汇总行，即没有任何检查结果")
        self.assertIsNone(re.search(r"\sPASS\s{2}", r.stdout),
                          "没有库时不得出现任何 PASS 条目")

    def test_modes_mutually_exclusive(self):
        r = self._run("--apply", "--behavior-tests", "--i-have-m0-approval")
        self.assertNotEqual(r.returncode, 0)
        low = (r.stderr + r.stdout).lower()
        self.assertTrue("not allowed" in low or "mutually exclusive" in low, low)


class _Diag(object):
    def __init__(self, sqlstate):
        self.sqlstate = sqlstate


class _FakeError(Exception):
    """够像 psycopg 异常的假件：只带 diag.sqlstate 和消息。"""

    def __init__(self, sqlstate=None, msg="boom"):
        Exception.__init__(self, msg)
        self.diag = _Diag(sqlstate)


class TestReadOnlyProof(unittest.TestCase):
    """P2（M2 2026-11-07 提出 / M3 同日附议）：只有 25006 算证据。

    旧判据 `st in (None, "25006") or "read-only" in msg` 会把断连、代理改写、
    权限错（42501）都记成「只读已生效」，等于用「未发现只读未生效」冒充
    「证明只读生效」。这里逐条钉住 fail-closed 行为。
    """

    def test_25006_is_proof(self):
        self.assertTrue(pf._rejection_proves_read_only(_FakeError("25006")))

    def test_no_sqlstate_is_not_proof(self):
        self.assertFalse(pf._rejection_proves_read_only(_FakeError(None)))
        self.assertFalse(pf._rejection_proves_read_only(
            Exception("server closed the connection unexpectedly")))

    def test_other_sqlstate_is_not_proof(self):
        self.assertFalse(pf._rejection_proves_read_only(_FakeError("42501")))

    def test_read_only_wording_alone_is_not_proof(self):
        """消息里带 read-only 但没 sqlstate —— 可能是代理改写，不算证据。"""
        self.assertFalse(pf._rejection_proves_read_only(
            _FakeError(None, "cannot execute CREATE TABLE in a read-only transaction")))
        self.assertFalse(pf._rejection_proves_read_only(
            _FakeError(None, "当前事务是只读的")))

    def test_source_has_no_permissive_fallback(self):
        src = open(SRC_FILE, encoding="utf-8").read()
        self.assertNotIn('st in (None, "25006")', src, "旧的宽松判据还在，P2 未修")


if __name__ == "__main__":
    unittest.main(verbosity=2)
