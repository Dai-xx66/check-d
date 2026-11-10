#!/usr/bin/env python
"""checkd 快照库预检 —— 拿到 DSN 后一条命令出结果。

三个模式，互斥，默认是真只读：

    # 默认：只读探测。只发 SELECT/SHOW/EXPLAIN，连接层强制只读事务。
    CHECKD_DEMO_DSN="postgresql://..." python tools/m1-server/preflight_snapshot_db.py

    # 写入型行为测试（造数据 + 清理）。必须 M0 书面批准后加 flag。
    CHECKD_DEMO_DSN="..." python tools/m1-server/preflight_snapshot_db.py \
        --behavior-tests --i-have-m0-approval

    # 执行 migration R3。必须 M0 对精确执行计划书面批准。
    CHECKD_DEMO_DSN="..." python tools/m1-server/preflight_snapshot_db.py \
        --apply --i-have-m0-approval

## 只读是怎么保证的（三层，不靠文档声称）

1. **连接层**：只读模式下连接串带 `-c default_transaction_read_only=on`，
   建立连接时即生效，连超级用户也拦（PostgreSQL 的该参数对 superuser 一样生效）。
2. **语句守卫**：所有查询必须经 `ro_exec()`，它按首关键字白名单放行
   （select / with / show / explain），并拒绝含写关键字（insert/update/delete/
   create/alter/drop/grant/truncate/copy/call/do/lock/…）的语句。
   被拒即抛 ReadOnlyViolation，不会执行。
3. **实测自证**：连接后真的去 `create temp table` 一次，**必须被数据库拒绝**
   （SQLSTATE 25006 read_only_sql_transaction）。能建成功 = 只读没生效 → BLOCKED。
   只认 25006：其它异常（无 sqlstate、42501 权限错、连接断开）一律记 FAIL，
   因为它们证明不了只读生效，只能证明「这次写没成功」。

对应 2026-11-07 M0 阻断件：旧版第 3–7 节行为测试无条件执行 INSERT/DELETE，
默认命令并非只读，邮件描述与代码不一致。本版把写操作全部移入
`behavior_tests()`，且它只能由 `--behavior-tests --i-have-m0-approval` 进入。

## 退出码

| 码 | 含义 |
|---|---|
| 0 | 全部检查项无 FAIL |
| 1 | 有 FAIL 项（结果文件里有明细） |
| 2 | 拿不到库 / 缺 psycopg3 —— 不出任何 PASS |
| 3 | REFUSED：写路径缺 `--i-have-m0-approval` |
| 4 | BLOCKED：只读证明失败（连接非只读，或探针建表成功），后续检查一律未执行 |

## 结果文件路径（唯一，与 cwd 无关）

只有一处：`<仓库根>/preflight_snapshot_db_result.json`
（仓库根由本文件位置上溯确定，找同时含 `tools/` 与 `tools/m1-server/` 的目录）。
要别的路径用 `--out`。**不再按环境分叉、不回退当前目录**（M0 令 N1）。

该文件由**仓库根的 `.gitignore`** 忽略 —— 注意不是 `tools/m1-server/.gitignore`：
git 只按「文件所在目录到根」的路径匹配，忽略文件放子目录管不到仓库根的文件。
（`tools/m1-server/.gitignore` 保留，只覆盖 `--out` 指到本目录的情况。）

## 不做什么

- 不建库、不 drop 任何东西。
- 不假通过：拿不到库 → exit 2 + BLOCKED，不出任何 PASS。
- 不打印 DSN 原文（含口令），只打印 host / dbname / user。
"""

import argparse
import json
import os
import re
import sys
import uuid
from datetime import datetime, timezone

# M2 12:15 P0-1：原先 dirname(dirname(__file__)) 拼到 tools/db/…，与本文件在
# tools/m1-server/ 的实际布局不一致，--apply 直接 FileNotFoundError。
_HERE = os.path.dirname(os.path.abspath(__file__))
_CANDIDATES = [
    os.path.join(_HERE, "migrations", "0001_snapshot_r3.sql"),   # 仓库内原地
    os.path.join(_HERE, "db", "0001_snapshot_r3.sql"),           # work/m1/db 副本
    os.path.join(os.path.dirname(_HERE), "m1", "db", "0001_snapshot_r3.sql"),
]
MIGRATION = next((c for c in _CANDIDATES if os.path.exists(c)), _CANDIDATES[0])

# ---------------------------------------------------------------- 只读 SQL 清单
# 全部只读查询集中在这里，方便人工审计 + 单测逐条过守卫。
# 注意：权限名（USAGE/CREATE）走参数，不写成 SQL 字面量——否则 'create'
# 这个字面量会被语句守卫当成写语句。
RO_SQL = {
    "conn": "select current_database(), current_user, version()",
    "pid": "select pg_backend_pid()",
    "ro_flag": "select current_setting('default_transaction_read_only')",
    "tables": ("select table_name from information_schema.tables "
               " where table_schema = %s order by 1"),
    "constraints": ("select conname from pg_constraint c "
                    " join pg_namespace n on n.oid = c.connamespace "
                    " where n.nspname = %s order by 1"),
    "indexes": "select indexname from pg_indexes where schemaname = %s",
    "gencol": ("select is_generated, generation_expression "
               " from information_schema.columns "
               " where table_schema = %s and table_name = %s and column_name = %s"),
    "role_exists": "select 1 from pg_roles where rolname = %s",
    "schema_priv": "select has_schema_privilege(%s, %s, %s)",
    "table_priv": "select has_table_privilege(%s, %s, %s)",
}

_ALLOWED_PREFIX = ("select", "with", "show", "explain", "values", "table")
_WRITE_WORDS = (
    "insert", "update", "delete", "merge", "truncate", "create", "alter",
    "drop", "grant", "revoke", "copy", "call", "do", "vacuum", "analyze",
    "refresh", "comment", "lock", "prepare", "execute", "set", "reset",
    "discard", "reindex", "cluster", "listen", "notify",
)


class ReadOnlyViolation(RuntimeError):
    """只读模式下试图执行写语句。"""


def is_read_only_sql(sql):
    """判断一条 SQL 是否只读。保守：宁可误拒，不可误放。"""
    head = (sql or "").lstrip().lower()
    if not head.startswith(_ALLOWED_PREFIX):
        return False, "首关键字不在白名单 %s" % (_ALLOWED_PREFIX,)
    for w in _WRITE_WORDS:
        if re.search(r"\b%s\b" % w, head):
            return False, "含写关键字 %r" % w
    return True, ""


def ro_exec(conn, sql, params=None):
    """只读执行的唯一入口。守卫不通过就抛异常，绝不执行。"""
    ok, why = is_read_only_sql(sql)
    if not ok:
        raise ReadOnlyViolation("%s | sql=%r" % (why, sql[:120]))
    if params is None:
        return conn.execute(sql)
    return conn.execute(sql, params)


RESULTS = []


def rec(name, ok, detail="", skipped=False):
    status = "SKIP" if skipped else ("PASS" if ok else "FAIL")
    RESULTS.append({"check": name, "status": status, "ok": bool(ok) and not skipped,
                    "detail": str(detail)[:400]})
    print("  %-46s %-4s  %s" % (name, status, str(detail)[:110]))


def safe_dsn(dsn):
    """只暴露 host / dbname / user，绝不打印口令。"""
    # 口令里可能含 @（M2 12:15 P2）。从右边找最后一个 @ 才是 host 分隔符。
    m = re.match(r"^([a-z+]+)://(.+)$", dsn)
    if not m:
        return {"host": "(无法解析)", "dbname": "(无法解析)"}
    rest = m.group(2)
    if "@" not in rest:
        return {"host": "(无法解析)", "dbname": "(无法解析)"}
    userinfo, hostpart = rest.rsplit("@", 1)
    user = userinfo.split(":", 1)[0]
    host = hostpart.split("/", 1)[0]
    db = hostpart.split("/", 1)[1] if "/" in hostpart else ""
    db = db.split("?", 1)[0]
    return {"host": host, "dbname": db, "user": user}


def default_out():
    """结果 JSON 的**唯一**默认路径 —— 不随当前目录变，也不随环境变（M0 令 N1）。

    固定为 `<仓库根>/preflight_snapshot_db_result.json`，其中仓库根由本文件位置
    上溯确定（找同时含 `tools/` 与 `tools/m1-server/` 的目录）。

    为什么不再"能找到 work/m1 就写那里"：那样同一个脚本在本机工作区和干净 clone
    下会写到两个位置，M0 执行前无法预测该去哪取文件 —— 这正是 N1 的原始问题，
    只把 cwd 换成"两套规则"不算修好。现在只有一处，脚本启动时就把绝对路径打出来。

    要写到别处用 `--out /path/to/file.json`。
    """
    p = _HERE
    for _ in range(8):
        if (os.path.isdir(os.path.join(p, "tools"))
                and os.path.isdir(os.path.join(p, "tools", "m1-server"))):
            return os.path.join(p, "preflight_snapshot_db_result.json")
        parent = os.path.dirname(p)
        if parent == p:
            break
        p = parent
    # 兜底：仍是脚本位置推出来的固定值，绝不回退 cwd
    return os.path.join(os.path.dirname(os.path.dirname(_HERE)),
                        "preflight_snapshot_db_result.json")


# ------------------------------------------------------------------ 只读检查


def check_connection(conn):
    """第 0 层：连接与只读自证。"""
    row = ro_exec(conn, RO_SQL["conn"]).fetchone()
    rec("连接 / 库名", True, "%s as %s" % (row[0], row[1]))
    ver = row[2].split()[1] if len(row[2].split()) > 1 else "?"
    parts = tuple(int(x) for x in re.findall(r"\d+", ver)[:2]) or (0,)
    rec("服务端版本 >= 14", (parts + (0,))[:2] >= (14, 0), ver)

    pid1 = ro_exec(conn, RO_SQL["pid"]).fetchone()[0]
    pid2 = ro_exec(conn, RO_SQL["pid"]).fetchone()[0]
    rec("连接后端稳定（非每语句换后端）", pid1 == pid2, "pid=%s/%s" % (pid1, pid2))

    flag = ro_exec(conn, RO_SQL["ro_flag"]).fetchone()[0]
    rec("连接层只读已开启（default_transaction_read_only）",
        str(flag).lower() in ("on", "true", "1"), "setting=%s" % flag)
    return str(flag).lower() in ("on", "true", "1")


def _rollback_quiet(conn):
    """静默回滚——只回滚事务，不发任何 SQL 语句。"""
    try:
        conn.rollback()
    except Exception:                                        # noqa: BLE001
        pass


def _rejection_proves_read_only(exc):
    """探针被拒这件事，够不够证明「只读真的生效」。

    P2（M2 2026-11-07 / M3 2026-11-07 附议）：只认 SQLSTATE **25006**
    （read_only_sql_transaction）。旧判据把「sqlstate 为空」和「消息里含
    read-only」也算通过——断连、代理改写、权限错（42501）都会落进来，于是把
    「未发现只读未生效」冒充成「证明只读生效」。这里一律 fail-closed：
    拿不到 25006 就记 FAIL，宁可给 M0 一条明确的失败，也不给一条虚的 PASS。
    """
    st = getattr(getattr(exc, "diag", None), "sqlstate", None)
    return st == "25006"


def prove_read_only(conn):
    """实测自证：只读事务里建临时表必须被数据库拒绝。

    这是本版的核心证据 —— 不是「文件名带 readonly」，是数据库真的拒绝了写。

    N3（M0 2026-11-07）：探针若**意外建表成功**，说明只读没生效，此时
    不得再执行任何「清理写」（旧版会 drop 掉探针表）；本版只回滚事务并把
    结论记 FAIL，由调用方立即 BLOCKED 退出。
    """
    try:
        conn.execute("begin")
        conn.execute("create temp table _checkd_ro_probe(x int)")
    except Exception as e:                                   # noqa: BLE001
        st = getattr(getattr(e, "diag", None), "sqlstate", None)
        ok = _rejection_proves_read_only(e)
        _rollback_quiet(conn)
        rec("写入实测被拒（只读真的生效）", ok,
            "sqlstate=%s %s%s" % (st, type(e).__name__,
                                  "" if ok else "（非 25006，不能证明只读生效）"))
        return ok
    # 不该走到这里：探针建表成功 = 只读未生效。只回滚，不做清理写（N3）。
    _rollback_quiet(conn)
    rec("写入实测被拒（只读真的生效）", False,
        "临时表居然建成功了——只读未生效（已回滚事务，未执行清理写）")
    return False


def check_schema(conn):
    """第 2 层：结构存在性（纯元数据查询）。"""
    tabs = [r[0] for r in ro_exec(conn, RO_SQL["tables"], ("checkd_demo",)).fetchall()]
    want_tabs = ["applied_change", "proposal", "snapshot", "snapshot_seq"]
    rec("4 张表齐全", tabs == want_tabs, ",".join(tabs) if tabs else "(schema 为空或不存在)")

    cons = [r[0] for r in ro_exec(conn, RO_SQL["constraints"], ("checkd_demo",)).fetchall()]
    # 13 条：11 条为 P0-1/P1/P2 主约束，另 2 条是 2026-11-07 追加的版本维度约束
    # （snapshot_id_version_uk + proposal_snapshot_version_fk），缺任一条 base_version
    # 都可能被传参伪造，所以这里必须逐条点名，不能只数个数。
    want = ["applied_change_proposal_fk", "applied_change_proposal_snapshot_fk",
            "applied_change_proposal_uk", "applied_change_snapshot_fk",
            "proposal_id_snapshot_uk", "proposal_id_user_uk",
            "proposal_snapshot_fk", "proposal_snapshot_version_fk",
            "proposal_ttl_ck", "snapshot_id_user_uk", "snapshot_id_version_uk",
            "snapshot_ttl_ck", "snapshot_version_uk"]
    missing = [c for c in want if c not in cons]
    rec("关键约束 13 条", not missing, "缺: %s" % missing if missing else "%d 条" % len(cons))

    idx = [r[0] for r in ro_exec(conn, RO_SQL["indexes"], ("checkd_demo",)).fetchall()]
    rec("latest 唯一索引存在", "snapshot_one_latest" in idx, ",".join(sorted(idx)) or "(无)")
    rec("冗余索引 snapshot_lookup 已删", "snapshot_lookup" not in idx, "")

    gen = ro_exec(conn, RO_SQL["gencol"],
                  ("checkd_demo", "proposal", "base_version")).fetchone()
    rec("base_version 是生成列（P1-2）",
        bool(gen) and gen[0] == "ALWAYS", (gen[1] if gen else "列不存在"))


def check_privileges(conn):
    """第 8/9 层：内置角色不该有权限（反向）；应用角色必须**有**权限（正向）。"""
    for role in ("anon", "authenticated"):
        if not ro_exec(conn, RO_SQL["role_exists"], (role,)).fetchone():
            continue
        has = ro_exec(conn, RO_SQL["schema_priv"],
                      (role, "checkd_demo", "USAGE")).fetchone()[0]
        rec("%s 无 schema usage（P2-4）" % role, not has, "has_usage=%s" % has)

    app_role = os.environ.get("CHECKD_APP_ROLE", "checkd_demo_app")
    if not ro_exec(conn, RO_SQL["role_exists"], (app_role,)).fetchone():
        rec("应用角色 %s 存在" % app_role, False,
            "角色不存在——应用连上会 permission denied")
        return
    rec("应用角色 %s 存在" % app_role, True, "")

    ok_usage = ro_exec(conn, RO_SQL["schema_priv"],
                       (app_role, "checkd_demo", "USAGE")).fetchone()[0]
    rec("应用角色有 schema usage", ok_usage, "usage=%s" % ok_usage)

    for tbl, want in (("snapshot", ("SELECT", "INSERT", "UPDATE")),
                      ("proposal", ("SELECT", "INSERT", "UPDATE")),
                      ("applied_change", ("SELECT", "INSERT")),
                      ("snapshot_seq", ("SELECT", "INSERT", "UPDATE"))):
        missing = [w for w in want if not ro_exec(
            conn, RO_SQL["table_priv"],
            (app_role, "checkd_demo." + tbl, w)).fetchone()[0]]
        rec("应用角色对 %s 有 %s" % (tbl, "/".join(want)),
            not missing, "缺: %s" % missing if missing else "齐")

    can_ddl = ro_exec(conn, RO_SQL["schema_priv"],
                      (app_role, "checkd_demo", "CREATE")).fetchone()[0]
    rec("应用角色无 create 权（最小权限）", not can_ddl, "create=%s" % can_ddl)


# ------------------------------------------------------------------ 写入路径
# 以下两个函数是全文件唯一的写操作来源，且都只能由显式 flag 进入。


def apply_migration(conn):
    """--apply：执行 migration R3，并验证幂等。需要 M0 书面批准。"""
    if not os.path.exists(MIGRATION):
        rec("migration 文件存在", False, MIGRATION)
        return
    sql = open(MIGRATION, encoding="utf-8").read()
    rec("migration 文件存在", True, "%d B" % len(sql.encode("utf-8")))
    try:
        # psycopg3 默认走 extended protocol，多语句会报
        # "cannot insert multiple commands into a prepared statement"。
        # R3 含多个语句与两个 do $$ 块，必须 prepare=False 走 simple query。
        conn.execute(sql, prepare=False)
        rec("migration R3 首次执行", True, "%d B" % len(sql.encode("utf-8")))
    except Exception as e:                                   # noqa: BLE001
        rec("migration R3 首次执行", False, "%s: %s" % (type(e).__name__, e))
        return
    try:
        conn.execute(sql, prepare=False)
        rec("migration R3 重复执行（幂等）", True, "")
    except Exception as e:                                   # noqa: BLE001
        rec("migration R3 重复执行（幂等）", False, "%s: %s" % (type(e).__name__, e))


def behavior_tests(conn):
    """--behavior-tests：唯一会写业务表的地方。造数据 → 断言被拒 → 自己清理。

    默认**不进入**。需 `--behavior-tests --i-have-m0-approval` 两条同时给。
    """
    uid = "preflight-" + uuid.uuid4().hex[:8]

    # 3 唯一索引挡住第二个 latest
    try:
        with conn.transaction():
            conn.execute("insert into checkd_demo.snapshot "
                         "(user_id,date_from,date_to,version,payload,payload_digest,"
                         " payload_bytes,expires_at) "
                         "values (%s,'2026-11-08','2026-11-10',1,'{}'::jsonb,'x',2,"
                         " now()+interval '1 hour')", (uid,))
            conn.execute("insert into checkd_demo.snapshot "
                         "(user_id,date_from,date_to,version,payload,payload_digest,"
                         " payload_bytes,expires_at) "
                         "values (%s,'2026-11-08','2026-11-10',2,'{}'::jsonb,'x',2,"
                         " now()+interval '1 hour')", (uid,))
        rec("同区间两个 latest 被拒（唯一索引生效）", False, "两条都插进去了，约束没生效")
    except Exception as e:                                   # noqa: BLE001
        ok = "snapshot_one_latest" in str(e) or "duplicate key" in str(e).lower()
        rec("同区间两个 latest 被拒（唯一索引生效）", ok, type(e).__name__)

    # 4 跨用户复合 FK
    try:
        with conn.transaction():
            sid = conn.execute(
                "insert into checkd_demo.snapshot "
                "(user_id,date_from,date_to,version,payload,payload_digest,payload_bytes,"
                " expires_at) values (%s,'2026-11-08','2026-11-10',3,'{}'::jsonb,'x',2,"
                " now()+interval '1 hour') returning snapshot_id", (uid,)).fetchone()[0]
            conn.execute("insert into checkd_demo.proposal "
                         "(user_id,snapshot_id,snapshot_version,expires_at) "
                         "values (%s,%s,3, now()+interval '10 min')",
                         ("preflight-other-" + uuid.uuid4().hex[:6], sid))
        rec("跨用户 proposal 指向他人 snapshot 被拒", False, "插进去了，P0-1 未生效")
    except Exception as e:                                   # noqa: BLE001
        ok = "23503" in str(e) or "foreign key" in str(e).lower()
        rec("跨用户 proposal 指向他人 snapshot 被拒", ok, type(e).__name__)

    # 5 applied_change 指向不一致被拒（R3 新增 P1）
    try:
        with conn.transaction():
            s1 = conn.execute(
                "insert into checkd_demo.snapshot (user_id,date_from,date_to,version,"
                " payload,payload_digest,payload_bytes,expires_at) values "
                "(%s,'2026-11-08','2026-11-10',4,'{}'::jsonb,'x',2,"
                " now()+interval '1 hour') returning snapshot_id", (uid,)).fetchone()[0]
            s2 = conn.execute(
                "insert into checkd_demo.snapshot (user_id,date_from,date_to,version,"
                " payload,payload_digest,payload_bytes,expires_at) values "
                "(%s,'2026-11-08','2026-11-10',5,'{}'::jsonb,'x',2,"
                " now()+interval '1 hour') returning snapshot_id", (uid,)).fetchone()[0]
            p = conn.execute(
                "insert into checkd_demo.proposal "
                "(user_id,snapshot_id,snapshot_version,expires_at) "
                "values (%s,%s,4, now()+interval '10 min') returning proposal_id",
                (uid, s1)).fetchone()[0]
            conn.execute("insert into checkd_demo.applied_change "
                         "(proposal_id,user_id,snapshot_id,result) "
                         "values (%s,%s,%s,'{}'::jsonb)", (p, uid, s2))
        rec("apply 记录与提案快照不一致被拒（R3 P1）", False, "插进去了，R3 未生效")
    except Exception as e:                                   # noqa: BLE001
        ok = "23503" in str(e) or "foreign key" in str(e).lower()
        rec("apply 记录与提案快照不一致被拒（R3 P1）", ok, type(e).__name__)

    # 6 TTL 早于创建被拒
    try:
        with conn.transaction():
            conn.execute(
                "insert into checkd_demo.snapshot (user_id,date_from,date_to,version,"
                " payload,payload_digest,payload_bytes,expires_at) values "
                "(%s,'2026-11-08','2026-11-10',9,'{}'::jsonb,'x',2, now()-interval '1 min')",
                (uid,))
        rec("TTL 早于 created_at 被拒（P2-1）", False, "插进去了，约束没生效")
    except Exception as e:                                   # noqa: BLE001
        ok = "snapshot_ttl_ck" in str(e) or "check constraint" in str(e).lower()
        rec("TTL 早于 created_at 被拒（P2-1）", ok, type(e).__name__)

    # 7 清理自己造的数据
    with conn.transaction():
        conn.execute("delete from checkd_demo.applied_change where user_id like 'preflight-%'")
        conn.execute("delete from checkd_demo.proposal where user_id like 'preflight-%'")
        conn.execute("delete from checkd_demo.snapshot where user_id like 'preflight-%'")
        left = conn.execute(
            "select (select count(*) from checkd_demo.snapshot where user_id like 'preflight-%')"
            "     + (select count(*) from checkd_demo.proposal where user_id like 'preflight-%')"
        ).fetchone()[0]
    rec("预检数据已清理", left == 0, "残留 %s 行" % left)


# ---------------------------------------------------------------------- main


def main():
    ap = argparse.ArgumentParser(
        description="checkd 快照库预检（默认只读；写操作必须显式授权）")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--behavior-tests", action="store_true",
                      help="跑写入型行为测试（造数据+清理）。需 --i-have-m0-approval")
    mode.add_argument("--apply", action="store_true",
                      help="执行 migration R3。需 --i-have-m0-approval")
    ap.add_argument("--i-have-m0-approval", action="store_true",
                    help="M0 已书面批准该写操作时才加")
    ap.add_argument("--out", default=None, help="结果 JSON 路径")
    args = ap.parse_args()

    writes = args.apply or args.behavior_tests

    # 硬闸：任何写路径都必须先拿到 M0 书面批准。
    if writes and not args.i_have_m0_approval:
        what = "--apply（DDL）" if args.apply else "--behavior-tests（INSERT/DELETE）"
        print("REFUSED: %s 会写库。" % what)
        print("         M0 2026-11-07 阻断件要求：书面批准前不得执行任何写入。")
        print("         获批后加 --i-have-m0-approval 再跑；只读探测请去掉该参数。")
        return 3

    # 固定结果路径（M0 令 N1）：与 cwd 无关，先算好并打印，跑完就知道去哪找。
    out = args.out or default_out()

    dsn = os.environ.get("CHECKD_DEMO_DSN") or os.environ.get("DATABASE_URL")
    if not dsn:
        print("BLOCKED: 未提供 CHECKD_DEMO_DSN。没有库就不出任何 PASS。")
        print("         mac/Linux: export CHECKD_DEMO_DSN='postgresql://...'")
        print("         Windows  : set CHECKD_DEMO_DSN=postgresql://...")
        return 2

    try:
        import psycopg
    except ImportError:
        print("BLOCKED: 缺 psycopg3。安装：python -m pip install 'psycopg[binary]'")
        return 2

    info = safe_dsn(dsn)
    print("目标库: host=%s dbname=%s user=%s" % (info["host"], info["dbname"],
                                                 info.get("user", "")))
    print("模式: %s" % ("APPLY(写)" if args.apply else
                       "BEHAVIOR-TESTS(写)" if args.behavior_tests else "READ-ONLY"))
    print("结果文件: %s" % os.path.abspath(out))

    # 只读模式：连接建立时就把 default_transaction_read_only 打开。
    # 放在 options 里而不是连上后 SET —— 少一个「先写后读」的窗口。
    opts = "-c statement_timeout=8000 -c lock_timeout=5000"
    if not writes:
        opts += " -c default_transaction_read_only=on"

    try:
        conn = psycopg.connect(dsn, connect_timeout=8, prepare_threshold=None,
                               application_name="checkd-preflight-ro" if not writes
                               else "checkd-preflight-w",
                               options=opts)
    except Exception as e:                                   # noqa: BLE001
        print("BLOCKED: 连不上库：%s: %s" % (type(e).__name__, e))
        return 2

    ro_proof = {}
    blocked = None
    try:
        with conn:
            conn.autocommit = True

            if args.apply:
                apply_migration(conn)

            ro_on = check_connection(conn)
            if writes:
                rec("只读自证（写模式跳过）", True, "写模式不做只读断言", skipped=True)
                ro_proof = {"applicable": False}
            elif not ro_on:
                # N2（M0 2026-11-07）：旧版只记一句「停止后续检查」却继续往下跑。
                # 本版真的停：不执行 check_schema / check_privileges，直接 BLOCKED。
                rec("只读自证", False,
                    "连接未处于只读 → 立即 BLOCKED，schema/权限检查不执行")
                ro_proof = {"applicable": True, "conn_setting": "off"}
                blocked = "连接层只读未生效（default_transaction_read_only 非 on）"
            else:
                proved = prove_read_only(conn)
                ro_proof = {"applicable": True, "conn_setting": "on",
                            "write_probe_refused": bool(proved)}
                if not proved:
                    blocked = "只读写入探针未被拒绝（临时表建成功）"

            if blocked:
                rec("只读阻断", False,
                    "BLOCKED：%s；后续 schema/权限/行为检查一律未执行" % blocked)
            else:
                check_schema(conn)
                check_privileges(conn)

                if args.behavior_tests:
                    behavior_tests(conn)
                else:
                    rec("写入型行为测试（唯一索引/FK/TTL 实拍）", True,
                        "未执行：需 --behavior-tests --i-have-m0-approval（默认跳过）",
                        skipped=True)

    finally:
        try:
            conn.close()
        except Exception:                                    # noqa: BLE001
            pass

    passed = sum(1 for r in RESULTS if r["status"] == "PASS")
    failed = sum(1 for r in RESULTS if r["status"] == "FAIL")
    skipped = sum(1 for r in RESULTS if r["status"] == "SKIP")

    print("\n合计 PASS %d / FAIL %d / SKIP %d（共 %d 项）"
          % (passed, failed, skipped, len(RESULTS)))

    try:
        os.makedirs(os.path.dirname(out), exist_ok=True)
    except Exception:                                        # noqa: BLE001
        pass
    payload = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "mode": "apply" if args.apply else
                "behavior-tests" if args.behavior_tests else "read-only",
        "out_path": os.path.abspath(out),
        "target": info,
        "read_only_proof": ro_proof,
        "write_statements_allowed": bool(writes),
        "blocked": blocked,
        "passed": passed, "failed": failed, "skipped": skipped, "total": len(RESULTS),
        "results": RESULTS,
    }
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("结果已写入 %s" % os.path.abspath(out))

    # 只读证明失败 = 立即 BLOCKED 退出（M0 令 N2），不与「有 FAIL 项」混用同一个码。
    if blocked:
        print("BLOCKED: %s" % blocked)
        print("         后续 schema / 权限 / 行为检查未执行；本文件不含它们的结论。")
        return 4
    if failed:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
