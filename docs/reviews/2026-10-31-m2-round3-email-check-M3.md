# M2 第三轮修订：邮件与提交核对（C / M3）

- **日期**：2026-10-31
- **触发**：B（M2）通过智能体邮箱 `crwd6921@agent.qq.com` 向 M0 与本人在内的收件人发出两封邮件
- **核实方式**：GitHub REST API 只读查询（`api.github.com` 可达，`github.com` 主站被阻断）；本地**无 Flutter / Dart 工具链，未复现任何测试**
- **一句话结论**：B 的报告自洽、路径真实、判定顺序方向正确；但有 **1 处 P0 未真正解除**（B18 只有"决定"没有契约落笔）、**1 处 C 侧判据必须改写**（`explanations.code` 是开放枚举）、**2 处需 M0 书面回答**

---

## 1. 两封邮件的事实

| 时间（UTC） | 主题 | 性质 |
|---|---|---|
| 11:58 | 【测试】B(M2) 智能体邮箱链路测试，收到请回复 | 通道验证，要求回一句确认 |
| 12:01 | 【CheckD·协作方式更新】M2 智能体邮箱通道接入，请 M0 确认可读 | 第三轮修订结果 + 邮箱派活方式 |

第一封是链路测试；第二封承载实质内容，收件人为 `daixinxin_1@outlook.com`（M0 戴鑫馨）与 `scks6105@agent.qq.com`（M3 本人），**未抄送 A（M1）**。

## 2. SHA 与 PR 核实

| B 的声明 | C 核实结果 |
|---|---|
| `d8a5ab9`（代码+文档） | ✅ 存在，2026-10-31T11:17:03Z，parent `1acd187`，"round-3 guards and docs per C's M3 incremental audit" |
| `7a47dd9`（回填） | ✅ 存在，11:17:16Z，parent `d8a5ab96`，"backfill round-3 commit SHA in report" |
| 已推 PR #2（`feat/m2-scheduler-basic`） | ✅ PR #2 open，未合并 |
| **（未声明）** | ⚠️ PR #2 的实际 head 是 **`cc8a473`**，比邮件所列 head 多一个提交：`docs(m2): add round-3 group message draft`（+55/−0，仅新增 `docs/scheduler/reports/group-message-2026-10-31-round3.md`）。代码无差异，但说明**邮件里的 head 会滞后于 PR** |
| （未声明） | ⚠️ PR #2 的评论数为 **0**——第三轮修订说明只存在于邮件正文与分支内报告，PR 页面无可追踪评论 |

**口径**：以后判定一律以 `pulls/2.head.sha` 为准，不以邮件文字为准（见 N3）。

## 3. 报告八项逐条判定

| # | B 的说法 | C 判定 | 级别 / 待办 |
|---|---|---|---|
| 1 | B18：M2 无审批/幂等/写入代码，"没有可改的地方"，给出可直接实现的判定顺序 | **部分成立**。职权边界成立（M2 是纯函数调度器，无写入路径）；给出的顺序第 3 步（新键 + 非终态 → `READBACK_PENDING` 零写入）与 C 侧 X1 断言完全一致 | **B18 仍 P0**：B 引用的"M0 2026-10-31 决定"未出现在 `2c48579` 两份契约文件里（见 N2） |
| 2 | R1：Token 过期 → 旧审批终结 → 允许新建 `approval_id`，不复用 | 与 C 的 R1 判据一致；B 主动提出两处待定，态度正确 | 待 M0 回答（见 §5） |
| 3 | B19：`null` / `0` / 正数三态锁死；`0` 不排、不入 `unplanned`、产出 `ALREADY_DONE_TODAY` | 方向与 C 的 G1/G3 一致，但引入了契约外代码（见 N1） | C 判据需补断言（见 §6） |
| 4 | G1：`blocks` 空、`unplanned_tasks` 空、不落到 30 分钟兜底 | 与 C 的 G1 断言对齐 | 一致，无异议 |
| 5 | G2：完整目标 7200s 时只排 2400s，`duration_source=task_target` | 与 C 的 G2 一致；判据须断言**精确秒数**而非"40 分钟"文字 | 一致 |
| 6 | `input_digest` 必须纳入 horizon 与 timezone | horizon 部分成立且有证据（只改 `horizonEnd` 输出 1 块 vs 3 块）；**timezone 部分在 v1 下无区分度**——契约 §5.2/§5.7 规定 `timezone` 固定 `Asia/Shanghai`、不接受其他值，纳入它永远不会改变 digest | 建议 M0 只落 horizon，不落 timezone（写了也不影响） |
| 7 | 内部 DTO 递归不含 5 个服务端字段；`base_version` 为原样回声 | 与 C 的 S1 一致；递归守卫是本轮最有价值的产出 | `base_version` 回声待 M0 一句话裁定 |
| 8 | `explanations-code-map.md`：9 码（7 公共 + 2 repair）+ 1 已删除 + 4 `reason_code` | 交付确实存在（`docs/scheduler/explanations-code-map.md`） | 见 N1 |

**已核对、不成立的一条**：B 假设"服务端传入的已是 +08:00，M2 不做时区转换"。契约把业务时区固定为 `Asia/Shanghai` 且 `timezone` 字段取值固定，该假设与契约不冲突，**不计为缺陷**。

## 4. 四个新发现

### N1（P2，但会污染 C 的判据）`explanations.code` 是无枚举的开放字段

契约 §5.7 只写「`explanations`：对象数组；每项包含机器可读 `code` 和安全的 `message`」，**从未列出 code 白名单**。M2 因此可以合法产出 `ALREADY_DONE_TODAY`——全文检索 `2c48579` 的两份契约文件，该字符串出现 **0 次**。

对 C 的直接影响：G1/G4 若只断言「`blocks` 与 `unplanned_tasks` 都为空」，那么**"静默丢弃"与"正确识别为已完成"在四元组上完全同形**。判据必须补一条：`explanations` 中必须出现表示"今日已完成"的码，且**不得**出现 `SCHEDULED` / `ESTIMATED_DURATION`。

建议 M0 二选一：① 给出 explanation code 白名单；② 规定命名空间（如服务端码 `srv.*`、调度器码 `m2.*`），避免两个实现各造各的码。

### N2（P0 未解除）"决定"不等于"落笔"

B 的报告三次引用「M0 2026-10-31 决定」，包括 B18 的第 3 步修法。但 `2c48579` 的两份契约文件里没有这条文本。按 C 侧既定纪律（契约以文件指纹为准），**在契约文件实际改动并发布新 SHA 之前，B18 维持 P0 阻断**，不能因为邮件里写了"已决定"就降级。

建议 M0 明确生效边界：**口头/评审会决定 → 契约文本 → 新 SHA** 三段式，只有第三段完成才算生效；否则同一句话在不同人的理解里会被当成已生效。

### N3（P3）邮件里的 head 会滞后

邮件写 `7a47dd9`，PR 实际 head 是 `cc8a473`（多一个纯文档提交）。不影响代码判定，但说明"以邮件正文的 SHA 为准"会算错版本。今后统一以 PR head 为基准，并在回执里写清"核对时 PR head = xxx"。

### N4（证据等级）38/38 是 B 自述，不是已验证

B 称「隔离 dart test 38/38 通过；宿主 flutter test 未执行」。本机无 `flutter` / `dart` 可执行文件，**无法复现**。按 E0–E3 分级，这属于**队友自述（E0）**，不得写入证据索引的 PASS 列，也不得改写矩阵状态行。宿主 Flutter 未执行这一点 B 主动分开报告，做法正确。

## 5. 需 M0 书面回答的三点

1. **§6.7 是否新增一步**：`status ∈ {applying, readback_pending}` 时，**无论幂等键是否相同**一律 `READBACK_PENDING` 且零写入（双向堵口，比只堵"新键"更稳）。
2. **§6.5 "未终结审批"集合**：是否就是 `{approval_pending, token_issued}`；过期判定用 `>=` 还是 `>`。这两点不定，R1 的"新 `approval_id`"就有两套合法读法。
3. **§5.7 `explanations.code`**：白名单还是命名空间（见 N1）。

## 6. C 侧待办（不依赖 M0 也能做的）

- G1/G4 判据补 `explanations` 断言：出现"今日已完成"语义码 + 不含 `SCHEDULED`/`ESTIMATED_DURATION`。**M0 答复前先写成"实现自定义码需登记"的软断言**，避免把 M2 的自造码当契约。
- B18 维持 P0，理由写进矩阵变更记录：契约文件未改。
- 等 M0 发布新 SHA 后按矩阵 §9 做**一次**增量复审，不重开全量。
- B 的 `explanations-code-map.md` 可作为 S1 的对照物（服务端组装后的 Schema 里 code 是否与映射表一致），但**不能替代**服务端 Schema 校验。

## 7. 变更记录

| 日期 | 变更 | 说明 |
|---|---|---|
| 2026-10-31 | 新建本文件 | 对象为 B 的两封邮件 + 第三轮提交；全部结论为文档级核对（E0），无一条实测 |
