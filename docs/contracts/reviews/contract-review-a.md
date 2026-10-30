# M1（WorkBuddy）评审反馈 · `agent-api-v1.md` v1 CANDIDATE

评审人：M1 模块负责人（WorkBuddy / 工具编排）
对象：`Dai-xx66/check-d` 分支 `feat/m0-api-contract` 的 `docs/contracts/agent-api-v1.md`（v1 CANDIDATE）
方式：逐条对照契约 + WorkBuddy 官方能力文档 + 用 MCP stdio mock 做了 14 条契约行为测试（`m1-evidence.md`，14/14 通过）
结论：**契约在数据语义上可以保留；但「身份」和「确认/审批」两处按 WorkBuddy 现状无法落地，`apply_approved_changes` 会永久 BLOCKED。建议 v1.1 增加审批通道后再冻结。**

---

## 1. 可以保留的设计

1. **五工具边界**：读（`list_tasks` / `get_calendar_events`）、提案（`generate_schedule` / `validate_schedule`）、写（`apply_approved_changes`）分工清楚，M1 可以把它们一对一映射成 WorkBuddy 的 MCP 工具。
2. **`api_version` / `request_id` / `timezone` 信封**：适合做工具入参的统一外壳，M1 可直接生成 JSON Schema（已产出 `tools.json`）。
3. **请求体禁止 `user_id`**：方向正确。WorkBuddy 侧不应由模型决定“我是谁”，否则提示词注入即可越权。mock 已验证：带 `user_id` 返回 `INVALID_ARGUMENT`（A2）。
4. **`query_version` 与 `base_version` 分离**：能防止 M1 把两次普通读取拼成“快照”。这对“模型自作聪明”是最有效的约束。
5. **`generate_schedule` 不收客户端 tasks/courses**：契约写得很清楚，mock 也已按此拒绝（A6）。WorkBuddy 的工具 schema 应把 `additionalProperties` 设为 `false`，否则模型一定会往里塞数据。
6. **`schedule_one_time` 只回读 `planned_date`/`scheduled_at`**：与现有模型一致，避免“写入成功、回读旧日期”的假成功（C 的 P0 也点到同一处）。
7. **`readback_verified` 必须为 true 才算成功**：M1 在对话里可以如实转述“已核验/未核验”，这是比赛要求“过程可追溯”的直接素材。
8. **§8 数据最小化与 §9 BLOCKED 清单**：BLOCKED 写得诚实，建议保留并把它变成可勾选的验证清单（见 §4）。

---

## 2. 必须修改（P0）

### P0-1　身份：WorkBuddy 没有“每用户已验证身份”的透传通道

契约 §4 要求“身份凭证必须通过实际工具通道或 HTTPS Authorization 元数据传递，并由服务端验证”，§8 要求“服务端只使用已验证凭证得出的主体 ID”。

**WorkBuddy 的 MCP 配置只有静态凭据**（官方文档/群内教程 7.3）：`headers` 或 `env` 里写死 Token，或走 OAuth 连接；它描述的是“这台 WorkBuddy 连接这个服务用哪个账号”，**没有把终端用户身份传给 MCP 工具的机制**。stdio 模式下更没有 header，只能靠 `env`。

后果：
- 若评委用你们的 WorkBuddy 打开分享的 Agent，工具调用带的是**你们配置的那个 token**，服务端无法分辨“现在是评委在操作”还是“队长在操作”。
- 契约里 `AUTH_REQUIRED`、跨用户 `FORBIDDEN/NOT_FOUND` 在平台层没有产生条件——不是实现问题，是通道不存在。

**建议改法（按代价从低到高，任选其一并在契约写明）：**
1. 增加 `auth_mode` 说明：`static_bearer_demo`（比赛演示，一人一 token，服务端 token→user 映射）与 `oauth_user`（生产）。v1 冻结 `static_bearer_demo`，并在材料里如实披露“演示环境身份由每个演示账号各自的 token 绑定，非终端用户 SSO”。
2. 若坚持“终端用户身份”，则必须放弃 WorkBuddy 直连，改成 WorkBuddy 打开一个带登录态的 H5（你们自己的前端），由 H5 调后端——但这就不再是“工具调用”，而是“WorkBuddy 里嵌网页”，比赛的技术实现分会受影响。
3. 最小改动：契约 §4 把“已验证凭证”降级为“服务端可验证的 bearer token”，并明确 token 的签发/轮换/演示边界；`user_id` 仍禁止出现在请求体。

> 我的判断：比赛场景选 1，别为了“真 SSO”把 M1 拖死。

### P0-2　确认/审批：五工具里没有任何通道能把“用户点了确认”变成服务端可验证的 `approval_token`

契约 §7.1 明确“五个工具中没有 `approve_schedule`，v1 不新增第六个接口”，同时又要求 `apply_approved_changes` 的 `approval_token` 必须“由可信审批服务签发、绑定 proposal/version/digest、未过期未撤销”。

**这两条互相矛盾**：WorkBuddy 的“确认”要么是模型在对话里问一句（不可信、可被提示词绕过），要么是 Workflow 的人工节点（是否可编程、是否带签名，均未证实）。没有第六条通道，审批服务永远收不到“人确认了”这个事件，`apply` 只能一直 BLOCKED。

**建议改法（推荐 a）：**
- **a. 增加第六个工具 `request_approval`**（或 `begin_approval`）：入参 `proposal_id`；服务端创建审批记录，返回 `approval_id` + `approval_url`（H5 页面或飞书卡片）；用户在**工具之外**点确认；审批服务校验登录主体与提案摘要后签发一次性 `approval_token`；Agent 再调 `apply_approved_changes`。模型拿不到“自签 token”的能力，安全性成立。
  - 已用 mock 证明完整链路可跑：`generate → validate → request_approval → apply → readback`，且同幂等键重放返回原结果（A9–A11）。
- **b. 不增工具**：明确 v1 只读 + 提案，`apply` 不进入比赛演示。风险是比赛要求“执行操作 + 核验反馈”的闭环，只读会被判“没闭环”。
- **c. 用 WorkBuddy Workflow 的人工确认节点**：需要先证明该节点能把“确认”以带签名的回调送到你们的审批服务。**目前无证据**，不建议押注。

> 我的判断：选 a。它只多一个工具，但把“可信审批”这件事从“平台黑盒”变成“你们自己的服务”，答辩时也讲得清。

### P0-3　工具入参缺机器可读 schema，M1 无法直接配置 WorkBuddy

契约 §6 只有文字描述，没有 JSON Schema。WorkBuddy 的 MCP 工具需要 `name/description/inputSchema`，否则模型只能靠自然语言猜参数。

**建议**：契约仓库补 `tools.json`（每个工具的 `inputSchema`，`additionalProperties:false`，枚举/必填/格式写全）。我已按契约文本生成一份可直接用的版本：`work/m1/tools.json`（6 个工具，含扩展的 `request_approval`），可直接作为 v1.1 的附件；M0 只需确认字段名。

---

## 2.1 必须修改（P1，可并行）

| 位置 | 问题 | 建议 |
|---|---|---|
| §4 错误码 | 契约给的是 HTTP 建议码，但 MCP 工具返回没有 HTTP 状态；WorkBuddy 只看到 `isError` + 文本 | 明确 MCP 映射：`isError=true` + `structuredContent.error.code`；HTTP 码仅用于将来 HTTPS 直连。否则 409/403 在对话里不可区分 |
| §6.2 | 31 天日历可能返回数百事件，WorkBuddy 工具返回长度上限未知 | 加 `max_events` + `truncated:true`；或 v1 把范围压到 ≤7 天 |
| §6.5 | 工具超时行为未知；“超时”可能已写入 | 契约写明“超时≠未写入”，客户端必须用同一 `idempotency_key` 重试；服务端在 `readback_pending` 时提供查询 |
| §3 | WorkBuddy 跑在学生本机，时区可能不是 +08:00 | 服务端忽略客户端 `timezone`、固定校验 `Asia/Shanghai`（mock A3 已按此拒绝 UTC） |
| §6.3 | 模型天然想传 `tasks` | schema `additionalProperties:false` + 工具 description 明确“只传 date_range/external_fixed_events/preferences” |
| §6.5 | 已 applied 的提案换幂等键再 apply，错误码未定义（C 也提了） | 固定为 `ALREADY_APPLIED`（或复用 `IDEMPOTENCY_CONFLICT`），别用 `WRITE_BLOCKED` 混过去 |
| §8 | “日志不记录任务名”只约束你们服务端，约束不了 WorkBuddy 平台侧 | 材料里披露“平台侧日志不可控”，演示统一用脱敏数据 |

---

## 3. 需要补充的测试（T-A）

判定口径：**响应码 + 状态 + 数据 + 实际写入次数**（与 C 的口径一致）。

| 编号 | 用例 | 预期 |
|---|---|---|
| T-A1 | `tools/list` 的 schema 与契约字段逐一比对 | 字段名/必填/枚举一致，`additionalProperties:false` |
| T-A2 | 无 token 调 `list_tasks` | `AUTH_REQUIRED`，不泄露数据 |
| T-A3 | 用户 B 的 token 调用户 A 的 `proposal_id` | `NOT_FOUND` 或 `FORBIDDEN`，且不泄露存在性 |
| T-A4 | `apply` 超时后用同一 `idempotency_key` 重试 | 只写一次，返回原结果或安全回读 |
| T-A5 | 31 天 + 200 条事件 | 返回 `truncated` 或分页，不静默截断 |
| T-A6 | 触发 `INVALID_ARGUMENT`/`SNAPSHOT_CONFLICT` | WorkBuddy 对话里能读出错误码与可展示文案（不泄露 payload） |
| T-A7 | 未 `request_approval` 直接 `apply` | `APPROVAL_REQUIRED`；确认后成功；token 复用第二次失败 |
| T-A8 | 外部会议与固定课程重叠/提案冲突 | `validate` 返回 `valid=false` + `violations`，不得进入 `pending_approval` |

已完成的：A1–A13（mock 层），14/14 通过，见 `m1-evidence.md`。其中 T-A8 的“冲突构造”mock 还没覆盖，需补。

---

## 4. 尚未验证（BLOCKED，需要 WorkBuddy 实机）

1. **WorkBuddy 是否接受自定义 stdio MCP server**：官方教程 7.3 说支持 stdio/http/sse；**本机未安装 WorkBuddy，未实测**。
2. **工具调用能否把 `env`/`headers` 里的 token 传给 server**：stdio 下应走 `env`，但 WorkBuddy 是否透传、是否支持 `_meta`，未验证。
3. **工具调用超时、最大返回长度、并发限制**：官方文档未写，需实测（直接影响 §6.2/§6.5）。
4. **“专家/Agent”分享链接能否被外部账号打开**：教程只说“可分享给他人”，未说明是否要求对方安装 WorkBuddy 并登录。比赛硬指标是“评委可访问”，必须用另一个账号实测。
5. **Workflow 是否有人工确认节点、能否回调**：决定 P0-2 的方案 c 是否可行。
6. **ADP（腾讯云智能体开发平台）路线**：队友已用 ADP 在一天内做出综测智能体并称“可直接参赛”，说明 ADP 的发布/分享链路是通的。若 WorkBuddy 分享链路验证失败，建议全队评估“ADP 主建 + WorkBuddy 过程材料”的合规说法（需组委会确认）。

---

## 5. 给队长的三句话

1. **契约数据语义我认可**，`query_version/base_version`、只回读 `planned_date/scheduled_at`、`readback_verified` 这三条请保留。
2. **必须加审批通道**（`request_approval` + 外部 H5/飞书确认），否则 `apply` 永远是 BLOCKED；这不是实现问题，是五工具集合里没有“人确认”的入口。我已用 mock 跑通该链路。
3. **身份先按“一人一 token 的演示模式”写进契约**，并在材料里披露；别在 v1 追求终端用户 SSO，WorkBuddy 给不了。

---

## 附：M1 交付物（可直接给 WorkBuddy 用）

- `work/m1/tool_server.py`：MCP stdio mock server，实现 5 个 v1 工具 + 1 个扩展 `request_approval`，含契约校验、幂等、回读、错误码。
- `work/m1/tools.json`：机器可读工具清单（可直接粘进契约或 WorkBuddy 配置）。
- `work/m1/run_evidence.py` / `m1-evidence.md` / `m1-evidence.json`：14 条一致性测试与证据。
- `work/m1/mcp.json.example`：WorkBuddy「自定义连接器」配置示例（stdio + env token）。

WorkBuddy 侧验证步骤（装好后照做，并把截图/日志贴回群里）见 `work/m1/workbuddy-test-plan.md`。