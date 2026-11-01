# D4 录屏分镜脚本：拆解 → 确认 → 实际写入 → 回读

- **归属**：M3 / C（同学 C）
- **计划依据**：`docs/CheckD_team_plan.md` D4（11/01）"录制一段内部连续录屏，覆盖拆解→确认→实际写入→回读"
- **当天关卡**：第一条可完整复现的真实 Agent 闭环；队长合并 PR 后打 MVP-1
- **当前状态**：真实写入 **BLOCKED**（§5.4 B9：真实 apply 端点、可信用户确认、第二账号只读复核均未打通）。因此本脚本设计为**双轨**，先用 B 轨抢时间，M0 打通后同脚本直接录 A 轨。
- **M0 裁定（2026-11-01 12:13）**：**双轨已获批**——B 轨可先录并作为 D4 阶段交付，A 轨不设虚假日期，等前置条件满足后同脚本补录。裁定全文与 4 条标识要求见 **§0**。

## 0. M0 对 D4 的裁定（2026-11-01 12:13 邮件，证据级 E2）

**裁定一：接受「B 轨先录、A 轨后补」作为 D4 阶段交付。**
- B 轨（Mock）：可按本脚本 8 镜录制，作为当前阶段交付。**只能证明 Mock 环境中的流程演示**，不得表述为真实 Agent 生产闭环、真实业务写入或真实权威回读。
- A 轨（真实）：待真实端点、可信的逐次用户确认、第二账号只读复核等前置条件具备后，沿用**同一份** storyboard 补录，不因迁就 B 轨而重写流程。
- A 轨**不设虚假完成日期**，等前置条件实际满足后再启动。

**裁定二：B 轨录制必须满足 4 条标识要求（缺一条则整条证据作废）**

| # | 要求 | 本脚本对应位置 |
|---|---|---|
| 1 | 片头**至少 3 秒**全屏标注 `MOCK · 非真实写入` | 镜头 1 片头 |
| 2 | 全程保留清晰、**不可误认**的 Mock 角标 | 全 8 镜右下角常驻 |
| 3 | 画面、**旁白**和结论均不得把 Mock 结果说成真实写入或生产回读 | §2 各镜口播稿 + §3 声明行 |
| 4 | 任何尚未实现的真实能力继续明确标为 **BLOCKED** | 镜头 6/7 口播 + §4 自检 |

**裁定三：`READBACK_PENDING` 的 `proposal_status` 严格按当前基准 c9dda83，无额外收窄。**
- 新幂等键 + Proposal 实际状态 `applying` → `READBACK_PENDING`，`proposal_status=applying`；
- 新幂等键 + Proposal 实际状态 `readback_pending` → `READBACK_PENDING`，`proposal_status=readback_pending`；
- 两条路径均零业务写入，不得执行第二次 apply。
- **Mock 演示也须按路径使用准确状态值，但必须明示这只是契约/Mock 断言，不代表真实端点已通过验证。**

**裁定四：证据纪律（不得越界）**
- A/M1 那 4 条缺 `proposal_status` 的 `READBACK_PENDING` 证据，**继续保持「未测」**（X1 / T03-b / Y1）；
- **不因本分镜已写明该字段，就把缺失的实现证据升级为 PASS**；真实端点验收时再补证。
- B20 复审 PASS 范围仅 B20；B21–B23 继续 P2，不并入本轮，不扩为 33 项全量重审；PR #1 / #4 继续保持未合并。

> 依据：M0 邮件 2026-11-01T04:13Z（`RE:【CheckD】【M0】B20 修复已提交｜统一基准更新为 c9dda831`）。本节为 M0 指令的落笔，后续如与本脚本 §0.1 冲突，以本节为准。

## 0.1 双轨策略（先定规矩，避免"看起来像真的"）

| 轨 | 何时录 | 后端 | 画面标注 | 可写进提交材料的话术 |
|---|---|---|---|---|
| **A 轨（真实）** | M0 交付 `apply_approved_changes` 真实端点 + 可信确认后 | 真实服务 | 无标注 | "真实写入闭环，回读一致" |
| **B 轨（Mock）** | 今天就能录 | M1 的 stdio MCP mock | **片头 3 秒全屏标注 `MOCK · 非真实写入`，且画面右下角常驻角标** | "闭环流程与界面已跑通，写入层为 Mock，真实写入待 M0 后端" |

**硬规则**：B 轨画面**任何时候**都不得让观众误以为是真实数据库写入。角标不是免责声明，是证据诚实性要求——评审若发现未标注的 Mock 冒充真实写入，整条证据链作废。

## 1. 录屏技术规范

| 项 | 要求 | 理由 |
|---|---|---|
| 分辨率 / 帧率 | 1920×1080 / 30fps | 文字可读，提交材料通用 |
| 录制方式 | **一次连续录制，不剪辑、不拼接** | "连续"本身是关卡要求；剪辑会毁掉时间连续性 |
| 时钟 | 屏幕显示系统时间（含秒） | 与日志时间戳对得上 |
| 同屏要求 | Agent 对话 + 终端日志（`tail -f`）同屏或画中画 | 证明"界面说的"和"服务端记的"是同一件事 |
| 脱敏 | Token 一律打码；任务内容用虚拟场景（不出现真实姓名/学号/手机号） | 提交前有匿名检查表 |
| 音频 | 建议口播（可用旁白稿），语速平稳 | 评委看录屏时通常无字幕耐心 |
| 分辨率外的要求 | 鼠标移动放慢，点击前停顿 0.5s | 让每个动作可辨认 |

## 2. 分镜表（8 镜，目标 4–5 分钟）

### 镜头 1｜开场与场景（20s）
- **画面**：WorkBuddy Agent 对话窗口 + 右侧终端。
- **操作**：口播介绍"教育场景：一周学习计划，含固定课程与临时会议"。
- **屏幕应见**：Agent 已连接自定义 MCP，`tools/list` 返回 **7 个工具**（终端里 `7/7 tools loaded`）。
- **证据点**：工具清单截图（对应 W1）。
- **B 轨标注**：片头全屏 `MOCK · 非真实写入`。

### 镜头 2｜读取真实任务与日历（30s）
- **操作**：发一句"看看我下周的任务和课表"。
- **屏幕应见**：`list_tasks` + `get_calendar_events` 两次真实工具调用；`request_id`、`trace_id` 可见；返回任务列表与固定课程。
- **口播**："这两个是**真实**只读调用，不是提示词编的。"
- **证据点**：`request_id` 特写（对应 W2 的 `c0c500ff…` 同款字段格式）。
- **失败回退**：若工具超时，展示超时提示与重试，**保留这段**——它是 W7 的证据。

### 镜头 3｜拆解：从一句自然语言到结构化提案（50s）
- **操作**：发"把课程报告拆成子任务，这周做完"。
- **屏幕应见**：Proposal 卡片——`proposal_id`、`status=draft`、`changes[]`（新增/修改分色）、`explanations[]`（对象数组，`code` 属七值闭集，如 `SCHEDULED`、`ESTIMATED_DURATION`）、`unplanned_tasks[]`（若有）、`expires_at` 倒计时。
- **口播要点**：① 这是**提案**不是写入；② 每条 block 都有 `duration_source`（`task_target` / `scheduler_estimate`）；③ 排不下的任务进 `unplanned_tasks` 并给 `reason_code`。
- **证据点**：Proposal JSON 展开一次（对应矩阵 T01/T10、V1）。
- **必须演示的细节**：`remaining_minutes_today=0` 时只出 `ALREADY_DONE_TODAY`、不进 `unplanned_tasks`（G1 判据）——若场景不适配，本镜跳过，改由镜头 7 的"异常补充"覆盖。

### 镜头 4｜校验与冲突说明（40s）
- **操作**：点"校验计划"（`validate_schedule`）。
- **屏幕应见**：`valid=true`，或 `violations[]`（对象结构 + 七值闭集，例如 `FIXED_EVENT_CONFLICT` 配 `related_task_ids`）。
- **口播**："冲突不是报错就完事，要告诉用户**哪一条**违规、**为什么**。"
- **证据点**：一条真实 `violations` 的特写（对应 T10 / V1 的负向分支）。

### 镜头 5｜确认：把"将改什么"摊开给用户（40s）
- **操作**：点"请求审批"（`request_approval`）→ 展示确认面板。
- **屏幕应见**：新增/修改逐条列出（旧值 → 新值）；`approval_readiness`（`not_requested` / `not_approvable`，**不是** `approval_status`）；用户明确点击"确认"后才出现 `approval_token`（Token 打码）。
- **口播**："用户不点确认，数据库一个字节都不变——这是本项目的核心承诺。"
- **证据点**：确认面板截图 + `approval_readiness` 字段特写（对应 T19/T21、B17 改名口径）。
- **反面演示（强烈建议保留 10s）**：点"取消"→ 展示"未写入"，并回读列表确认无变化。

### 镜头 6｜实际写入（40s）
- **操作**：点"应用变更"（`apply_approved_changes`），带 `Idempotency-Key`。
- **屏幕应见**：三种之一，**必须说明是哪一种**：
  - 成功：`status=success`，`data.proposal_status=applied`，`data.recovery_evidence`（`readback_only` / `business_write_count_delta` / `second_apply_executed=false`）；
  - 未终局：`READBACK_PENDING`（503，`retryable=true`），**详情 `proposal_status` 必须是 `applying` 或 `readback_pending` 且与真实状态一致**（本镜最关键的新断言）；
  - 不一致：`READBACK_MISMATCH`（502），`proposal_status=failed`，不得返回成功。
- **口播**："写入次数只有一次。重复点击、换幂等键、执行中重试，都会拿到零写入的确定性错误。"
- **证据点**：响应体特写 + 终端里服务端写入计数（W4 四层口径）。
- **B 轨注意**：Mock 会稳定返回 `READBACK_PENDING`（写后未知），正好用来演示"未终局"分支；**不要**把它说成成功。
- **按路径定值（M0 裁定三）**：Mock 演示中也须按实际路径给准确值——`new_key + applying` → `applying`，`new_key + readback_pending` → `readback_pending`。口播必须补一句：「**这是 Mock 按契约给出的断言，不代表真实端点已验证**」。本镜 B 轨**只作契约/Mock 断言证据**，不得据此把 X1 / T03-b / Y1 升级为 PASS。

### 镜头 7｜回读与终局收敛（40s）
- **操作**：再调一次 `list_tasks` / `get_calendar_events` 回读。
- **屏幕应见**：新增/修改的 block 真实出现在日程里；时间、时长与提案一致；固定课程**未被移动**。
- **口播**："回读一致才叫成功；不一致就是失败，且不允许第二次写入。"
- **证据点**：回读前后对比截图（这就是"计划前/后差异"的现场版，可复用 `before-after-spec.md` 的版式）。

### 镜头 8｜异常收尾（30s，可剪入镜头 6 后）
- **操作**：同键重试一次；再换新键试一次。
- **屏幕应见**：同键 → 幂等结果或 `IDEMPOTENCY_IN_PROGRESS`（409，`retryable=true`）；新键 + 非终态 → `READBACK_PENDING` 且 `business_write_count_delta=0`。
- **口播**："这就是防重复写入的三道闸。"
- **证据点**：两次响应体并列截图（对应 X1 / Y1）。

## 3. 收尾清单（录完立刻做，别拖）

| 项 | 要求 |
|---|---|
| 文件名 | `d4-closed-loop-{A|B}-{YYYYMMDD}.mp4` |
| 时长 | 4–5 分钟；超过 6 分钟剪掉镜头 8（但不得剪镜头 1–7 的连续性） |
| 截图 | 6 张：工具 7/7、拆解提案、violations、确认面板、写入响应体、回读对比 |
| 日志 | 服务端日志片段（含 request_id / trace_id / 写入计数），与录屏时间戳对齐 |
| 落点 | `docs/demo/` + 证据索引对应行；B 轨文件名与片头标注必须含 `MOCK` |
| 声明 | 提交材料里一行话说明"哪段是真实、哪段是 Mock"，不得含糊 |

## 4. 关卡自检（8 条全过才算 D4 达成）

1. 一次连续录制，无剪辑接缝；
2. 镜头 2 的只读调用可核（`request_id` 可见、能对上终端日志）；
3. 镜头 3 的提案**未写入**（回读证明列表未变）；
4. 镜头 4 至少展示一条真实 `violations`，或明确说明本场景零违规；
5. 镜头 5 证明"不确认 → 零变化"；
6. 镜头 6 的 `proposal_status` 与其真实状态一致（c9dda83 §4.1 硬要求）；
7. 镜头 7 的回读一致，固定课程未移动；
8. 镜头 8 证明重复请求零写入。

**当前可达成**：B 轨可过 1、2、3、4、5、8；第 7 条走 `readback_pending` 路径可演示收敛；**第 6 条当前不可达成（BLOCKED）**——见 §6 实测。
**A 轨待 M0**：真实 apply 端点 + 可信用户确认 + 第二账号只读复核（W4/W5/W6 三条 blocked 解除）。

> **不得因本脚本已写明 `proposal_status` 就把第 6 条记为通过**（M0 裁定四）：脚本是要求，不是证据。

## 6. B 轨录制状态与证据落点（M0 裁定要求的回报项）

### 6.1 状态（截至 2026-11-01 13:00）

| 项 | 状态 | 依据 |
|---|---|---|
| 分镜脚本 | **就绪** | 本文档 8 镜 + 8 条自检 |
| Mock 后端可启动 | **已验证** | `initialize` 成功（`checkd-agent-mock 0.4.0`），`tools/list` = 7 工具 |
| 全链路可跑 | **已验证** | list(4 任务) → generate(12 变更) → validate(0 violations) → approve → token → apply |
| 镜头 1–5 可录 | **就绪** | 上述链路覆盖 |
| 镜头 6（`proposal_status` 断言） | **BLOCKED** | Mock 返回 `details=[]` 或字段名 `proposal.status`，与 c9dda83 不符 |
| 镜头 7 收敛 | **部分** | `readback_pending` 路径可收敛；`applying` 崩溃路径永远 `IDEMPOTENCY_IN_PROGRESS` |
| 镜头 8 零写入 | **可录** | `IDEMPOTENCY_IN_PROGRESS` + 服务端写入计数增量 0 |
| 实际开录 | **未开始（M1 `1d4f3f2` 复测 3/7 不通过，崩溃路径未修）** | M0 已选甲方案，见 §6.2 |

实测明细与复现命令：`docs/reviews/2026-11-01-m1-mock-brail-probe-M3.md`（E1）。

### 6.2 处置决定：**M0 已选甲方案（2026-11-01 12:46 邮件，E2）**

- **甲（已采纳）**：M1 修 4 处偏差 → C 用**同一探测脚本**复测这 4 项 → 全部通过后才一次性录完整 8 镜；
- **乙（未采纳）**：先录 1–5/8 镜、镜头 6 标 BLOCKED。M0 的理由：这 4 项不是新功能，而是 Mock 对 c9dda83 已有契约的实现偏差，应先修齐再录；
- **修复前**：镜头 6 **保持 BLOCKED**，不得录制、不得标 PASS；若复测仍有任一项不通过，如实保留 BLOCKED 并报告实际差异（M0 明确要求）。

**复测闸门（机器判，不靠肉眼）**：

```bash
python tools/m3-checks/assert_brail_contract.py <path>/tools/m1-mock/tool_server.py
# exit 0 = 通过可开录；exit 1 = 不通过，镜头 6 保持 BLOCKED
```

| 闸门 | 判据（全部来自 c9dda83 明文） |
|---|---|
| G0 | 四条 `READBACK_PENDING` 的 `details` 均非空（空 details 不得算通过） |
| G1 | `details` 条目字段名为 `proposal_status`，不是 `proposal.status` |
| G2 | 真实状态为 `applying` 时，值必须是 `applying`（崩溃路径 + 预存 applying 两处都查） |
| G3 | 真实状态为 `readback_pending` 时，值必须是 `readback_pending` |
| G4 | 四条 `READBACK_PENDING` 的 `retryable` 均为 `true` |
| G5 | 写前路径的 `details` 含 `business_write_count_delta=0` |
| G6 | 写前路径服务端写入增量 = 0（不得触发第二次 apply） |

**基线演进（同一命令，可复现）**：

| 日期 | mock 版本 | 结果 | 说明 |
|---|---|---|---|
| 11-01 13:00 | `36ab22e` | 5/7 不通过 | G1/G2/G4/G5 全败，字段名 `proposal.status`、`retryable` 三条 false |
| 11-01 22:50 | `1d4f3f2` | **3/7 不通过** | 字段名、`retryable`、两条新键路径的 delta 均已修好；**仅崩溃路径 `details: []` 未修** |

新基线三项失败（G0 / G2 / G5）同源于一处：`tool_server.py` L862-866 的 `simulate_applying_crash` 分支抛 `READBACK_PENDING` 时未传 `details`。补一句 `proposal_status=applying` + `business_write_count_delta=0` 即可全绿。**镜头 6 仍 BLOCKED，不得开录。**

> 本闸门只判 Mock 行为，判过也不等于真实端点通过；A 轨证据仍需真实服务。

### 6.3 证据落点（录完即按此归档）

| 产物 | 路径 | 命名 |
|---|---|---|
| 录屏 | `docs/demo/` | `d4-closed-loop-B-{YYYYMMDD}.mp4`（文件名必须含 `B`，片头标注必须含 `MOCK`） |
| 截图 6 张 | `docs/demo/d4-b-shots/` | `01-tools-7of7.png` … `06-readback-diff.png` |
| 服务端日志 | `docs/demo/d4-b-shots/server-log.txt` | 含 `request_id` / `trace_id` / 写入计数，与录屏时间戳对齐 |
| 探测原始输出 | `docs/demo/d4-b-shots/probe-output.txt` | `probe_brail_chain.py` / `probe_brail_pending.py` 的完整输出 |
| 声明 | 提交材料 + 视频简介 | 一句话写明"B 轨为 Mock 演示，非真实写入/A 轨待前置条件" |

## 5. 与提交材料的衔接

- 本脚本落实后，`docs/demo/before-after-spec.md` 的"计划前/后"版式可作为镜头 7 的画面模板；
- 截图 6 张直接进 `docs/submission/scoring-evidence-map.md` 的"功能完整性"一栏；
- 匿名检查：录屏里出现的任务名必须是 `fixtures/education/` 里的虚拟场景（高等数学 / 大学英语 / 数据结构 / 大学物理实验）。
