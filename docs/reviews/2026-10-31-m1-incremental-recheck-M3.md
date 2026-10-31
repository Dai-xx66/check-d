# C 增量复审（10 项清单）· e7be8c9

- **日期**：2026-10-31
- **对象**：PR #3 `e7be8c9`
- **方法**：源码核对 + C 独立探针（`probe2_incremental.py`、`probe3_incremental.py`，直调 mock 工具函数），全部按「错误码 + 状态 + 数据 + 写入次数」四元组记录
- **环境**：**仅 Mock**。无实机、无真实审批服务、无真实数据库

---

## 一、逐项结论

| # | 复审项 | 结论 | 证据 |
|---|---|---|---|
| 1 | Proposal 与 Approval 状态迁移完整性 | **不完整** | Proposal 只有 `draft → pending_approval → applied` 三次赋值（`:527/:532/:682`）；`expired` 不落库（仅 `proposal_expired()` 即时算）；无 `cancelled`/`superseded`。Approval 只有 `pending→approved`，`expired` 同样只在轮询即时算（`:590`），`consumed` 只写在 token 记录（`:683`）而非审批记录。契约 §5.7 也缺 `readback_pending` |
| 2 | 五个错误码可达性 | **2 可达 / 3 未定义** | `PROPOSAL_EXPIRED` 可达（实测：过期提案 request 与 apply 均返回该码）；`ALREADY_APPLIED` 可达（实测换键重放）；`APPROVAL_PENDING`、`APPROVAL_EXPIRED`、`APPROVAL_CONSUMED` 在实现中**零命中**，不存在可达性问题——它们根本没有定义 |
| 3 | 重复 `request_approval` 幂等 | **通过，但被 F1 破坏** | 实测同一提案重复 request 返回同一 `approval_id`、审批记录不新增；但过期后仍复用死记录（见 F1），幂等边界失效 |
| 4 | 同键重放与换键重复 apply 判定顺序 | **通过，顺序需写入契约** | 实测顺序：token 校验 → 幂等缓存 → 已应用 → 摘要重算 → 状态检查 → 过期 → 写入。同键重放返回缓存结果且不重写；换键返回 `ALREADY_APPLIED` |
| 5 | Proposal 30 分钟 / Token 5 分钟边界 | **Proposal 通过，Token 未实现** | `expires_in_30min()` 用于提案与审批；但 token 记录字段仅 `approval_id/base_version/consumed/proposal_id/user`，**无任何过期字段**，5 分钟边界不存在，token 永久有效 |
| 6 | 版本冲突是否零写入 | **通过** | 实测：validate 触发 `SNAPSHOT_CONFLICT` 后，tasks 与 overrides 全量深比较无变化 |
| 7 | `readback_pending` 是否只允许回读、禁止重写 | **通过** | 实测：首次 apply 写 override `ov_0038`、条目数 6 → 同键重试返回成功，`override_id` 不变、条目数不变，未发生二次写入 |
| 8 | 单次事项旧 `scheduled_at` 冲突防护 | **不通过（最严重）** | 见 F6：change 不带 `scheduled_at` 时，旧值被**静默清空**，且回读判 PASS |
| 9 | daily override 唯一键与完整回读字段 | **部分** | 见 F7：mock 用 dict 覆盖并换新 `override_id`（实测 `ov_0038 → ov_0063`），真实库 `(userId,itemType,itemId,localDate)` 唯一键下必撞；回读只校验 `planned_start/end_minute`，未校验 `action`/`item_type`/`override_id` |
| 10 | 四元组验收口径 | **保持** | 本轮全部用例均按四元组记录，与矩阵 §5 一致 |

---

## 二、本轮新发现（承接上一轮 F1–F5 编号）

### F6（P0，实现缺陷）旧 `scheduled_at` 被静默清空，回读仍判 PASS

- **构造**：任务 `t_1002` 已有 `scheduled_at=2026-11-01T09:00`、`planned_date=2026-11-01`；提案 change 只给 `planned_date=2026-11-02`，**不带 `scheduled_at` 键**（契约中该字段可选）。
- **实测**：apply 返回 `success`；结果 `planned_date=2026-11-02`、`scheduled_at=None`；`readback_verified=true`。
- **根因**：`tool_server.py:663-664` 无条件执行 `t["scheduled_at"] = ch.get("scheduled_at")`，缺失即写 `None`；回读断言 `t.get("scheduled_at") != ch.get("scheduled_at")` 两侧都是 `None`，因此通过（`:702`）。
- **危害**：这是"成功但丢数据"，比直接失败严重得多。用户原来的定时安排被抹掉，且四元组全部显示正常，验收与排障都发现不了。
- **建议**：① change 中 `scheduled_at` 缺失时**保持原值**；或 ② 若语义就是清空，必须显式 `clear_scheduled_at: true`，并在回读时校验"原值已被显式清除"。契约 §6.4 需补一条"省略 vs 清空"的区分规则。

### F7（P1，契约缺项）override 唯一键与回读字段不完整

- **实测**：同一 `(item_id, local_date)` 先由提案 A 写入 `ov_0038`，再由新快照下的提案 B 写入 → mock 直接替换为 `ov_0063`，条目数仍 6。
- **风险**：真实库 `app_database.dart:366-368` 对 `(userId,itemType,itemId,localDate)` 建唯一键。若服务端按 mock 这样"新 uuid + INSERT"，必撞键；若 `UPDATE`，则 `override_id` 不应变化。契约未规定采用哪种，验收时无法判定对错。
- **回读字段缺失**：`verify_readback` 只比对 `planned_start_minute`/`planned_end_minute`，未校验 `action`、`item_type`、`override_id`、`local_date`。若实现把 `reschedule` 写成 `skip` 而分钟数恰好相同，回读仍 PASS。
- **建议**：契约明确"服务端必须复用既有 `override_id`（UPSERT）"，并把回读字段扩到 `action + item_type + override_id + local_date + 起止分钟`。

### 承接上一轮，仍开放
F1 过期审批被永久复用（提案锁死）；F2 审批第三态在 `status` 上不存在；F3 `readback_verified` 硬编码 `True` 且回读失败时 `proposal_status` 仍 `applied`；F4 23:59 封顶边界；F5 `duration_source` 枚举词汇不一致。

---

## 三、按四元组汇总的实测结果

| 用例 | 错误码 | 状态 | 数据 | 写入次数 | 判定 |
|---|---|---|---|---|---|
| 过期提案 request | `PROPOSAL_EXPIRED` | `pending_approval` 不变 | 无审批新增 | 0 | PASS |
| 过期提案 apply | `PROPOSAL_EXPIRED` | 不变 | 无变更 | 0 | PASS |
| 重复 request（未过期） | `success` | `pending` | 同一 `approval_id` | 0（不新增） | PASS |
| 重复 request（已过期） | `success` | `pending` | **复用过期记录** | 0 | **FAIL（F1）** |
| 换键重复 apply | `ALREADY_APPLIED` | `applied` | 无变更 | 0 | PASS |
| 同键重放 | `success`（缓存） | `applied` | 无变更 | **0** | PASS |
| 版本冲突（validate） | `SNAPSHOT_CONFLICT` | `draft` | 全量无变化 | 0 | PASS |
| 回读失败 + 同键重试 | 首次 `READBACK_MISMATCH`，重试 `success` | 幂等记录 `readback_pending → done` | `override_id`/条目数不变 | 1（仅首次） | PASS |
| 旧 `scheduled_at` 只改 planned_date | `success` | `applied` | **旧值被清空** | 1 | **FAIL（F6）** |
| 既有 override 再次写入 | `success` | `applied` | `override_id` 被替换 | 1 | 需契约定义（F7） |

---

## 四、结论

- 10 项中 **5 项通过**（2、4、6、7、10 的可达/顺序/零写入/只读部分），**1 项部分**（9），**3 项不通过**（1 状态迁移、5 Token TTL、8 旧 `scheduled_at`），第 3 项通过但被 F1 破坏。
- **F6 建议优先于契约讨论修复**：它是实现层可独立修的严重缺陷，且旧 18/18 与 26/26 都没覆盖到（因为没有一条用例构造"change 缺 `scheduled_at`"）。
- 冻结建议不变：**有条件同意实现，反对在契约正文更新前冻结**。

---

## 五、变更记录

| 日期 | 变更 |
|---|---|
| 2026-10-31 | 初版，对应队长 C 增量复审 10 项；新增 F6、F7 |
