# A 侧 M1 修订验收清单（C / Evaluation）

- **日期**：2026-10-31
- **归属**：M3 / Evaluation（同学 C）
- **对象**：队长 10-31 状态表中 A 的 9 项「待处理」+ 1 项 BLOCKED
- **用途**：A 改完后按本清单逐项验收。**本清单只定义判据，不含任何实测结论**；A 提交新固定 HEAD 后，C 在同一 HEAD 上执行并把结果回填到 `docs/contest/acceptance-matrix.md` 的实测列。
- **纪律**：旧 `18/18` 只作历史留档，**不得作为本轮冻结依据**（队长已明确）。任何一项若拿旧证据交差，直接记 F3（证据缺陷）。

---

## 0. 总则：三项通用验收闸门

A 的每一项修复都必须同时过这三关，缺一不算通过：

| 闸门 | 判据 | 不通过示例 |
|---|---|---|
| G1 可达性 | 该错误码 / 分支**有实际执行路径**，不是"定义了但走不到" | `ALREADY_APPLIED` 存在但被状态检查抢先返回（本轮已发生过一次） |
| G2 契约一致 | 返回的 `error.code`、HTTP 状态、`details` 字段与契约正文表述一致 | 实现返 `NOT_FOUND`，契约写 `FORBIDDEN` |
| G3 证据可复现 | 证据脚本能在指定 HEAD 上重跑并得到同样结果，且标注 Mock / 真实服务 | 有人手工截图，无脚本、无 HEAD |

---

## 1. 逐项验收判据

### A1 Schema `$defs/date_range` 无法独立解析

- **对应用例**：S01（Schema 自洽性，新增）
- **验收判据**：把 `tools.candidate.json` 单独取出，用标准 JSON Schema 校验器（draft 2020-12）做 `$ref` 解析，**不依赖任何外部文件**即可通过；`date_range` 的起止约束（`from <= to`）在 schema 层可表达，或明确声明为运行期校验并写入 description。
- **证据要求**：解析器名称 + 版本 + 退出码 + 报错原文（修复前 / 后各一份）。
- **不通过判据**：仍然报 `Unresolvable $ref`，或靠"运行时先注入定义"绕过解析。

### A2 `ALREADY_APPLIED` 判定顺序

- **对应用例**：T08
- **验收判据**：同一 Proposal、**不同幂等键**二次 apply → 必须返回 `ALREADY_APPLIED`（HTTP 409），且**写入次数为 0**；不得再返回笼统的 `APPROVAL_REQUIRED`。判定顺序应为：幂等记录命中 → 已应用检查 → Proposal 状态检查。
- **证据要求**：T08 完整四元组（响应码 + Proposal 状态 + 数据结果 + 写入次数），并附调用序列日志证明第二次走到了已应用分支。
- **不通过判据**：错误码存在但返回其它值（G1 失败）；或返回 `ALREADY_APPLIED` 但发生了第二次写入。

### A3 validate 重算 `input_digest`，解锁 `SNAPSHOT_CONFLICT`

- **对应用例**：T04（apply 阶段）、**T04-b（新增，validate 阶段摘要不符）**
- **验收判据**：
  - T04-b：validate 请求携带的 `base_version` / `input_digest` 与快照实际不符 → `SNAPSHOT_CONFLICT`，Proposal 保持 `draft`，零写入；
  - T04：apply 阶段 `base_version` 已变 → `SNAPSHOT_CONFLICT`，且该 Proposal 的 token 失效，重试仍失败。
- **证据要求**：构造"两次读取之间快照变化"的时序日志，证明是**摘要重算**触发的冲突，不是硬编码返回。
- **不通过判据**：`SNAPSHOT_CONFLICT` 只能通过传错字段触发，真实漂移时不报（G1 假修复）。

### A4 移除硬编码 `expires_at` 与日期型 `23:59:59`

- **对应用例**：T05（审批过期）、T06（提案过期）、**T16（新增，审批第三态与重复 request 幂等）**
- **验收判据**：
  - `Proposal.expires_at` / `Approval.expires_at` 由**注入时钟**计算，同一输入在不同时钟下得到不同过期时间；
  - 过期后 apply → `APPROVAL_EXPIRED`（审批维度）/ `PROPOSAL_EXPIRED`（提案维度），两者不得混用；
  - 过期 Proposal **不得创建审批**（`request_approval` 返回 `PROPOSAL_EXPIRED`）；
  - 不得出现"创建即过期"（当前 `2026-10-30T23:59` 硬编码的表现）。
- **证据要求**：两套时钟（当前 / 未来）下的响应对比，附 Proposal 与 Approval 的 `expires_at` 实际值。
- **不通过判据**：只把常量改成"当前时间 + N 天"，仍无过期判定路径；或过期判定依赖请求时间而非服务端时钟。

### A5 周期任务时长来源优先级

- **对应用例**：**T12-b（新增）**
- **验收判据**：优先级必须是 `duration_target_seconds`（任务自身） > `snapshot_estimate`（快照估算） > fallback；三种来源分别构造，`duration_source` 字段必须如实标注实际采用了哪一档；无论采用哪档，`end_at` **都不进入持久化与回读断言**（T12 的反向断言仍然生效）。
- **证据要求**：三档各一条响应，`duration_source` 与预期一致；数据库列无结束时间字段。
- **不通过判据**：优先级写反（估算覆盖任务自身值）；或 `duration_source` 恒为同一值（未真正分档）。

### A6 缺失 item 返回 `NOT_FOUND`

- **对应用例**：T09-b
- **验收判据**：对不存在的 `item_id` 发起 `schedule_one_time` / `upsert_daily_override` → `NOT_FOUND`（HTTP 404），**服务进程不崩溃、不出现未捕获异常、后续请求仍正常**。
- **证据要求**：异常请求前后各发一次正常请求，证明进程存活；附 stderr 无 traceback。
- **不通过判据**：返回 `INVALID_ARGUMENT` 或 500；或进程退出（MCP Server 崩溃是本项最严重的失败形态）。
- **备注**：此项同时解除 T09-b 的"假通过"风险——旧 18/18 里该用例从未真正校验过 item 存在性。

### A7 A16 改用正规 `external_fixed_events`

- **对应用例**：T10-a/b
- **验收判据**：冲突用例通过契约允许的 `external_fixed_events` 表达，**不再注入 `__test_conflict_event` 之类的私有字段**；请求体在 `additionalProperties: false` 下仍能通过校验。
- **证据要求**：A16 请求原文 + schema 校验结果；grep 证明实现中无 `__test_` 前缀残留。
- **不通过判据**：保留私有注入通道（等于契约存在未公开的输入面）。

### A8 重复 request 幂等 + 审批第三态

- **对应用例**：**T16（新增）**
- **验收判据**：
  - 同一 Proposal 重复 `request_approval` → 返回**同一 `approval_id`**，不新建记录（幂等），响应码明确；
  - `get_approval_status` 状态机至少五态：`pending` / `approved` / `token_issued` / `consumed` / `expired`；**token 签发后轮询必须返回 `token_issued`，而不是 `approved` + `token: null`**（这是旧实现最容易被误读的第三态）；
  - `consumed` 之后不得再次签发 token。
- **证据要求**：同一 Proposal 连续三次轮询的状态序列；重复 request 前后的审批记录条数。
- **不通过判据**：重复 request 生成多条审批记录；或第三态缺失，客户端无法区分"已批准未签发"与"已签发"。

### A9 修复后重建 Mock 证据

- **对应用例**：全部
- **验收判据**：新证据必须标注**固定 HEAD**（完整 40 位 SHA）、执行时间、执行人、环境（Mock）；旧 18/18 移入归档目录并在文件名或首行注明「历史留档，不作为冻结依据」；新证据的用例编号必须与本清单 / 矩阵编号可对应（不得自造编号）。
- **证据要求**：证据目录结构清晰（`archive/` vs `current/`），`current/` 下每个用例有独立输出文件。
- **不通过判据**：只有一份汇总"18/18 PASS"而无逐用例输出——汇总无法定位失败原因，等同于无证据。

---

## 2. BLOCKED 项：不得用修复成果掩盖

队长表中「M1 实机验证 → WorkBuddy 八步验证 → BLOCKED（等安装客户端）」这一项，**不因 A1–A9 修复而解除**。C 的口径：

- A1–A9 修完后，可写入候选契约的是**契约表述与 Mock 可验证部分**；
- `WorkBuddy 实机调用`、`真实审批服务`、`真实数据库写入与事务性`、`readback_pending 终局判定`、`token 密码学保护（签名 + TTL）` 仍保持 BLOCKED；
- 演示脚本中，这些项必须以"明确阻断 + 原因"呈现，不得用 Mock 成功结果替代（已写入 `docs/contest/demo-script.md` §4 边界声明）。

---

## 3. 验收执行顺序（A 提交后）

1. 取新固定 HEAD，先跑 **G1 可达性**：A2/A3/A4 三条错误路径必须实际走到（这三项历史上都出现过"码在路不通"）。
2. 再跑 **A6 崩溃测试**（唯一可能导致进程退出的项，优先排除）。
3. 然后按 T04-b → T05 → T06 → T08 → T16 → T12-b → T10 顺序执行，每项填四元组。
4. 最后核对 **A9 证据结构**，确认旧 18/18 已归档标注。
5. 结果回填矩阵实测列，输出「冻结建议：同意 / 有条件同意 / 反对」并列出剩余未验证项。

---

## 4. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-10-31 | 初版，对应队长 10-31 状态表中 A 侧 9 项待处理 + 1 项 BLOCKED |
