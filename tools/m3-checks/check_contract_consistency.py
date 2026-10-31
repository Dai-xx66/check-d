#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""M3 / C 侧：契约文件一致性机检（不依赖任何 Mock 实现，纯静态）。

用途
    对 `docs/contracts/agent-api-v1.md` 与 `agent-api-v1.examples.json` 做结构化
    比对，回答三个问题：
      1. 示例里的错误码、状态值、原因码是否都在契约正文的枚举里（有无越界）。
      2. 示例的信封结构是否完整（缺字段会让验收断言无法定位）。
      3. 20 个错误码里哪些没有示例（示例缺口清单）。

用法
    python tools/m3-checks/check_contract_consistency.py            # 默认 HEAD
    python tools/m3-checks/check_contract_consistency.py 2c48579    # 指定提交

退出码
    0 = 无越界且结构完整（示例缺口仍会打印，但不视为失败）
    1 = 存在越界或结构缺失
    2 = 文件缺失 / JSON 无法解析

注意
    本脚本只做"是否越界"的判定，**不做可达性判定**。错误码"写在表里但代码路径
    走不到"属于实现层问题，须用 acceptance-matrix 的 G1 闸门单独验证。
"""

import json
import re
import subprocess
import sys

MD = "docs/contracts/agent-api-v1.md"
EX = "docs/contracts/agent-api-v1.examples.json"

# 契约正文中固定的闭集枚举（改契约时若变动，这里要同步，否则会报"正文不含"）
REASON_CODES = {"WINDOW_INSUFFICIENT", "PAST_DEADLINE", "OVERLAPS_FIXED", "NO_AVAILABILITY"}
DURATION_SOURCES = {"task_target", "scheduler_estimate"}


def git(*args):
    return subprocess.run(["git"] + list(args), capture_output=True, check=False).stdout.decode("utf-8")


def load(sha):
    md = git("show", "%s:%s" % (sha, MD))
    raw = git("show", "%s:%s" % (sha, EX))
    if not md.strip() or not raw.strip():
        print("FATAL: 在 %s 上读不到契约文件" % sha)
        sys.exit(2)
    try:
        examples = json.loads(raw)["examples"]
    except Exception as exc:  # noqa: BLE001
        print("FATAL: 示例 JSON 解析失败: %s" % exc)
        sys.exit(2)
    return md, examples


def main():
    sha = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
    md, examples = load(sha)

    codes = re.findall(r"^\| `([A-Z][A-Z_]+)` \| (\d{3}) \|", md, re.M)
    code_set = {c for c, _ in codes}

    # Proposal 状态：只在 §5.7 段内取，避免误取 §5.2 的 Task status
    sec = md[md.index("### 5.7"):md.index("## 6. 工具契约")]
    blk = re.search(r"- `status`：(.+?)状态机固定为", sec, re.S).group(1)
    proposal_states = set(re.findall(r"`(\w+)`", blk)) - set(REASON_CODES) - {
        "blocks", "changes", "unplanned_tasks", "explanations", "task_id",
        "reason_code", "remaining_minutes", "message", "code", "related_task_ids",
        "generated_at", "expires_at",
    }

    approval_states = set(re.findall(r"- `status=(\w+)`", md))
    # §6.4 的 approvability 枚举（同名不同域，见矩阵 B17）
    approvability = set(re.findall(r"`(not_requested|not_approvable)`", md))
    tools = set(re.findall(r"### 6\.\d+ `(\w+)`", md))

    print("提交: %s" % git("rev-parse", "--short", sha).strip())
    print("§4.1 错误码: %d 条 / %d 唯一" % (len(codes), len(code_set)))
    print("Proposal 状态: %d  %s" % (len(proposal_states), sorted(proposal_states)))
    print("Approval 状态: %d  %s" % (len(approval_states), sorted(approval_states)))
    print("approvability(§6.4): %s" % sorted(approvability))
    print("工具: %d  %s" % (len(tools), sorted(tools)))

    used, issues = [], []
    for e in examples:
        n = e.get("name", "?")
        req, resp = e.get("request") or {}, e.get("response") or {}
        for k in ("api_version", "request_id", "timezone", "input"):
            if k not in req:
                issues.append("%s: request 缺 %s" % (n, k))
        for k in ("api_version", "request_id", "trace_id", "status"):
            if k not in resp:
                issues.append("%s: response 缺 %s" % (n, k))

        if resp.get("status") == "error":
            err = resp.get("error") or {}
            used.append(err.get("code"))
            if err.get("code") not in code_set:
                issues.append("%s: error.code=%s 不在 §4.1" % (n, err.get("code")))
            for k in ("message", "retryable"):
                if k not in err:
                    issues.append("%s: error 缺 %s" % (n, k))

        blob = json.dumps(e, ensure_ascii=False)
        for st in set(re.findall(r'"proposal_status":\s*"(\w+)"', blob)):
            if st not in proposal_states:
                issues.append("%s: proposal_status=%s 越界" % (n, st))
        for st in set(re.findall(r'"approval_status":\s*"(\w+)"', blob)):
            # 必须落在 §6.4 的 approvability 域，不能混用 §6.6 的审批状态
            if st not in approvability:
                issues.append("%s: approval_status=%s 既不在 §6.4 approvability 也不在 §6.6 状态" % (n, st))
        for st in set(re.findall(r'"status":\s*"(pending|approved|token_issued|consumed|rejected|expired)"', blob)):
            if st not in approval_states:
                issues.append("%s: approval status=%s 越界" % (n, st))
        for st in set(re.findall(r'"reason_code":\s*"(\w+)"', blob)):
            if st not in REASON_CODES:
                issues.append("%s: reason_code=%s 越界" % (n, st))
        for st in set(re.findall(r'"duration_source":\s*"(\w+)"', blob)):
            if st not in DURATION_SOURCES:
                issues.append("%s: duration_source=%s 越界" % (n, st))
        if e.get("tool") and e["tool"] not in tools:
            issues.append("%s: 工具 %s 不在 7 工具内" % (n, e["tool"]))

    missing = sorted(c for c in code_set - set(used))
    print("\n示例: %d 条 | 错误响应: %d | 覆盖错误码: %d/%d"
          % (len(examples), len(used), len(set(used)), len(code_set)))
    print("无示例的错误码 %d 个: %s" % (len(missing), ", ".join(missing) or "-"))
    print("结构/枚举问题: %d" % len(issues))
    for i in issues:
        print("  - %s" % i)

    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
