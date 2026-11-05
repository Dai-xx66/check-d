# B（M2）按 M0 2026-10-31 决定的增量修订

> 执行人：B（M2）　日期：2026-10-31　分支：`feat/m2-scheduler-basic`（PR #2）
> 依据：队长转达的 M0 正式决定（P1 时长兜底 / P2 explanations 枚举 / P3 示例 /
> P4 Proposal 序列化 / 五·四条安全问题）
> 契约基准：`2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6`（未改动 M0 契约本体）
>
> **执行边界**：只改自己的 M2 分支；不修改契约本体；不开发新功能；不合并 PR。

## 一、逐条执行结果

### P1 时长兜底 —— 照办，并补两条防误解的注释

| 决定 | 落地 |
|---|---|
| 保留 `max(minimum_block_minutes, 30)` | 保留（上一轮已补齐） |
| 不删除本次修复 | 未删除 |
| `requiredMinutes` 代表服务端可信快照估算，**不接受 LLM 直接提供的伪可信估算** | 写进 `ScheduleTaskDemand.requiredMinutes` 的契约注释：只能由服务端包装层从一致性快照折算后填入；它是进程内 DTO 字段，**不是** `generate_schedule` 远程请求参数 |
| `remaining_minutes_today = 0` 仍为特殊情况，**不进入时长兜底** | `_durationOf` 里该分支排在三级之前直接返回 0，并加注释说明「已做完 ≠ 没有时长依据」；新增 P3 样例一锁死（见下） |

### P2 explanations 枚举 —— 已封闭，并把两侧都对齐了

v1 公共枚举写进代码：`kPublicExplanationCodes`（7 个），repair 专用码写进
`kRepairOnlyExplanationCodes`（`DISPLACED_BY_FIXED`、`REPAIR_SUMMARY`）。

| 我原有的码 | 处置 |
|---|---|
| `SCHEDULED` `NO_AVAILABILITY_WINDOW` `AVAILABILITY_SATURATED` `FIXED_BLOCKS_OVERLAP` `ALREADY_DONE_TODAY` | 本就在公共枚举内，保留 |
| `NO_VALID_DURATION` | **不进公共枚举** → 已把这条分支整段删掉（它本就不可达），不再产出任何需要服务端再过滤一次的输出 |
| `DISPLACED_BY_FIXED` `REPAIR_SUMMARY` | 留在 repair 逻辑，并在 `ScheduleNote.isPublic` 与 `ScheduleProposal.publicExplanations` 上明确标为**不得进入 v1 远程响应** |

**两侧同步核对的结果**（按"不要只改一侧"的要求）：

- 示例侧：示例里用的 `PRESERVED_FIXED_EVENTS`、`ESTIMATED_DURATION` 现已是枚举成员 ✅；
  示例出现的错误码（`READBACK_PENDING` 等）不在 explanations 枚举管辖范围内，无冲突。
- M2 侧：我原来**不产出**这两个码，而示例和枚举都用它们。已补齐语义明确的产出：
  - `PRESERVED_FIXED_EVENTS`：输入含固定块时产出一条全局说明（固定课程/会议一律保留、不为其让位）；
  - `ESTIMATED_DURATION`：凡是 `duration_source = scheduler_estimate` 的块都产出一条带 `related_task_ids` 的说明（估算不写回 Task）。
- 新增守卫：generateSchedule 的每条解释必须 `isPublic`；repair 输出只允许出现已登记的两个内部码；
  `publicExplanations` 过滤后不含内部码。**任一侧新增了枚举外的码，测试立刻红。**

### P3 示例 —— 两个服务端内部快照样例已变成可执行用例

| 样例 | 期望 | 用例 |
|---|---|---|
| `remaining_minutes_today = 0` | 不产生 block、不进 `unplanned_tasks`、产出 `ALREADY_DONE_TODAY` | `冻结目标守卫 · P3 样例一` |
| `remaining_minutes_today = 40`，完整目标 120 分钟 | 只排 40 分钟，`duration_source = task_target` | `冻结目标守卫 · P3 样例二` |

样例一里我额外断言了 `codes` 不含 `SCHEDULED` / `ESTIMATED_DURATION`——用来证明 `= 0`
确实没掉进兜底（否则会排出 30 分钟）。

`remaining_minutes_today` 与 `scheduling_weight` 的注释已写明：**只属服务端可信快照，
不得作为 LLM 远程请求参数**。

### P4 Proposal 序列化 —— 选方案 A，M2 停止伪造服务端字段

**这条动到了真实行为**：我原来会自己派生 `proposal_id`（`_proposalId(input, prefix)`，
由 baseVersion + 任务 ID 拼出）。方案 A 下这属于"M2 自行生成服务端字段"，已整段删除。

现在 M2 的输出**不含** `proposal_id`；`snapshot_ref` / `input_digest` /
`generated_at` / `expires_at` 一如既往不构造（模型不得伪造）。
`base_version` 保留为**原样带回**服务端给进来的值，不生成、不改写——便于服务端对账，
若 M0 认为连它都不该出现在内部结果里，回一句我删。

> `status` 不在 M0 列举的"服务端生成"字段里，因此仍恒为 `draft`。
> 若 M0 希望连 `status` 也一并移交给服务端状态机，同样一句话的事。

### 五 · 四条安全问题 —— 前三条是契约侧，我只能核对与留档

| # | 决定 | M2 能做的 | 状态 |
|---|---|---|---|
| 1 | R1：Token 过期后旧审批终结；Proposal 仍有效时允许重建 `approval_id` | 契约 §6.5/§6.6 属服务端语义，M2 无审批逻辑。已把这条从「必修缺口」改为「已决定、待契约文本落地」 | 等 M0 写进契约 |
| 2 | X1：`applying`/`readback_pending` 时任何新幂等键返回 `READBACK_PENDING`、零写入 | 同上；已在矩阵与清单里标记为已决定 | 等 M0 写进契约 |
| 3 | `input_digest` 覆盖 horizon 起止与 Asia/Shanghai 时区 | 补了一个可执行证据：**只改 horizonEnd 就会改变输出**（窄到 10:30 只排 1 条，宽到 22:00 排 3 条），因此摘要不覆盖 horizon 会让两个不同提案拿到同一 digest。时区只作为可规范化字段携带 | **M2 不做时区转换**（见 BLOCKED） |
| 4 | 明确 Proposal/Approval 状态迁移、过期边界、`readback_pending` 恢复路径 | 契约侧；M2 只保证自己产出的结果不带终态语义（恒 `draft`） | 等 M0 补图与口径 |

## 二、修改文件（全部在 M2 地盘内）

| 文件 | 改动 |
|---|---|
| `lib/features/agent_scheduler/domain/schedule_contract.dart` | 删除 `ScheduleProposal.proposalId` 及其 JSON 输出；新增 `kPublicExplanationCodes`（7 个公共码）、`kRepairOnlyExplanationCodes`、`ScheduleNote.isPublic`、`ScheduleProposal.publicExplanations`；`requiredMinutes` / `remainingMinutesToday` 补来源与"不得作远程请求参数"注释 |
| `lib/features/agent_scheduler/domain/schedule_engine.dart` | 删除 `_proposalId` 及 4 处调用；删除 `NO_VALID_DURATION` 分支；新增 `PRESERVED_FIXED_EVENTS` 与 `ESTIMATED_DURATION` 产出；`_durationOf` 补 `= 0` 不走兜底的注释 |
| `test/agent_scheduler_test.dart` | 去掉 `proposal_id` 相关断言；新增 4 个用例（P3 样例一/二、枚举合规 + repair 码不外泄、horizon 影响输出、时区仅作可规范化字段） |

**没有**改动任何他人文件。`flutter test` 尝试期间被自动重写的
`macos/Flutter/GeneratedPluginRegistrant.swift` 与 `windows/flutter/generated_*.{cc,h,cmake}`
已 `git checkout --` 还原；`pubspec.yaml` / `pubspec.lock` 未被改动。

## 三、测试命令与真实执行结果（**隔离与宿主分开报告**）

### 1) 隔离验证工程 —— 真实执行，通过

```bash
# 工程：E:\m2-verify（纯 Dart，不依赖 Flutter 插件与原生库）
export PATH="/e/flutter/bin:$PATH"
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
cd /e/m2-verify && dart test
```

结果：**35/35 通过**（`dart test`，Dart VM 通道）。
历史数字 18/18 → 22/22 → 26/26 → 28/28 → 29/29 → 30/30 → **35/35** 全部保留，不合并。

### 2) 宿主工程 `flutter test` —— 尝试过，**未通过，且失败与本次改动无关**

```bash
export PATH="/e/flutter/bin:$PATH"
cd /e/Projects/check-d-lhy && flutter test test/agent_scheduler_test.dart
```

结果：**未跑起来**。卡在原生资产构建阶段：

```
Building native assets failed.
By default, this package downloads a pre-compiled SQLite library. This failed
(attempted to download .../sqlite3-3.8.0/sqlite3.x64.windows.dll).
Original cause: HttpException: Proxy failed to establish tunnel (502 Bad Gateway), uri = //github.com:443
```

即 `sqlite3` 的 hook 要从 GitHub 下载预编译 DLL，本机代理返回 502，构建中止，
**一行测试都没执行**。这是环境/网络问题，不是代码问题；我不把它记为"通过"，也不记为"失败"。

> 与上一轮的区别：此前记录的原因是"插件 symlink / Windows 开发人员模式"，
> 本轮实测到的失败点已变成 sqlite3 原生库下载被代理拒绝。两个原因都成立、都不归我。

## 四、未解决的 BLOCKED 项

| 项 | 状态 | 说明 |
|---|---|---|
| **时区** | **BLOCKED（M2 侧明确不做）** | M2 直接用 Dart `DateTime`、**不做时区转换**，假设服务端传入已是 +08:00。`input_digest` 要覆盖时区这件事只能由服务端在规范化时做；M2 只能保证该字段在输入上可拿到 |
| R1 / X1 / 状态机图 / 过期边界 / `readback_pending` 恢复路径 | BLOCKED 至契约落地 | 属 M0 契约条文，M2 无审批与状态机实现；本轮只做核对与留档 |
| `base_version` 生成与校验 | BLOCKED | 契约 §7.2 自标 BLOCKED；M2 只原样带回 |
| `SNAPSHOT_CONFLICT` / `WRITE_BLOCKED` 证据 | BLOCKED | 需要真实快照与原子写入 |
| WorkBuddy 真实认证、真实审批、生产回读 | BLOCKED | 全队一致，未变 |
| 真实 Proposal Schema 校验 | BLOCKED | 方案 A 下由服务端序列化，M2 侧无完整 Proposal 可校验（这正是方案 A 的结论） |

## 五、请 M0 在新契约里落笔的四条（我这边已按"已决定"记账，但文本还没改）

1. §6.5：明确"未终结审批"集合，并写明 **Token 过期 → 旧审批终结 → Proposal 未过期时可新建 `approval_id`**（否则 R1 仍在）。
2. §6.7：写明 `applying` / `readback_pending` 下**任何新幂等键**一律 `READBACK_PENDING` 且零写入。
3. §5.7：`input_digest` 的规范化输入**显式列入 horizon 起止与 Asia/Shanghai 时区**。
4. §5.7 状态机图：补 Approval 迁移图、Proposal×Approval 组合表、过期边界口径（`>=` 还是 `>`）、
   `readback_pending` 的恢复路径。

另附两条待 M0 一句话确认的判断题（我已按最合理方式落地，可推翻）：
- `base_version` 是否允许 M2 原样带回（现允许）；
- `status` 是否仍由 M2 恒出 `draft`（现保留）。
