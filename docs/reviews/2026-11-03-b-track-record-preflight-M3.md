# B 轨 8 镜录制 · 前置核验记录（M3）

- 记录时间：2026-11-03 12:55（北京时间）/ 04:55Z
- 授权依据：M0 2026-11-03 04:47:51Z「正式启动 B 轨 8 镜录制」+ 04:42:31Z「请执行 §5.8 专项闭集核验 / PR-branch 对齐 / JSON 同步判定」
- 录制状态：**未开始**。本文件是录制前置核验，不是录制结果。8 镜需 M3 出镜实拍，未拍完前不报「通过」。

## 一、固定版本组合（录制期间不得漂移）

| 项 | 值 |
|---|---|
| 代码 HEAD | `7e1367c2e22f03cebc29770b44a87c6f0c71066e` |
| 契约 commit | `39f7f96559abac9d4bc59d5c560e6a706ec19946` |
| 契约 md blob | `9579be9e70673748bae83ed30db83b7048cb9bd1` |
| 契约分支 | `feat/m0-api-contract` |

## 二、实际运行代码 SHA 核对（M0 指令一：不一致即停）

不采信目录名，直接取远端原始字节与本地运行副本逐字节比对：

| 文件 | 远端 @7e1367c2 | 本地运行副本 | 逐字节一致 |
|---|---|---|---|
| `tools/m1-mock/tool_server.py` | 52477 B / CRLF 1156 / sha256 `ee2eeb10defb6b59c820cd30bc5eee2e` | 同 | **是** |
| `tools/m1-mock/test_block_overlap.py` | 6896 B / CRLF 0 / sha256 `95ea739720f0182f2a294fe69904f771` | 同 | **是** |

结论：实际运行代码与 `7e1367c2` 一致，无需停止。

## 三、PR #4 / 分支头对齐（M0 第三、四项）

API 直读（`api.github.com`，非采信自述）：

| 查询 | 结果 |
|---|---|
| PR #4 state / merged | `open` / `false` |
| PR #4 head | `Dai-xx66:feat/m0-api-contract` = `39f7f96559abac9d4bc59d5c560e6a706ec19946` |
| PR #4 base | `Dai-xx66:main` = `dc7ef2cd` |
| PR #4 updated_at | `2026-11-03T04:35:52Z` |
| `feat/m0-api-contract` head | `39f7f96559abac9d4bc59d5c560e6a706ec19946`（commit date `2026-11-03T04:35:51Z`） |
| compare `PR head...39f7f965` | `status: identical`，ahead 0 / behind 0 |
| compare `39f7f965...PR head` | `status: identical`，ahead 0 / behind 0 |

**结论：PR #4 head 已经是 39f7f965，且与分支头同一提交。** 「PR head 仍停在 c9dda83」「还需 git apply 旧 patch」两个判断均已过期，作废。M1 无需再应用 §5.8 补丁，M0 无需再做 GitHub UI 操作。

## 四、§5.8 专项闭集核验（M0 原命令，逐字执行）

```
python tools/m3-checks/check_contract_closed_set.py \
  --repo <check-d 克隆> \
  --contract 39f7f96559abac9d4bc59d5c560e6a706ec19946 \
  --against c9dda83195a9af4b9ca762d8556fdd0e8d43010a \
  --expect BLOCK_OVERLAP
```

输出：契约 27696 字符；§5.8 闭集 **8 个**；基线 `c9dda83` **7 个**；新增 `['BLOCK_OVERLAP']`；删除 无；`RESULT: PASS`；**exit 0**。

改动范围旁证（`git diff --stat c9dda83 39f7f965`）：仅 1 个文件、1 删 1 增、单个 hunk 在 L406；字节 46666→46684（+18 B）、字符 27680→27696（+16），恰好等于插入一个 `BLOCK_OVERLAP` + 一个顿号，无夹带。

## 五、旧 evidence verifier 复跑（并声明其局限）

```
python tools/m3-checks/verify_m1_evidence.py \
  --evidence docs/contracts/reviews/m1-evidence-c9dda83.json \
  --contract 39f7f96559abac9d4bc59d5c560e6a706ec19946
```

输出：条目 35（core 15 + examples 20）；自述通过 35/35；契约冲突 0；未测 A 0；未测 B 0；需说明 1（EX-01 沿用）；**exit 0**。

**局限声明（不可省略）**：`contract_codes()` 只解析 Markdown 表格 §4.1 的 21 个错误码，§5.8 的 violation 闭集是散文枚举，不在其解析范围；同一份证据在 `c9dda83` 与 `39f7f965` 下输出除「契约基准」行外逐字相同。故本条**不能**作为 §5.8 闭集证据，§5.8 是否生效只由第四节判定。

## 六、`examples.json` 是否需同步（M0 第三项）

**判定：不属于规范性 violation code 枚举，不需要同步；不要求每个合法码都出现。**

依据（均可复核）：

1. 文件自述 `document_type = checkd_agent_api_v1_mock_examples`、`status = candidate_not_frozen`，即 Mock 示例集，非冻结规范。
2. 全文递归检索 `enum|closed_set|allowed_codes|violation_codes|code_list` 类字段：**0 命中**，不存在任何码值枚举定义。
3. 权威 `agent-api-v1.md` 全文 **0 次**提及 `examples.json`，契约未以引用方式纳入它。
4. 核验器源码 **0 处**引用它，它不是核验输入。
5. 反证：`validate_schedule` 示例共 6 条，只覆盖原 7 码中的 2 个（`PLANNED_BEFORE_AVAILABLE_FROM`、`PLANNED_AFTER_DATE_ONLY_DEADLINE`），其余 5 码从未出现。既有 7 码都没配齐，不存在「新增 1 码必须补示例」的先行义务。

若后续要做，属**增强**不属**同步**：会改 45→46 条、examples 证据 20→21，触发 M1 重生成证据 + 我重核，等于再换一次 head，冻结期不建议动。最小形态：`validate_schedule` 一条 `invalid` + `violations=[{code:"BLOCK_OVERLAP", related_block_ids:[b1,b2]}]`。

## 七、录制前条件清单

| 条件 | 状态 |
|---|---|
| 代码 `7e1367c2` 复核通过（16/16、11/11、G0–G6 7/7、35 条 0/0/1、8 镜演练 0 异常） | 已完成，按 M0 指令**不重跑** |
| 契约 `39f7f965` §5.8 闭集 7→8 | 通过（exit 0） |
| 代码×契约配对复验 | 通过（exit 0，含局限声明） |
| PR #4 / 分支 / 包含关系对齐 | 已对齐，`identical` |
| `examples.json` 同步判定 | 不需要 |
| 8 镜实拍 | **未开始**（需出镜，非本人可代办） |

## 八、录制边界（照 M0 原话执行）

- B 轨标注为 Mock / MCP stdio 演示；不表述为真实后端闭环、真实生产写入或已完成 A 轨。
- A 轨真实 apply / 可信确认 / 第二账号复核继续 BLOCKED。
- 录制期间冻结 `7e1367c2` 与 `39f7f965`；PR #2/#3/#4 保持 Open 不合并。
- 不重跑会改写证据文件或改变录制候选 HEAD 的生成流程。
- 不泄露真实凭据、token、个人敏感数据。
- 失败保留现场与日志，不删改、不补拍掩盖。

## 九、录制后需交付 M0 的六项

1. 8 镜是否全部完成；
2. 每镜通过/失败及简要说明；
3. 录制时实际代码 SHA、契约 SHA；
4. 原始录屏、日志、截图、证据的准确路径/链接；
5. 是否异常、是否重试、重试原因；
6. 最终结论：B 轨演示是否通过 + 未解决事项。
