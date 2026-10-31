# B（M2）契约增量对齐记录：c53b1a9（M0 新固定 SHA）

> 指令来源：队长 2026-10-31 邮件「[CheckD][M2] M0 新 SHA 已发布｜调度 DTO 与公开枚举增量对齐」。
> 对齐对象：`upstream/feat/m0-api-contract` → **`c53b1a91c17cd9acdee6d3937c093fcf97515ba0`**
> （`docs/contracts/agent-api-v1.md` + `docs/contracts/agent-api-v1.examples.json`，PR #4）。
> 上一轮基准：`2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6`。
> 日期：2026-10-31　对齐人：B（M2）
>
> **纪律：不修改 M0 契约本体；不扩大业务实现；不碰 TaskRepository / app_database / 他人文件；
> 本轮只做「红线信号」命中的代码改动 + 守卫用例，其余只记结论。**

## 零、契约文件清单核验（diff 查不出新增/删除文件）

```bash
git ls-tree -r --name-only c53b1a91c17cd9acdee6d3937c093fcf97515ba0 | grep contracts
```

结果仍是两份文件：`docs/contracts/agent-api-v1.md` + `docs/contracts/agent-api-v1.examples.json`，无增删。

## 一、增量 diff 结论（contract-diff-check.sh 输出要点）

- 变更规模：md 新增 179 行 / 删除 28 行；examples.json 新增 878 行 / 删除 4 行。
- 工具清单：仍是七个工具，无改名、无第 8 个。✅
- 错误码集合：新增 `IDEMPOTENCY_IN_PROGRESS`（1 个）。
- 冻结关键字：`READBACK_PENDING`/`APPROVAL_CONSUMED`/`token_issued` 等计数上升（审批/回读状态机补全）。
- TTL：Proposal 固定 30 分钟、Token 5 分钟，无「当日 23:59 截断」口径。✅（我此前的「当日截断」旧建议已作废，无需再退。）

## 二、逐条核对（队长邮件 6 项 + 清单 8 项）

| 项 | 判据 | 结论 | M2 动作 |
|---|---|---|---|
| 工具清单 | 仍是七个 | ✅ 无变化 | 无 |
| 时长优先级第三级 | 兜底仍是 `max(minimum_block_minutes, 30)` | ✅ 无变化 | 无 |
| `remaining_minutes_today` 三态 | null / 0 / 正数语义不变 | ✅ 无变化 | 无 |
| `explanations[].code` 公开枚举 | 七值闭集 | ✅ 契约已写死七值，与我 `kPublicExplanationCodes` 逐字一致 | 无代码改动，守卫已绑定 |
| repair 专用码不外泄 | `DISPLACED_BY_FIXED`/`REPAIR_SUMMARY` 禁止进 v1 | ✅ 契约明文 | 已有 `kRepairOnlyExplanationCodes` + 守卫 |
| `violations` 七值闭集（新 §5.8） | 服务端校验职责 vs M2 纯函数职责 | ⚠️ 见下 | **不实现 violations**（见第三节） |
| Proposal 序列化方案 A | M2 不输出服务端权威字段 | ✅ **契约从「暂定」改为「明文」** | **命中红线，改代码**（见第四节） |
| `input_digest` 覆盖 horizon + 时区 | Asia/Shanghai 纳入摘要 | ✅ 契约明文 | M2 无 digest 实现；时区证据用例已保留 |

## 三、violations：不做，但要说明边界

新 §5.8 定义了 `validate_schedule.violations` 的统一对象结构与七值闭集
（`PLANNED_BEFORE_AVAILABLE_FROM`、`PLANNED_AFTER_DATE_ONLY_DEADLINE`、
`BLOCK_AFTER_EXACT_DEADLINE`、`BLOCK_TIME_INVALID`、`FIXED_EVENT_CONFLICT`、
`MULTIPLE_CHANGES_FOR_ONE_TIME_TASK`、`MULTIPLE_BLOCKS_FOR_RECURRING_TASK_DAY`），
未知 `code` 以 `PROPOSAL_INVALID` 拒绝。

**归属判定**：`violations` 是 `validate_schedule` 这一**服务端校验工具**的输出，
不是 M2 纯调度函数的职责。队长邮件第 3 项明确「区分服务端校验职责和 M2 纯函数职责；
不要求 M2 自行实现服务器认证或写入」。因此：

- **M2 不产出 `violations`、不产出 `PROPOSAL_INVALID`**，不新增任何 violation 枚举/字段。
- M2 仍只输出 `blocks` / `changes` / `unplanned_tasks` / `explanations` 四部分内部结果。
- 结构错误（如 `scheduled_at` 与 `planned_date` 跨本地日）在 M2 侧由「单次事项必须显式带
  与 `planned_date` 同日的 `scheduled_at`」守卫从源头避免，不留该路径。

## 四、命中的红线信号：Proposal 序列化方案 A（改代码）

契约 §5.7 本次**明文写死**方案 A：M2 纯调度函数「不得生成或输出 `proposal_id`、
`snapshot_ref`、`base_version`、`input_digest`、`generated_at`、`expires_at` 或 `status`」。
上一轮（2c48579）只是「暂定方案 A」，我的 `toJson()` 当时仍带出 `base_version` / `status`
（且可选 `snapshot_ref` / `input_digest`）。本轮契约把它定为硬规则，因此**必须改**：

改动的文件（仅 M2 三块地盘内）：

- `lib/features/agent_scheduler/domain/schedule_contract.dart`
  - `ScheduleProposal` 移除 `baseVersion` / `status` / `snapshotRef` / `inputDigest` 字段；
    构造函数只保留 `blocks` / `changes` / `unplannedTasks` / `notes`。
  - `toJson()` 只输出 `blocks` / `changes` / `unplanned_tasks` / `explanations` 四部分。
  - `ScheduleProposalStatus` 枚举保留作契约状态机的进程内参照，更新注释标明它是
    服务端权威字段、M2 不序列化（契约状态机迁移图仍属验收参照）。
- `lib/features/agent_scheduler/domain/schedule_engine.dart`
  - `generateSchedule` / `repairSchedule` 的 `ScheduleProposal(...)` 构造去掉 `baseVersion:` 实参。

守卫用例同步（`test/agent_scheduler_test.dart`）：

- 「内部调度 DTO 递归不含任何服务端字段」：黑名单加入 `base_version`、`status`。
- 「写入次数可推算…」：改为断言 `status` / `snapshot_ref` / `input_digest` **不出现在** JSON。
- 「提案 JSON 字段与契约第 5.7 节一致」：改为断言 `status` 不出现在 JSON。
- 「DTO 键集合与契约逐字对齐」：顶层允许键收敛为 `blocks/changes/unplanned_tasks/explanations`
  四个，服务端字段一律不得出现。
- 三处 `repairSchedule` 用例里直接构造 `ScheduleProposal(baseVersion: ...)` 的实参删除。

`ScheduleInput.baseVersion` **保留**（它是 M2 的**输入**，服务端把版本随快照给进来，
M2 用它承接版本校验，不生成、不改写、不序列化回输出）。

## 五、两套测试（分开报告）

- **隔离工程 `/e/m2-verify`（`dart test`，纯 Dart VM）**：**38/38 通过**。
- **宿主工程 `flutter test test/agent_scheduler_test.dart`**：**38/38 通过**
  （本轮宿主环境正常，flutter_tester 未触发 WebSocket/sqlite3 异常；跑完已
  `git checkout --` 还原被自动改写的 `macos/Flutter/GeneratedPluginRegistrant.swift`
  与 `windows/flutter/generated_*`）。

## 六、未解决项 / 待队长答复

1. 无新增阻塞。`violations` 七值闭集已落契约，属服务端职责，M2 不实现（第三节）。
2. `base_version` 作为输入仍由 M2 承接，但**不再序列化回输出**——若服务端需要 M2 回传
   对账版本，应由服务端包装层自己在组装时写入，请队长确认这条口径。

## 七、PR #2 状态

- 分支 `feat/m2-scheduler-basic`，本轮提交见 `git rev-parse HEAD`。
- 未合并 PR，未碰 M0 契约 / TaskRepository / app_database / 他人文件。
