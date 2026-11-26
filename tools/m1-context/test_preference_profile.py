"""PreferenceProfile 契约测试。

对应：M0 11-26 14:35 联合收口任务单第二节 1/2/3/5 项。
跑法：python -m unittest test_preference_profile -v
纯标准库，无数据库、无网络。
"""

import json
import unittest

import preference_profile as pp
from preference_profile import PreferenceError


def slot(weekday="__absent__", start=1140, end=1260):
    """构造一条时段。weekday 默认缺省，便于测「每日偏好」。"""
    s = {"start_minute": start, "end_minute": end}
    if weekday != "__absent__":
        s["weekday"] = weekday
    return s


def profile(slots=None, **kw):
    base = {"confirm": True, "preferred_slots": slots or []}
    base.update(kw)
    return base


class TestSlotShape(unittest.TestCase):
    def test_missing_weekday_means_daily(self):
        """weekday 缺省 = 每日默认。"""
        out = pp.validate_profile(profile([slot()]))
        self.assertIsNone(out["preferred_slots"][0]["weekday"])

    def test_explicit_null_weekday_means_daily(self):
        """显式 weekday:null 与缺省等价。"""
        out = pp.validate_profile(profile([slot(weekday=None)]))
        self.assertIsNone(out["preferred_slots"][0]["weekday"])

    def test_weekday_one_to_seven_accepted(self):
        for d in range(1, 8):
            out = pp.validate_profile(profile([slot(weekday=d)]))
            self.assertEqual(out["preferred_slots"][0]["weekday"], d)

    def test_weekday_zero_and_eight_rejected(self):
        for d in (0, 8, -1):
            with self.assertRaises(PreferenceError) as ctx:
                pp.validate_profile(profile([slot(weekday=d)]))
            self.assertEqual(ctx.exception.code, "INVALID_SLOT_RANGE")

    def test_zero_length_slot_rejected(self):
        with self.assertRaises(PreferenceError) as ctx:
            pp.validate_profile(profile([slot(start=600, end=600)]))
        self.assertEqual(ctx.exception.code, "INVALID_SLOT_RANGE")

    def test_start_at_1440_rejected(self):
        with self.assertRaises(PreferenceError) as ctx:
            pp.validate_profile(profile([slot(start=1440, end=1440)]))
        self.assertEqual(ctx.exception.code, "INVALID_SLOT_RANGE")

    def test_end_beyond_1440_rejected(self):
        with self.assertRaises(PreferenceError) as ctx:
            pp.validate_profile(profile([slot(start=1430, end=1441)]))
        self.assertEqual(ctx.exception.code, "INVALID_SLOT_RANGE")

    def test_non_object_slot_rejected(self):
        with self.assertRaises(PreferenceError) as ctx:
            pp.validate_profile(profile(["19:00-21:00"]))
        self.assertEqual(ctx.exception.code, "INVALID_SLOT")

    def test_bool_is_not_accepted_as_int(self):
        with self.assertRaises(PreferenceError):
            pp.validate_profile(profile([slot(start=True, end=600)]))


class TestSlotLimit(unittest.TestCase):
    def test_exactly_32_accepted(self):
        slots = [slot(weekday=(i % 7) + 1, start=480 + i, end=480 + i + 30) for i in range(32)]
        out = pp.validate_profile(profile(slots))
        self.assertEqual(len(out["preferred_slots"]), 32)

    def test_33_rejected_not_truncated(self):
        """超限硬失败。detail 要带原始条数，证明没被静默截断。"""
        slots = [slot(weekday=(i % 7) + 1, start=480 + i, end=480 + i + 30) for i in range(33)]
        with self.assertRaises(PreferenceError) as ctx:
            pp.validate_profile(profile(slots))
        self.assertEqual(ctx.exception.code, "TOO_MANY_SLOTS")
        self.assertEqual(ctx.exception.detail, 33)


class TestConfirmation(unittest.TestCase):
    def test_missing_confirm_rejected(self):
        with self.assertRaises(PreferenceError) as ctx:
            pp.validate_profile({"preferred_slots": []})
        self.assertEqual(ctx.exception.code, "CONFIRMATION_REQUIRED")

    def test_string_true_is_not_confirmation(self):
        """客户端把 confirm 发成字符串也必须拒绝，否则类型松散就能绕过确认。"""
        with self.assertRaises(PreferenceError) as ctx:
            pp.validate_profile({"confirm": "true", "preferred_slots": []})
        self.assertEqual(ctx.exception.code, "CONFIRMATION_REQUIRED")

    def test_numeric_one_is_not_confirmation(self):
        with self.assertRaises(PreferenceError) as ctx:
            pp.validate_profile({"confirm": 1, "preferred_slots": []})
        self.assertEqual(ctx.exception.code, "CONFIRMATION_REQUIRED")

    def test_inferred_has_no_confirmed_at(self):
        out = pp.validate_profile(profile(source="inferred"))
        self.assertIsNone(out["confirmed_at"])

    def test_explicit_gets_server_confirmed_at(self):
        out = pp.validate_profile(profile())
        self.assertEqual(out["confirmed_at"], "SET_BY_SERVER")


class TestResolution(unittest.TestCase):
    def test_explicit_overrides_daily(self):
        """显式 weekday 覆盖每日默认，不是叠加。"""
        slots = [
            {"weekday": None, "start_minute": 1140, "end_minute": 1260},
            {"weekday": 6, "start_minute": 540, "end_minute": 660},
        ]
        sat = pp.slots_for_day(slots, 6)
        self.assertEqual(sat, [{"start_minute": 540, "end_minute": 660}])

    def test_daily_used_when_day_absent(self):
        slots = [{"weekday": None, "start_minute": 1140, "end_minute": 1260}]
        self.assertEqual(pp.slots_for_day(slots, 3),
                         [{"start_minute": 1140, "end_minute": 1260}])

    def test_no_match_yields_empty_not_whole_day(self):
        """没有偏好 ≠ 全天可用。返回空，由调用方决定走默认窗口。"""
        slots = [{"weekday": 1, "start_minute": 1140, "end_minute": 1260}]
        self.assertEqual(pp.slots_for_day(slots, 2), [])

    def test_daily_and_seven_explicit_are_equivalent_in_resolution(self):
        daily = [{"weekday": None, "start_minute": 1140, "end_minute": 1260}]
        explicit = [{"weekday": d, "start_minute": 1140, "end_minute": 1260} for d in range(1, 8)]
        for d in range(1, 8):
            self.assertEqual(pp.slots_for_day(daily, d), pp.slots_for_day(explicit, d))

    def test_not_normalized_storage_stays_distinct(self):
        """形态等价但存储不互转：序列化结果必须不同，否则会丢「逐日设置过」这个事实。"""
        daily = pp.validate_profile(profile([slot()]))["preferred_slots"]
        explicit = pp.validate_profile(profile([slot(weekday=d) for d in range(1, 8)]))["preferred_slots"]
        self.assertNotEqual(json.dumps(daily), json.dumps(explicit))
        self.assertEqual(len(daily), 1)
        self.assertEqual(len(explicit), 7)

    def test_invalid_weekday_in_resolution_rejected(self):
        with self.assertRaises(PreferenceError):
            pp.slots_for_day([], 0)

    def test_merge_segments_joins_adjacent(self):
        segs = [{"start_minute": 480, "end_minute": 600},
                {"start_minute": 600, "end_minute": 700}]
        self.assertEqual(pp.merge_segments(segs),
                         [{"start_minute": 480, "end_minute": 700}])

    def test_merge_segments_keeps_gap(self):
        segs = [{"start_minute": 480, "end_minute": 600},
                {"start_minute": 610, "end_minute": 700}]
        self.assertEqual(len(pp.merge_segments(segs)), 2)


class TestVersioning(unittest.TestCase):
    def test_first_write_from_expected_zero(self):
        out = pp.apply_upsert(None, profile(), expected_version=0)
        self.assertEqual(out["data_version"], 1)

    def test_first_write_with_stale_expected_rejected(self):
        with self.assertRaises(PreferenceError) as ctx:
            pp.apply_upsert(None, profile(), expected_version=5)
        self.assertEqual(ctx.exception.code, "VERSION_CONFLICT")
        self.assertEqual(ctx.exception.detail, 0)

    def test_match_increments_by_one(self):
        cur = {"data_version": 2}
        out = pp.apply_upsert(cur, profile(), expected_version=2)
        self.assertEqual(out["data_version"], 3)

    def test_mismatch_reports_current_version(self):
        cur = {"data_version": 7}
        with self.assertRaises(PreferenceError) as ctx:
            pp.apply_upsert(cur, profile(), expected_version=6)
        self.assertEqual(ctx.exception.code, "VERSION_CONFLICT")
        self.assertEqual(ctx.exception.detail, 7)

    def test_null_expected_skips_check(self):
        cur = {"data_version": 9}
        out = pp.apply_upsert(cur, profile(), expected_version=None)
        self.assertEqual(out["data_version"], 10)

    def test_schema_version_never_bumped_by_upsert(self):
        """结构版本不属于并发版本：写多少次都还是 1。"""
        v = pp.apply_upsert(None, profile(), 0)["data_version"]
        for _ in range(5):
            out = pp.apply_upsert({"data_version": v}, profile(), v)
            v = out["data_version"]
            self.assertEqual(out["schema_version"], pp.SCHEMA_VERSION)
        self.assertEqual(v, 6)


class TestDurationRanges(unittest.TestCase):
    def test_focus_bounds(self):
        for ok in (5, 25, 480):
            pp.validate_profile(profile(focus_minutes=ok))
        for bad in (4, 481, 0, -1):
            with self.assertRaises(PreferenceError) as ctx:
                pp.validate_profile(profile(focus_minutes=bad))
            self.assertEqual(ctx.exception.code, "CHECK_VIOLATION")
            self.assertEqual(ctx.exception.field, "focus_minutes")

    def test_break_bounds(self):
        for ok in (0, 5, 120):
            pp.validate_profile(profile(break_minutes=ok))
        for bad in (-1, 121):
            with self.assertRaises(PreferenceError) as ctx:
                pp.validate_profile(profile(break_minutes=bad))
            self.assertEqual(ctx.exception.code, "CHECK_VIOLATION")
            self.assertEqual(ctx.exception.field, "break_minutes")

    def test_null_durations_allowed(self):
        out = pp.validate_profile(profile(focus_minutes=None, break_minutes=None))
        self.assertIsNone(out["focus_minutes"])
        self.assertIsNone(out["break_minutes"])


class TestSampleFixtures(unittest.TestCase):
    def test_sample_file_matches_implementation(self):
        """仓库里的固定样例必须能被实现重算出来（防止文档与代码漂移）。"""
        with open("samples/preference_profile_sample.json", encoding="utf-8") as fh:
            sample = json.load(fh)
        out = pp.apply_upsert(None, sample["input"], expected_version=0)
        for key in ("preferred_slots", "focus_minutes", "break_minutes",
                    "source", "data_version", "schema_version"):
            self.assertEqual(out[key], sample["expected"][key], key)

    def test_sample_resolution_matches(self):
        with open("samples/preference_profile_sample.json", encoding="utf-8") as fh:
            sample = json.load(fh)
        slots = sample["expected"]["preferred_slots"]
        for day, want in sample["resolved"].items():
            got = pp.slots_for_day(slots, int(day))
            self.assertEqual(got, want, f"weekday {day}")


if __name__ == "__main__":
    unittest.main()
