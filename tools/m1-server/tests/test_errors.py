#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""errors.py 的单元测试。

只用标准库 unittest：本仓库没有 CI、没有 pytest、没有 pyproject。
`python -m unittest` 从干净环境直接可跑，不需要装任何东西。
（若装了 pytest，本文件同样能被 pytest 收集，因为用的是 TestCase 类。）

Run（在仓库根）:
    python -m unittest discover -s tools/m1-server/tests -v
或:
    python tools/m1-server/tests/test_errors.py

判据：全部通过且 exit 0。
"""

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
sys.path.insert(0, SRC)

import errors  # noqa: E402

# 独立抄录一份契约 §4.1 的 21 码与 HTTP 建议，用于比对。
# 刻意不从 errors.HTTP_BY_CODE 推导期望值——否则就是「自己验证自己」。
CONTRACT_TABLE = {
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

# 契约 §4.1 的 HTTP 建议值反向分布（A1 §6.2 已核算：6 个唯一状态各 1 码 + 3 个多值状态）
EXPECTED_DISTRIBUTION = {400: 1, 401: 1, 403: 5, 404: 1, 409: 7, 422: 1, 500: 1, 502: 1, 503: 3}


class TestCodeSet(unittest.TestCase):
    """21 码闭集本身。"""

    def test_exactly_21_codes(self):
        self.assertEqual(len(errors.HTTP_BY_CODE), 21, "契约 §4.1 是 21 码闭集")

    def test_no_code_missing_or_extra(self):
        self.assertEqual(set(errors.HTTP_BY_CODE), set(CONTRACT_TABLE),
                         "码集合与契约 §4.1 不一致（缺或多）")

    def test_each_code_maps_to_contract_value(self):
        diff = {c: (errors.HTTP_BY_CODE.get(c), v)
                for c, v in CONTRACT_TABLE.items() if errors.HTTP_BY_CODE.get(c) != v}
        self.assertEqual(diff, {}, "逐码 HTTP 建议值与契约不一致：%s" % diff)

    def test_http_distribution(self):
        got = {}
        for v in errors.HTTP_BY_CODE.values():
            got[v] = got.get(v, 0) + 1
        self.assertEqual(got, EXPECTED_DISTRIBUTION,
                         "反向分布不符，可能漏码或重复映射")

    def test_all_http_values_legal(self):
        legal = {400, 401, 403, 404, 409, 422, 500, 502, 503}
        bad = {c: v for c, v in errors.HTTP_BY_CODE.items() if v not in legal}
        self.assertEqual(bad, {}, "出现契约之外的 HTTP 状态：%s" % bad)


class TestEnforced(unittest.TestCase):
    """契约里唯一被写成「固定」的那一条。"""

    def test_enforced_is_only_idempotency_in_progress(self):
        self.assertEqual(errors.HTTP_ENFORCED, frozenset({"IDEMPOTENCY_IN_PROGRESS"}),
                         "契约全文只有 IDEMPOTENCY_IN_PROGRESS 被写成固定 409")

    def test_idempotency_in_progress_is_409(self):
        self.assertEqual(errors.http_status("IDEMPOTENCY_IN_PROGRESS"), 409)

    def test_enforced_flag_reports_true_only_for_that_code(self):
        true_codes = [c for c in errors.HTTP_BY_CODE if errors.is_http_enforced(c)]
        self.assertEqual(true_codes, ["IDEMPOTENCY_IN_PROGRESS"])

    def test_other_codes_are_not_enforced(self):
        for code in ("READBACK_PENDING", "DEPENDENCY_UNAVAILABLE", "FORBIDDEN"):
            self.assertFalse(errors.is_http_enforced(code), "%s 不应被标为强制" % code)


class TestUnknownCode(unittest.TestCase):
    """未知码的安全侧行为。"""

    def test_unknown_code_not_known(self):
        self.assertFalse(errors.is_known_code("NOT_A_REAL_CODE"))

    def test_unknown_code_maps_to_500_without_raising(self):
        self.assertEqual(errors.http_status("NOT_A_REAL_CODE"), 500)

    def test_unknown_code_not_retryable(self):
        self.assertFalse(errors.is_retryable("NOT_A_REAL_CODE"),
                         "未知失败不该被重试：可能放大故障或重复写入")

    def test_unknown_code_source_is_unknown(self):
        self.assertEqual(errors.retryable_source("NOT_A_REAL_CODE"), "unknown")


class TestRetryable(unittest.TestCase):
    """retryable：区分契约明文与未裁建议值。"""

    def test_contract_values_are_exactly_two(self):
        self.assertEqual(set(errors.RETRYABLE_CONTRACT),
                         {"IDEMPOTENCY_IN_PROGRESS", "READBACK_PENDING"},
                         "契约明文只有这两处 retryable=true")

    def test_contract_values_are_true(self):
        for code in errors.RETRYABLE_CONTRACT:
            self.assertTrue(errors.is_retryable(code))

    def test_contract_takes_priority_over_suggestion(self):
        overlap = set(errors.RETRYABLE_CONTRACT) & set(errors.RETRYABLE_SUGGESTED)
        for code in overlap:
            self.assertEqual(errors.RETRYABLE[code], errors.RETRYABLE_CONTRACT[code],
                             "%s 在两张表里都有，契约值必须优先" % code)

    def test_readback_mismatch_is_not_retryable(self):
        # 全表最危险的一项：Proposal 此时是终态 failed，重试等于对终态重复写入
        self.assertFalse(errors.is_retryable("READBACK_MISMATCH"),
                         "READBACK_MISMATCH 必须 false，否则与契约 §6.7 终态规则冲突")

    def test_readback_mismatch_source_is_suggested_not_contract(self):
        # 这条不说「契约这么定」，只说「设计件这么建议」，避免把建议说成契约
        self.assertEqual(errors.retryable_source("READBACK_MISMATCH"), "suggested",
                         "READBACK_MISMATCH 的 retryable=false 是 A1 §6.4 建议值，M-3 未裁，"
                         "不得标记为契约值")

    def test_every_code_has_a_retryable_value(self):
        missing = [c for c in errors.HTTP_BY_CODE if c not in errors.RETRYABLE]
        self.assertEqual(missing, [], "这些码没有 retryable 取值：%s" % missing)

    def test_retryable_true_set_matches_design(self):
        # 与 A1 §6.4 建议表一致（4 个 true）。M-3 裁定后若变化，改 errors.py 表并同步本断言。
        true_codes = sorted(c for c, v in errors.RETRYABLE.items() if v)
        self.assertEqual(true_codes, sorted([
            "DEPENDENCY_UNAVAILABLE",
            "WRITE_BLOCKED",
            "IDEMPOTENCY_IN_PROGRESS",
            "READBACK_PENDING",
        ]))

    def test_source_classification_covers_all_codes(self):
        contract = [c for c in errors.HTTP_BY_CODE if errors.retryable_source(c) == "contract"]
        suggested = [c for c in errors.HTTP_BY_CODE if errors.retryable_source(c) == "suggested"]
        self.assertEqual(sorted(contract), ["IDEMPOTENCY_IN_PROGRESS", "READBACK_PENDING"])
        self.assertEqual(len(contract) + len(suggested), 21,
                         "契约 2 + 建议 19 应覆盖全部 21 码，当前 %d + %d"
                         % (len(contract), len(suggested)))


class TestEnvelope(unittest.TestCase):
    """失败响应信封结构（契约 L117-135 / L294）。"""

    def test_envelope_has_required_fields(self):
        env = errors.to_envelope("INVALID_ARGUMENT", "请求参数无效。",
                                 request_id="req_1", trace_id="trace_1")
        self.assertEqual(env["api_version"], "checkd.agent.v1")
        self.assertEqual(env["status"], "error")
        self.assertEqual(env["request_id"], "req_1")
        self.assertEqual(env["trace_id"], "trace_1")
        for key in ("code", "message", "retryable"):
            self.assertIn(key, env["error"], "error 缺必填字段 %s" % key)

    def test_envelope_retryable_matches_table(self):
        for code in errors.HTTP_BY_CODE:
            env = errors.to_envelope(code, "某个安全可展示的说明。")
            self.assertEqual(env["error"]["retryable"], errors.is_retryable(code),
                             "%s 的信封 retryable 与表不一致" % code)

    def test_details_absent_by_default(self):
        env = errors.to_envelope("NOT_FOUND", "资源不存在。")
        self.assertNotIn("details", env["error"],
                         "缺省时不应写入 details 键，更不能写成 null")

    def test_details_passed_through_as_list(self):
        details = [{"field": "input.date_range.start", "reason": "invalid_date"}]
        env = errors.to_envelope("INVALID_ARGUMENT", "请求参数无效。", details=details)
        self.assertEqual(env["error"]["details"], details)
        self.assertIsInstance(env["error"]["details"], list)

    def test_empty_message_rejected(self):
        for bad in ("", "   ", None):
            with self.assertRaises(ValueError):
                errors.to_envelope("INTERNAL_ERROR", bad)

    def test_details_must_be_list(self):
        with self.assertRaises(TypeError):
            errors.to_envelope("INVALID_ARGUMENT", "说明。", details={"field": "x"})

    def test_envelope_contains_no_raw_token_like_field(self):
        # 契约：错误 message 不得回显原始 payload / 凭证。这一条只做结构性防呆：
        # 信封里不应出现 token / payload / password 这类键。
        env = errors.to_envelope("APPROVAL_UNTRUSTED", "审批凭据无效。")
        flat = repr(env).lower()
        for banned in ("password", "secret", "raw_token"):
            self.assertNotIn(banned, flat, "信封里出现疑似敏感键：%s" % banned)



class TestUnknownCodeGuard(unittest.TestCase):
    """未知 code 不得静默包装成信封（M0 2026-11-05 12:46:18Z 裁定一.2）。

    M3 的实测发现：修复前 `to_envelope("INVALID_ARGUMENTT", ...)` 会正常返回一个
    HTTP 500、retryable=False 的信封，远程调用方看不出这是拼写错误。
    """

    def test_unknown_code_raises(self):
        with self.assertRaises(errors.UnknownErrorCode):
            errors.to_envelope("INVALID_ARGUMENTT", "说明。")

    def test_guard_is_value_error_subclass(self):
        # 既有调用方可能只写了 except ValueError；换成独立异常类会静默漏掉。
        self.assertTrue(issubclass(errors.UnknownErrorCode, ValueError))

    def test_error_message_names_the_bad_code(self):
        bad = "NOT_A_REAL_CODE"
        with self.assertRaises(errors.UnknownErrorCode) as ctx:
            errors.to_envelope(bad, "说明。")
        self.assertIn(bad, str(ctx.exception),
                      "异常消息应含传入的原值，否则拼错的码无法定位")

    def test_no_envelope_is_ever_returned_for_unknown_code(self):
        # 「不静默包装」的正面表述：函数要么抛，要么返回合法信封，没有第三种。
        for bad in ("", "INVALID_ARGUMENTT", "invalid_argument",
                    "INVALID_ARGUMENT ", "INVALID-ARGUMENT", None, 400):
            try:
                env = errors.to_envelope(bad, "说明。")
            except errors.UnknownErrorCode:
                continue
            self.fail("未知 code %r 未抛异常，返回了信封：%r" % (bad, env))

    def test_all_21_known_codes_still_pass(self):
        # 反向误伤检查：校验不能把闭集内的码判成未知。
        for code in errors.HTTP_BY_CODE:
            env = errors.to_envelope(code, "某个安全可展示的说明。")
            self.assertEqual(env["error"]["code"], code)

    def test_guard_agrees_with_is_known_code(self):
        # 两处判定必须同源，否则以后加码会出现「能查不能包」或反之。
        for code in list(errors.HTTP_BY_CODE) + ["BOGUS", "", None]:
            self.assertEqual(errors.is_known_code(code) is False,
                             self._envelope_raises(code),
                             "%r 上 is_known_code 与 to_envelope 判定不一致" % (code,))

    def _envelope_raises(self, code):
        try:
            errors.to_envelope(code, "说明。")
        except errors.UnknownErrorCode:
            return True
        except (ValueError, TypeError):
            return False
        return False



if __name__ == "__main__":
    unittest.main(verbosity=2)
