# -*- coding: utf-8 -*-
"""运行时标记的边界测试。

这个模块存在的唯一理由是回答一个事实问题（容器重启后磁盘是否沿用），
所以测试要钉住的不是功能，而是**它没有越界**：

1. 标记内容里不含任何像凭据的东西（无 eyJ 前缀、无 Bearer、无 ad-/rt- 前缀口令）。
2. 写进去的只能是随机标记，内容每次不同。
3. 三个候选路径互不干扰；缺失路径不会抛异常。
4. 清理之后三个路径都不在了。
5. 模块里没有任何网络访问、没有读环境变量里的口令。
"""

import os
import re
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))

import runtime_marker as rm  # noqa: E402


class TestMarkerContentIsNotACredential(unittest.TestCase):

    def test_content_shape(self):
        text = rm._marker_text()
        # 只有 "MARKER <iso8601> <32位hex>"
        self.assertRegex(text.strip(),
                         r"^MARKER \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z [0-9a-f]{32}$")

    def test_no_credential_patterns(self):
        """这几条是硬边界：出现任何一种都说明它越界了。"""
        text = rm._marker_text()
        for bad, why in (
            ("eyJ", "JWT 的固定前缀"),
            ("Bearer", "认证头"),
            ("ad-", "管理口令前缀"),
            ("rt-", "真实通道口令前缀"),
            ("access_token", "令牌字段名"),
            ("sb_publishable", "Supabase 公开密钥前缀"),
        ):
            self.assertNotIn(bad, text, "标记里出现了 %s（%s）" % (bad, why))

    def test_each_write_is_different(self):
        """每次写都不同 → 读回来能确认「这是不是同一次写入」。"""
        self.assertNotEqual(rm._marker_text(), rm._marker_text())


class TestMarkerFiles(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="marker-test-")
        # 把三个候选路径全部指到临时目录，避免污染真实 /tmp 与家目录
        self._orig = rm._CANDIDATES
        rm._CANDIDATES = (
            ("package_dir", lambda p: os.path.join(p, rm.MARKER_NAME)),
            ("tmp", lambda p: os.path.join(p, "tmp-" + rm.MARKER_NAME)),
            ("home", lambda p: os.path.join(p, "home-" + rm.MARKER_NAME)),
        )

    def tearDown(self):
        rm._CANDIDATES = self._orig
        for name in os.listdir(self.tmp):
            try:
                os.unlink(os.path.join(self.tmp, name))
            except OSError:
                pass
        os.rmdir(self.tmp)

    def test_write_read_clean_roundtrip(self):
        w = rm.write_markers(self.tmp)
        self.assertEqual(len(w["results"]), 3)
        self.assertTrue(all(r["ok"] for r in w["results"]),
                        w["results"])

        r = rm.read_markers(self.tmp)
        contents = [x.get("content") for x in r["results"]]
        self.assertTrue(all(c == w["marker"] for c in contents),
                        "读回来的内容与写下去的不一致：%s" % contents)

        c = rm.clean_markers(self.tmp)
        self.assertEqual(len(c["results"]), 3)
        self.assertTrue(all(x["removed"] for x in c["results"]), c["results"])

        r2 = rm.read_markers(self.tmp)
        self.assertFalse(any(x["exists"] for x in r2["results"]))

    def test_clean_when_absent_is_not_an_error(self):
        c = rm.clean_markers(self.tmp)
        self.assertTrue(all(x["removed"] is False for x in c["results"]))

    def test_unwritable_path_reports_error_not_raise(self):
        rm._CANDIDATES = (("bad", lambda p: "/proc/definitely-not-writable/x"),)
        w = rm.write_markers(self.tmp)
        self.assertFalse(w["results"][0]["ok"])
        self.assertIn("error", w["results"][0])
        # 读也不能抛
        r = rm.read_markers(self.tmp)
        self.assertFalse(r["results"][0]["exists"])


class TestMarkerModuleHasNoNetworkOrSecrets(unittest.TestCase):

    def test_no_network_imports(self):
        with open(os.path.join(HERE, "..", "runtime_marker.py"),
                  encoding="utf-8") as fh:
            src = fh.read()
        for bad in ("urllib", "http.client", "requests", "socket", "subprocess"):
            self.assertNotIn("import " + bad, src,
                             "标记模块不该引入网络/进程能力：%s" % bad)

    def test_no_credential_env_reads(self):
        """不许读任何 CHECKD_ 环境变量——它没有理由知道口令。"""
        with open(os.path.join(HERE, "..", "runtime_marker.py"),
                  encoding="utf-8") as fh:
            src = fh.read()
        self.assertIsNone(re.search(r"CHECKD_\w+", src),
                          "标记模块出现了 CHECKD_ 环境变量引用")
        self.assertNotIn("environ", src)


if __name__ == "__main__":
    unittest.main(verbosity=2)
