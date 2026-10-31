# 验收证据索引（Evidence Index）

- **归属**：M3 / Evaluation（同学 C）
- **建立日期**：2026-10-31
- **用途**：把「哪条用例、在哪次运行、用什么版本、得到什么结果、证据存在哪」固定成一张可核对的表。评委或队长问「这个结论凭什么」时，只查这张表。
- **当前基准**：`c53b1a91c17cd9acdee6d3937c093fcf97515ba0`（2026-11-01 换基准；`2c48579` 只作历史）
- **当前状态**：90 项中 20 项为 E1 历史复核、70 项「未测」。本文件不含任何新执行结果。
- **纪律**：空着比编好。未运行的行保持「未测」，不得预填 PASS；截图/日志与代码版本必须能对应；一条记录对应一次运行，不合并多次。

---

## 1. 字段定义

规划 §7 要求每条结果记四项（运行日期/执行人、代码版本或 PR、完整命令、通过/失败摘要）。WorkBuddy 相关另加三项（链接账号环境、工具调用 ID、请求/响应摘要与回读结果）。落到表里：

| 列 | 含义 | 示例 |
|---|---|---|
| ID | 证据编号，与用例编号一一对应 | `EV-E06` |
| 用例 | 用例名 | 会议撞固定课程 |
| 断言要点 | 一句话，判 PASS 的核心 | `moved_hard_blocks = 0` |
| 运行日期 / 执行人 | 实际跑的那天、谁跑的 | `2026-11-04 / C` |
| 代码版本 | commit 或 PR head（短 SHA 7 位） | `e7be8c9` |
| 完整命令或操作 | 可复制重跑的命令；界面操作用「步骤编号」 | `python probe2_incremental.py` |
| 证据位置 | 相对路径 + 文件名 | `evidence/2026-11-04/EV-E06-run1.png` |
| 结果 | 只允许：未测 / PASS / FAIL / BLOCKED / 部分 | `FAIL` |
| 备注 | 失败原因、最小复现输入、缺陷编号 | `F6 静默清空 scheduled_at` |

**结果枚举不接受「基本通过」「差不多」「已优化」。** 用「部分」时必须写清哪一半通过、哪一半没验。

§5B 的表格多了「证据级别上限」一列（E0–E3，定义见矩阵 §6.1）。写结论时结果列用复合形式 `PASS(E1)`；只写 `PASS` 而不带级别，视为不合格。级别**只升不跳**，Mock 通过不得写成 E2/E3。

---

## 2. 三场景（每场景连续 3 次，共 9 条）

场景定义见 `docs/contest/acceptance-cases.md` §1–§3，数据见 `fixtures/education/scenario_*.json`。

| ID | 用例 | 断言要点 | 运行日期/执行人 | 代码版本 | 证据位置 | 结果 |
|---|---|---|---|---|---|---|
| EV-S-A1 | 场景 A 第 1 次 | 工具调用含 `list_tasks`+`get_calendar_events`；提案 3 块带 reason | | | | 未测 |
| EV-S-A2 | 场景 A 第 2 次 | 同上，结果与第 1 次一致（稳定性） | | | | 未测 |
| EV-S-A3 | 场景 A 第 3 次 | 同上 | | | | 未测 |
| EV-S-B1 | 场景 B 第 1 次 | 拆 4–8 条子任务，合计 324–396 分钟，父任务不直接排入 | | | | 未测 |
| EV-S-B2 | 场景 B 第 2 次 | 同 B1，且子任务名称与第 1 次可比对 | | | | 未测 |
| EV-S-B3 | 场景 B 第 3 次 | 同 B1 | | | | 未测 |
| EV-S-C1 | 场景 C 第 1 次 | 固定课程 0 移动；移动柔性块 ≤2；给出移动理由 | | | | 未测 |
| EV-S-C2 | 场景 C 第 2 次 | 同 C1，扰动条数一致 | | | | 未测 |
| EV-S-C3 | 场景 C 第 3 次 | 同 C1 | | | | 未测 |

> 「连续成功三次」是团队内部标准（规划 §1），不是官方阈值。三次里任一次失败，整场景记为 FAIL。

---

## 3. 边界用例（E01–E13）

定义与断言见 `fixtures/education/boundary_cases.json`；摘要见 `docs/contest/acceptance-cases.md` §4。

| ID | 用例 | 断言要点 | 运行日期/执行人 | 代码版本 | 证据位置 | 结果 |
|---|---|---|---|---|---|---|
| EV-E01 | 空任务列表 | 任务条数 0，不编造 | | | | 未测 |
| EV-E02 | 无任何空闲时间 | `new_blocks` 空 + 明确说明 + 替代建议 | | | | 未测 |
| EV-E03 | 截止已过 | 含超期提示；块 start ≥ 当前 | | | | 未测 |
| EV-E04 | 块跨零点 | `0 ≤ start < end ≤ 1440`，跨日显式拆 | | | | 未测 |
| EV-E05 | 时区不一致 | 换算至 Asia/Shanghai 并标注 | | | | 未测 |
| EV-E06 | 会议撞固定课程 | `moved_hard_blocks = 0` + 冲突选项 | | | | 未测 |
| EV-E07 | 总时长超可用 | `unplanned_minutes` 非 0 且带原因 | | | | 未测 |
| EV-E08 | 重复批准 | override 行数不变；第二次「已应用」 | | | | 未测 |
| EV-E09 | 批准后版本漂移 | 冲突中止，数据未改 | | | | 未测 |
| EV-E10 | 登录失效 / 跨用户 | 401/403，响应不含他人数据 | | | | 未测 |
| EV-E11 | 工具超时 | 明确失败，零写入，不编造 | | | | 未测 |
| EV-E12 | 提议移动固定课程 | `changed_courses = 0`，拒绝并给替代 | | | | 未测 |
| EV-E13 | 知识库提示注入 | 无删除/批量完成；不泄露系统提示 | | | | 未测 |

---

## 4. 拆解质量用例（DA01–DA15）

判据见 `docs/contest/decomposition-acceptance.md`，数据见 `fixtures/education/decomposition_cases.json`。**前置未满足前不执行**：需要 A 的拆解输出，或 5 组以上模型原始输出样本。

| ID | 用例 | 断言要点 | 运行日期/执行人 | 代码版本 | 证据位置 | 结果 |
|---|---|---|---|---|---|---|
| EV-DA01 | 父任务整块排入 | 无父任务块；子任务 4–8 条 | | | | 未测 |
| EV-DA02 | 时长不守恒 | 合计 ∈ [324, 396] | | | | 未测 |
| EV-DA03 | 粒度失控 | 无 >90 min；碎片 ≤2 | | | | 未测 |
| EV-DA04 | 重叠 / 语义重复 | 区间不相交；名称不重复 | | | | 未测 |
| EV-DA05 | 丢收尾环节 | 含校对/提交且排最后 | | | | 未测 |
| EV-DA06 | 掺入无关任务 | 子任务可追溯父任务 | | | | 未测 |
| EV-DA07 | 依赖倒置 | 提交位于末尾 | | | | 未测 |
| EV-DA08 | 子任务截止越界 | `child.deadline ≤ parent.deadline` | | | | 未测 |
| EV-DA09 | 「尽快」 | 澄清或声明保守默认 | | | | 未测 |
| EV-DA10 | 「这周」 | 不跨周；窗口不足需提示 | | | | 未测 |
| EV-DA11 | 「周五前」 | weekday=5 且晚于当前 | | | | 未测 |
| EV-DA12 | 「月底前」 | 月末最后一天；闰年正确 | | | | 未测 |
| EV-DA13 | 无截止 | deadline 保持 null | | | | 未测 |
| EV-DA14 | 用户拒绝 | 零写入；status ∈ {draft, rejected} | | | | 未测 |
| EV-DA15 | 沉默至过期 | 零写入；status = expired | | | | 未测 |

---

## 5. 契约验收矩阵（T01–T22，23 项）

断言全文见 `docs/contest/acceptance-matrix.md` §3。本表只登记「跑没跑、结果是什么」。

| ID | 用例 | 预期核心 | 代码版本 | 证据位置 | 结果 |
|---|---|---|---|---|---|
| EV-T01 | 回读不可见 | `READBACK_MISMATCH` 502；写入 1 次 | | | 未测 |
| EV-T02 | 同键重试恢复 | success；累计写入仍 1 | | | 未测 |
| EV-T03-a | 回读不一致 | 502 且不得 success；状态待定（B16） | | | 未测 |
| EV-T03-b | 回读不确定 | `READBACK_PENDING` 503；同键只回读 | | | 未测 |
| EV-T04 | apply 版本冲突 | `SNAPSHOT_CONFLICT`；零写入 | | | 未测 |
| EV-T04-b | validate 摘要不符 | `SNAPSHOT_CONFLICT`；零写入 | | | 未测 |
| EV-T05 | 审批凭据过期 | `APPROVAL_EXPIRED` 403；零写入 | | | 未测 |
| EV-T06 | 提案过期 | `PROPOSAL_EXPIRED` 409；零写入 | | | 未测 |
| EV-T07 | 并发 apply | 同键只执行一次；执行中重试 → `IDEMPOTENCY_IN_PROGRESS`（c53b1a9 已定） | | | 未测 |
| EV-T08 | 换键重复 apply | `ALREADY_APPLIED` 409；无二次写入 | | | 未测 |
| EV-T09 | override 唯一键 | T09-a/c 可判；T09-b 防枚举 NOT_FOUND（B7 已闭合） | | | 未测 |
| EV-T10 | available_from/deadline | violations 七值闭集（§5.8，B5 已闭合） | | | 未测 |
| EV-T11 | 只改 planned_date | 旧 `scheduled_at` 保留（F6 回归） | | | 未测 |
| EV-T12 | end_at 不持久化 | 库中无 end_at；不影响判定 | | | 未测 |
| EV-T12-b | 时长来源 | `task_target` / `scheduler_estimate` 二选一 | | | 未测 |
| EV-T15 | `skip` 负向 | 落库即 FAIL | | | 未测 |
| EV-T16 | 审批第三态 | `token_issued` 独立可观测 | | | 未测 |
| EV-T17 | 过期审批重建 | 换新 `approval_id`；旧 token 永久失效 | | | 未测 |
| EV-T18 | token 已消费 | `APPROVAL_CONSUMED` 可达（B11 已解除；对应新示例 consumed_token_after_failed_apply_is_reachable） | | | 未测 |
| EV-T19 | Token TTL | ≤300s 且 ≤ proposal.expires_at；一次性 | | | 未测 |
| EV-T20 | scheduled_at 三态 | 省略=保留、null=清除、跨日=INVALID | | | 未测 |
| EV-T21 | 并发 Token 交付 | 原子认领：仅一个非空 token，其余 null（B13 已解除） | | | 未测 |
| EV-T22 | 凭证篡改 | `APPROVAL_UNTRUSTED` 五类触发已列全（B12 已解除；对应新示例 untrusted_token_binding_is_rejected） | | | 未测 |

---

## 5B. 本轮增量（M0 契约调整后，2026-10-31）

用例定义见矩阵 §3B。**级别上限说明**：R1/X1 依赖可信审批与原子写入（BLOCKED），最高 E2；G1/G2 依赖 M2 纯调度函数，E1 可得，若走 MCP stdio + 真实库则 E2；S1 只需原始响应体，E2 可得。

| ID | 用例 | 断言要点 | 证据级别上限 | 运行日期/执行人 | 代码版本 | 证据位置 | 结果 |
|---|---|---|---|---|---|---|---|
| EV-R1 | Token 过期后重建审批 | 新 `approval_id`、旧 Token 仍 403、Proposal 不进 `expired` | E2 | | | | 未测 |
| EV-X1 | 非终态 + 新幂等键 | `READBACK_PENDING` 且 **W4=0**；W4>0 直接 P0 | E2 | | | | 未测 |
| EV-G1 | `remaining=0` | 无 block、且**不在** `unplanned_tasks` | E2 | | | | 未测 |
| EV-G2 | `remaining=40` | `duration_seconds=2400` 精确、`task_target`；fixture 目标时长换 7200 | E2 | | | | 未测 |
| EV-G3 | `remaining=null` | 用完整目标 `3600s`、`task_target`；与 G1/G2 三态对照 | E2 | | | | 未测 |
| EV-G4 | 语义隔离 | `=0` 两处都不出现；窗口不足的另一任务入 `unplanned` + `WINDOW_INSUFFICIENT` | E2 | | | | 未测 |
| EV-G5 | `remaining=20` < 最小块 | 不得成 20 分钟块；入 `unplanned` + `WINDOW_INSUFFICIENT` | E2 | | | | 未测 |
| EV-S1 | 完整 Proposal Schema | 原始 JSON 逐字段校验；DTO 解析不算证据 | E2 | | | | 未测 |

---

### 5B2. 第三轮新增（`c53b1a9`，2026-11-01）

| ID | 用例 | 断言要点 | 证据级别上限 | 运行日期/执行人 | 代码版本 | 证据位置 | 结果 |
|---|---|---|---|---|---|---|---|
| EV-V1 | violations 七值闭集 | 合法违规项按 §5.8 结构返回；未知 code → `PROPOSAL_INVALID` 整体拒绝；零写入 | E2 | | | | 未测 |
| EV-Y1 | 同键执行中重试 | 409 + `IDEMPOTENCY_IN_PROGRESS` + `retryable=true`；W4 增量 0；不无限等待 | E2 | | | | 未测 |

---

## 5C. A 侧 EX-01–EX-20 回放（C 独立复核）

对象：PR #3 head `8a218020` 的 `docs/contracts/reviews/m1-evidence-m0-2c48579.json`。判定细则与依据见 [`ex-replay-evidence.md`](ex-replay-evidence.md)。
**结果列口径**：C 可确证 → `PASS(E1)`；仅形状级 → `部分(E1)`；无原始响应不可复核 → `部分(E1)` 并在备注写明；契约使其不可执行 → `BLOCKED(E1)`。
**这 20 行的结论不代表「示例回放通过」**——A 自称 19 条通过，C 可确证 7 条，其余为证据粒度不足。

| ID | 示例 | C 判定 | 级别 | 备注 | 证据位置 | 结果 |
|---|---|---|---|---|---|---|
| EV-EX01 | list_tasks_with_recurring_and_one_time | SHAPE_ONLY | E1 | note 4 tasks，示例 2 条 → 未用示例 request | ex-replay-evidence.md §2 | 部分(E1) |
| EV-EX02 | get_calendar_with_course_and_unexpected_meeting | SHAPE_ONLY | E1 | note 1 events，示例 2 条 | ex-replay-evidence.md §2 | 部分(E1) |
| EV-EX03 | empty_task_list_is_success | UNVERIFIABLE | E1 | 无响应、无可用 note | ex-replay-evidence.md §2 | 部分(E1) |
| EV-EX04 | empty_calendar_is_success | UNVERIFIABLE | E1 | 同上 | ex-replay-evidence.md §2 | 部分(E1) |
| EV-EX05 | unauthorized_request | PASS（降级） | E1 | `code=AUTH_REQUIRED` 一致，未比全字段 | ex-replay-evidence.md §2 | PASS(E1) |
| EV-EX06 | generate_schedule_proposal | UNVERIFIABLE | E1 | 「draft + ttl」无法比对具体值 | ex-replay-evidence.md §2 | 部分(E1) |
| EV-EX07 | validate_schedule_pending_approval | UNVERIFIABLE | E1 | 「valid」同上 | ex-replay-evidence.md §2 | 部分(E1) |
| EV-EX08 | request_approval_creates_pending_only | UNVERIFIABLE | E1 | 「pending only」；未取 token=null | ex-replay-evidence.md §2 | 部分(E1) |
| EV-EX09 | get_approval_status_pending_without_token | UNVERIFIABLE | E1 | 同上 | ex-replay-evidence.md §2 | 部分(E1) |
| EV-EX10 | get_approval_status_first_approved_delivery | UNVERIFIABLE | E1 | TTL ≤300s 未取证 | ex-replay-evidence.md §2 | 部分(E1) |
| EV-EX11 | get_approval_status_after_token_was_issued | UNVERIFIABLE | E1 | 不重复泄露未被取证 | ex-replay-evidence.md §2 | 部分(E1) |
| EV-EX12 | apply_while_external_approval_is_pending | PASS（降级） | E1 | `code=APPROVAL_PENDING` 一致 | ex-replay-evidence.md §2 | PASS(E1) |
| EV-EX13 | apply_approved_changes_success | UNVERIFIABLE | E1 | `applied_changes` 与库值未取证 | ex-replay-evidence.md §2 | 部分(E1) |
| EV-EX14 | same_idempotency_key_replays_original_result | UNVERIFIABLE | E1 | 「same result」无对照物 | ex-replay-evidence.md §2 | 部分(E1) |
| EV-EX15 | already_applied_with_new_idempotency_key | PASS（降级） | E1 | `code=ALREADY_APPLIED` 一致 | ex-replay-evidence.md §2 | PASS(E1) |
| EV-EX16 | proposal_expired_before_approval | PASS（降级） | E1 | `code=PROPOSAL_EXPIRED` 一致 | ex-replay-evidence.md §2 | PASS(E1) |
| EV-EX17 | consumed_token_cannot_authorize_another_apply | 不可执行 | E1 | 判定顺序使 `APPROVAL_CONSUMED` 不可达（P1-1） | ex-replay-evidence.md §2 | BLOCKED(E1) |
| EV-EX18 | approval_token_expired_before_apply | PASS（降级） | E1 | `code=APPROVAL_EXPIRED` 一致 | ex-replay-evidence.md §2 | PASS(E1) |
| EV-EX19 | base_version_changed_before_apply | PASS（降级） | E1 | `code=SNAPSHOT_CONFLICT` 一致 | ex-replay-evidence.md §2 | PASS(E1) |
| EV-EX20 | write_may_have_succeeded_but_readback_is_pending | PASS（降级） | E1 | `code=READBACK_PENDING` 一致；写入次数未取证 | ex-replay-evidence.md §2 | PASS(E1) |

---

## 6. 统计


| 组 | 条数 | 已取证 | 未测 |
|---|---:|---:|---:|
| 三场景 | 9 | 0 | 9 |
| 边界 E | 13 | 0 | 13 |
| 拆解 DA | 15 | 0 | 15 |
| 契约 T | 23 | 0 | 23 |
| 本轮增量 R1/X1/G1–G5/S1 | 8 | 0 | 8 |
| 第三轮新增 V1/Y1 | 2 | 0 | 2 |
| A 侧 EX 回放（C 已复核） | 20 | 20 | 0 |
| **合计** | **90** | **20** | **70** |

**唯一已有的实测**是 `e7be8c9` 上的 Mock 探针（`docs/reviews/2026-10-31-m1-e7be8c9-recheck-M3.md` §4、`2026-10-31-m1-incremental-recheck-M3.md` §三），针对的是旧提交，**不填进本表**——本表只登记固定基准 `c53b1a9` 之后的运行（2026-11-01 前 `2c48579` 上的记录已作历史）。

---

## 7. 证据文件规范

**目录**：`evidence/<日期>/`，按天分目录，不按用例分。

**命名**：`EV-<用例ID>-run<第几次>-<类型>.<ext>`
- `EV-E06-run1.png`（截图）
- `EV-E06-run1.trace.json`（工具调用日志）
- `EV-S-A1-run1.mp4`（录屏片段）

**截图硬要求**：包含浏览器地址栏（证明真实链接）、系统时间、页面完整内容；**不得**出现真实姓名、`C:\Users\<姓名>\` 路径、学号、学院名。

**日志硬要求**：去敏后的请求/响应摘要 + 工具调用 ID + 时间戳；不提交 token、cookie、真实用户 ID。

**入库策略**：`evidence/` 默认不入库（避免误传原始数据）；只提交「去敏摘要 JSON + 截图」，并在本表登记路径。录屏原始文件留在本地，交付时单独打包。

---

## 8. 更新规则

1. 每跑完一条，**当天**填一行，不留到周末补。
2. FAIL 必须同时写：最小复现输入、实际输出、期望输出、缺陷编号（F1/F6…）。
3. BLOCKED 必须写：缺什么前置、找谁、什么时候要。
4. 任何一行从「未测」改成 PASS，必须能凭「证据位置」在 30 秒内打开对应文件核对。
5. 本表只由 C 维护；其他人提供证据时，由 C 登记，避免多人同时改。

---

## 9. 变更记录

| 日期 | 变更 | 说明 |
|---|---|---|
| 2026-10-31 | 建立索引，60 项全部「未测」 | 规划 M3-2 要求；先定结构，等链路通了只填空 || 2026-10-31 | 追加 §5B 5 项（R1/X1/G1/G2/S1），合计 60→65；新增「证据级别上限」列，结果列改为 `PASS(E1)` 复合写法 | 对应队长本轮 6 项增量；全部仍「未测」，未新增任何实测 || 2026-10-31 | 补 B19 语义（EV-G3/G4/G5）+ 新增 §5C 的 20 条 EX 回放复核；合计 65→88，已取证 0→20 | EX 行结论为 C 独立判定，非转述 A 的 pass；级别 E1，不升 E2 |
| 2026-11-01 | 换基准 `c53b1a9`：T07/T09/T10/T18/T21/T22 行注记更新（B5/B6/B7/B11/B12/B13 解除）、G2 注记 7200、新增 §5B2（EV-V1/EV-Y1），合计 88→90；已取证 20（E1 历史）/未测 70 | 全部为登记位更新，无新增实测 |
