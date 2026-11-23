# B 轨 v2 重录 · 前置核验记录（M3）

- 时间：2026-11-03 15:10 (+08)
- 触发：M0 2026-11-03T06:42:38Z 裁定（选方案 a，重录一版补 `trace_id` 可见性），并要求录制前确认「实际业务 Mock 仍是代码 `7e1367c2`、契约仍是 `39f7f965`」「`3ce0817` 不得触碰业务代码/运行服务/契约，若触及即停手报告」。
- 目的：在按下录制键之前，把「跑的是什么」钉住；录完若有人问，这份就是基线。

## 一、固定组合（逐字节实测，不采信目录名）

| 对象 | 标识 | 字节 | sha256 | 核对方式 |
|---|---|---|---|---|
| Mock 服务 `tools/m1-mock/tool_server.py` @代码 `7e1367c2` | blob = 远端 7e1367c2 | 52,477 | `ee2eeb10defb6b59c820cd30bc5eee2e78a596f80a547c7a05b8ceb72a674490` | 远端 `raw.githubusercontent.com` 原始字节 vs 本地运行副本，两者 sha256 相同 |
| 契约 `docs/contracts/agent-api-v1.md` @契约 `39f7f965` | blob `9579be9e70673748bae83ed30db83b7048cb9bd1` | 46,684 | `372867530fef0b29734f7d485eee71084e72d55dfd7a5b9ce2ef83d52e7d68cc` | `git show 39f7f965:docs/contracts/agent-api-v1.md` |
| 演示驱动 `tools/m3-checks/demo_driver.py` @`3ce0817`（本次录制所用字节） | 工作区干净，无未提交改动 | 33,593 | `45af7bd19ed6dcaa1fedb9417c9e801c97eb8a9124baa78751cba0a714bd4a7a` | `git status --porcelain` 对该文件 0 行 |

结论：代码侧未漂移、契约侧未漂移；驱动是 `3ce0817` 的原样字节，录制时不会另行改动。

## 二、`3ce0817` 改动范围（M0 要求「触及业务代码即停手」）

```
$ git show --name-only --format="" 3ce0817
docs/demo/evidence/b-track-20261103/ACCEPTANCE-REPORT.md
tools/m3-checks/demo_driver.py

$ git show --stat --format="" 3ce0817
 .../evidence/b-track-20261103/ACCEPTANCE-REPORT.md |  2 ++
 tools/m3-checks/demo_driver.py                     | 19 +++++++++++++++++++
 2 files changed, 21 insertions(+)
```

- 无 `lib/` 下任何路径；无 `docs/contracts/agent-api-v1.md`；无 `tools/m1-mock/` 下任何路径。
- 该提交只新增每个工具调用的 `trace_id` 打印行与 `--log` 落盘参数，不改任何工具调用逻辑与返回值。
- **结论：未触碰业务运行代码、未触碰运行服务、未触碰契约，无需停手。**

## 三、PR 与分支头对齐（API 直读）

| 查询 | 结果 |
|---|---|
| PR #3 state / merged | `open` / `false` |
| PR #3 head | `7e1367c2e22f03cebc29770b44a87c6f0c71066e`（ref `review/m1-contract-v1`，updated `2026-11-03T04:04:23Z`） |
| PR #4 state / merged | `open` / `false` |
| PR #4 head | `39f7f96559abac9d4bc59d5c560e6a706ec19946`（ref `feat/m0-api-contract`，updated `2026-11-03T04:35:52Z`） |
| 我的分支 `feat/m3-fixtures-e2e` 远端头 | `3ce08179c53385409d0dc60ba1137f382cbe7d80`（`2026-11-03T06:13:09Z`）= 本地 HEAD |

三个 PR 均 Open 未合并，固定组合与分支头均未漂移。

## 四、§5.8 闭集专项（M0 原命令复跑）

```
python tools/m3-checks/check_contract_closed_set.py \
  --repo <check-d 克隆> \
  --contract 39f7f96559abac9d4bc59d5c560e6a706ec19946 \
  --against c9dda83195a9af4b9ca762d8556fdd0e8d43010a \
  --expect BLOCK_OVERLAP
```

输出：契约 27,696 字符；§5.8 闭集 **8 个**；基线 `c9dda83` 7 个；新增 `['BLOCK_OVERLAP']`；删除 无；`RESULT: PASS`；**exit 0**。

## 五、35 条证据复跑（并沿用其局限声明）

```
python tools/m3-checks/verify_m1_evidence.py \
  --evidence docs/contracts/reviews/m1-evidence-c9dda83.json \
  --contract 39f7f96559abac9d4bc59d5c560e6a706ec19946
```

输出：条目 35（core 15 + examples 20）；自述通过 35/35；契约冲突 0；未测 A 0；未测 B 0；需说明 1（`list_tasks_with_recurring_and_one_time` 自述与示例存在 fixture/字段差异）；**exit 0**。

**局限照旧声明**：`contract_codes()` 只解析 §4.1 表格的 21 个错误码，§5.8 是散文枚举，不在解析范围。本条不能当 §5.8 证据，§5.8 只由第四节判定。

## 六、新驱动空跑（不录，只验 trace_id 与判定是否失真）

```
python tools/m3-checks/demo_driver.py --mock <7e1367c2>/tools/m1-mock/tool_server.py \
  --auto --lead 0 --hold 0 --start-delay 0 --log /tmp/dryrun-v2.log
```

| 项 | 实测 | 与 v1 对比 |
|---|---|---|
| exit code | 0 | 同 |
| `trace_id` 行数 | **11** | v1 画面 0 行（本次目的） |
| `request_id` 行数 | 11 | 同 |
| 镜 6 | `[PASS]`：`code=READBACK_PENDING` / `retryable=true` / `details.proposal_status=applying` / `delta=0` | 同 |
| 镜 7 | 逐条一致 **4/4**，变化 0 条，写入 1 条 | 同 |
| 镜 8 | 同键 `IDEMPOTENCY_IN_PROGRESS`、换键 `READBACK_PENDING`，均 `delta=0` | 同 |

样例（画面上每块调用的呈现顺序）：

```
<- trace_id=trace_2eaf6642689e46af   (response.status=success)
  list_tasks               : status=success
    request_id             : req_172364429d86
    ...（响应体字段）
```

`trace_id` 与 `request_id`、响应体在同一屏同一调用块内，满足 M0「同时可见」的要求。

**结论：新驱动只是多打印一行，逐镜判定与 v1 零差异，不存在「为了补 trace_id 而改坏流程」的情况。**

## 七、录制参数（就位）

```
python tools/m3-checks/demo_driver.py \
  --mock "…/m1_7e1367c/Tony2215-check-d-7e1367c/tools/m1-mock/tool_server.py" \
  --auto --hold 12 --start-delay 10 \
  --log docs/demo/evidence/b-track-20261103-v2/run.log
```

- `--hold 12`：与 v1 一致。M0 明确接受 3:06.94、不要求为凑 4–5 分钟拖慢。
- `--log`：逐镜终端日志，补上六项交付里第 2 项。
- 输出落 `docs/demo/evidence/b-track-20261103-v2/`，v1 目录不动。

## 八、录制边界（照 M0 裁定执行）

1. 保持原正式 8 镜分镜及顺序；一次连续拍摄，不剪辑、不补拍
2. `MOCK` 角标全程
3. 镜 7 如实展示 `applying` 未收敛
4. 每条工具调用画面同时出现 `request_id`、`trace_id`、响应体/结果
5. B 轨仅为 Mock / MCP stdio 演示，不宣称真实后端闭环或端到端自然语言 Agent 集成
6. A 轨继续 `BLOCKED`；不改 `7e1367c2` 与 `39f7f965`；不合并 PR #2/#3/#4

## 九、预检结论

**可以开录。** 六项里五项已钉死（代码字节、契约字节、驱动字节、闭集、35 条复跑），第六项「逐镜结果不变」由空跑证明。录制完成后交付：新视频 SHA256、时长、字节数、`--log` 路径、关键帧、音轨转写、逐镜 PASS/BLOCKED。
