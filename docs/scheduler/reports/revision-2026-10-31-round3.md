# M2 增量修订报告（第三轮 · 2026-10-31）

> 指令来源：队长（@B），依据 C 完成的 M3 本轮增量审计。
> 契约基准：`2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6`（本轮上游无新提交）
> 代码基准：本提交（`feat/m2-scheduler-basic`，SHA 见文末）
> 纪律：不改 M0 契约本体、不扩大功能范围、不合并 PR；隔离 Dart 与宿主 Flutter 分开报告。

## 一、逐项结果

### 1. B18：`applying` / `readback_pending` 换新幂等键可能二次写入 —— **M2 侧无实现可改（已举证）**

M2 是纯函数调度器，**没有任何审批 / 幂等 / 写入代码路径**。证据：对两个源文件逐一检索
`approval / approval_id / token / idempotency / idempotent / applying / readback_pending /
expires_at / generated_at / snapshot_ref / input_digest`，命中全部为 0；
仅有的命中（2/2/1/1/3/2 处）全部是**状态枚举的符号名**与「服务端字段不得伪造」的**注释**，
不是实现。这不是推诿，是职权边界：**没有那段代码，就没有可改的地方。**

我能交付的是**可直接实现的判定顺序**（供 M1 mock / M0 契约落笔）：

```
apply_approved_changes(proposal_id, idempotency_key, approval_token, base_version):
  1. 幂等键已存在？
       ├─ 状态 applied            → 200，返回原结果（重放）
       └─ 状态 applying/readback_pending → 409 READBACK_PENDING，零写入
  2. 幂等键不存在，但同一 proposal_id 已有 applied 记录 → 409 ALREADY_APPLIED，零写入
  3. 同一 proposal_id 处于 applying/readback_pending（换键）→ 409 READBACK_PENDING，零写入
     （M0 2026-10-31 决定：任何新幂等键一律如此，堵住唯一二次写入通道）
  4. Proposal 已过 expires_at → 409 PROPOSAL_EXPIRED
  5. base_version 不一致 → 409 SNAPSHOT_CONFLICT，零写入
  6. Token 校验（在状态/版本检查之后）→ APPROVAL_CONSUMED / APPROVAL_EXPIRED / …
  7. 全部通过 → 写入 N 条 changes（N == proposal.changes.length），事务提交
```

以上每一步均**零写入**。需要 M1 在 mock 里按此顺序实现并补对应用例，需要 M0 把第 3 步写进 §6.7。

### 2. R1：Token 过期后的重新审批，不复用旧 approval_id —— **同为契约条文，M2 无实现**

按 §6.6 与 M0 的决定给出可落笔的规则，供 M1/M0：

```
Token 过期 → 旧审批终结（进入终态 APPROVAL_EXPIRED，不再视为「未终结」）
→ Proposal 尚未过 expires_at 时，允许重新 request_approval 创建**新的 approval_id**
→ 不复用旧 approval_id；「未终结审批」集合定义为 {approval_pending, token_issued}
```

仍待契约明写的两点：① §6.5 的「未终结」集合是否就是上面两个状态；② 过期判定用 `>=` 还是 `>`。

### 3. B19：`remaining_minutes_today` 的 null / 0 / 正数语义 —— ✅ 已明确并锁死

| 取值 | 语义 | 行为 |
|---|---|---|
| `null` | 没有当日口径（服务端快照未给） | 按完整 `duration_target_seconds` 排，标 `task_target` |
| `0` | 当天已做完 | **不排**、**不计入 unplanned_tasks**、产出 `ALREADY_DONE_TODAY`；**不进兜底** |
| 正数 | 当天剩余待做量 | 排这么多分钟，完整目标被折算覆盖，标 `task_target` |

三态都排在三级兜底（`max(minimum_block_minutes, 30)`）**之前**，绝不退化成 30 分钟兜底。
新增守卫用例：`冻结目标守卫 · B19：remaining_minutes_today 三态语义（null / 0 / 正数）`。

### 4. G1：`= 0` 不产生 block、不进入 unplanned_tasks —— ✅（已有用例 + 本轮强化）

用例 `P3 样例一` 断言：`blocks` 为空、`unplanned_tasks` 为空、产出 `ALREADY_DONE_TODAY`、
且不产出 `SCHEDULED`/`ESTIMATED_DURATION`（不落到兜底排 30 分钟）。本轮的三态用例再次覆盖。

### 5. G2：`= 40` 只安排 40 分钟、`duration_source=task_target` —— ✅（已有用例 + 本轮强化）

用例 `P3 样例二` 断言：完整目标 120 分钟（`targetDurationSeconds=7200`）时，
只排 40 分钟且 `duration_source == 'task_target'`。本轮的三态用例再次覆盖。

### 6. `input_digest` 包含 horizon 起止时间与 Asia/Shanghai 时区 —— 时区结论已撤回（C 指正）

M2 **不计算** `input_digest`（恒 null，禁止伪造），这是方案 A 的职责。M2 提供一条可执行证据：

- **horizon 必须纳入**：`冻结目标守卫 · horizon 起止会改变输出` —— 只改 `horizonEnd`
  （10:30 vs 22:00）输出就不同（1 块 vs 3 块）。摘要不覆盖 horizon 会让两个不同提案共享同一 digest。
- **时区结论已撤回**：原「digest 必须纳入时区」说法撤销——契约把 `timezone` 固定为
  Asia/Shanghai、不接受其他值，纳入 digest 永远不产生区分度（C 指正）。M2 侧保留事实性陈述：
  `冻结目标守卫 · 时区标签不改变 M2 输出（M2 不做时区转换）`。

建议的规范化输入（供 M0 落笔）：`{now, horizon_start, horizon_end, base_version, timezone,
availability, fixed_blocks, demands, existing_placements, preferences}` 按稳定键序序列化 + SHA-256。

### 7. Proposal 只输出内部调度 DTO，不自行生成服务端字段 —— ✅ 已落地并加递归守卫

上一轮已删除 M2 自行派生的 `proposal_id`；`snapshot_ref`/`input_digest`/`generated_at`/`expires_at`
从不构造。本轮新增守卫 `冻结目标守卫 · 内部调度 DTO 递归不含任何服务端字段`：
递归扫描输出 JSON，断言这 5 个服务端字段**在任意层级都不出现**。

**一处如实标注**：`base_version` 目前是服务端给定值的**原样带回**（echo，非生成）。
我已在上一轮向 M0 提问未获答复；若 M0 裁定连回声也不该出现在内部 DTO 里，回一句我删掉。

### 8. explanations 内部代码映射表 —— ✅ 已交付

`docs/scheduler/explanations-code-map.md`：9 个实际产出码（7 公共 + 2 repair 专用）+ 1 个已删除码
+ 4 个 `reason_code`（单列、与契约逐字一致）。每个码给出产出位置、触发条件、是否对外、推荐公共 code。
表与代码由守卫用例绑定，任一侧漂移立刻红。

## 二、修改文件（全在 M2 地盘）

- `test/agent_scheduler_test.dart`（+3 用例：B19 三态 / 时区证据 / 内部 DTO 递归守卫）
- `docs/scheduler/explanations-code-map.md`（新增，第 8 项的交付）
- `docs/scheduler/reports/revision-2026-10-31-round3.md`（本报告）
- `docs/scheduler/acceptance-matrix-m2.md`、`algorithm-and-license.md`（登记本轮）

**未动**：`lib/features/agent_scheduler/domain/*.dart`（本轮无需改实现，语义本就正确）、
M0 契约、任何他人文件。

## 三、测试结果（**两条通道分开报告**）

| 通道 | 命令 | 结果 |
|---|---|---|
| 隔离验证工程 | `cd /e/m2-verify && dart test` | **38/38 通过**（35 + 本轮 3 个新用例） |
| 宿主工程 | `cd /e/Projects/check-d-lhy && flutter test test/agent_scheduler_test.dart` | **未执行**：加载即失败 `Unable to connect to flutter_tester process: WebSocketException`，一行测试都没跑；不记通过也不记失败。期间被自动改写的 `GeneratedPluginRegistrant.swift` 与 `windows/flutter/generated_*.{cc,h,cmake}` 已还原 |

历史序列保留：18/18 → 22/22 → 26/26 → 28/28 → 29/29 → 30/30 → 35/35 → **38/38**。
**宿主 Flutter 与隔离 Dart 永远不合并统计**；M1 的 26/26 是 Mock 用例数，不并入。

## 四、未解决 BLOCKED

- R1 / B18 属契约条文，需 M1 在 mock 里实现、M0 落笔 §6.5/§6.7 —— M2 无代码可改（本报告给了判定顺序）。
- 时区解析（M2 明确不做时区转换，需服务端在 digest 规范化时纳入）。
- `base_version` 回声是否保留在内部 DTO（待 M0 确认）。
- 可信快照服务、`base_version` 事务内比较、`SNAPSHOT_CONFLICT` 可执行证据、
  `WRITE_BLOCKED`、WorkBuddy 真实认证与审批、生产回读。
- 宿主 `flutter test` 环境未修复（本次是 `flutter_tester` WebSocket 握手失败，与上轮 sqlite3 502 不是同一原因）。

## 五、提交

- 代码与测试提交：**`d8a5ab96698d279d593c023f35a6b9cb0834b456`**（已推 `feat/m2-scheduler-basic`，PR #2 自动更新）。
- 本报告 SHA 回填属文档微调，追加在下一提交。
