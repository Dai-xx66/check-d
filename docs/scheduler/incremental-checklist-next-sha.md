# B（M2）：收到 M0 固定 SHA 后「只检查增量」的清单

> 背景：队长 2026-10-31 @所有人——「M0 已完成 v1 CANDIDATE 最终决策收口，
> 当前修改仍在 M0 本地，**待队长本人提交并发布固定 SHA**；B/C 收到新 SHA 后**只检查增量，
> 不重新开展完整评审**。PR #2、PR #3 暂不合并。」
>
> 上一轮对齐基准：`upstream/feat/m0-api-contract` @ `2c48579`
> （预对齐记录见 `docs/scheduler/alignment-v1-candidate-2c48579.md`）。
> 日期：2026-10-31　维护人：B（M2）
>
> **本清单存在的意义**：新 SHA 到手后不再临时起意地"再看看全文"，只跑一遍固定的增量项，
> 5 分钟出结论，其余一概不看。
>
> **2026-10-31 起契约基准是两份文件**，不再只有 md：
> `docs/contracts/agent-api-v1.md` + `docs/contracts/agent-api-v1.examples.json`。
> 守住一条纪律：**diff 结果为 0 行只能说明「这份文件内容没变」，
> 不能说明「基准没变」**——文件清单本身的新增/删除 diff 查不出来，必须手动核过 `git ls-tree`。

## 零、三步流程

```bash
cd /e/Projects/check-d-lhy
git fetch upstream
# 第 0 步：先确认契约文件清单本身没变（diff 查不出新增/删除文件）
git ls-tree -r --name-only <新的固定SHA> | grep contracts
bash docs/scheduler/tools/contract-diff-check.sh <新的固定SHA>
```

脚本会直接给出十组 diff：前六组针对 `agent-api-v1.md`（**变更规模 / 错误码集合 /
工具清单 / 冻结关键字计数 / TTL 段落 / §5.6–§5.7 正文**），§7–§10 针对
`agent-api-v1.examples.json`（**变更规模 / tools 清单 / 示例条目清单 / M2 关键字计数**）。
看它的输出，再对照下面的第 1–8 项逐条判。

> 如果某份契约文件被增删，脚本会明确打印「跳过：新旧 SHA 中至少一方没有这份示例文件」，
> 看到这行就说明**基准变了**，不是「没变化」——别把它当成通过。

> 如果 `[1] 变更规模` 显示 0 行 → **无需任何对齐**，只需要向 M0 确认一句
> "这就是最终稿"（同一份文本在不同 SHA 下的重放也要留这句话，避免以后扯皮）。

## 零之二、本轮已由 M0 决定、只需核对「是否真写进契约」的条目

| 项 | M0 的决定 | 新 SHA 到手后我要做的 |
|---|---|---|
| R1 | Token 过期 → 旧审批终结；Proposal 未过期可重建 `approval_id` | 只看 §6.5 是否真写了「未终结」集合；没写 → 退回 |
| X1 | `applying`/`readback_pending` 下任何新幂等键 → `READBACK_PENDING` + 零写入 | 只看 §6.7；没写 → 退回 |
| `input_digest` | 覆盖 horizon 起止与 Asia/Shanghai 时区 | 只看 §5.7；M2 侧已给出「只改 horizon 输出就不同」的证据 |
| 状态机 | 补 Approval 迁移图、组合表、过期边界、`readback_pending` 恢复路径 | 只看 §5.7 图与 §6.6/§6.7 口径；缺哪项退回哪项 |
| Proposal 序列化 | **方案 A**：服务端序列化，M2 不输出 `proposal_id` 等服务端字段 | 若契约改选方案 B，我再改一次 DTO |

## 一、只看这 8 项

| # | 看契约哪一节 | 判据（通过的样子） | 不通过怎么办 |
|---|---|---|---|
| 1 | §4.1 错误码集合 | 与我审计的 20 个码一致；若新增 `PROPOSAL_NOT_APPROVABLE` → 必须是 **409**，且定义窄化为"主体正确但状态不允许建审批" | 若其定义泛化到能覆盖 expired/applied，退回——会吞掉 `PROPOSAL_EXPIRED` / `ALREADY_APPLIED` 的语义 |
| 2 | §6.x 工具清单 | **仍是七个工具**，无第 8 个，无工具改名 | 工具数或签名变了 → 此清单作废，需要重新评审（属重大变更） |
| 3 | §6.5 `request_approval` | **答了 R1**：明确定义"未终结审批"集合（建议 `{pending, approved, token_issued 且 Token 未过期}`） | 不答 → `APPROVAL_EXPIRED` 之后死锁依旧，该码在「Token 过期后重走审批」这条路径上仍然不可达 | 
| 4 | §6.7 `apply_approved_changes` 判定顺序 | 仍是 ①幂等记录 ②是否已 applied（换键→`ALREADY_APPLIED`）③Proposal TTL ④`base_version` ⑤Token | 顺序变动 → 「哪个错误码优先」的验收期望全部改写 |
| 4b | §5.6 时长优先级第三级 | 兜底仍是 `max(preferences.minimum_block_minutes, 30)` | 改成别的值 → 我的守卫用例随之改；改成"不应由纯函数兜底" → 我把第三级删掉并让 `NO_VALID_DURATION` 重新生效 |
| 5 | §6.7 换幂等键 + 中间态 | **补了 X1**：Proposal 处于 `applying`/`readback_pending` 时换幂等键一律零写入 | 不补 → 唯一一条可能二次写入的通道仍然存在 |
| 6 | §5.7 / §7.1 TTL | Proposal 固定 30 分钟、**不按当日 23:59 截断**；Token 5 分钟且不得越过 `expires_at` | 出现任何"当日截断"口径 → 引用我已作废的旧建议并再退一次 |
| 7 | §5.2 / §5.6 排程输入 | `remaining_minutes_today` 三态语义不变；`scheduling_weight` 仍 BLOCKED 或明确"由服务端折算后给 M2" | 若要求 M2 直接消费 BLOCKED 的 weight → 声明不可接受（会让输出不可复现） |
| 8 | §5.7 `input_digest` 范围 | 是否纳入 **horizon 与时区** | 不纳入 → 同一 digest 不同 horizon 会产出不同提案而 validate 察觉不到 |
| 9 | `examples.json` 示例条目清单 | 脚本 §9 报出新增/删除/改名的示例名，逐个判落在谁的边界（属 A/C 的不碰） | 新增 `generate_schedule` 相关示例 → 必须重跑 M2 输出对照，不能只看 md |
| 10 | `examples.json` 里的 `explanations[].code` | M0 是否已给出**封闭枚举**，且示例取值落在该枚举内 | 仍是「md 无枚举 + 示例自造码 + M2 自造码」三套零交集 → P2 继续挂起，我不照抄示例 |
| 11 | `examples.json` 里的完整 Proposal 实例 | 是否仍含 `snapshot_ref`/`input_digest`/`generated_at`/`expires_at` 四个服务端字段 | 若契约改为「不含它们也能过 Schema」→ P4 自动消解；否则坚持要写明序列化职责归属 |

## 二、M2 会跟着改代码的「红线信号」（命中才有事做）

以下 5 处任一发生变化，我才会动 `lib/` 与 `test/`；其余变化**一律不动代码**，
只在此清单下面追加一行结论。

1. `schedule_block`（§5.6）字段增删或改名；
2. `schedule_proposal.status`（§5.7）8 态枚举增删；
3. `changes` 白名单（§5.7 表格）增删 type 或必填字段；
4. `unplanned_tasks.reason_code` 四值枚举变化；
5. `explanations` 元素形状变化（目前 `{code, message, related_task_ids?}`）。

命中任一条时的固定动作：改实现 + 改对应守卫用例 + 在 §8 追加一行验证记录 +
**不覆盖历史 18/18、22/22、26/26、28/28 的数字**。

## 三、明确不做的事（防止手滑扩大范围）

- **不重新通读契约全文**（只跑 diff + 上表 8 项）；
- **不重新评审 PR #3**（A 的 `e7be8c9` 及其 26/26 Mock 证据属 M1 侧，我不重跑也不重评）；
- **不碰 `task_repository` / `calendar_occurrence_builder` / `app_database` 等他人文件**；
- **不生成 `tools.candidate.json`**（M1 产物）；
- 不把 M1 的 26/26 与 M2 的 28/28 混为一谈——**前者是 Mock 用例数，后者是纯函数用例数，两者不可比**。

## 四、还欠 M0 的三件事（新 SHA 之前也可以答）

1. `explanations[].code` 的枚举（M2 现用 8 个值，契约只写"机器可读 code"没登记）；
2. R1 死锁（上面第 3 项）；
3. X1 二次写入（上面第 5 项）。

这三件不答，四判定项里「错误码」和「写入次数」两栏就还有开不了口的格子。

## 五、c53b1a9 轮结论（2026-10-31 已跑）

新固定 SHA `c53b1a91c17cd9acdee6d3937c093fcf97515ba0` 到手后按本清单跑了 diff + 8 项：

- 工具清单仍是七个、时长兜底仍是 `max(minimum_block_minutes, 30)`、`remaining_minutes_today`
  三态不变 —— 均无代码改动。
- `explanations[].code` 七值闭集契约已写死，与 `kPublicExplanationCodes` 逐字一致；repair 专用
  `DISPLACED_BY_FIXED`/`REPAIR_SUMMARY` 禁止进 v1 也已明文 —— 守卫早已绑定，无改动。
- 新增 §5.8 `violations` 七值闭集 —— 属 `validate_schedule` 服务端校验职责，**M2 不实现**。
- **命中红线**：契约把「方案 A」从暂定改为明文（M2 不输出 `proposal_id`/`snapshot_ref`/
  `base_version`/`input_digest`/`generated_at`/`expires_at`/`status`），已改 `ScheduleProposal`
  序列化只输出内部四部分，并同步守卫用例。详见 `reports/incremental-alignment-m2-c53b1a9.md`。

历史用例数不覆盖：本轮 38/38（隔离）+ 38/38（宿主 flutter test，本轮环境正常）。

## 六、c9dda83 轮结论（2026-11-01 已跑）

新固定 SHA `c9dda83195a9af4b9ca762d8556fdd0e8d43010a`（B20 最小一致性修复，M0 队长本人提交）到手后跑 diff + 增量核对：

- 相对 c53b1a9 仅改 `docs/contracts/agent-api-v1.md` 一处，2 insertions / 1 deletion；JSON/业务代码/状态机/HTTP 码/错误码表均未动。
- 唯一变化：§4.1 `READBACK_PENDING` 的错误详情 `proposal_status` 取值从「固定 readback_pending」改为「只能为 `applying` 或 `readback_pending`，且须准确反映 Proposal 当前真实状态」。两种路径仍零业务写入、不允许二次 apply。
- 错误码集合无变化、工具清单仍七个、§5.6/§5.7 及示例文件零变化。
- **不命中「红线信号」任何一条**（schedule_block 字段 / status 8 态 / changes 白名单 / reason_code 四值 / explanations 形状均未变），`proposal_status` 属服务端错误详情语义，非 M2 输出结构。
- **结论：零代码改动、零测试。** 仅切换契约基准为 c9dda831（`contract-diff-check.sh` BASE_SHA 更新），PR #2 继续保留未合并。

本轮无测试运行（M0 明确本轮不需为这处纯文档变更重跑 38/38）。

