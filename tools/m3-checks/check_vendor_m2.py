"""守卫：本地 M2 调度引擎快照必须与固定 SHA 的远程文件逐字节一致。

为什么需要它
    `tools/m3-checks/measure_reschedule.dart` 跑的是 vendor 里的快照。
    如果快照被悄悄改动（例如为了「跑通」而改一行），D6 的测量结论就不再
    指向 M2 的真实实现。本脚本把「快照 == 远程固定 SHA 文件」变成可机检的事实。

用法
    python tools/m3-checks/check_vendor_m2.py            # 联网比对（默认）
    python tools/m3-checks/check_vendor_m2.py --offline  # 只报本地哈希，不联网

退出码
    0 = 一致（或 offline 模式下仅输出）
    1 = 不一致 / 文件缺失
    2 = 网络或读取失败
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import sys
import urllib.request

PINNED_SHA = "e77623217"
REMOTE_TEMPLATE = (
    "https://raw.githubusercontent.com/Tony2215/check-d/{sha}/{path}"
)
FILES = [
    "lib/features/agent_scheduler/domain/schedule_engine.dart",
    "lib/features/agent_scheduler/domain/schedule_contract.dart",
]
VENDOR = pathlib.Path(__file__).resolve().parent / "vendor" / "m2-scheduler"


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()

    ok = True
    for rel in FILES:
        local_path = VENDOR / pathlib.Path(rel).name
        if not local_path.exists():
            print("✗ 缺失本地快照: %s" % local_path)
            ok = False
            continue
        local_bytes = local_path.read_bytes()
        local_hash = _sha256(local_bytes)
        if args.offline:
            print("· %s  %s" % (local_path.name, local_hash[:16]))
            continue
        try:
            with urllib.request.urlopen(
                REMOTE_TEMPLATE.format(sha=PINNED_SHA, path=rel), timeout=30
            ) as resp:
                remote_bytes = resp.read()
        except Exception as exc:  # noqa: BLE001
            print("✗ 取远程失败 %s: %s" % (rel, exc))
            return 2
        remote_hash = _sha256(remote_bytes)
        same = local_hash == remote_hash
        ok = ok and same
        print(
            "%s %-28s 本地 %s / 远程 %s"
            % ("✓" if same else "✗", local_path.name, local_hash[:16], remote_hash[:16])
        )

    print("结论：%s（固定 SHA %s）" % ("一致" if ok else "不一致", PINNED_SHA))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
