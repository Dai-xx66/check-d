#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""M3 / C 侧：核 §5.8 violation code 闭集（散文枚举），不依赖表格解析。

为什么需要这个工具
    verify_m1_evidence.py 的 contract_codes() 只认 markdown 表格行
    `| `CODE` | 400 |`，从 agent-api-v1.md 里取到的是 §4.1 的 21 个错误码；
    而 §5.8 的 violation code 闭集是**散文枚举**（「公开 `code` 的 v1 完整闭集
    仅为：A、B、…」），两者交集为空集。后果：M0 在 §5.8 加一行 BLOCK_OVERLAP，
    verify_m1_evidence.py 的解析结果一字不变，那次「全绿」对该契约变更零信息。

口径
    断言对象是**契约文本本身**，不是 M1 的证据：
      1) 从指定 commit 取出 docs/contracts/agent-api-v1.md；
      2) 只解析「公开 `code` 的 v1 完整闭集仅为：…未知 `code`」这一段内的反引号码，
         与表格行无关，避免把 §4.1 错误码混进来；
      3) --against 给基线 commit 时做集合 diff：只允许新增，不允许删除/改名；
      4) --expect 可指定必须新增的唯一 code（本轮为 BLOCK_OVERLAP），多一个少一个都判负。

退出码
    0 = 符合预期（基线模式下：新增集合 == {--expect}，且无删除）
    1 = 不符合预期（缺码 / 多码 / 有删除 / 解析不到段落）
    2 = 输入无法读取

用法
    # 打印某 commit 的闭集
    python check_contract_closed_set.py --repo <repo> --contract c9dda83
    # 复算基线（应判负：BLOCK_OVERLAP 还没有）
    python check_contract_closed_set.py --repo <repo> --contract c9dda83 --expect BLOCK_OVERLAP
    # 新契约到手后：与基线比，必须恰好新增一个 BLOCK_OVERLAP
    python check_contract_closed_set.py --repo <repo> --contract <新SHA> \
        --against c9dda83 --expect BLOCK_OVERLAP
"""

import argparse
import re
import subprocess
import sys

PATH = "docs/contracts/agent-api-v1.md"
# 「公开 `code` 的 v1 完整闭集仅为：」到「未知 `code` 必须以」之间就是闭集本体
SEG = re.compile(r"公开\s*`code`\s*的\s*v1\s*完整闭集仅为：(.*?)未知\s*`code`", re.S)
CODE = re.compile(r"`([A-Z][A-Z_]{2,})`")


def git(repo, *args):
    r = subprocess.run(["git", "-C", repo] + list(args), capture_output=True, check=False)
    return r.stdout.decode("utf-8", "replace"), r.returncode


def closed_set(repo, sha):
    md, rc = git(repo, "show", "%s:%s" % (sha, PATH))
    if rc != 0 or not md.strip():
        print("FATAL: 读不到 %s:%s（rc=%d）" % (sha, PATH, rc))
        sys.exit(2)
    m = SEG.search(md)
    if not m:
        print("FATAL: %s 里定位不到 §5.8 闭集段落（散文枚举可能被改了结构）" % sha)
        sys.exit(1)
    codes = CODE.findall(m.group(1))
    # 段落里若夹入非码词，宁可报出来也不要静默放过
    return set(codes), len(codes), len(md)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True, help="含契约提交的 git 仓库路径（只读）")
    ap.add_argument("--contract", required=True, help="待核契约所在 commit")
    ap.add_argument("--against", help="基线 commit；给了就做集合 diff")
    ap.add_argument("--expect", action="append", default=[], help="基线模式下要求的唯一新增码，可重复")
    a = ap.parse_args()

    cur, n, nchars = closed_set(a.repo, a.contract)
    print("契约: %s  (%d 字符)" % (a.contract, nchars))
    print("§5.8 闭集: %d 个" % n)
    for c in sorted(cur):
        print("  - %s" % c)

    if not a.against:
        # 无基线模式：--expect 退化为「闭集里必须包含这些码」，用于开录前的单点断言
        if a.expect:
            miss = set(a.expect) - cur
            if miss:
                print("\nRESULT: FAIL（闭集里缺 %s）" % sorted(miss))
                sys.exit(1)
            print("\nRESULT: PASS（闭集包含 %s）" % sorted(set(a.expect)))
            sys.exit(0)
        print("RESULT: 只读打印，未做 diff")
        sys.exit(0)

    base, nb, _ = closed_set(a.repo, a.against)
    added, removed = cur - base, base - cur
    print("\n基线: %s（%d 个）" % (a.against, nb))
    print("新增: %s" % (sorted(added) or "无"))
    print("删除: %s" % (sorted(removed) or "无"))

    bad = []
    if removed:
        bad.append("出现删除/改名：%s" % sorted(removed))
    if a.expect:
        want = set(a.expect)
        if added != want:
            bad.append("新增集合 %s ≠ 预期 %s" % (sorted(added), sorted(want)))
    else:
        if len(added) != 1:
            bad.append("未指定 --expect 时要求恰好新增 1 个，实际 %d" % len(added))
    if n != nb + len(added) - 0:
        bad.append("计数不自洽：%d ≠ %d + %d" % (n, nb, len(added)))

    if bad:
        print("\nRESULT: FAIL")
        for b in bad:
            print("  ! %s" % b)
        sys.exit(1)
    print("\nRESULT: PASS（闭集恰好新增 %s，无删除）" % sorted(added))


if __name__ == "__main__":
    main()
