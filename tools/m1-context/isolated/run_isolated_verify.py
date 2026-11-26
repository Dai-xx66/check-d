"""在本地隔离 PostgreSQL 上复现 stage04 全部验证，输出可核的 JSON 证据。

为什么需要它：三个 migration 在正式库里一次都没执行过，而「函数创建成功」不等于
「函数能调用」——本脚本就是为了抓到后者（第一次跑就抓到一个 CTE 没投影列的真 bug）。

前提（脚本不负责起服务）：
  1. 已解压 PostgreSQL binaries（EDB 的 windows zip 即可，无需安装）
  2. 已 initdb，且 server 在 127.0.0.1:<port> 运行

起服务（单独一条命令，放脚本里会把自己阻塞）：
  <pg_bin>/pg_ctl.exe -D <data_dir> -o "-p 55432 -c listen_addresses=127.0.0.1" -l <log> start

用法：
  PG_BIN=/path/to/pgsql/bin python run_isolated_verify.py
  PG_BIN=/path/to/pgsql/bin python run_isolated_verify.py --port 55432 --keep-db

产出：
  默认写 isolated/evidence/isolated-db-verification-<yyyymmdd>.json
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent              # tools/m1-context/isolated
REPO = HERE.parents[2]                              # check-d 仓库根
MIGRATIONS = REPO / "supabase" / "migrations"
PG_BIN = Path(os.environ.get("PG_BIN", "")).expanduser()   # 必须通过 --pg-bin 或环境变量给
EVIDENCE_DIR = HERE / "evidence"

DB = "checkd_isolated"
STAGE04 = [
    "202611260001_stage04_behavior_events.sql",
    "202611260002_stage04_context_snapshot.sql",
    "202611260003_stage04_preference_profiles.sql",
]

# 期望值：(id, 说明, 输出里必须出现的片段)
EXPECTATIONS = [
    ("A", "无身份调用写函数 → AUTH_REQUIRED", "A => SQLSTATE 42501 / AUTH_REQUIRED"),
    ("B", "A 账号写事件成功 inserted=true", '"inserted": true'),
    ("C", "同 event_id 重放 → inserted=false", "C(幂等重放) =>"),
    ("D", "A 直写表被拒（表级写权限已收回）", "permission denied for table behavior_events"),
    ("E1", "B 账号读不到 A 的事件（RLS 隔离）", "E(B 看到的事件数) => 0"),
    ("E2", "A 账号能看到自己的事件", "E(A 看到的事件数) => 1"),
    ("F", "事件挂他人 task → TASK_NOT_OWNED", "F => SQLSTATE 42501 / TASK_NOT_OWNED"),
    ("G", "偏好未确认 → CONFIRMATION_REQUIRED", "CONFIRMATION_REQUIRED"),
    ("H", "偏好首次写入 data_version=1", '"data_version": 1'),
    ("I", "版本冲突 → 40001 VERSION_CONFLICT", "VERSION_CONFLICT"),
    ("J", "B 读 A 的偏好 → absent", '"status": "absent"'),
    ("L1", "周四课程只含本学期 + 无学期课", "L1 课程 => 本学期-数据结构 | 无学期-历史课"),
    ("L2", "周四任务只含工作日任务 + 无排期老任务", "L2 任务 => 工作日任务 | 无排期老任务"),
    ("L4", "空闲时段切分（3 段 / 620 分钟）", "L4 空闲 => 3 段 / 共 620 分钟"),
    ("M1", "周六任务只剩周末任务 + 无排期老任务", "M1 任务 => 周末任务 | 无排期老任务"),
    ("N", "occurrence 表存在但无覆盖 → MISSING", '"task_occurrences": "missing"'),
    ("O", "同 ID 写三次后表里仍只有 1 行", "O 行数（应为 1）=> 1"),
]


def psql(db: str, *args: str, sql: str | None = None) -> subprocess.CompletedProcess:
    cmd = [str(PG_BIN / ("psql.exe" if os.name == "nt" else "psql")), "-h", "127.0.0.1", "-p", str(PORT),
           "-U", "postgres", "-d", db, "-q", *args]
    if sql:
        cmd += ["-c", sql]
    env = {**os.environ, "PGCLIENTENCODING": "UTF8"}
    return subprocess.run(cmd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", env=env, timeout=300)


def run_file(db: str, path: Path) -> tuple[bool, str]:
    p = subprocess.run(
        [str(PG_BIN / ("psql.exe" if os.name == "nt" else "psql")), "-h", "127.0.0.1", "-p", str(PORT), "-U", "postgres",
         "-d", db, "-q", "-f", str(path)],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        env={**os.environ, "PGCLIENTENCODING": "UTF8"}, timeout=300,
    )
    ok = p.returncode == 0
    return ok, (p.stdout or "") + (p.stderr or "")


def main() -> int:
    global PORT, PG_BIN
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=55432)
    ap.add_argument("--pg-bin", default=None, help="PostgreSQL bin 目录（也可用 PG_BIN 环境变量）")
    ap.add_argument("--keep-db", action="store_true", help="保留库不重建")
    args = ap.parse_args()
    PORT = args.port
    if args.pg_bin:
        PG_BIN = Path(args.pg_bin).expanduser()

    psql_name = "psql.exe" if os.name == "nt" else "psql"
    if not PG_BIN or not (PG_BIN / psql_name).exists():
        sys.exit("找不到 psql。请用 --pg-bin 或环境变量 PG_BIN 指向 PostgreSQL 的 bin 目录，\n"
                 "例如：PG_BIN=~/pg/pgsql/bin python run_isolated_verify.py")

    probe = psql("postgres", sql="select 1")
    if probe.returncode != 0:
        sys.exit(f"连不上 127.0.0.1:{PORT}。先启动本地 server（见脚本头部说明）。")

    record: dict = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "environment": {
            "kind": "local PostgreSQL (EDB windows binaries)",
            "server": f"127.0.0.1:{PORT}",
            "database": DB,
            "is_production": False,
            "note": "不是 Supabase，也不是正式库；auth.uid() 由本地 session 变量模拟。",
        },
        "server_version": psql("postgres", "-tA", sql="select version();").stdout.strip(),
        "steps": [],
        "checks": [],
    }

    if not args.keep_db:
        psql("postgres", sql=f"drop database if exists {DB};")
        psql("postgres", sql=f"create database {DB};")
        record["steps"].append({"step": "create database", "ok": True})

    # 1) 底座
    ok, out = run_file(DB, HERE / "00_supabase_stub.sql")
    record["steps"].append({"step": "00_supabase_stub.sql", "ok": ok})
    if not ok:
        print("底座执行失败：", out[:800])
        return 1

    # 2) 既有 migration（按文件名序，只跑到 stage04 之前）
    for f in sorted(MIGRATIONS.glob("*.sql")):
        if f.name in STAGE04:
            continue
        ok, out = run_file(DB, f)
        record["steps"].append({"step": f.name, "ok": ok})
        if not ok:
            print(f"既有 migration 失败：{f.name}\n{out[:800]}")
            return 1

    # 3) 本次要验的三个
    for name in STAGE04:
        ok, out = run_file(DB, MIGRATIONS / name)
        record["steps"].append({"step": name, "ok": ok})
        if not ok:
            print(f"stage04 migration 失败：{name}\n{out[:1200]}")
            return 1

    # 4) 行为验证 + 快照验证
    combined = ""
    for script in ("02_verify.sql", "03_snapshot.sql"):
        ok, out = run_file(DB, HERE / script)
        record["steps"].append({"step": script, "ok": ok})
        combined += out

    # 5) 逐项判定
    for cid, desc, needle in EXPECTATIONS:
        record["checks"].append({
            "id": cid,
            "desc": desc,
            "pass": needle in combined,
            "evidence": needle,
        })

    passed = sum(1 for c in record["checks"] if c["pass"])
    total = len(record["checks"])
    record["summary"] = {
        "checks_passed": passed,
        "checks_total": total,
        "all_pass": passed == total,
        "migrations_executed": len([s for s in record["steps"] if s["step"].endswith(".sql")]),
    }

    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)
    out_path = EVIDENCE_DIR / f"isolated-db-verification-{datetime.now():%Y%m%d}.json"
    out_path.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"\n{passed}/{total} 项通过")
    for c in record["checks"]:
        print(("  PASS " if c["pass"] else "  FAIL ") + f"[{c['id']}] {c['desc']}")
    print(f"\n证据：{out_path}")
    return 0 if passed == total else 1


PORT = 55432

if __name__ == "__main__":
    raise SystemExit(main())
