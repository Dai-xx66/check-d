#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CheckD Agent API v1 统一错误语义。

契约基准：`39f7f96559abac9d4bc59d5c560e6a706ec19946`
  - §4.1（L138-166）21 码闭集 + 每码 HTTP 建议
  - 信封结构（L117-135）失败响应必须含 status="error" / error{code,message,retryable,details} / trace_id

设计件：`A-runtime-blueprint-a1.md`
  - §6.2 HTTP 映射现状（「1 强制 + 20 建议」）
  - §6.4 M-3 retryable 覆盖缺口（18 个码契约无值）

## 这个模块刻意把三件容易混淆的事分开表达

1. `HTTP_BY_CODE` —— 21 码的 HTTP 状态。契约原文是「HTTP 建议」，**不是强制**。
2. `HTTP_ENFORCED` —— 契约里唯一被写成「固定为」的那一条（`IDEMPOTENCY_IN_PROGRESS` = 409）。
3. `RETRYABLE_CONTRACT` / `RETRYABLE_SUGGESTED` —— 契约明文只定义了 2 个码的
   `retryable`，其余 19 个是 A1 §6.4 的设计建议，**M-3 尚未裁定**。

第 3 条尤其要注意：`retryable` 是失败响应必填字段，调用方据此决定是否重试。
在 M-3 裁定前，本模块给出的是「与设计件一致」的取值，**不得对外声称与契约一致**。
裁定后若取值变化，只需改本文件两张表，调用点零改动。

## 不做什么

- 不做 HTTP 服务（本目录是隔离的接口骨架，不含 web 框架）
- 不做鉴权、不做持久化、不做审批链
- 不重试、不记日志、不产生 trace_id
- 不为未知 code 造信封：`to_envelope()` 对闭集外的 code 直接抛 `UnknownErrorCode`，拒绝由调用方决定
"""

# --- 契约 §4.1 的 21 码闭集 -------------------------------------------------
# 逐码抄录，顺序按契约表格，便于与原文逐行对照。
HTTP_BY_CODE = {
    "AUTH_REQUIRED": 401,
    "FORBIDDEN": 403,
    "INVALID_ARGUMENT": 400,
    "NOT_FOUND": 404,
    "DEPENDENCY_UNAVAILABLE": 503,
    "PROPOSAL_INVALID": 422,
    "PROPOSAL_EXPIRED": 409,
    "SNAPSHOT_CONFLICT": 409,
    "APPROVAL_REQUIRED": 403,
    "APPROVAL_PENDING": 409,
    "APPROVAL_REJECTED": 403,
    "APPROVAL_EXPIRED": 403,
    "APPROVAL_UNTRUSTED": 403,
    "APPROVAL_CONSUMED": 409,
    "ALREADY_APPLIED": 409,
    "IDEMPOTENCY_IN_PROGRESS": 409,
    "IDEMPOTENCY_CONFLICT": 409,
    "WRITE_BLOCKED": 503,
    "READBACK_PENDING": 503,
    "READBACK_MISMATCH": 502,
    "INTERNAL_ERROR": 500,
}

# 契约 §4.1 原文：「`IDEMPOTENCY_IN_PROGRESS` 的 HTTP 建议码固定为 409」。
# 全文只有这一处把建议写成强制；其余 20 码仍是建议。
HTTP_ENFORCED = frozenset({"IDEMPOTENCY_IN_PROGRESS"})

# --- retryable：契约明文部分（只有 2 个码）--------------------------------
# `IDEMPOTENCY_IN_PROGRESS` → L164 明文 true
# `READBACK_PENDING`         → L680 明文 true
# 注：L709 的「false」是 `APPROVAL_CONSUMED` 在 failed 场景下的取值，属场景性结论，
#     不是该码的无条件值，因此不放进这张表，按建议值 false 处理。
RETRYABLE_CONTRACT = {
    "IDEMPOTENCY_IN_PROGRESS": True,
    "READBACK_PENDING": True,
}

# --- retryable：M-3 未裁部分的建议值（A1 §6.4）----------------------------
# 这 19 项契约没有给出取值。本表与 A1 §6.4 建议表逐行一致。
# M-3 裁定后若与本表不符，改这里，不要散落到调用点。
RETRYABLE_SUGGESTED = {
    "DEPENDENCY_UNAVAILABLE": True,
    "WRITE_BLOCKED": True,
    # READBACK_MISMATCH 是全表最危险的一项：Proposal 此时为终态 failed，
    # 标 true 会让调用方对终态重复发起写入尝试，与契约 §6.7「终态不允许再次写入」
    # 直接冲突。这一项必须是 false，改它之前先看 A1 §6.4 的说明。
    "READBACK_MISMATCH": False,
    "AUTH_REQUIRED": False,
    "FORBIDDEN": False,
    "INVALID_ARGUMENT": False,
    "NOT_FOUND": False,
    "PROPOSAL_INVALID": False,
    "PROPOSAL_EXPIRED": False,
    "SNAPSHOT_CONFLICT": False,
    "APPROVAL_REQUIRED": False,
    "APPROVAL_PENDING": False,
    "APPROVAL_REJECTED": False,
    "APPROVAL_EXPIRED": False,
    "APPROVAL_UNTRUSTED": False,
    "APPROVAL_CONSUMED": False,
    "ALREADY_APPLIED": False,
    "IDEMPOTENCY_CONFLICT": False,
    "INTERNAL_ERROR": False,
}

# 合并视图：契约值覆盖建议值（同一键以契约为准）
RETRYABLE = dict(RETRYABLE_SUGGESTED)
RETRYABLE.update(RETRYABLE_CONTRACT)

API_VERSION = "checkd.agent.v1"


class UnknownErrorCode(ValueError):
    """传入的 code 不在契约 §4.1 的 21 码闭集内。

    为什么必须抛而不是兜底：信封一旦生成，远程调用方就会把它当成一个合法错误码
    去做分支处理。拼错的码（如 `INVALID_ARGUMENTT`）静默进信封，等于把一次
    调用方的编码错误伪装成一次业务失败，而且它还会被 is_retryable 判成不可重试，
    让正确的重试逻辑失效。所以这里 fail-fast。
    """


def is_known_code(code):
    """该 code 是否在契约 §4.1 的 21 码闭集内。

    未知 code 必须由调用方转成 PROPOSAL_INVALID 拒绝（契约 §5.8 对 violation 的要求是
    同类逻辑），不得把它当作「扩展错误」透传给远程调用方。
    """
    return code in HTTP_BY_CODE


def http_status(code):
    """返回该 code 的 HTTP 状态。

    未知 code 返回 500 而不是抛异常：这一层不负责拒绝，只负责映射；
    拒绝由调用方用 `is_known_code()` 判定，避免把「映射失败」和「非法输入」混在一起。
    """
    return HTTP_BY_CODE.get(code, 500)


def is_http_enforced(code):
    """该码的 HTTP 状态是否由契约强制（而非建议）。"""
    return code in HTTP_ENFORCED


def is_retryable(code):
    """该码是否可重试。

    未知 code 一律返回 False。理由：未知码意味着我们不知道发生了什么，
    安全侧是不重试——重试一个未知失败可能放大故障或造成重复写入。
    """
    return RETRYABLE.get(code, False)


def retryable_source(code):
    """该码的 retryable 取值来源，用于审计与测试。

    返回 "contract"（契约明文）/ "suggested"（A1 §6.4 建议，M-3 未裁）/ "unknown"。
    对外汇报时必须区分这两类，不得把 suggested 写成契约值。
    """
    if code in RETRYABLE_CONTRACT:
        return "contract"
    if code in RETRYABLE_SUGGESTED:
        return "suggested"
    return "unknown"


def to_envelope(code, message, *, request_id=None, trace_id=None, details=None):
    """组装契约 L117-135 规定的失败响应信封。

    - `message` 必须已脱敏：不得含原始 payload、数据库语句、凭证、Token、内部 ID。
    - `details` 是数组（契约示例为 `[{"field":..., "reason":...}]`），缺省为空数组，
      不写 `null`——契约说的是可选字段，不是可空字段。
    - `trace_id` 由服务端产生；这一层不生成，调用方传入。
    """
    if not is_known_code(code):
        raise UnknownErrorCode(
            "未知错误码 %r：不在契约 §4.1 的 21 码闭集内。"
            "调用方应先用 is_known_code() 判定，把未知码转成可展示的拒绝，"
            "不得包装成信封透传给远程调用方。" % (code,)
        )
    if not isinstance(message, str) or not message.strip():
        raise ValueError("message 必须是非空字符串：它是给用户看的必填字段")
    if details is not None and not isinstance(details, list):
        raise TypeError("details 必须是数组，契约示例为 [{field, reason}]")

    envelope = {
        "api_version": API_VERSION,
        "request_id": request_id,
        "trace_id": trace_id,
        "status": "error",
        "error": {
            "code": code,
            "message": message,
            "retryable": is_retryable(code),
        },
    }
    if details:
        envelope["error"]["details"] = list(details)
    return envelope
