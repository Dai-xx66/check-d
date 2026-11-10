#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""explanations 对外过滤：只放行公开闭集内的 code。

## 为什么需要这一层

M2 引擎按方案 A 只输出内部四部分（`blocks` / `changes` / `unplanned_tasks` /
`explanations`），其中 `explanations` 含 **repair 专用码**，属于引擎内部诊断信息，
不能出现在 v1 公开响应里。引擎侧的 `publicExplanations`（schedule_contract.dart L763）
按 M2 2026-11-07T03:45:00Z 答复，责任方划给 **M1 服务端**（依据契约 §5.7 L326-328
「服务端包装层组装完整 Proposal」+ L316-318「公开 code 是封闭枚举」）。

## 依据（契约原文，不是自拟）

契约 `39f7f965` L316-318 规定公开 `code` 是封闭枚举：

    SCHEDULED / ESTIMATED_DURATION / ALREADY_DONE_TODAY /
    FIXED_BLOCKS_OVERLAP / NO_AVAILABILITY_WINDOW /
    AVAILABILITY_SATURATED / PRESERVED_FIXED_EVENTS

同段末句明确：

    `DISPLACED_BY_FIXED` 与 `REPAIR_SUMMARY` 仅供 M2 内部 repair 逻辑使用，
    禁止出现在（公开响应）

## 设计取舍

- **白名单而非黑名单**：引擎以后新增内部码时，默认被剔除，不需要改这里。
  黑名单会让新码悄悄泄漏。
- **剔除要记账，不静默丢**：丢弃条数进 `dropped`，由 `/diag` 汇总。
  「静默过滤」和「静默不报错」是同一类错误——出事时没人知道过滤发生过。
- **不带出被剔除的内容**：不给调用方「哪些被过滤了」的清单，因为码名本身就是
  内部信息。只回条数。
"""

# 契约 L317-318 的公开闭集，逐字照抄，不要改成"看起来更全"的集合。
PUBLIC_CODES = frozenset({
    "SCHEDULED",
    "ESTIMATED_DURATION",
    "ALREADY_DONE_TODAY",
    "FIXED_BLOCKS_OVERLAP",
    "NO_AVAILABILITY_WINDOW",
    "AVAILABILITY_SATURATED",
    "PRESERVED_FIXED_EVENTS",
})

# 契约同段明文禁止出现在公开响应的码。列出来是为了让测试能直接断言它们被剔除，
# 不影响白名单逻辑（不在白名单里自然就被剔除）。
INTERNAL_ONLY_CODES = frozenset({
    "DISPLACED_BY_FIXED",
    "REPAIR_SUMMARY",
})


class FilterStats:
    """累计过滤统计。进程内共享，供 /diag 读。"""

    def __init__(self):
        self.seen = 0
        self.dropped = 0
        self.unknown_codes = set()

    def snapshot(self):
        return {
            "seen": self.seen,
            "dropped": self.dropped,
            # 只报码名，不报内容；码名本身是内部枚举，但它是判断
            # 「引擎是否新增了未登记码」的唯一线索，留着比藏起来有用。
            "unknown_codes": sorted(self.unknown_codes),
        }

    def reset(self):
        self.seen = 0
        self.dropped = 0
        self.unknown_codes.clear()


STATS = FilterStats()


def is_public(code):
    return isinstance(code, str) and code in PUBLIC_CODES


def filter_explanations(items, stats=None):
    """过滤 explanations 数组，只留公开 code。

    入参允许 None / 非列表 —— 引擎实现变化时不因此崩，返回空列表。
    每项必须是带 `code` 的对象；没有 `code` 的项一律剔除（宁可少说，不可乱说）。
    """
    st = stats if stats is not None else STATS
    if not isinstance(items, list):
        return []
    out = []
    for item in items:
        if not isinstance(item, dict):
            st.seen += 1
            st.dropped += 1
            continue
        st.seen += 1
        code = item.get("code")
        if is_public(code):
            out.append(item)
        else:
            st.dropped += 1
            if isinstance(code, str) and code not in INTERNAL_ONLY_CODES:
                # 既不在公开集也不在已知内部集 → 引擎新增了未登记的码，
                # 这是要人看一眼的信号，不能只丢不记。
                st.unknown_codes.add(code)
    return out


def sanitize_proposal(proposal, stats=None):
    """对引擎返回的内部结果做对外净化。

    只改 `explanations` 一处，其余三部分原样返回 —— 这一层不做业务加工，
    加工越多越容易与引擎语义错位。
    """
    if not isinstance(proposal, dict):
        return proposal
    cleaned = dict(proposal)
    cleaned["explanations"] = filter_explanations(proposal.get("explanations"), stats)
    return cleaned
