# 契约变更申请：`list_tasks` 的 `date_range` 语义（口径乙）

> 出件：M1　2026-11-10 20:22 (+08)
> 依据：M0 2026-11-10T11:57:18Z 裁定 1；M3 2026-11-10T11:57:48Z 独立复核
> 状态：**本地已实现、306 项测试全绿、未发布、未申请上线**
> 关联缺陷：M1 19:56 交付件 §2（`date_range` 收下不生效）

---

## 一、变更原因

原实现对 `start` / `end` **只做回显不做事**：

```python
# 原 real_read.py L353-357，只有两个过滤条件，无任何日期条件
filters=["deleted_at=is.null", "status=in.(active)"]
```

`start`/`end` 仅被传进 `_tasks_payload`（L394），在 L434 写进 `data_window` 字段。
契约 `39f7f96` §6.1 原文：`tasks` 是「**范围内**可供展示/调度的去重 Task 定义」，
`date_range` 是「**实际查询范围**」。⇒ 原实现构成契约违反。

M3 逐行复核确认（她引用的是 `db5cb581` 的 L347 / L354 / L394 / L434），与我结论一致，非互相采信。

---

## 二、变更内容（四项，全部向后兼容）

### 2.1 `tasks[]` 每项新增两个字段

| 字段 | 类型 | 取值 | 含义 |
|---|---|---|---|
| `window_status` | string | `in_window` / `overdue` / `undated` | 该任务与查询窗口的关系 |
| `window_reason` | string | 中文短句 | 可直接展示给用户的原因 |

### 2.2 `data` 顶层新增 `window_applied`

```json
"window_applied": true
```

存在的意义：此前从响应上**分辨不出「筛过」和「没筛」**——这是缺陷能藏住的原因。
有了这个字段，任何验收方一眼能确认窗口是否生效。

### 2.3 `data` 顶层新增 `window_counts`

```json
"window_counts": {
  "in_window": 1,
  "overdue": 3,
  "undated": 1,
  "excluded_out_of_window": 0
}
```

### 2.4 `tasks[]` 的构成变化（**唯一有行为差异的一条**）

原：返回全部 `active` 任务。
新：返回 `in_window` + `overdue` + `undated`，**排除 `out_of_window`**（未来才到期且不在窗口内）。

三类保留项的依据（对应 M0 裁定原文）：

| 类别 | 为什么保留 | 依据 |
|---|---|---|
| `in_window` | 范围内待调度 | 契约 §6.1 |
| `overdue` | 「逾期任务可供用户了解」；但 `window_status=overdue` 明确标记，引擎**不得**排进未来 | M0 裁定 1 第二句 |
| `undated` | 「未设日期的 active 任务怎么归类须明确，不能无依据丢弃」 | M0 裁定 1 第三句 |

---

## 三、兼容性评估

| 消费方 | 影响 | 应对 |
|---|---|---|
| 旧 adapter 读 `tasks` | 数组可能变短（窗口外未逾期的被排除） | 这是缺陷修正，不是破坏；且 M0 已判定「M2 在新契约发布前自行过滤，不能假定读取层已修复」 |
| 旧 adapter 读 `task_count` | 语义变为「本次返回条数」（原来等于全部 active 数） | `window_counts` 给出完整拆分，需要全量基线的看 `in_window + overdue + undated + excluded_out_of_window` |
| 只读 `source` / `as_of` | 无影响 | — |
| 新增字段 | 旧代码忽略未知字段即可 | 全部为新增，无删除、无改名 |

**这两个概念的区分是 M0 明确要求保留的**：

- **账号全量基线核对**（历史 5 条）= 不传窗口或传覆盖性窗口时的读取，用于「账号里到底有多少东西」；
- **窗口查询输出** = 传具体窗口的结果，条数少于基线**不是读取失败**。

---

## 四、测试证据

| 项 | 结果 |
|---|---|
| 全套测试 | **306 项 OK**（原 292 + 新增 14） |
| 新增文件 | `tools/m1-server/tests/test_window_filter.py` |
| 修改文件 | `tools/m1-server/real_read.py`（+约 100 行） |
| 原 4 项失败测试 | **已自然恢复通过**，未修改任何测试代码 |

原来严格过滤时有 4 个 `TestDeadlineMapping` 用例失败（窗口与夹具日期不匹配导致 IndexError）。
改为口径乙后它们全部通过——**这反证了口径乙是对的**：逾期任务被保留，所以依赖逾期任务的字段映射测试不再被误伤。

### 负向测试（M0 裁定要求、M3 复核项）

`test_window_filters_everything_out_still_source_real`：全部任务都不符合窗口条件 ⇒
`tasks == []`、`source == "real"`、`excluded_out_of_window == 2`，且断言不含 MOCK 夹具特征。

`test_overdue_exception_does_not_block_empty_set`：存在逾期例外时仍能构造真空集 ——
证明「逾期保留」没有把空集这条路堵死（这是 M0 裁定原文括号里的要求）。

`test_empty_table_path`：库中无 active 任务时的早退路径，同样 `source=real`。

**L4 的准确表述（采纳 M3 建议拆两条）**：

- **L4a 空集不回落 MOCK**：`PASS`（静态可判：`_tasks_payload` 的 `source` 恒为 `real`；`app.py` L142/L150/L766/L879/L1178 均 fail-closed，无静默回退）
- **L4b 空集可达性（窗口真生效）**：原 `FAIL` → 本次修复后本地 `PASS`（负向测试见上）
- **整体 L4**：按 M0 2026-11-10 裁定，**对外仍标 NOT TESTED，不引用旧 PASS**，待发布后由 M3 复核负向证据

---

## 五、未做的事（明确声明）

- **未发布**。线上仍是 16:03:45 那版，无补丁。
- **未改 DDL / RLS / 表结构**。
- **未动 MOCK 侧**（`tools/m1-mock/`）。
- **未修 `get_calendar_events`**：其 `courses` 是全量读。判断是**课程属学期维度、不属窗口维度**，逐课程按窗口筛会切碎课表。若 M0/M2 认为该改，请明确语义后再动。
- 未写 `course_schedule_rules` 的窗口过滤（同上）。

---

## 六、申请事项

请 M0 在下列条件满足后单独授权发布：

1. 契约变更获准（本文档）；
2. 回归结果复核通过（306 项 OK，可复跑：`python -m unittest discover -s tests`）；
3. M3 复核负向测试证据（`docs/evidence/`）。

**在获准前不发布。** 现场演示仍用线上现状（窗口不筛选），对外表述为「窗口过滤已定位并修复，待发布」。

---

## 七、坐标

| 内容 | 位置 |
|---|---|
| 实现 | `tools/m1-server/real_read.py` |
| 测试 | `tools/m1-server/tests/test_window_filter.py` |
| 脱敏证据 | `docs/evidence/realread-2026-11-10T11-07Z.redacted.json` |
| 本地 commit | `a2db88a` 之后未提交（工作区改动） |
