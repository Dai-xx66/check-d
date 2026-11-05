# maxShiftMinutes 服务层接入落点说明

> 依据：M0 2026-11-03 05:49 邮件 B 项（服务层默认 120 的接入落点说明）。
> 维护人：B（M2）。本文件**只写说明，不新造 service wrapper，不改 DTO / API 契约**。

## 一、现状结论：真实服务层调用入口**尚不存在**

全仓证据（2026-11-03，head `6609c3b` 之后核实）：

```
grep -rn "repairSchedule" --include=*.dart lib/
# 仅 3 处，全部在 domain 层：
#   schedule_contract.dart:293  （文档注释）
#   schedule_engine.dart:5      （文档注释）
#   schedule_engine.dart:560    （函数定义）
grep -rn "agent_scheduler\|generateSchedule" lib/features/schedule/ lib/app/ lib/core/
# 零引用
```

- `lib/features/agent_scheduler/` 目前**只有 `domain/`** 一个子目录，没有
  application / data 层；
- `maxShiftMinutes` 目前只出现在测试里（显式 60 / 120 / 180）；
- 因此「服务层默认 120」是**待接入**状态，现在硬造包装层就是没有调用方的死代码，
  M0 已明确本轮不造。

## 二、未来第一个真实调用方的准确落点

按当前代码分层推断（**预测性落点，文件/类/方法名以届时实际为准，M2 不猜死名字、
不预先创建**）：

| 候选 | 路径 | 依据 |
|---|---|---|
| 最可能 | `lib/features/schedule/application/` 下未来新增的 agent 调度 provider | 该目录已是 Riverpod application 层（现有 `day_schedule_providers.dart`），负责组装 repository + 领域调用，与 `lib/core/sync`、通知等基础设施的接线模式一致 |
| 次可能 | 契约 §5.7 的服务端包装层（proposal_id / snapshot / base_version 事务层，A 轨/M0 侧） | 契约把 `repairSchedule` 的真实入口定义在服务端包装层，该层负责幂等键与事务核验 |

规则：**谁建入口谁接线**。M2 的地盘是 `agent_scheduler/domain`，不越界去
`lib/features/schedule/` 建文件；入口出现时 M2 只做两件事——确认传参、补验收测试。

## 三、传参规则（M0 2026-11-03 裁定）

1. **服务层默认 120**：服务层调用 `repairSchedule` 时显式传
   `maxShiftMinutes: 120`。建议 domain 层届时导出
   `const int kDefaultMaxShiftMinutes = 120;` 作为单一事实源，服务层引用常量
   而非写字面量——将来改阈值只动一处。常量的引入属于 domain 小改，等入口
   出现时与接入同一轮提交。
2. **显式覆盖优先**：调用方显式传值时按显式值，不与服务层默认合并。
3. **domain 的 Dart 默认值保持 `null`（无边界）**：`120` 是**服务层职责**，
   不是 Dart 语义默认。两者必须区分，有专门守卫测试钉死（见下）。
4. **新加入任务不得套用阈值**：`maxShiftMinutes` 只约束「上一版已有位置」
   （displaced）的块的就近重排；上一版里不存在的新任务走最早可用，天然
   不受该参数影响——这是实现的构造性行为（`_placeNearest` 仅对
   `originStartByTask` 中有原位置的块生效），服务层无需（也不应）做额外过滤。
5. 阈值依据：C 的扫描显示 120 落在 [90, 180] 中段偏下，给 90 分钟最近可行
   移动留 30 分钟余量，同时挡住 420 分钟那类大幅回退。

## 四、验收标准（三类测试）

| 类别 | 断言内容 | 现状 |
|---|---|---|
| **不传参 = 无边界（domain 守卫）** | `repairSchedule(input, previous)` 缺省时：+180 分钟位移的候选**被接受**（若有人把 Dart 默认值改成 120，此断言立刻变红）；同一场景显式 120 → 超界退最早可用 08:00 | ✅ 已有：`test/agent_scheduler_test.dart`「不传 maxShiftMinutes 就是无边界：超 120 分钟的位移照常接受」（本轮新增，第 48 条） |
| **显式覆盖行为（domain 守卫）** | 显式 60 → 两侧超界退 08:00；显式 180 → 界内候选不误杀仍落 17:00；显式 120 → 180/360 均超界退 08:00 | ✅ 已有：三条既有 repair 边界用例 + 本轮新用例的第二断言 |
| **服务层默认路径测试** | 服务层调用**不显式传参**（走其内部默认 120）时，行为必须等于显式传 120：C 场景（15:00 被撞）落 16:30（+90）而非 08:00（−420）；显式传 300 等其他值时按显式值 | ⏳ 待入口出现后补——没有调用方就没有默认路径可测，提前写就是假测试。届时由服务层所属负责人补该层测试，M2 提供 domain 侧对照用例作参考基准 |

补充：M0 说的「证明默认调用会传入 120」在包装层落地前**没有证明点**——
这不是 M2 拖延，是调用方不存在。落点出现后此条自动升级为必测。

## 五、边界

- 本文件与配套守卫测试不改 domain 默认值、不改算法策略、不新增服务层入口；
- 不动 `lib/features/schedule/`（他人地盘）；
- 不改公共契约：`maxShiftMinutes` 不进 API DTO，是服务端→domain 的进程内参数；
- 冻结组合不受影响：录制代码 `7e1367c2` + 契约 `39f7f965` 未动。
