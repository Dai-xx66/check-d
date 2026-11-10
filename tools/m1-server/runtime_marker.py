# -*- coding: utf-8 -*-
"""运行时标记文件（**仅用于判定「容器重启后磁盘是否沿用」**）。

背景
----
2026-11-10 实测：容器在没有任何发布的情况下自行重启了两次
（15:38:03Z、15:55:34Z）。因此「把短期令牌放内存里撑到明天」不成立。
要不要改成落盘，取决于一个**纯事实问题**：

    容器重启时，是「沿用原来的磁盘」，还是「从部署包重建一个新容器」？

沿用 → 落盘有效；重建 → 任何持久化都是白做。

这个模块只回答这个问题。**它不接触任何凭据**：写进去的是随机无用字符，
不写令牌、不写口令、不写密钥、不写真实用户数据。

边界（M0 2026-11-10T07:45:25Z 批复的六条）
------------------------------------------
1. 只写随机、无业务含义的标记字符串，并在一次容器重启后检查是否仍存在。
2. 目标路径、生成与清理方式、验证方式全部在邮件里事先说明。
3. 只做实现本测试所必需的最小改动；**不实现 JWT 落盘、不做自动恢复、
   不做凭据缓存、不改任何鉴权逻辑**。
4. 不读取/复制/打印/传输/覆盖真实 JWT，不访问 Supabase。
5. 标记不进 Git、不进部署包、不进日志、不进备份。
6. 只需一次发布；范围一旦超出就停下来先报告。
"""

import os
import secrets
import time

# 标记文件名。刻意用一个显眼、带前缀的名字：
# 这样在仓库/部署包的扫描里一眼能认出来，也便于构建脚本做「不许出现」的断言。
MARKER_NAME = "checkd-runtime-marker.txt"

# 三个候选路径，一次写入全部。为什么是三个而不是一个：
#   包目录 = 将来「令牌文件」会放的地方（就放在 app.py 旁边）。
#   /tmp   = 对照组。容器里 /tmp 经常是内存盘，重启必清。
#   家目录 = 另一个候选（若包目录被平台重建成只读或每次覆盖）。
# 三者的存活组合能把平台行为区分得比单一路径清楚得多：
#   三个都在          → 沿用磁盘（落盘可行）
#   只有 /tmp 不在     → 沿用磁盘但 /tmp 是内存盘（落盘仍可行，别放 /tmp）
#   包目录没了 /tmp 在 → 容器换了但 /tmp 被复用（罕见，但说明包被重铺）
#   三个都不在         → 每次重建容器（落盘无意义）
_CANDIDATES = (
    ("package_dir", lambda pkg_dir: os.path.join(pkg_dir, MARKER_NAME)),
    ("tmp", lambda pkg_dir: os.path.join("/tmp", MARKER_NAME)),
    ("home", lambda pkg_dir: os.path.join(os.path.expanduser("~"), MARKER_NAME)),
)


def _targets(pkg_dir):
    out = []
    for label, fn in _CANDIDATES:
        try:
            out.append((label, fn(pkg_dir)))
        except Exception as exc:                      # 路径都拼不出来就跳过
            out.append((label, None))
    return out


def _marker_text():
    """标记内容：时间戳 + 随机串。

    时间戳不是业务数据，只是为了「读回来时能确认是同一次写入」；
    随机串保证它不可能被当成任何凭证，也不可能与真实数据撞上。
    """
    return "MARKER %s %s\n" % (
        time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        secrets.token_hex(16),
    )


def write_markers(pkg_dir):
    """往三个候选路径各写一份标记。返回每条的处置结果（不回显到日志）。"""
    text = _marker_text()
    results = []
    for label, path in _targets(pkg_dir):
        if not path:
            results.append({"where": label, "path": None, "ok": False,
                            "error": "path_unresolved"})
            continue
        try:
            with open(path, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(text)
            st = os.stat(path)
            results.append({"where": label, "path": path, "ok": True,
                            "bytes": st.st_size})
        except Exception as exc:
            # 只报异常类型，不报路径细节之外的任何东西
            results.append({"where": label, "path": path, "ok": False,
                            "error": type(exc).__name__})
    return {"marker": text.strip(), "written_at_utc": time.strftime(
        "%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "results": results}


def read_markers(pkg_dir):
    """读回三个路径。**这是重启之后唯一要跑的动作。**"""
    results = []
    for label, path in _targets(pkg_dir):
        if not path:
            results.append({"where": label, "path": None, "exists": False,
                            "error": "path_unresolved"})
            continue
        try:
            exists = os.path.exists(path)
            item = {"where": label, "path": path, "exists": exists}
            if exists:
                with open(path, "r", encoding="utf-8", errors="replace") as fh:
                    content = fh.read(200)
                st = os.stat(path)
                item["bytes"] = st.st_size
                item["mtime_utc"] = time.strftime(
                    "%Y-%m-%dT%H:%M:%SZ", time.gmtime(st.st_mtime))
                item["content"] = content.strip()
            results.append(item)
        except Exception as exc:
            results.append({"where": label, "path": path, "exists": None,
                            "error": type(exc).__name__})
    return {"results": results}


def clean_markers(pkg_dir):
    """清理标记。**测试结论出来之前不调用**，调用即代表这一轮测试结束。"""
    results = []
    for label, path in _targets(pkg_dir):
        if not path:
            continue
        try:
            if os.path.exists(path):
                os.unlink(path)
                results.append({"where": label, "removed": True})
            else:
                results.append({"where": label, "removed": False,
                                "reason": "not_present"})
        except Exception as exc:
            results.append({"where": label, "removed": False,
                            "error": type(exc).__name__})
    return {"results": results}
