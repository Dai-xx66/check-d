# D6 测量：突发事件重排的移动数量与冲突情况 vs 最简单优先级基线

- **归属**：M3 / C（钟钰芬）
- **日期**：2026-11-03（D6）
- **任务来源**：`docs/CheckD_team_plan.md` D6（11/03）C 侧——「测量调度前后移动数量与冲突情况，和最简单优先级排序基线做对比」
- **被测对象**：M2 调度引擎 `lib/features/agent_scheduler/domain/schedule_engine.dart` @ `0f87d4431`（PR #2 head）
- **场景**：`fixtures/education/scenario_c_meeting_replan.json`（下午插入 15:00–16:30 固定会议）
- **证据级别**：**E1**（本机实跑 M2 源码，命令与输出可复现；快照哈希由脚本守卫）
- **结论一句话**：**块数维度 repair 明显胜出（1 块 vs 4 块），冲突两边都是 0；但「最小扰动」只对块数成立、对位移不成立——被移动那一块实际位移 7 小时，而就近可行位置只需 1.5 小时。**

## 1. 口径（先说清楚在量什么）

| 指标 | 定义 |
|---|---|
| `moved_count` | 与上一版提案相比，开始或结束时刻发生变化的柔性块数（新出现的块也计入，不掩盖） |
| `unchanged_count` | 位置完全不变的块数 |
| `shift_minutes_total` | 所有被移动块的 \|Δ开始时刻\| 之和（分钟） |
| `overlaps_fixed` | 新提案里的块与固定项（课程/会议）重叠的次数——**冲突情况的机器判据** |
| `overlaps_between_blocks` | 新提案内部块与块的重叠次数 |
| `unplanned_count` / `unplanned_minutes` | 未能排入的任务数与未排分钟 |
| `deadline_violations` | 结束时间晚于截止的块数 |
| `deterministic` | 相同输入连跑两次，提案 JSON 是否逐字节相同 |
| `nearest_feasible_delta_minutes` | 参照量：仅按「离原位置最近」选空档时的位移（用于量化「块数最少 ≠ 位移最小」） |

两条策略：

- **repair**：M2 的 `repairSchedule`（保留不冲突的块，只重排被撞掉的）；
- **baseline**：**最简单优先级排序基线** = 忽略上一版、每次从零整表重排，任务按截止/优先级贪心放置（即 M2 的 `generateSchedule`）。

## 2. 可复现命令

```bash
# 0) 引擎快照必须与固定 SHA 逐字节一致（不一致则测量结论作废）
python tools/m3-checks/check_vendor_m2.py

# 1) 跑测量（Dart SDK 3.12.2 stable，便携安装，不入仓）
dart tools/m3-checks/measure_reschedule.dart fixtures/education/scenario_c_meeting_replan.json
dart tools/m3-checks/measure_reschedule.dart fixtures/education/scenario_c_meeting_replan.json --json
```

- 基准日固定为 `2026-11-06`（周五）。理由：fixture 的两门课分别在周一/三、周二/四，而 fixture 的 4 条既有安排（09:30 / 14:00 / 15:00 / 21:00）与课程时段重叠，说明该场景的「今天」本身无课；周五是满足这一语义的确定性取值。课程在非当天不参与固定项。
- 引擎与 DTO 以 `tools/m3-checks/vendor/m2-scheduler/` 快照引入（`SOURCE.md` 记 SHA 与用途）；PR #2 合并后删除该目录，改引用 `lib/`。

## 3. 结果（本机实跑输出，原样）

```
会议插入前：块 4 个 / 排程 175 分钟 / 冲突 0
插入会议 15:00-16:30 → 与上一版冲突 1 处（待消解）

| 指标 | repair（最小扰动） | baseline（从零重排） |
|---|---|---|
| moved_count | 1 | 4 |
| unchanged_count | 3 | 0 |
| shift_minutes_total | 420 | 1505 |
| overlaps_fixed | 0 | 0 |
| overlaps_between_blocks | 0 | 0 |
| unplanned_count | 0 | 0 |
| deadline_violations | 0 | 0 |
| blocks_total | 4 | 4 |
| planned_minutes_total | 175 | 175 |
| deterministic | true | true |

被移动那块的位移：实际 -420 分钟 / 就近可行最优 +90 分钟
```

逐块明细：

| 任务 | 上一版 | repair 后 | baseline 后 |
|---|---|---|---|
| task-calc-homework（高数第三章习题） | 15:00–16:00 | **08:00–09:00**（−420） | 08:55–09:55（−365） |
| task-ds-report（数据结构实验报告） | 09:30–10:30 | 不动 | 09:55–10:55（+25） |
| task-eng-vocab（六级词汇） | 14:00–14:25 | 不动 | 08:00–08:25（−360） |
| task-reading（课外阅读） | 21:00–21:30 | 不动 | 08:25–08:55（−755） |

## 4. 三条结论

**4.1 块数维度：repair 胜，且满足当天关卡。**
repair 只移动 1 块（恰是 fixture 预期的 `task-calc-homework`），其余 3 块原位不动；固定项移动 0、与固定项冲突 0、块间冲突 0、未排 0、截止违例 0。对应 fixture 断言 C1/C2/C3/C4/C5 全部成立。baseline 移动 4 块（全表重排）。

**4.2 位移维度：repair 的「最小扰动」是块数意义上的，不是位移意义上的。**
被移动那一块从 15:00 挪到了 **08:00**，位移 420 分钟；而 16:30–17:30 当时就是空的（会议 16:30 结束、21:00 才有阅读块），**就近可行位置只需 90 分钟位移**。实际位移是最优的 **4.7 倍**。
原因在实现：`repairSchedule` 把被撞掉的块放进 `displaced` 队列，`_placeDemand` 从**最早可用**的空档开始放，没有「离原位置最近」的偏好。用户原话是「其他尽量别动」，把唯一被动的块甩到早上 7 小时前，体验上与「尽量别动」不符。

**4.3 baseline 的特征可以量化了：**
从零重排把 4 块全部压到 08:00–10:55 的连续区间（总排程分钟不变 175），总位移 1505 分钟、块数 4/4 —— 这是「最整齐」但「最扰民」的一版，正好用作对照：**只看排程紧凑度会得出 baseline 更优的错误结论，加上位移维度才看得出代价。**

## 5. 给 B（M2）的一条建议（不改代码，只提判据）

在 `displaced` 队列的放置排序里加一层 proximity：先尝试「原位置之后最近的可行空档」，再退到「原位置之前」，最后才按最早可用兜底。判据可以直接用本脚本的 `nearest_feasible_delta_minutes` 对照 `actual_delta_minutes`——两者相等即达到「位移最小」。这不是新增功能，属于 D6 B 侧「局部重排与扰动成本」的既有任务范围。

## 6. 边界（不掩盖）

1. **只测纯函数层**：不含 MCP 信封、审批、数据库写入与实际回读；「真实日历变化」仍属 A 轨，本测量不能替代。
2. **未走 LLM 编排**：fixture 的 prompt 没有经过 Agent 解析，输入是按 fixture 字段直接映射成 DTO 的。
3. **只跑场景 C**：场景 A/B 与边界用例未纳入本次测量（D7 的 C 侧任务是 ≥10 条边界用例，届时补）。
4. **Dart SDK 为便携安装**（`dart-sdk 3.12.2`），未写入仓库、未改系统 PATH；复现需本机有 Dart 或自行安装。
5. 基准日取 2026-11-06 属**确定性取值**，理由见 §2；换日期会改变输出，故写死在默认参数里而非取系统时间。

## 7. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-03 | 建立；M2 引擎 `0f87d4431` 实跑，repair 1 块 / baseline 4 块，冲突均 0；量化「块数最少 ≠ 位移最小」（420 vs 90 分钟） |
