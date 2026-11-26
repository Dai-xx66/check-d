#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""explanations 过滤单测。

契约依据：`39f7f965` L316-318 公开 code 封闭枚举 + 末句禁止 DISPLACED_BY_FIXED /
REPAIR_SUMMARY 出现在公开响应。

跑法：
    cd work/repo/check-d
    python -m unittest discover -s tools/m1-server/tests -v
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import explanations_filter as ef  # noqa: E402


def _stats():
    return ef.FilterStats()


class TestPublicCodes(unittest.TestCase):
    def test_all_seven_public_codes_pass(self):
        """契约 L317-318 的七个公开码一个都不能被误杀。"""
        items = [{"code": c, "message": "m"} for c in sorted(ef.PUBLIC_CODES)]
        out = ef.filter_explanations(items, _stats())
        self.assertEqual(len(out), 7)
        self.assertEqual({x["code"] for x in out}, set(ef.PUBLIC_CODES))

    def test_contract_whitelist_has_exactly_seven(self):
        """白名单数量锁死为 7。多一个少一个都说明有人改过契约口径。"""
        self.assertEqual(len(ef.PUBLIC_CODES), 7)


class TestInternalCodesDropped(unittest.TestCase):
    def test_repair_codes_are_dropped(self):
        """契约明文禁止的两个码必须被剔除。"""
        items = [
            {"code": "REPAIR_SUMMARY", "message": "内部修复摘要"},
            {"code": "DISPLACED_BY_FIXED", "message": "被固定日程挤走"},
            {"code": "SCHEDULED", "message": "已排"},
        ]
        st = _stats()
        out = ef.filter_explanations(items, st)
        self.assertEqual([x["code"] for x in out], ["SCHEDULED"])
        self.assertEqual(st.dropped, 2)

    def test_unknown_code_is_dropped_and_recorded(self):
        """引擎新增未登记码时：剔除 + 记录。不能只丢不记。"""
        st = _stats()
        out = ef.filter_explanations([{"code": "SOME_NEW_INTERNAL_CODE"}], st)
        self.assertEqual(out, [])
        self.assertIn("SOME_NEW_INTERNAL_CODE", st.unknown_codes)

    def test_known_internal_code_not_in_unknown_list(self):
        """已知内部码不算"未登记"，否则 unknown_codes 会被噪音填满。"""
        st = _stats()
        ef.filter_explanations([{"code": "REPAIR_SUMMARY"}], st)
        self.assertEqual(st.unknown_codes, set())


class TestMalformedInput(unittest.TestCase):
    def test_none_returns_empty(self):
        self.assertEqual(ef.filter_explanations(None, _stats()), [])

    def test_non_list_returns_empty(self):
        self.assertEqual(ef.filter_explanations({"code": "SCHEDULED"}, _stats()), [])
        self.assertEqual(ef.filter_explanations("SCHEDULED", _stats()), [])

    def test_item_without_code_is_dropped(self):
        st = _stats()
        out = ef.filter_explanations([{"message": "no code"}], st)
        self.assertEqual(out, [])
        self.assertEqual(st.dropped, 1)

    def test_non_dict_item_is_dropped(self):
        st = _stats()
        out = ef.filter_explanations(["SCHEDULED", None, 42], st)
        self.assertEqual(out, [])
        self.assertEqual(st.dropped, 3)

    def test_lowercase_code_is_not_public(self):
        """枚举区分大小写。'scheduled' 不是公开码，不能因为"看着像"就放行。"""
        st = _stats()
        out = ef.filter_explanations([{"code": "scheduled"}], st)
        self.assertEqual(out, [])
        self.assertIn("scheduled", st.unknown_codes)


class TestSanitizeProposal(unittest.TestCase):
    def test_only_explanations_touched(self):
        """净化只改 explanations，其余三部分原样，避免与引擎语义错位。"""
        prop = {
            "blocks": [{"block_id": "b1"}],
            "changes": [{"change_id": "c1"}],
            "unplanned_tasks": [{"task_id": "t1"}],
            "explanations": [{"code": "REPAIR_SUMMARY"}, {"code": "SCHEDULED"}],
        }
        out = ef.sanitize_proposal(prop, _stats())
        self.assertEqual(out["blocks"], prop["blocks"])
        self.assertEqual(out["changes"], prop["changes"])
        self.assertEqual(out["unplanned_tasks"], prop["unplanned_tasks"])
        self.assertEqual([x["code"] for x in out["explanations"]], ["SCHEDULED"])

    def test_does_not_mutate_input(self):
        """不改入参：同一份引擎结果可能被多处读取，就地改会串味。"""
        prop = {"explanations": [{"code": "REPAIR_SUMMARY"}]}
        ef.sanitize_proposal(prop, _stats())
        self.assertEqual(len(prop["explanations"]), 1)

    def test_non_dict_passthrough(self):
        self.assertIsNone(ef.sanitize_proposal(None, _stats()))


class TestStatsSnapshot(unittest.TestCase):
    def test_snapshot_reports_counts_not_content(self):
        st = _stats()
        ef.filter_explanations([{"code": "SCHEDULED"}, {"code": "REPAIR_SUMMARY"}], st)
        snap = st.snapshot()
        self.assertEqual(snap["seen"], 2)
        self.assertEqual(snap["dropped"], 1)
        self.assertEqual(snap["unknown_codes"], [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
