# M2 · A2 确定性调度数据与有效链路设计

> **依据**：M0 2026-11-05 `[CheckD][M0协调] 11/05 并行大工作包` 第二节【M2】。
> **性质**：只读分析 + 独立文档交付。**未修改**业务代码、契约、Mock、测试基线、数据库；未提交、未推送、未建 PR。
> **本文件不覆盖任何冻结件**；A4 原件与既有哈希未动。

## 基准声明（本文所有事实的锚点）

| 项 | 值 |
|---|---|
| M2 代码基准 | `feat/m2-scheduler-basic` head `070fb6e`（`lib/features/agent_scheduler/domain/` 两份 + `test/agent_scheduler_test.dart` 48 条） |
| 契约基准 | `agent-api-v1.md` + `examples.json` @ `39f7f96559abac9d4bc59d5c560e6a706ec19946` |
| Mock 基准 | `upstream/pr/3` @ `bbf0992307531f8945fe5ac25107e2da79dc0e76`；`tools/m1-mock/tool_server.py` blob `5e7733298757b21e1d430fece76bb8299345ac44`，**31,782 B / 716 行 / sha256 `c7e1fd38…`** |
| Mock 观察方式 | 本地 `import` 后调用 `tool_generate_schedule` / `tool_validate_schedule`（纯进程内，未写 approval 文件、未连任何库、未改 Mock 源码） |
| 标注体系 | 【源码实证】/【实测输出】/【契约原文】/【建议】（建议一律不写成已裁定） |

> **版本提醒**：M3 此前引用的 Mock 版本为 `b01387ef`，本文件基于 `upstream/pr/3` 当前版（blob `5e773329`）。若两者对 `schedule()` 的实现有差异，以本文件为准的部分需重新对齐——本文所有结论都附了可重跑的最小探针（见附录 A）。

---

## 零、结论摘要（先给能落地的三句）

1. **M0 任务书的前提需要修正**：当前 Mock 下，`2026-11-05` 单日 **不是 invalid，而是 valid**。5 个 range 实测全部 `valid`、`violations=[]`。原因不是"截止冲突"，而是 **Mock 根本没有实现契约 §5.8 里三个与截止相关的 violation**。
2. **但在契约语义下，M0 的判断是对的**：若按契约补齐 `BLOCK_AFTER_EXACT_DEADLINE` / `PLANNED_AFTER_DATE_ONLY_DEADLINE` / `PLANNED_BEFORE_AVAILABLE_FROM`，则 `2026-11-05` 起**必然** invalid，而 `2026-10-30` 仍然 valid。**"现象"与"预期"之间的差，是 Mock 的实现缺口，不是数据设计问题。**
3. **顺带查出两个比截止更严重的缺陷**，都会直接卡住 G2/G3：
   - **块间重叠**：三个任务的块全部从同一时刻起算、两两重叠，而 `validate` 判 `valid`（`BLOCK_OVERLAP` 未实现）。
   - **`explanations` 结构违约**：Mock 输出**字符串数组**，契约 §5.7 要求**对象数组**（含 `code` + `message`）。这正是 G18「解释缺失」的实现层根因。

---

## 一、t_1001 / t_1002 的截止时间与 date_range 的关系

### 1.1 源码实证：两套任务的原始定义

【源码实证】`tool_server.py` L26–L46（`TASKS`）：

| task_id | kind | name | available_from | deadline | duration_target_seconds |
|---|---|---|---|---|---|
| `t_1001` | one_time | 完成实验报告 | `2026-10-29` | **`{"kind":"exact","at":"2026-10-31T18:00:00+08:00"}`** | 5400（90 分钟） |
| `t_1002` | one_time | 英语六级听力复习 | `2026-10-29` | **`{"kind":"date_only","date":"2026-11-02"}`** | 3600（60 分钟） |
| `t_1003` | recurring | 背单词 | `starts_on 2026-10-20`、`ends_on null` | **无 deadline** | 1800（30 分钟，日复） |

课程侧【源码实证】L48–L58：`c_2001 离散数学`，`weekday=4`（**周四**）、`every_week`、`08:00–09:40`。

> 由此先得一个关键事实：**`t_1003` 无截止，任何 range 下都可排**。所以"某个 range 排不出块"这个假设从一开始就不成立。

### 1.2 实测输出：5 个 range 的 validate 结果

【实测输出】探针逐次调用 `generate_schedule` → `validate_schedule`（同进程、同 token、不改任何文件）：

| # | date_range | validation_status | violations | blocks | unplanned |
|---|---|---|---|---|---|
| A | `2026-10-30` ~ `2026-10-30`（周五，无课） | **valid** | `[]` | 3 | 0 |
| B | `2026-11-05` ~ `2026-11-05`（周四，有课） | **valid** | `[]` | 3 | 0 |
| C | `2026-10-29` ~ `2026-10-30`（含周四） | **valid** | `[]` | 4 | 0 |
| D | `2026-11-05` ~ `2026-11-11`（整周） | **valid** | `[]` | 9 | 0 |
| E | `2026-10-31` ~ `2026-11-01` | **valid** | `[]` | 4 | 0 |

**结论：`2026-11-05` 并不 invalid。** 任务书里"11-05 起恒 invalid"这一现象，在当前 Mock 上**复现不出来**。

### 1.3 根因一：`schedule()` 完全不检查 deadline

【源码实证】`schedule()` L253–L318 的完整逻辑：

```python
ones = [t for t in payload["tasks"] if t["kind"] == "one_time" and t["status"] == "active"]
for t in sorted(ones, key=deadline_key):     # ← deadline 只做排序键
    need = int(t.get("duration_target_seconds") or 0)
    placed = False
    for d in iter_dates(start, end):         # ← 逐日找空档，从不问「这天是否已过截止」
        ...
    if not placed:
        unplanned.append({"task_id": t["task_id"], "reason": "no_free_slot"})
```

`deadline_key()`（L248–L250）只返回一个排序元组：

```python
return (dl.get("at") or (dl.get("date", "") + "T23:59:59+08:00") or "9999", t["task_id"])
```

它对 deadline 的唯一用途是**决定先排谁**。**没有任何一处把 deadline 与候选日 `d` 做比较**。所以：

- `2026-11-05` 排 `t_1001` 时，Mock 不知道 10-31 18:00 已经过去 5 天；
- 结果照样把 90 分钟块放在 11-05 09:40；
- `validate` 也不查，于是判 `valid`。

**这就是"为什么 11-05 也能 valid"的直接答案：不是数据问题，是 Mock 少了一道检查。**

### 1.4 根因二：契约 §5.8 的 8 个 code，Mock 只实现了 3 个

【契约原文】§5.8 公开 `code` 的 v1 完整闭集（8 值）：

`PLANNED_BEFORE_AVAILABLE_FROM`、`PLANNED_AFTER_DATE_ONLY_DEADLINE`、`BLOCK_AFTER_EXACT_DEADLINE`、`BLOCK_TIME_INVALID`、`FIXED_EVENT_CONFLICT`、`BLOCK_OVERLAP`、`MULTIPLE_CHANGES_FOR_ONE_TIME_TASK`、`MULTIPLE_BLOCKS_FOR_RECURRING_TASK_DAY`

【源码实证】`check_hard_constraints()` L321–L343 **只产出 3 个**：

| 契约 code | Mock 是否产出 | 说明 |
|---|---|---|
| `BLOCK_TIME_INVALID` | ✅ L326–L327 | `end <= start` |
| `FIXED_EVENT_CONFLICT` | ✅ L333–L335 | 块与 `fixed` 事件重叠 |
| `MULTIPLE_CHANGES_FOR_ONE_TIME_TASK` | ✅ L340–L342 | 同任务多条 change |
| `BLOCK_OVERLAP` | ❌ 未实现 | 块与块重叠不检查 |
| `PLANNED_BEFORE_AVAILABLE_FROM` | ❌ 未实现 | 早于 available_from 不检查 |
| `PLANNED_AFTER_DATE_ONLY_DEADLINE` | ❌ 未实现 | **t_1002 这类 date_only 过期不检查** |
| `BLOCK_AFTER_EXACT_DEADLINE` | ❌ 未实现 | **t_1001 这类 exact 过期不检查** |
| `MULTIPLE_BLOCKS_FOR_RECURRING_TASK_DAY` | ❌ 未实现 | 周期任务同日多块不检查 |

**三个截止类 violation 全部缺失**，所以截止时间对 `valid`/`invalid` 的影响是 **0**。

### 1.5 契约语义下的正确结论：M0 的判断成立

若按契约补齐上述三项，则同一份数据的行为将变为：

| range | 起点 vs 两个 deadline | 契约语义下的预期 |
|---|---|---|
| `2026-10-30` | 早于 10-31 18:00 与 11-02 | `t_1001`/`t_1002` 均可在截止前排入 → **valid**（前提是块不重叠，见 §1.6） |
| `2026-11-01` | 晚于 10-31 18:00、早于 11-02 | `t_1001` 触发 `BLOCK_AFTER_EXACT_DEADLINE` → **invalid** |
| `2026-11-05` 起 | 晚于两个 deadline | `t_1001` → `BLOCK_AFTER_EXACT_DEADLINE`；`t_1002` → `PLANNED_AFTER_DATE_ONLY_DEADLINE` → **invalid**，且范围越长越稳定 invalid |

**所以 M0 的预期在契约语义下完全正确，只是当前 Mock 还没这道闸。** 这也解释了 M3 与 M1 两边结论为何看似矛盾：M1 用 `2026-10-30` 拿到 `valid`（真实但不完备），M3 在别处判 `invalid`（很可能撞上了 `__test_conflict_event` 或入参问题，她本人也已更正过 `NOT_FOUND` 是入参错）。

**关键分水岭日期**：`2026-10-31T18:00:00+08:00`（t_1001 精确截止）。**range 起点 ≤ 10-31 才有机会 valid；≥ 11-01 必 invalid。**

### 1.6 顺带发现（一）：块间重叠，且 validate 判定为 valid

【实测输出】range `2026-10-30` 的 3 个块：

```
t_1001  08:00 -> 09:30  (dur=5400)
t_1002  08:00 -> 09:00  (dur=3600)
t_1003  08:00 -> 08:30  (dur=1800)
```

两两重叠三对，而 `validation_status = valid`、`violations = []`。

【源码实证】根因在 `schedule()`：每个任务**独立**计算 `busy`，**只含 `fixed` 事件，从不把前面已排出的块加进去**（L269、L297）。于是所有任务都从同一个 `day_start` 起算，必然同点起排。

**后果**：按契约 §5.8，这份 proposal 应报 3 条 `BLOCK_OVERLAP`，实为 `invalid`。**当前是"假 valid"。**

### 1.7 顺带发现（二）：`explanations` 结构违反契约

【源码实证】`tool_generate_schedule()` L408：

```python
"explanations": ["固定课程与外部会议不可移动。", "单次事项只持久化一个计划日期。"],
```

【契约原文】§5.7：`explanations`：**对象数组**；每项包含机器可读 `code` 和安全的 `message`，可选 `related_task_ids`。

**字符串数组 ≠ 对象数组**。这正是 G18 所说"缺少可展示的中文解释"的实现层根因之一：结构本身就不合法，任何按契约解析的下游都读不到 `code`。

同时【契约原文】§5.8 规定 `violation.message` 为**必填**，而 Mock 的 violation 只给 `code` + `block_id`/`event_id`/`task_id`，**没有 `message`**：

```python
violations.append({"code": "FIXED_EVENT_CONFLICT", "block_id": b["block_id"], "event_id": e["event_id"]})
```

---

## 二、两套最小预置数据设计

> 设计原则：**只改数据、不改 Mock 代码**；两套 fixture 除一个变量外完全相同，便于定位差异。

### 2.1 一个必须先说清的约束

由于 §1.6 的缺陷（不扣减已排块），**当前 Mock 下任何"同日多任务"的 proposal 必然重叠**。若按契约校验，必然 `BLOCK_OVERLAP`。

因此本文件给出**三级 fixture**，按依赖递进：

| Fixture | 用途 | 依赖当前 Mock 能否直接 valid |
|---|---|---|
| **V1 单任务 valid 基线** | 立即可用，验证链路贯通 | ✅ 可以 |
| **V2 多任务 valid（契约口径）** | 待 Mock 补齐块扣减后使用 | ❌ 需先修 `schedule()` |
| **I 明确 invalid 对照** | 验证闸门真的会拦 | ✅ 可以（唯一现实路径见 §2.4） |

### 2.2 Fixture-V1：单任务最小 valid 基线（立即可用）

只保留一个单次任务，块不与任何东西重叠：

| 字段 | 值 | 语义说明 |
|---|---|---|
| `task_id` | `fx_v1` | |
| `kind` | `one_time` | |
| `status` | `active` | |
| `name` | 确定性夹具-单任务 | |
| `available_from` | `2026-11-05` | 早于截止，不触发 `PLANNED_BEFORE_AVAILABLE_FROM` |
| `deadline` | `{"kind":"exact","at":"2026-11-10T18:00:00+08:00"}` | **晚于 range 终点**，块必在截止前 |
| `duration_target_seconds` | `3600` | 60 分钟 |
| **date_range** | `2026-11-05` ~ `2026-11-05` | 单日，周四（有课，用于验证避让） |

课程保留 `c_2001`（周四 08:00–09:40），用于验证**与固定事件不冲突**。

**预期**：`blocks=1`，`09:40–10:40`（课程后第一个满足 60 分钟的位）；`changes=1`（`schedule_one_time`）；`unplanned=0`；`violations=[]`；`validation_status=valid`。

> ⚠️ 注意：`t_1003`（recurring）必须从 fixture 中移除，否则它也会在 09:40 起排 30 分钟，与 `fx_v1` 重叠。**这正是 V1 只能单任务的原因。**

### 2.3 Fixture-V2：多任务 valid（契约口径，需先修 Mock）

若 Mock 的 `schedule()` 改为"每排一块即从 `busy` 扣除"（与 M2 引擎 `_subtract` 同构），则可用下套：

| task_id | kind | deadline | duration | 说明 |
|---|---|---|---|---|
| `fx_v1` | one_time | exact `2026-11-10T18:00` | 3600 | 排最早可用位 |
| `fx_v2` | one_time | date_only `2026-11-12` | 1800 | 排 `fx_v1` 之后的下一个空档 |
| `fx_v3` | recurring daily | 无 | 1800 | 每天一块，排当日剩余最早空档 |

**预期（契约口径）**：`validation_status=valid`、`violations=[]`、块两两不重叠、每个 `one_time` 任务恰好一条 `schedule_one_time` change、`recurring` 每本地日最多一块（不触发 `MULTIPLE_BLOCKS_FOR_RECURRING_TASK_DAY`）。

### 2.4 Fixture-I：明确 invalid 对照（三种可选，按可控性排序）

| 方案 | 构造方式 | 触发 code | 可控性 | 是否需改 Mock |
|---|---|---|---|---|
| **I-1 截止过期（推荐，契约口径）** | 沿用现有 `t_1001`/`t_1002`，range 设 `2026-11-05`~`2026-11-05` | `BLOCK_AFTER_EXACT_DEADLINE` + `PLANNED_AFTER_DATE_ONLY_DEADLINE` | 最高 | **需补齐 3 个截止类 violation** |
| **I-2 固定事件冲突（当前即可用）** | `preferences.__test_conflict_event` 注入 `2026-10-30 08:00–08:30` 的外部事件 | `FIXED_EVENT_CONFLICT` × N | 高（但走测试后门） | 否 |
| **I-3 块重叠（契约口径）** | 任一同日多任务 range（如 `2026-10-30`） | `BLOCK_OVERLAP` × 3 | 高 | **需实现 `BLOCK_OVERLAP`** |

**I-2 实测证据**（唯一当前可跑通的 invalid 路径）：

```
validation_status = invalid
violations = [
  {"code":"FIXED_EVENT_CONFLICT","block_id":"b_0001","event_id":"ev_probe_conflict"},
  {"code":"FIXED_EVENT_CONFLICT","block_id":"b_0003","event_id":"ev_probe_conflict"},
  {"code":"FIXED_EVENT_CONFLICT","block_id":"b_0005","event_id":"ev_probe_conflict"}
]
```

**三条而非一条**，是因为三个任务的块都落在 08:00 附近（§1.6）。这反而是块重叠缺陷的旁证。

> **边界提醒**：`__test_conflict_event` 是 Mock 里 `preferences` 下的**测试后门**（L398–L399），只注入 validate 用的事件列表、不参与排程。它可用于 **QA 内部验证闸门**，**不得**写进对用户可见的演示脚本，也不得据此宣称"冲突检测已对接真实日历"。

### 2.5 两套数据的差异表（便于现场对照）

| 维度 | Fixture-V1（valid） | Fixture-I-1（invalid，契约口径） |
|---|---|---|
| 任务集 | 仅 `fx_v1` | `t_1001` + `t_1002`（沿用现网） |
| 起点 vs 最早 deadline | 起点 `11-05` **早于** deadline `11-10` | 起点 `11-05` **晚于** deadline `10-31` / `11-02` |
| 课程 | 保留周四 08:00–09:40 | 同 |
| 预期 violations | `[]` | `BLOCK_AFTER_EXACT_DEADLINE`、`PLANNED_AFTER_DATE_ONLY_DEADLINE` |
| 预期 validation_status | `valid` | `invalid` |
| 用途 | 证明链路能跑通 | 证明闸门会拦 |

---

## 三、两套数据对应的输入与预期结果

### 3.1 ScheduleInput 映射（M2 侧 DTO ← 远程入参 + 可信快照）

| ScheduleInput 字段 | 远程 v1 是否可传 | Fixture-V1 取值 | Fixture-I-1 取值 | 语义要点 |
|---|---|---|---|---|
| `now` | ❌ 服务端注入 | 调用时刻 | 同 | **M2 引擎不读系统时间**，全部以 `now` 为准 |
| `horizonStart` / `horizonEnd` | ✅ 由 `date_range.start/end` 映射 | `2026-11-05` / `2026-11-05` | `2026-11-05` / `2026-11-05` | 上海本地日；`input_digest` 必须覆盖起止 |
| `baseVersion` | ❌ 服务端可信快照 | 服务端给 | 同 | 不透明字符串，M2 只透传 |
| `timezone` | ✅ 固定 `Asia/Shanghai` | 同 | 同 | **M2 引擎不消费**，由服务层先做本地化 |
| `preferences.dayStartMinute` | ✅ | `480`（08:00） | 同 | 下限 |
| `preferences.dayEndMinute` | ✅ | `1320`（22:00） | 同 | 上限 |
| `preferences.minimumBlockMinutes` | ✅ | `30` | 同 | 碎片阈值 + 时长兜底 |
| `availability` | ⚠️ 契约 §6.3 无此字段 | 空（按偏好逐日推导） | 同 | **D3 未裁定**：`null` vs `[]` 语义待 M0 |
| `fixedBlocks` | ✅ 快照内课程/会议 | `c_2001` 周四 08:00–09:40 | 同 | 永不可移动 |
| `demands[].requiredMinutes` | ✅ 服务端可信折算 | `60` | `90` / `60` | 只来自可信快照，不接受 LLM 直供 |
| `demands[].deadline` | ✅ | `exact 2026-11-10T18:00+08:00` | `exact 2026-10-31T18:00+08:00` / `dateOnly 2026-11-02` | **见 §3.4 due_at/due_date 语义** |
| `demands[].taskKind` | ✅ | `oneTime` | `oneTime` ×2 | 决定 change 类型 |
| `existingPlacements` | ✅（repair 用） | 空 | 空 | generate 不消费 |

### 3.2 generate_schedule 预期结果

**Fixture-V1**

| 项 | 预期 |
|---|---|
| `blocks` | 1 条：`fx_v1`，`2026-11-05T09:40:00+08:00` → `10:40:00+08:00`，`duration_seconds=3600`，`duration_source=task_target`，`persistable_as=one_time_schedule` |
| `changes` | 1 条 `schedule_one_time`：`planned_date=2026-11-05`，`scheduled_at=2026-11-05T09:40:00+08:00`（**必须与 block 起始同一上海本地日**，否则 `PROPOSAL_INVALID`） |
| `unplanned_tasks` | `[]` |
| `explanations` | 契约口径：对象数组，至少含 `{code, message}`；当前 Mock 输出字符串数组 → **本项必然失败，属已知缺口** |

**Fixture-I-1**（当前 Mock）

| 项 | 当前实测 | 契约口径预期 |
|---|---|---|
| `blocks` | 3 条，全部从 09:40 起（`t_1001` 90min / `t_1002` 60min / `t_1003` 30min，**互相重叠**） | 若补齐截止检查：`t_1001`/`t_1002` 不应被排入（或排入即触发 violation），`t_1003` 仍可排 |
| `unplanned_tasks` | `[]`（**错误**：过期任务本应进 unplanned 或触发 violation） | 至少 `t_1001`、`t_1002` 应出现，或因 violation 整体 invalid |
| `validation_status` | `valid`（**假通过**） | `invalid` |

### 3.3 validate_schedule 预期结果

| 项 | Fixture-V1 | Fixture-I-1（契约口径） |
|---|---|---|
| `validation_status` | `valid` | `invalid` |
| `proposal_status` | `pending_approval`（valid 后置） | `draft`（invalid 保持） |
| `approval_status` | `pending_approval` | `not_approvable` |
| `violations` | `[]` | `[{"code":"BLOCK_AFTER_EXACT_DEADLINE","message":"…","related_task_ids":["t_1001"]}, {"code":"PLANNED_AFTER_DATE_ONLY_DEADLINE","message":"…","related_task_ids":["t_1002"]}]` |
| `violations[].message` | — | **必填**（§5.8）；当前 Mock 缺失 → 已知缺口 |

### 3.4 字段 / 时区 / 日期范围 / due_at 与 due_date 语义（必须写死的四条）

1. **时区**：全链路固定 `Asia/Shanghai`（契约 `timezone` 只接受该值）。`date_range.start/end`、`planned_date`、`local_date` 都是**上海本地日**，不是 UTC 日。跨时区不做换算，`ScheduleInput.timezone` 字段存在但 M2 引擎**不消费**（R1 待裁定）。
2. **日期范围**：`end >= start`，且 `(end - start).days + 1 <= 31`【源码实证 L146–L148】。范围是**闭区间**。
3. **`due_at`（exact）语义**：一个**绝对时刻**，含时区偏移。块 `end_at` **必须 ≤ due_at** 才不触发 `BLOCK_AFTER_EXACT_DEADLINE`。`t_1001` 的 `2026-10-31T18:00:00+08:00` 表示**10-31 上海时间 18:00 整**，不是当天 23:59。
4. **`due_date`（date_only）语义**：一个**本地日历日**，语义上宽限到该日 `23:59:59 +08:00`。`t_1002` 的 `2026-11-02` 表示**11-02 整天仍可排**，`PLANNED_AFTER_DATE_ONLY_DEADLINE` 只在计划日 **晚于 11-02** 时触发。**绝不能把 date_only 折成当天 23:59 再当成"精确时刻"参与比较**——那会把"当天可排"误判成"当天已过期"。

---

## 四、如何稳定验证 proposal 生成 / 过期状态 / 重复调用

### 4.1 确定性边界：哪些"确定"、哪些"不确定"

【实测输出】同一 range（`2026-10-30`）连调两次：

| 维度 | 两次是否一致 | 说明 |
|---|---|---|
| `base_version` | ✅ 相同 | 由 `snapshot` digest 派生，纯函数 |
| `input_digest` | ✅ 相同 | 快照内容未变 |
| `blocks[].start_at/end_at` | ✅ 相同 | 排程逻辑确定 |
| **`proposal_id`** | ❌ 不同（`prop_0014` vs `prop_0021`） | `_next_id()` 递增计数，**不是内容派生** |
| **`blocks[].block_id`** | ❌ 不同 | 同上 |

**结论**：Mock 的确定性**只在内容层（digest + 时间位）成立，在标识层不成立**。因此：

- 断言"重复调用结果一致"时，**只能比 digest / base_version / 时间位**，不能比 `proposal_id`、`block_id`。
- 若要对齐 M2 侧口径：M2 的 `toJson()` **不输出** `proposal_id`（方案 A），也不输出 `block_id` 之外的生成态 ID，因此 M2 侧的 `jsonEncode` 逐字节比较是成立的（48 条里有两条确定性用例支撑）。

### 4.2 过期状态：当前是硬编码，且已过期 6 天

【源码实证】`tool_generate_schedule()` L406：

```python
"expires_at": "2026-10-30T23:59:00+08:00",
```

**硬编码**，不随 `now` 或 `generated_at` 变化。今天是 `2026-11-05`，该值**已过期 6 天**。

而 `tool_validate_schedule()`（L416–L437）**完全不检查 `expires_at`**，所以过期提案仍能被 validate 成 `pending_approval`。

**验证"过期状态"的正确姿势**（不改 Mock 的前提下）：

| 要验证什么 | 不能怎么做 | 应该怎么做 |
|---|---|---|
| 提案 TTL 30 分钟 | 不能靠读 `expires_at` 字面值（硬编码） | 记录 `generated_at`（若 Mock 无此字段，则记为**缺口**），由服务端侧校验 30 分钟 TTL |
| 过期后不得 apply | 不能假设 validate 会拦 | 在**服务端**用 `expires_at` 与当前时刻比较；Mock 侧此闸缺失，需单列为缺口 |
| 状态机推进 | 不能把 `status: draft → pending_approval` 当成完整 8 态 | 8 态由服务端推进；Mock 只有 `draft` / `pending_approval` 两态的可观测跳变 |

### 4.3 重复调用：能证明什么、不能证明什么

| 断言 | 可否用 Mock 证明 | 说明 |
|---|---|---|
| 同入参 → 同 digest | ✅ | 已验证 |
| 同入参 → 同 `proposal_id` | ❌ | 明确不同，且**不应**要求相同（每次生成是新提案） |
| 重复请求 → 返回同一 `approval_id` | ⚠️ 部分 | 依赖 §6.5「未终结审批集合」；Mock 的 approval 走文件存储，需按 §6.5 口径测 |
| 幂等键去重 | ❌ | Mock 的 `idempotency` 只在进程内字典，**重启即失** |

### 4.4 关于"进程内状态"的表述红线（M0 明确要求）

**不得**把下列内容描述成持久化：

| Mock 里的东西 | 真实性质 | 允许的说法 | 禁止的说法 |
|---|---|---|---|
| `STATE["proposals"]` | 进程内 dict，进程退出即失 | "同一 stdio 会话内可复现" | "提案已持久化" / "重启后仍可查" |
| `STATE["idempotency"]` | 进程内 dict | "会话内幂等" | "幂等记录已落库" |
| `STATE["tokens"]` | 进程内 dict | "会话内有效" | "Token 已持久化" |
| `mock_approvals.json` | **文件**（非数据库） | "文件级审批占位，供人工外带确认" | "审批服务已对接" / "已写入生产库" |
| `applied_proposals`（set） | 进程内 set | "会话内防重复 apply" | "写入事务已实现" |

---

## 五、A2 输出与 G18 所需 explanations / related_task_ids 的衔接

### 5.1 G18 的三项要求逐项拆解

M0 在 §一.3 中把 G18 定义为三项缺口：`validate_schedule` 缺可展示中文解释、`violations` 缺 `message`、`related_task_ids` 未按 A4-P1 提供。逐项归属：

| G18 子项 | 契约依据 | 归属 | M2 现状 | 缺口在哪 |
|---|---|---|---|---|
| `explanations` 可展示中文解释 | §5.7：**对象数组**，每项 `code` + `message`（+可选 `related_task_ids`） | **调度器输出侧**（M2）+ 服务端组装 | M2 已产出 `ScheduleNote{code, message, taskId}`，`toJson()` 输出 `explanations`（对象数组），7 个公共码封闭，repair 2 码 `isPublic=false` 隔离 | **Mock 输出字符串数组，结构本身违约** → 这是当前"解释缺失"的直接原因 |
| `violations[].message` | §5.8：`message` **必填**、安全且可展示 | **服务端校验侧**（M2 不产出 violations） | M2 不产出 violations（§5.8 属 `validate_schedule`） | Mock 的 violation 只给 `code` + 定位字段，**无 `message`** |
| `related_task_ids` | §5.8：可选数组；§5.7：`explanations` 也可选带 | **两侧都可能**：violations 侧=服务端；explanations 侧=调度器 | M2 的 `ScheduleNote` 有 `taskId`（单值），`ProposedBlock` 有 `taskId`；**没有 `related_task_ids` 数组字段** | 若要求 M2 的 explanations 带 `related_task_ids`（复数），需先在契约里明确它是 explanations 项的字段还是仅 violations 的字段 |

### 5.2 字段边界表（谁产出、谁组装、谁校验）

| 字段 | M2 调度器 | 服务端组装层 | 服务端校验层（validate_schedule） |
|---|---|---|---|
| `blocks[]`（含 `duration_source`/`persistable_as`） | ✅ 产出 | 透传 | 只读校验 |
| `changes[]`（白名单两 type） | ✅ 产出 | 透传 + 事务核验 | 只读校验 |
| `unplanned_tasks[]`（4 值 reason_code） | ✅ 产出 | 透传 | 只读校验 |
| `explanations[]`（对象数组，7 公共码） | ✅ 产出（**已合规**） | 用 `publicExplanations` 过滤 repair 码 | 不校验 |
| `violations[]`（8 值 + 必填 message） | ❌ **不产出** | 透传 | ✅ **产出于此** |
| `related_task_ids`（violations 内） | ❌ | — | ✅ 由校验层填 |
| `related_task_ids`（explanations 内） | ⚠️ **未实现**，需契约明确 | — | — |
| 6 个权威字段（`proposal_id`/`snapshot_ref`/`base_version`/`input_digest`/`generated_at`/`expires_at`/`status`） | ❌ **不产出**（方案 A） | ✅ 生成并持久化 | 只读 |

### 5.3 给 M0 的一句结论

**G18 不能整体派给 M2**：三项里只有 `explanations` 属调度器输出，且 M2 侧**结构已合规**（对象数组 + 7 公共码）。真正缺失的是 ① Mock 的输出结构、② 校验层的 `message` 与 `related_task_ids`。**把 G18 记在"服务端 + Mock"账上更准确；M2 侧唯一可能要补的是 `explanations` 里是否要带 `related_task_ids` 数组——这一条需要契约先明确。**

---

## 六、端到端联调前置条件与最小测试序列

### 6.1 前置条件（缺一不可，按依赖排序）

| # | 前置 | 当前状态 | 阻塞谁 |
|---|---|---|---|
| P1 | Mock 补齐 3 个截止类 violation | ❌ 未实现 | Fixture-I-1 无法按契约生效 |
| P2 | Mock 实现 `BLOCK_OVERLAP`（或修 `schedule()` 扣减已排块） | ❌ 未实现 | 多任务 proposal 必然"假 valid" |
| P3 | `explanations` 改为对象数组 + `violations.message` 必填 | ❌ 未实现 | G18 无法验收 |
| P4 | `expires_at` 改为按 `generated_at + 30min` 生成，且 validate/apply 检查 | ❌ 硬编码且已过期 6 天 | 过期状态无法验证 |
| P5 | 客户端注册与信任（G1 从"部分"升 PASS） | ❌ 未执行 | G1 无法升级 |
| P6 | 审批与写入接真实服务 | ❌ Mock 占位 | G3 / S4 无法推进 |
| P7 | `scheduling_weight` 层级、时区语义、`availability` null/[] | ❌ 待 M0 裁定 | 引擎侧用例无法写 |

### 6.2 最小测试序列（8 步，全部可在单会话内完成）

| 步 | 动作 | 预期 | 失败判据 |
|---|---|---|---|
| 1 | `generate_schedule`（Fixture-V1，range `2026-11-05`~`2026-11-05`） | 返回 `status=draft`，`blocks=1`，位置 `09:40–10:40` | 块与课程重叠 / `blocks=0` |
| 2 | `validate_schedule`（上一步 `proposal_id`） | `validation_status=valid`、`violations=[]` | 任何 violation |
| 3 | 同上，检查 `explanations` | **对象数组**，每项有 `code`+`message` | 出现字符串元素 → G18 未修 |
| 4 | `generate_schedule`（Fixture-I-1，range `2026-11-05`~`2026-11-05`） | **契约口径**：`violations` 含 `BLOCK_AFTER_EXACT_DEADLINE` + `PLANNED_AFTER_DATE_ONLY_DEADLINE` | 返回 `valid` → P1 未修（**当前必然失败**） |
| 5 | 同 range 再调一次 `generate_schedule` | `base_version`/`input_digest` 与前次相同；`proposal_id` 不同 | digest 变化 → 快照不确定 |
| 6 | 检查 `expires_at` | 等于 `generated_at + 30min` | 仍为 `2026-10-30T23:59` → P4 未修 |
| 7 | `request_approval`（对 valid 提案） | 返回 `pending` + `approval_url`，**不返回 token** | 直接返回 token → 违反 §6.5 设计 |
| 8 | `get_approval_status` + `apply_approved_changes` | 未确认前不得写入；确认后事务写入且回读一致 | 未确认即写入 → 严重 |

### 6.3 预期状态（每步的 `proposal_status` / `validation_status`）

```
generate(V1)   → draft / 未校验
validate(V1)   → pending_approval / valid
request_approval → pending_approval / valid  (+ approval_id, 无 token)
get_approval_status → pending（人工未确认）
   ├─ 确认 → approved → apply → applied（+ 回读一致）
   └─ 拒绝 → rejected（终态，禁止再写）
generate(I-1)  → draft / 未校验（契约口径下 validate 应 invalid）
validate(I-1)  → draft / invalid   ← 当前实测为 valid，假通过
```

### 6.4 trace 记录要求（与 A4 §7 对齐，M2 侧只承诺能提供什么）

| 环节 | 必须留痕 | M2 能否提供 |
|---|---|---|
| `generate_schedule` 请求/响应 | 完整 JSON + `request_id` + `trace_id` | ✅ 请求侧由服务端；**M2 引擎不产生 trace_id**（纯函数，无 IO） |
| 排程输入快照 | `base_version` + `input_digest` + range | ✅ `input_digest` 覆盖 range 起止（M2 侧已用用例锁死） |
| 块与变更 | `blocks[]` + `changes[]` 逐条 | ✅ |
| 解释 | `explanations[]` 对象数组 | ✅（M2 侧合规；Mock 侧待修） |
| violations | `code` + `message` + `related_*` | ❌ 属校验层 |
| 审批/写入 | `approval_id` + 幂等键 + 事务结果 | ❌ 属服务端 |

**一句话**：M2 侧能为 trace 贡献的是「**确定性输入指纹 + 块/变更/解释三元组**」；`trace_id`、审批、写入三类都产生在服务端，M2 不伪造。

---

## 七、边界声明与未决问题

### 7.1 本次做了什么 / 没做什么

- ✅ 只读检查：M2 domain 两份源码、48 条测试基线（**未运行**）、Mock `tool_server.py`（本地 import 调用 generate/validate，未改一行）
- ✅ 实测：5 个 date_range 的 generate→validate、重复调用、块间重叠检测、`__test_conflict_event` 后门
- ❌ **未运行** 48 条 Dart 测试（M0 明令不重复）
- ❌ 未改业务代码、契约、Mock、测试基线、数据库、migration
- ❌ 未提交、未推送、未建 PR、未合并
- ❌ 未擅自裁定 Q2 / R4 / Q3 / 可信门槛 / `scheduling_weight` / 时区 / `availability` 语义

### 7.2 需要 M0 裁定的两项（本文不代定）

| # | 问题 | 选项 | 不裁定的后果 |
|---|---|---|---|
| **A** | `related_task_ids` 到底挂在哪一层：仅 `violations`（校验层），还是 `explanations` 也要带（调度器层）？ | ① 仅 violations（M2 零改动）② explanations 也带（M2 需加字段 + 补用例） | G18 的第三项无法定归属，M2 会被反复要求"补 related_task_ids"但契约没写清 |
| **B** | Mock 的 5 个缺失 violation（含 `BLOCK_OVERLAP` 与 3 个截止类）由谁补、什么时候补？ | ① M1 补（他的工具）② M0 补 ③ 冻结到下一轮 | Fixture-I 无法按契约生效；G4 的 F2/F4 也无法验收 |

### 7.3 一个必须留下的提醒

**当前 `2026-11-05` 的 `valid` 是"假 valid"。** 如果现场按这个结果演示"调度链路已通过校验"，一旦 Mock 补上截止检查，同一份数据立刻变 `invalid`——**演示结论会当场翻车**。

建议现场口径：

> "调度链路（S1–S3）可运行；`validate_schedule` 目前只实现了 8 个 violation 中的 3 个，截止类与块重叠类尚未实现，因此当前 `valid` 不代表完整校验通过。"

---

## 附录 A：可重跑的最小探针（不含任何写操作）

```python
import sys, os
sys.path.insert(0, 'tools/m1-mock')          # 或本地副本所在目录
os.environ['MOCK_APPROVAL_FILE'] = '/tmp/_probe_approvals.json'
import tool_server as mock

USER = "demo-alice"
def env(rid, inp):
    return {"api_version": "checkd.agent.v1", "timezone": "Asia/Shanghai",
            "request_id": rid, "input": inp}

def probe(start, end):
    inp = {"date_range": {"start": start, "end": end}}
    p = mock.tool_generate_schedule(env("g1", inp), USER)
    v = mock.tool_validate_schedule(env("v1", {"proposal_id": p["proposal_id"]}), USER)
    print(start, end, v["validation_status"], v["violations"],
          len(p["blocks"]), len(p["unplanned_tasks"]))

for r in [("2026-10-30","2026-10-30"), ("2026-11-05","2026-11-05"),
          ("2026-10-29","2026-10-30"), ("2026-11-05","2026-11-11"),
          ("2026-10-31","2026-11-01")]:
    probe(*r)
```

预期输出（与 §1.2 一致）：五行全部 `valid` / `[]` / 3 或 9 或 4 块 / 0 未排。

---

## 附录 B：本文引用的关键行号（Mock `5e773329`）

| 内容 | 行号 |
|---|---|
| `TASKS` 定义（t_1001/t_1002/t_1003） | L26–L46 |
| `COURSES`（c_2001 周四 08:00–09:40） | L48–L58 |
| `date_range` 31 天上限 | L146–L148 |
| `deadline_key`（仅排序用） | L248–L250 |
| `schedule()`（**不检查 deadline、不扣减已排块**） | L253–L318 |
| `check_hard_constraints()`（**只产 3 个 code**） | L321–L343 |
| `tool_generate_schedule()`（`expires_at` 硬编码 L406、`explanations` 字符串数组 L408） | L387–L413 |
| `tool_validate_schedule()`（**不检查 expires_at**） | L416–L437 |
| `__test_conflict_event` 后门 | L398–L399 |
