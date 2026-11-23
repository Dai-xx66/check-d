# M2 · A2 决策—代码—测试追踪矩阵（回归补强）

> **依据**：M0 2026-11-05 `[CheckD][M0] 11-05 任务续派与验收口径确认` 第三节【M2】。
> **交付形式**：独立分支 `feat/m2-a2-traceability`（基于 `070fb6e`），**不合并主线**。
> **性质**：追踪矩阵（只读）+ 真缺口补测（3 条）。**未改动任何 domain 逻辑**。

## 基准声明

| 项 | 值 |
|---|---|
| 分支 | `feat/m2-a2-traceability`（自 `feat/m2-scheduler-basic @ 070fb6e` 拉出） |
| 契约 | `39f7f96559abac9d4bc59d5c560e6a706ec19946` |
| 测试文件 | `test/agent_scheduler_test.dart`，**48 → 51 条** |
| 变更面 | 仅 `test/agent_scheduler_test.dart`（+3 条）与本文件；`lib/` **零改动** |
| 标注 | ✅ 有代码有测试 ／ ⚠️ 有代码原无测试（本轮补） ／ 🚫 无代码（不属 M2） ／ ⏸ 未裁定 |

---

## 一、矩阵总表

| # | 决策项 | 源码文件 · 符号 · 行号 | 测试用例 · 行号 | 实测 | 状态 |
|---|---|---|---|---|---|
| 1 | **D2** 公共解释过滤落点（方案①：M2 出全集，服务端用 `publicExplanations`） | `schedule_contract.dart` · `kPublicExplanationCodes` :544 ／ `kRepairOnlyExplanationCodes` :557 ／ `isPublic` :576 ／ `publicExplanations` :620 ／ `ScheduleProposal.toJson` :624 | 既有 ㊴ :1598、㊼ :2039；**新增** :2100、:2146、:2159 | 51/51 pass | ⚠️→✅ |
| 2 | **R6** `READBACK_MISMATCH.retryable = false`（终态 failed 不可重写） | **无对应代码** —— M2 不实现 Proposal 状态机、不产出 `retryable`、不产出 §4.1 错误码 | 无（不可写） | — | 🚫 服务端职责 |
| 3 | **R1** 时区：服务层先转本地时间，M2 不做转换 | `ScheduleInput.timezone`（字段携带，不消费）；`ScheduleDeadline.isPast` | :1454、:1517 | pass | ✅ |
| 4 | **R2** `scheduling_weight`：服务端折算进 `priority`，M2 不引入 tie-break 层 | `_orderedDemands`（三级键：截止 → priority → taskId） | :450 | pass | ✅ |
| 5 | **R3** `maxShiftMinutes`：domain 默认 `null`，服务层传 120 | `repairSchedule(…, {int? maxShiftMinutes})` ／ `_placeNearest` | :856（无边界守卫）、:757／:809 | pass | ✅ |
| 6 | 错误码 / `retryable` 映射 | **无对应代码** —— M2 只产 `UnplannedReason`（4 值）与 `explanations`（7 公共码），不产 §4.1 二十一码 | ㊻ :2012（`reason_code` 闭集，**非 §4.1**） | pass | 🚫 服务端 HTTP 层 |
| 7 | 状态机终态（8 态、终态禁写） | **无对应代码** —— M2 的 proposal 恒为内部四部分，不输出 `status`（方案 A） | ㊳ :1548（DTO 不含服务端字段） | pass | 🚫 服务端职责 |
| 8 | 重复请求幂等（同用户同 Proposal 返同一 `approval_id`） | **无对应代码** —— M2 无幂等键、无存储 | 无 | — | 🚫 服务端 + DB |

> **一句话**：M0 点名的 4 个重点方向里，只有 **D2** 属 M2；`R6`、错误码/`retryable`、状态机终态、幂等 **四项全部落在服务端**，M2 侧没有可测对象。硬在纯函数里造这四项的测试，等于**用测试冒充能力**，与 M0「不得自行推断未裁定语义」直接冲突。

---

## 二、逐项详表

### 2.1 D2 公共解释过滤（本轮唯一真缺口）

**决策原文**：M0 2026-11-03 裁定方案①——M2 的 `toJson()` 保留内部全集，服务端组装 v1 时用 `publicExplanations` 过滤；`E2E-EXPL-FILTER` 留作服务端验收义务。

**代码事实**

| 符号 | 行号 | 行为 |
|---|---|---|
| `kPublicExplanationCodes` | :544 | 7 个公共码：`PRESERVED_FIXED_EVENTS`、`ESTIMATED_DURATION`、`FIXED_BLOCKS_OVERLAP`、`NO_AVAILABILITY_WINDOW`、`AVAILABILITY_SATURATED`、`ALREADY_DONE_TODAY`、`SCHEDULED` |
| `kRepairOnlyExplanationCodes` | :557 | 2 个 repair 码：`DISPLACED_BY_FIXED`、`REPAIR_SUMMARY` |
| `ScheduleNote.isPublic` | :576 | `kPublicExplanationCodes.contains(code)` —— **枚举外码天然返回 false** |
| `publicExplanations` | :620 | `notes.where((note) => note.isPublic).toList()` |
| `ScheduleProposal.toJson()` | :624 | 输出 `notes` **全集**（方案 A：这是内部四部分，不是 v1 响应） |

**原有覆盖的不足**

| 既有用例 | 断言了什么 | 缺了什么 |
|---|---|---|
| ㊴ :1598 `explanations 码必须落在 v1 公共枚举内，repair 专用码不得外泄` | 从**真实引擎输出**里取样，验证 c ode 落在闭集内 | 只覆盖引擎**实际会产出**的码，**没有**构造「公共 + repair + 枚举外」三种码共存的 proposal，因此没验证**过滤后的差集** |
| ㊼ :2039 `explanations 元素结构统一，且不带额外字段` | 元素键集合 = `{code, message, related_task_ids}` | 不涉及过滤行为 |

**本轮新增 3 条（:2100 / :2146 / :2159）**

| 用例 | 断言要点 | 防的是什么 |
|---|---|---|
| `publicExplanations 与内部全集隔离：repair 码与枚举外码都不进远程响应`（:2100） | 5 条 notes（2 公共 + 2 repair + 1 枚举外）：`toJson()` 得 5 条、`publicExplanations` 得 2 条、**差集恰好 = `{DISPLACED_BY_FIXED, REPAIR_SUMMARY, UNLISTED_FUTURE_CODE}`**；再逐条断言 public 中无 repair 码、且都在公共集合内 | ① 有人把 `publicExplanations` 改成「只滤 repair 码」而放过枚举外码；② 有人把 `toJson()` 改成默认只出公共码（会破坏方案 A 的"内部全集"语义） |
| `isPublic 只认公共码：repair 码与枚举外码一律 false`（:2146） | 4 个单点：`SCHEDULED` → true；`DISPLACED_BY_FIXED` / `UNLISTED_FUTURE_CODE` / `''` → false | 未来新增 explanation code 时**忘记加白名单**，导致新码被静默丢弃却无人发现 |
| `公共码与 repair 专用码两个集合互斥，且规模符合 M0 裁定`（:2159） | `intersection == empty`；公共 7 个、repair 2 个 | 同一个码被同时放进两个集合（会造成 `isPublic` 语义自相矛盾）；集合规模被悄悄改动 |

### 2.2 R6 终态 failed 不可重写 —— 🚫 无代码可测

**M0 的裁定**：`READBACK_MISMATCH.retryable = false`，理由是终态 `failed` 禁止再次写入。

**M2 侧的事实**：

- M2 **不实现** Proposal 状态机（8 态全在服务端推进）；
- M2 **不产出** §4.1 错误码，因此**没有** `retryable` 字段可赋值；
- M2 的 `ScheduleProposal` 在方案 A 下**不输出 `status`**（㊳ :1548 已用用例锁死"内部 DTO 递归不含任何服务端字段"）。

**能提供的只有契约证据链**（已在此前邮件中提交，此处留痕）：

| 契约位置 | 原文要点 |
|---|---|
| §4.1 L161 | `READBACK_MISMATCH` = 502，「不得返回成功」 |
| §4.1 L167 | 必须包含 `proposal_status=failed` |
| §6.7 L672–673 | 确认不一致 → 转**终态 failed，不允许再次写入** |
| §6.7 L707 | `failed`/`rejected`/`expired` 均为终态，不允许再次写入 |

**结论**：R6 的验收只能在服务端做（状态机 + 幂等记录 + 回读）。**M2 侧不补测试**——补了就是伪造。

### 2.3 R1 / R2 / R3 —— ✅ 已有覆盖

| 项 | 裁决内容 | 代码位置 | 测试 | 说明 |
|---|---|---|---|---|
| R1 时区 | 服务层统一转本地时间，M2 不做转换 | `ScheduleInput.timezone`（仅携带）；引擎内**无** `DateTime.now()`、无时区库 | :1454、:1517 | 两条互补：一条声明"只携带不转换"，一条证明"换时区标签不改变输出" |
| R2 `scheduling_weight` | 服务端折算进 `priority`，M2 不加 tie-break 层 | `_orderedDemands`：截止 rank → priority 降序 → taskId 字典序 | :450 | 用例名直接写明"`scheduling_weight` 尚不参与"，把未消费这件事**显式锁死** |
| R3 `maxShiftMinutes` | domain 默认 `null`（无边界），服务层传 120 | `repairSchedule(…, {int? maxShiftMinutes})`、`_placeNearest` | :856（不传参 = 无边界）、:757（兜底）、:809（边界不误杀） | :856 是**防止有人把 Dart 默认值改成 120** 的守卫；「服务层默认 120」由服务层测试负责，M2 不代测 |

### 2.4 错误码 / `retryable` 映射 —— 🚫 不属 M2

M2 只有两套封闭枚举，**都不是 §4.1**：

| 枚举 | 位置 | 值数 | 用途 |
|---|---|---|---|
| `kPublicExplanationCodes` | contract :544 | 7 | `explanations[].code` |
| `UnplannedReason` | contract :124 | 4 | `unplanned_tasks[].reason_code`，用例 ㊻ :2012 已锁闭集 |
| §4.1 错误码 | 契约 §4.1 | 21 | **服务端 HTTP 响应**，M2 不产出 |
| §5.8 violations | 契约 §5.8 | 8 | **服务端 `validate_schedule`**，M2 不产出 |

四个闭集严格分离，任何"合并"都会造成码表污染。**M2 无法为 `retryable` 写测试**，因为 `retryable` 只存在于 §4.1 错误响应里。

### 2.5 状态机终态 —— 🚫 不属 M2

8 态（`draft → pending_approval → applying → readback_pending → applied / rejected / expired / failed`）全部由服务端推进。M2 只产出"draft 语义的内部四部分"，且**不输出 `status`**。相关守卫用例 ㊳ :1548 已锁死。

### 2.6 重复请求幂等 —— 🚫 不属 M2

M2 是**无状态纯函数**：同一输入必得同一输出（:299、:369 两条确定性用例），但「重复请求返回同一 `approval_id`」依赖 §6.5 的未终结审批集合与持久化幂等记录，**两者都在服务端**。

M2 能贡献的只有：确定性（同输入同输出）与「每 block 恰一条 change」（㊶ :1677）。这两条都已有。

---

## 三、本轮变更清单

| 文件 | 变更 | 行数 |
|---|---|---|
| `test/agent_scheduler_test.dart` | +3 条测试，新增 group `D2 公共解释过滤（追踪矩阵补强）` | +58 |
| `docs/scheduler/M2-A2-Decision-Code-Test-Traceability.md` | 本文件 | 新建 |

**`lib/` 零改动**：未改 `schedule_contract.dart`、未改 `schedule_engine.dart`。本轮只补测试，不动实现。

---

## 四、测试命令与结果（两通道分开，各跑各的）

### 通道 A：隔离工程（`dart test`）

```bash
cp lib/features/agent_scheduler/domain/schedule_contract.dart \
   lib/features/agent_scheduler/domain/schedule_engine.dart \
   /e/m2-verify/lib/features/agent_scheduler/domain/
sed -e "s|package:check_d/features/agent_scheduler/domain/schedule_contract.dart|package:m2_verify/features/agent_scheduler/domain/schedule_contract.dart|" \
    -e "s|package:check_d/features/agent_scheduler/domain/schedule_engine.dart|package:m2_verify/features/agent_scheduler/domain/schedule_engine.dart|" \
    -e "s|package:flutter_test/flutter_test.dart|package:test/test.dart|" \
    test/agent_scheduler_test.dart > /e/m2-verify/test/agent_scheduler_test.dart
cd /e/m2-verify && export PATH="/e/flutter/bin:$PATH" && dart test test/agent_scheduler_test.dart
```

- 结果：**51/51 通过**
- 退出码：**0**
- 日志：`.workbuddy/tmp/iso_51.log`

### 通道 B：宿主工程（`flutter test`）

```bash
export PATH="/e/flutter/bin:$PATH"
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  flutter test test/agent_scheduler_test.dart
```

- 结果：**51/51 通过**
- 退出码：**0**
- 日志：`.workbuddy/tmp/host_51.log`
- 跑完必须还原被自动改写的 4 个生成文件：

```bash
git checkout -- macos/Flutter/GeneratedPluginRegistrant.swift \
  windows/flutter/generated_plugin_registrant.cc \
  windows/flutter/generated_plugin_registrant.h \
  windows/flutter/generated_plugins.cmake
```

> **为什么必须去代理**：本机 `http_proxy` 会劫持 `flutter` ↔ `flutter_tester` 的 localhost WebSocket 握手，报 `Invalid WebSocket upgrade request`。证据见 `docs/scheduler/reports/verification-2026-11-02-host-channel.md`。

### 稳定性声明

- **无 skip**：51 条全部执行，无 `skip:` 标记。
- **无 flaky**：本轮连续跑 2 次（隔离 1 次 + 宿主 1 次），均 51/51；此前 48 条基线累计多轮亦稳定。
- **可重复**：不依赖系统时间（固定 `_monday = DateTime(2026, 11, 2)`）、不依赖网络、不依赖文件系统外部状态。

---

## 五、阻塞与未裁定项（本轮不推断）

| # | 项 | 状态 | 影响 |
|---|---|---|---|
| 1 | `related_task_ids` 是否也要出现在 `explanations[]` | ⏸ **待 M0 裁定** | 若要求，M2 需在 `ScheduleNote` 增字段 + 补用例；当前 `taskId` 单值只能映射成单元素数组 |
| 2 | `scheduling_weight` 在 tie-break 链的层级 | ⏸ 契约 §5.2 BLOCKED | M2 不消费，:450 已锁"尚不参与" |
| 3 | 时区若改为引擎侧解析 | ⏸ 待裁定 | 需引入时区库，破坏 domain 零依赖纪律 |
| 4 | 服务层默认 120 的真实入口 | ⏸ 待入口出现 | domain 无调用方，默认路径测试无法写 |
| 5 | R6 / 错误码 retryable / 状态机 / 幂等 | 🚫 服务端职责 | M2 侧无测试可写，只能提供契约证据 |

---

## 六、边界声明

- ✅ 本轮**允许写测试**，已按 M0 授权执行；**未改 domain 实现**（`lib/` 零改动）
- ❌ 未修改冻结契约、A1/T-DOC/A4 原件
- ❌ 未连接 Production / Dev 数据库，未执行 migration
- ❌ 未合并主线；交付在独立分支 `feat/m2-a2-traceability`，等待审查
- ✅ 保持 48/48 基线不退步（现为 51/51，基线用例一条未删未改）
- ❌ 未把作者自报写成独立核验；未把 Mock 写成真实能力
