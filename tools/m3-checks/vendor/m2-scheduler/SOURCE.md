# vendor/m2-scheduler —— 只读测量快照

- **来源**：`Tony2215/check-d` @ `0f87d4431`（PR #2 head，`feat/agent-scheduler` 分支）
- **文件**：`lib/features/agent_scheduler/domain/schedule_engine.dart`、`schedule_contract.dart`
- **用途**：M3（C）D6 测量脚本 `tools/m3-checks/measure_reschedule.dart` 在无 Flutter 工程环境下的**只读**依赖。
- **性质**：本仓自有代码（非第三方库，M2 自研确定性算法，见 `docs/scheduler/algorithm-and-license.md`），此处仅为固定 SHA 的快照，**不得在本目录内修改**；PR #2 合并后删除本目录，改从 `lib/features/agent_scheduler/domain/` 引用。
- **一致性守卫**：`tools/m3-checks/check_vendor_m2.py` 会比对本地快照与上述 SHA 的远程文件哈希；不一致即报错，避免快照被悄悄改动后测量结论失真。
