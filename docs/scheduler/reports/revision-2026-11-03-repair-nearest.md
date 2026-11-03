# M2 修订报告（2026-11-03）· repair 就近重排：最小扰动补上位移维度

> 触发：M3（C）2026-11-03 邮件《D6 当日结果》（提交 `a7af452`，PR #1 评论 `6594577354`）
> 契约基准：`c9dda83195a9af4b9ca762d8556fdd0e8d43010a`（无新 SHA，本轮不跑增量 diff）
> 代码基准：`feat/m2-scheduler-basic`，本次提交（SHA 见文末）
> 范围：仅 `lib/features/agent_scheduler/domain/schedule_engine.dart` + `test/agent_scheduler_test.dart`，
> 不改契约本体、不改公共 explanations 枚举、不合并 PR。

## 一、C 测出来的问题（原话要点）

C 用我 PR #2 head `0f87d4431` 的真实 `repairSchedule` 跑 `scenario_c_meeting_replan`
（15:00–16:30 插入固定会议），结果：

| 指标 | repair | baseline（从零重排） |
|---|---|---|
| 移动块数 | **1** | 4 |
| 总位移（分钟） | **420** | 1505 |
| 冲突 / 重叠 / 未排 / 截止违例 | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |

他的判词很准：**「最小扰动」只在块数维度成立，位移维度不成立。**
唯一被撞掉的那块（高数第三章习题）从 15:00 挪到 08:00，位移 420 分钟；
而 16:30–17:30 当时是空的，**就近只需 90 分钟**——实际是最优的 4.7 倍。
用户的原话是「其他尽量别动」，把唯一被动的块甩到 7 小时前，跟这句话不符。

根因也确实在实现里：`_placeDemand` 只做「最早可用」，**没有「离原位置最近」的偏好**。

## 二、修复

新增 `_placeNearest(free, demand, input, originStart)`，只在 `repairSchedule` 里对
**上一版已有位置**的块使用；新加入的任务仍走原来的最早可用（它们没有「原位置」可言）。

规则按序：

1. 在同一个空闲片段内，可行起点是连续区间 `[minStart, latestEnd - need]`
   （`minStart` 已并入 `now`、`earliestStartAt`；`latestEnd` 已并入截止）。
   所以**离原位置最近的点**就是把原位置夹进这个区间：`clamp(originStart, minStart, maxStart)`。
2. 跨片段取位移最小的候选；
3. 位移相同时**优先落在原位置之后**（往后顺延比往前甩更符合预期）；
4. 所有片段都放不下才返回 `null`，由调用方退到最早可用兜底（不会消失、也不会被静默丢弃）。

顺带把扰动成本**两维都可读**：

- `REPAIR_SUMMARY` 文案：`共移动 N 处安排，总位移 M 分钟，其余保持不变。`
- `DISPLACED_BY_FIXED` 文案：`…从 15:00 就近移到 16:30–17:30（位移 90 分钟）。`

两个 code 仍在 repair 内部（`ScheduleNote.isPublic == false`），不进 v1 公共 explanations 枚举，
与 `explanations-code-map.md` 的隔离规则一致。

## 三、同场景行为对比

C 的场景骨架（15:00–16:00 有一块，插入 15:00–16:30 会议，16:30–17:30 空闲）：

| | 修复前 | 修复后 |
|---|---|---|
| 移动块数 | 1 | 1（不变，块数维度本来就没问题） |
| 被撞块的落点 | 08:00 | **16:30** |
| 位移 | 420 分钟 | **90 分钟** |
| 是否等于最近的可行位移 | 否（4.7 倍） | **是** |

## 四、测试（新增 3 条，总数 40 → 43）

1. `被撞掉的块就近重排：落在原位置之后最近空档，不是最早可用`
   —— 4 块既有安排（8:00/9:30/13:00/15:00）＋ 15:00–16:30 会议：被撞块必须落 **16:30（位移 90）**，
   且显式排除老实现的 11:00 落点；同时断言其余 3 块 `movedFromPreviousPlan == false`（块数维度不回退）。
   并断言 `DISPLACED_BY_FIXED` 含「位移 90 分钟」、`REPAIR_SUMMARY` 含「总位移 90 分钟」。
2. `就近重排：位移相同时优先落在原位置之后`
   —— 之后 16:00（+60）与之前 14:00（−60）等距，取**之后**。
3. `就近重排：只有往前才排得下时才往前，不跳到最早可用`
   —— 14:00 之后无空档，前移到 **13:00（−120）**，而不是 08:00（−420）。

运行结果（两条通道分开记录）：

| 通道 | 命令 | 结果 |
|---|---|---|
| 隔离 Dart | `cd /e/m2-verify && dart test test/agent_scheduler_test.dart` | **43/43 通过**，退出码 0 |
| 宿主 Flutter | `env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy flutter test test/agent_scheduler_test.dart` | **43/43 通过**，退出码 0 |

## 五、与 C 的验收判据对齐

C 建议的判据是 `nearest_feasible_delta_minutes == actual_delta_minutes`。本实现按**构造**满足它：

- 同一片段内不存在比 `clamp` 结果更近的可行起点——可行起点是连续闭区间，`clamp` 就是区间上的最近点；
- 跨片段取最小，因此全局最近；
- 「等距取之后」「只能往前才往前」两条边界各有独立用例，避免判据在平局处退化成偶然成立。

**需要 C 用他的脚本在新 SHA 上重跑**才能算 E1 闭环——我这边只能证明「落点 = 我算出的最近可行点」，
不能替代他的测量脚本与 fixture。

## 六、边界与遗留

- **不改契约**：未新增/删除任何 explanation code，未改 DTO 字段，未动 §5.7 序列化职责。
- **不改 baseline 策略**：`generateSchedule` 仍是「最早可用贪心」，从零重排的位移劣势（1505 分钟）
  是它的固有特征，本轮不优化——C 用它做对照，保持原样才有可比性。
- **未覆盖**：场景 A/B、≥10 条边界用例属 D7；审批与真实日历变化仍是 BLOCKED（A 轨）。
- **隔离工程的同步方式已修正**：原先 `/e/m2-verify/lib/` 下有两份同名副本，
  `package:m2_verify/schedule_engine.dart` 实际指向顶层那份（不是 `features/...` 那份），
  导致改完源码后隔离通道仍跑旧代码。现已改为指向
  `package:m2_verify/features/agent_scheduler/domain/...` 并删除顶层重复文件，
  与仓库路径一一对应。这个坑差点让「改完就绿」变成假通过，记在这里。
