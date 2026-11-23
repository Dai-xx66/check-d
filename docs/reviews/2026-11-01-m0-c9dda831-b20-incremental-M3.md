# B20 增量复审（`c9dda83`）— M3 / C 侧

- **结论先行**：**B20 PASS（已闭合）**，证据级别 **E1（机检可复现）**，提交与差异为 E2。四条检查点全部通过，未发现新增 P0/P1。
- **基准**：`c9dda83195a9af4b9ca762d8556fdd0e8d43010a`（PR #4 head，`feat/m0-api-contract`，open / 未合并）
- **上一基准**：`c53b1a91c17cd9acdee6d3937c093fcf97515ba0`（其上第三轮对齐结论继续有效，仅 §4.1 一句被修订）
- **范围**：按队长 2026-11-01 01:49 邮件指令，**只审 B20**；未重跑 33 项全量审计，未扩至 B21–B23。

## 0. 基准核实（E2，可外部复算）

| 项 | 结果 | 来源 |
|---|---|---|
| PR #4 `state` / `merged` / `head_sha` | `open` / `false` / `c9dda83195a9af4b9ca762d8556fdd0e8d43010a` | `GET api.github.com/repos/Dai-xx66/check-d/pulls/4` |
| 提交存在性 | HTTP 200 | `GET …/commits/c9dda831…` |
| 与 `c53b1a9` 的差异 | 仅 `docs/contracts/agent-api-v1.md`，**2 insertions / 1 deletion** | `git diff --stat c53b1a9 c9dda83` —— 与队长邮件自述完全一致 |
| JSON / 业务代码 / 状态机 / HTTP 码 / 错误码表 | 未改动（diff 只命中一个文件一个 hunk） | 同上 |

**文件指纹（`c9dda83`）**

| 文件 | git blob | SHA-256 |
|---|---|---|
| `docs/contracts/agent-api-v1.md` | `f7cd37b932b483086278551e604f2c1a777d8e6a` | `dd70432acb218c88a40bfc06d309825944558e8023a805bf1b8606394db7dce2` |
| `docs/contracts/agent-api-v1.examples.json` | `f9c916c824fc67b6b22fedc21cf425e1a67e40e2` | `335d1444ece8825a8eb52960e8d79016ea4fc9939907f5ed09dccd4e61c8b935` |

**唯一文本变化（§4.1，第 165–166 行）**

```diff
-`READBACK_PENDING` 的错误详情必须包含 `proposal_status=readback_pending`；
+`READBACK_PENDING` 的错误详情必须包含 `proposal_status`，其值只能为
+`applying` 或 `readback_pending`，并必须准确反映当前 Proposal 的真实状态；
```

## 1. 检查点一：§4.1 与 §6.7 是否一致 —— PASS

把 §6.7 全部会产出 `READBACK_*` 的路径逐条对照新 §4.1：

| §6.7 位置 | 路径 | 响应码 | 该路径下 Proposal 真实状态 | 是否落在新 §4.1 允许集 |
|---|---|---|---|---|
| 第 670–671 行 | 写后无法权威回读、结果未知 | `READBACK_PENDING` | `readback_pending` | ✅ |
| 第 677–680 行 | `readback_pending` 恢复、回读仍无终局 | `READBACK_PENDING` | `readback_pending` | ✅ |
| 第 704–705 行 | **新幂等键** + Proposal `applying` | `READBACK_PENDING` | `applying` | ✅（本次修复的关键点） |
| 第 704–705 行 | **新幂等键** + Proposal `readback_pending` | `READBACK_PENDING` | `readback_pending` | ✅ |
| 第 677–679 行 | 回读确认不一致 | `READBACK_MISMATCH` | `failed` | ✅（§4.1 第 167 行"必须包含 `proposal_status=failed`"未变） |

**判定**：不存在任何合法路径返回 `READBACK_PENDING` 而 Proposal 状态落在 `{applying, readback_pending}` 之外；原"同一响应码不可能同时满足两句"的硬冲突消失。§6.7 的零写入与"不得第二次 apply"表述未改动，语义保持。

## 2. 检查点二：示例 #21 / #31 / #34 的取值准确性 —— PASS

契约的 `error.details` 是 `[{field, reason}]` 数组（见 §4.1 第 130 行信封示例），下表取 `field=proposal_status` 的 `reason`：

| 示例 | 名称 | 触发路径 | `code` | `proposal_status` | `business_write_count_delta` | 其他 | 判定 |
|---|---|---|---|---|---|---|---|
| **#21** | `new_idempotency_key_while_readback_pending_zero_writes` | 新键 + `readback_pending` | `READBACK_PENDING` | `readback_pending` | `0` | — | ✅ |
| **#31** | `new_idempotency_key_while_applying_returns_readback_pending` | 新键 + `applying` | `READBACK_PENDING` | **`applying`** | `0` | — | ✅ **修复点**：旧 §4.1 下此示例非法，新 §4.1 下合法且与 §6.7 第 704–705 行吻合 |
| **#34** | `same_idempotency_key_while_readback_pending_only_reads` | 同键同摘要 + `readback_pending` | `READBACK_PENDING` | `readback_pending` | `0` | `operation=readback_only` | ✅ 与 §6.7 第 702–703 行"只继续回读"一致 |

**全量旁证**（45 条示例中所有 `READBACK_*` 响应，未发现越界）：

| 示例 | 码 | `proposal_status` | delta | 说明 |
|---|---|---|---|---|
| #20 | `READBACK_PENDING` | `readback_pending` | 未给 | 写后未知的原始路径；此时写入可能已发生，故不强制 `delta=0`，合理 |
| #25 | `READBACK_MISMATCH` | `failed` | 未给 | 终态，允许再次写入的断言不适用 |
| #45 | `READBACK_MISMATCH` | `failed` | `0` | `readback_pending → failed` 恢复路径，零写入 |
| #21/#31/#34 | `READBACK_PENDING` | 见上表 | 均 `0` | 三条恢复/阻断路径零写入 |

**判定**：`applying` 与 `readback_pending` 两种取值与实际路径一一对应，无张冠李戴；`READBACK_MISMATCH` 仍恒为 `failed`。

## 3. 检查点三：两条新幂等键路径均零写入、无第二次 apply —— PASS

| 路径 | 契约依据 | 零写入依据 | 示例证据 |
|---|---|---|---|
| 新键 + `applying` | §6.7 第 704–705 行"统一返回 `READBACK_PENDING`，零业务写入" | 响应为 `error/503`，不含 `data`，无写入成功语义 | #31 `business_write_count_delta=0` |
| 新键 + `readback_pending` | 同上 | 同上 | #21 `business_write_count_delta=0` |
| （同族对照）新键 + `applied` | §6.7 第 706 行 → `ALREADY_APPLIED`，零业务写入 | 同上 | 示例覆盖见 §4 码覆盖表 |
| （对照）同键同摘要 + `readback_pending` | §6.7 第 702–703 行"只继续回读…不得再次写入" | 回读不算写入；`operation=readback_only` | #34 |

**关于"无第二次 apply"**：三条路径均在判定顺序第 6 步（原子消费 Token → `applying`）之前返回，Token 未被再次消费，故不可能启动第二次写入；§6.7 第 720–724 行"一旦消费不得恢复"进一步封死。契约层判据完备。

## 4. 检查点四：范围控制与机检锚点 —— PASS

**范围**：仅 B20。B21–B23 维持 P2（队长明确"不并入本次修订"），未提出新 P0/P1，也未"顺手"重审 33 项。

**机检**：`tools/m3-checks/check_contract_consistency.py` 新增 B20 专项规则（正文侧要求 §4.1 同时允许两值；示例侧要求 `READBACK_PENDING`/`READBACK_MISMATCH` 的 `details` 必须携带合法 `proposal_status`）。同一脚本在旧基准上能抓出问题、在新基准上归零，构成可复现的判别力证明：

```
$ python tools/m3-checks/check_contract_consistency.py c53b1a9
结构/枚举问题: 1
  - §4.1: READBACK_PENDING 未同时允许 applying/readback_pending（B20 未闭合）
exit=1

$ python tools/m3-checks/check_contract_consistency.py c9dda83
示例: 45 条 | 错误响应: 24 | 覆盖错误码: 17/21
结构/枚举问题: 0
exit=0
```

两轮共同项（未受修订影响）：21 错误码 / 8 Proposal 状态 / 6 Approval 状态 / 7 工具 / explanations 与 violations 各 7 值闭集；无示例的错误码仍为 4 个（`DEPENDENCY_UNAVAILABLE`、`INTERNAL_ERROR`、`INVALID_ARGUMENT`、`WRITE_BLOCKED`），与上一轮一致。**该缺口未被本次修订改变，也不属于 B20 范围**，仅作事实记录。

## 5. 证据边界（不可外推）

- 本结论是**静态一致性判定（E1）**：证明"文本与示例自洽、冲突消失、断言可定值"。**不证明**任何实现在 `applying` 路径上真的返回 `applying`——那需要按 §3C.4 跑实现，属 E1 之后的实测。
- `business_write_count_delta=0` 在示例中是**契约断言**，不是计数器观测值；实测需 W4 四层写入口径（§6.2）。
- 真实服务、可信身份、原子写入、生产回读**仍 BLOCKED**，不因本次修复而解除。

## 6. B21–B23 状态（不变，等 M0 落笔）

| 编号 | 状态 | 等待项 |
|---|---|---|
| B21 | P2 | 不强行统一证据形状；C 侧 W4 按两套解析分支实现即可（队长已定方向，无需改契约） |
| B22 | P2 | 方向已定（缺 Token → `APPROVAL_REQUIRED`、跨 Proposal → `APPROVAL_UNTRUSTED`），**待契约明文**后方可升硬断言 |
| B23 | P2 | 方向已定（同键不同摘要 `IDEMPOTENCY_CONFLICT` 优先于 `ALREADY_APPLIED`），**待契约明文**；T08 断言暂不写死顺序 |

## 7. 与 M1 证据的衔接（供 M0 答复 A 时参考）

A 的 EX-17 修复方向——跨 Proposal 错绑 → `APPROVAL_UNTRUSTED`、同 Proposal 已消费未 `applied` → `APPROVAL_CONSUMED`——与队长对 B22 给出的方向一致，也与 §6.7 第 726–729 行（`APPROVAL_UNTRUSTED` 触发条件）互补，不冲突。C 侧可在 M0 确认后，按 `c9dda83` 复核 A 的 EX 响应体与写入计数（A 已补 `writes` 计数器，见其 02:08 邮件）。
