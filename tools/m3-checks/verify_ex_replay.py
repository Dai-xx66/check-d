#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""C 侧独立复核：A 的 EX-01–EX-20 回放与 core 用例。

不复用 A 的 pass 标记，只读证据文件里的**原始响应**，用 C 自己的断言重判。
证据文件的来源由 --evidence 指定（A 的 PR 产物，或 C 本地复现的产物）。

用法：
    python tools/m3-checks/verify_ex_replay.py --evidence path/to/m1-evidence-m0-2c48579.json
    python tools/m3-checks/verify_ex_replay.py --evidence ... --examples-ref 2c48579 --json-out out.json

判定分三档：
    PASS        原始响应可读且四维吻合
    UNVERIFIABLE 证据里没有原始响应，只有 pass/note —— 不可独立复核，不采信为通过
    UNBACKED    用例外声称了某项（如「零写入」）但证据没有任何对应字段
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEFAULT_EXAMPLES_REF = "2c48579"

# §5.7 schedule_proposal 必填字段
PROPOSAL_REQUIRED = [
    "proposal_id", "snapshot_ref", "base_version", "input_digest", "status",
    "generated_at", "expires_at", "blocks", "changes", "unplanned_tasks",
    "explanations",
]
PROPOSAL_STATUS = {"draft", "pending_approval", "applying", "readback_pending",
                   "applied", "rejected", "expired", "failed"}

# C 侧断言表：只写契约有依据的期望。write_claim=True 表示该用例声称了写入次数。
CORE_ASSERT = {
    "P1": {"proposal_no_internal": True},
    "P2": {"proposal_complete": True},
    "E1": {"explanations_objects": True},
    "E2": {"envelope": True},
    "R1-1": {"code": "APPROVAL_EXPIRED", "write_claim": True},
    "R1-2": {"new_approval_id": True},
    "R1-3": {"code": "APPROVAL_EXPIRED"},
    "R1-4": {"status": "success", "readback_verified": True},
    "X1-a": {"code": "READBACK_PENDING", "detail_status": "readback_pending"},
    "X1-1": {"code": "READBACK_PENDING", "detail_status": "readback_pending"},
    "X1-2": {"code": "READBACK_PENDING", "detail_status": "readback_pending",
             "write_claim": True},
    "ORD-1": {"code": "ALREADY_APPLIED"},
    "ORD-2": {"code": "ALREADY_APPLIED"},
}

WRITE_KEYS = ("write_count", "writes", "persisted", "row_count", "rows_written",
              "applied_rows", "db_writes", "write_evidence")


def load_examples(ref: str) -> list[dict]:
    txt = subprocess.run(
        ["git", "show", "%s:docs/contracts/agent-api-v1.examples.json" % ref],
        cwd=str(REPO), capture_output=True, text=True,
    )
    if txt.returncode != 0:
        raise SystemExit("FATAL 取不到契约示例 %s：%s" % (ref, txt.stderr[:200]))
    return json.loads(txt.stdout)["examples"]


def envelope_of(result: dict) -> dict:
    """从三种形态里取业务信封：MCP 包装 / 裸 proposal / 裸信封。"""
    if not isinstance(result, dict) or not result:
        return {}
    js = result.get("jsonrpc") and result.get("result")
    if isinstance(js, dict):
        sc = js.get("structuredContent")
        if isinstance(sc, dict):
            return sc
        for c in js.get("content") or []:
            if c.get("type") == "text" and (c.get("text") or "").startswith("{"):
                try:
                    return json.loads(c["text"])
                except json.JSONDecodeError:
                    pass
        return {}
    # core 的 P1/P2/E1 直接存了 proposal 本体，没有信封；须先于 status 判断，
    # 因为 proposal 自带 status=draft 字段，会被误认成信封
    if "proposal_id" in result:
        return {"status": "success", "data": result}
    if "status" in result:
        return result
    return {}


def find_write_evidence(obj) -> bool:
    if isinstance(obj, dict):
        for k, v in obj.items():
            if any(w in k.lower() for w in WRITE_KEYS):
                return True
            if find_write_evidence(v):
                return True
    elif isinstance(obj, list):
        return any(find_write_evidence(x) for x in obj)
    return False


def judge_core(case: str, rec: dict) -> tuple[str, list[str]]:
    key = next((p for p in CORE_ASSERT if case.startswith(p)), None)
    notes: list[str] = []
    if key is None:
        return "UNVERIFIABLE", ["C 侧无该用例的断言定义"]
    spec = CORE_ASSERT[key]
    env = envelope_of(rec.get("response") or {})
    if not env:
        return "UNVERIFIABLE", ["响应中没有可解析的业务信封"]
    err = (env.get("error") or {}).get("code")
    data = env.get("data") or {}

    if spec.get("proposal_no_internal"):
        bad = [k for k in data if k in ("id", "created_at", "updated_at", "user_id", "deleted_at")]
        return ("PASS", ["leaked=[]"]) if not bad else ("FAIL", ["泄露内部字段：%s" % bad])
    if spec.get("proposal_complete"):
        miss = [k for k in PROPOSAL_REQUIRED if k not in data]
        if miss:
            return "FAIL", ["缺必填字段：%s" % miss]
        if data.get("status") not in PROPOSAL_STATUS:
            return "FAIL", ["status 越界：%s" % data.get("status")]
        return "PASS", ["11 字段齐全，status=%s" % data.get("status")]
    if spec.get("explanations_objects"):
        ex = data.get("explanations")
        if not isinstance(ex, list) or not ex:
            return "FAIL", ["explanations 不是非空数组"]
        for i, item in enumerate(ex):
            if not isinstance(item, dict) or "code" not in item or "message" not in item:
                return "FAIL", ["第 %d 项不是含 code+message 的对象" % i]
        return "PASS", ["%d 项均为对象" % len(ex)]
    if spec.get("envelope"):
        need = ["api_version", "request_id", "trace_id", "status"]
        miss = [k for k in need if k not in env]
        return ("PASS", ["信封齐全"]) if not miss else ("FAIL", ["信封缺：%s" % miss])

    if "code" in spec:
        if err != spec["code"]:
            return "FAIL", ["码不符：期望 %s，实际 %s" % (spec["code"], err)]
        notes.append("code=%s" % err)
    if "status" in spec:
        if env.get("status") != spec["status"]:
            return "FAIL", ["status 不符：期望 %s，实际 %s" % (spec["status"], env.get("status"))]
        notes.append("status=%s" % env.get("status"))
    if spec.get("readback_verified") and data.get("readback_verified") is not True:
        return "FAIL", ["readback_verified 不为 true：%r" % data.get("readback_verified")]
    if spec.get("new_approval_id"):
        aid = data.get("approval_id")
        if not aid:
            return "UNVERIFIABLE", ["响应未返回 approval_id"]
        notes.append("approval_id=%s" % aid)
    if "detail_status" in spec:
        details = (env.get("error") or {}).get("details") or []
        flat = json.dumps(details, ensure_ascii=False)
        if spec["detail_status"] not in flat:
            notes.append("details 未标 %s" % spec["detail_status"])
    if spec.get("write_claim"):
        if find_write_evidence(rec):
            notes.append("有写入计数字段")
        else:
            return "UNBACKED", notes + ["声称涉及写入次数，但证据无任何写入计数字段"]
    return "PASS", notes


NOTE_CODE = re.compile(r"code=([A-Z_]+)")
NOTE_COUNT = re.compile(r"^(\d+)\s+(tasks|events)$")


def judge_ex(rec: dict, contract: dict) -> tuple[str, list[str]]:
    if rec.get("status") == "not_executable":
        return "SKIP", [rec.get("note") or "A 侧标为不可执行"]
    name = rec.get("name")
    if name != contract.get("name"):
        return "UNVERIFIABLE", ["示例名与契约第 %s 条不一致" % contract.get("name")]
    exp = contract.get("response") or {}
    note = rec.get("note") or ""
    notes: list[str] = []
    if rec.get("response"):
        env = envelope_of(rec["response"])
        if env:
            exp_code = (exp.get("error") or {}).get("code")
            got_code = (env.get("error") or {}).get("code")
            if exp_code != got_code:
                return "FAIL", ["码不符：期望 %s，实际 %s" % (exp_code, got_code)]
            if exp.get("status") != env.get("status"):
                return "FAIL", ["status 不符：期望 %s，实际 %s" % (exp.get("status"), env.get("status"))]
            return "PASS", ["原始响应已比对"]
    # 无原始响应：只能用 note 做降级比对
    m = NOTE_CODE.search(note)
    if m:
        exp_code = (exp.get("error") or {}).get("code")
        if exp_code != m.group(1):
            return "FAIL", ["note 里的 code=%s 与契约期望 %s 不符" % (m.group(1), exp_code)]
        notes.append("降级比对：code 一致")
        return "PASS", notes + ["仅 note 可见值，非全字段"]
    m = NOTE_COUNT.match(note.strip())
    if m:
        n, kind = int(m.group(1)), m.group(2)
        key = "tasks" if kind == "tasks" else "events"
        got = (exp.get("data") or {}).get(key)
        if isinstance(got, list) and len(got) != n:
            # 数量不同不等于失败：说明回放用的是自有 fixture，而不是示例数据。
            return "SHAPE_ONLY", [
                "note 说 %d 条、示例是 %d 条 → 未使用示例 request，仅形状级" % (n, len(got))
            ]
        notes.append("降级比对：%s 数量与示例一致" % key)
        return "PASS", notes + ["仅 note 可见值，非全字段"]
    return "UNVERIFIABLE", ["证据只有 status=pass，无响应也无可用 note 值"]


def main() -> int:
    ap = argparse.ArgumentParser(description="C 侧独立复核 EX 回放")
    ap.add_argument("--evidence", required=True, help="A 或 C 产出的 m1-evidence JSON")
    ap.add_argument("--examples-ref", default=DEFAULT_EXAMPLES_REF)
    ap.add_argument("--json-out", default="")
    args = ap.parse_args()

    path = Path(args.evidence)
    if not path.exists():
        print("FATAL 找不到证据文件：%s" % path)
        return 1
    ev = json.loads(path.read_text(encoding="utf-8"))
    examples = load_examples(args.examples_ref)
    by_name = {e["name"]: e for e in examples}

    print("== C 侧独立复核 ==")
    print("  证据文件：%s" % path.name)
    print("  证据声明基准：%s" % ev.get("baseline_contract", "?")[:12])
    print("  契约示例：%s（%d 条）" % (args.examples_ref, len(examples)))

    core_rows, ex_rows = [], []
    for rec in (ev.get("core") or {}).get("results") or []:
        verdict, notes = judge_core(rec.get("case", ""), rec)
        core_rows.append((rec.get("case"), rec.get("pass"), verdict, "; ".join(notes)))

    ex_results = (ev.get("examples") or {}).get("results") or []
    for i, rec in enumerate(ex_results, 1):
        contract = by_name.get(rec.get("name"), {})
        verdict, notes = judge_ex(rec, contract)
        ex_rows.append((rec.get("id") or "EX-%02d" % i, rec.get("name"), rec.get("status"),
                        verdict, "; ".join(notes)))

    def tally(rows, idx):
        c = {}
        for r in rows:
            c[r[idx]] = c.get(r[idx], 0) + 1
        return c

    print("\n-- core（%d 条）--" % len(core_rows))
    for case, apass, verdict, note in core_rows:
        flag = "" if verdict == "PASS" else "  <== A 报 %s" % ("pass" if apass else "fail")
        print("  %-6s %-46s %s%s" % (verdict, case[:46], note[:70], flag))

    print("\n-- EX 回放（%d 条）--" % len(ex_rows))
    for eid, name, astatus, verdict, note in ex_rows:
        print("  %-5s %-12s %-52s %s" % (eid, verdict, (name or "")[:52], note[:60]))

    print("\n-- 统计 --")
    print("  core：%s" % tally(core_rows, 2))
    print("  EX  ：%s" % tally(ex_rows, 3))
    a_pass = sum(1 for r in ex_rows if r[2] == "pass")
    c_pass = sum(1 for r in ex_rows if r[3] == "PASS")
    print("  A 自称通过 %d 条，C 可确证 %d 条，差 %d 条" % (a_pass, c_pass, a_pass - c_pass))

    if args.json_out:
        Path(args.json_out).write_text(json.dumps(
            {"core": core_rows, "ex": ex_rows}, ensure_ascii=False, indent=1), encoding="utf-8")
        print("  明细已写：%s" % args.json_out)

    bad = [r for r in core_rows + ex_rows if r[-2 if r in core_rows else 3] == "FAIL"] \
        if core_rows else []
    fails = len([r for r in core_rows if r[2] == "FAIL"]) + len([r for r in ex_rows if r[3] == "FAIL"])
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
