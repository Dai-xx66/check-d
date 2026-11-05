#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""verify_m1_evidence.py 的反例回归（自检）。

为什么要有这个文件
    M0 在 2026-11-02T12:54Z 与 15:27Z 两次指出同一个病根：核验器"太宽容"会让字段
    缺失或类型不对的证据被判为齐全（文本回退、bool() 转换）。每次修口径都必须能
    用一个反例证明它真的会报错，否则等于没修。

做法
    造一份最小证据样本，逐项做"破坏"（删字段 / 改类型 / 改取值），跑真核验器，
    断言它报了该报的话。对不上就算回归失败（exit 1）。

用法
    python tools/m3-checks/selftest_verifier.py --contract c9dda83

退出码
    0 = 全部反例都被正确识别
    1 = 有反例没被抓到（口径回退，不得提交）
    2 = 环境问题（契约读不到）
"""

import argparse
import copy
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
VERIFIER = os.path.join(HERE, "verify_m1_evidence.py")

# 一条"完全合规"的 READBACK_PENDING 证据（字段名与类型都按清单 §2）
GOOD = {
    "case": "SELFTEST 合规样本 → READBACK_PENDING",
    "expected": "READBACK_PENDING, proposal_status=applying, writes_delta=0",
    "got": "READBACK_PENDING",
    "pass": True,
    "raw": {
        "code": "READBACK_PENDING",
        "proposal_status": "applying",
        "writes_delta": 0,
        "retryable": True,
        "details": [
            {"field": "proposal_status", "reason": "applying"},
            {"field": "business_write_count_delta", "reason": "0"},
        ],
    },
}


def evidence_with(row):
    return {"contract": "c9dda83", "core": {"results": [row]}, "examples": {"results": []}}


def run_verifier(ev, contract):
    tmp = tempfile.mkdtemp(prefix="selftest_ev_")
    path = os.path.join(tmp, "ev.json")
    json.dump(ev, open(path, "w", encoding="utf-8"), ensure_ascii=False)
    p = subprocess.run(
        [sys.executable, VERIFIER, "--evidence", path, "--contract", contract],
        capture_output=True, text=True, encoding="utf-8",
    )
    return p.returncode, p.stdout + p.stderr


def mutate(drop=(), setv=None):
    row = copy.deepcopy(GOOD)
    for k in drop:
        row["raw"].pop(k, None)
    for k, v in (setv or {}).items():
        row["raw"][k] = v
    return row


CASES = [
    # (说明, 行, 期望输出里必须出现的话, 期望 exit)
    ("合规样本应判齐全", mutate(), ("未测 A（READBACK_* 缺必填 raw 字段）: 0",), 0),
    ("删除 raw.proposal_status（文本仍写着）应判 A 类未测",
     mutate(drop=("proposal_status",)), ("缺 raw.proposal_status",), 0),
    ("删除 raw.details 应判 A 类未测",
     mutate(drop=("details",)), ("缺 raw.details",), 0),
    ("retryable 用字符串 \"false\" 应判类型不对（不是当成 True 放过）",
     mutate(setv={"retryable": "false"}), ("契约要求 JSON 布尔",), 0),
    ("retryable 用 1/0 数字也应判类型不对",
     mutate(setv={"retryable": 1}), ("契约要求 JSON 布尔",), 0),
    ("retryable=false 与 PENDING 示例相反应判冲突",
     mutate(setv={"retryable": False}), ("与契约示例相反",), 1),
    ("writes_delta 用字符串 \"0\" 应判 B 类未测",
     mutate(setv={"writes_delta": "0"}), ("未给 raw.writes_delta 整数",), 0),
    ("writes_delta=2 应判冲突",
     mutate(setv={"writes_delta": 2}), ("≠ 0",), 1),
    ("proposal_status 取非法值应判冲突",
     mutate(setv={"proposal_status": "applied"}), ("非法",), 1),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--contract", default="c9dda83")
    a = ap.parse_args()

    # 先确认契约能读到，读不到是环境问题不是口径问题
    rc, out = run_verifier(evidence_with(mutate()), a.contract)
    if "FATAL" in out:
        print("FATAL: 契约 %s 读不到，无法自检\n%s" % (a.contract, out))
        return 2

    bad = 0
    for desc, row, expects, want_rc in CASES:
        rc, out = run_verifier(evidence_with(row), a.contract)
        miss = [e for e in expects if e not in out]
        rc_ok = (rc == want_rc)
        if miss or not rc_ok:
            bad += 1
            print("  ✗ %s" % desc)
            if miss:
                print("      期望输出含 %r，实际没有" % miss)
            if not rc_ok:
                print("      期望 exit=%d，实际 exit=%d" % (want_rc, rc))
        else:
            print("  ✓ %s" % desc)

    print()
    print("反例回归：%d 项，失败 %d 项" % (len(CASES), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
