# B 轨 8 镜录制执行卡（2026-11-03 · 固定组合版）

> 用途：录屏时把这一页放第二屏，逐镜照做照念。
> 授权：M0 2026-11-03T04:47:51Z「正式启动 B 轨 8 镜录制」。
> 取代：`d4-recording-runbook.md`（那份绑的是 `e7dd43b1d` + `c9dda83`，已过期，勿用）。

## 0. 固定组合（录错即作废，开录前必须核）

| 项 | 值 | 怎么核 |
|---|---|---|
| 代码 HEAD | `7e1367c2e22f03cebc29770b44a87c6f0c71066e` | 驱动启动横幅打印 `mock sha256`，应为 `ee2eeb10defb6b59c820cd30bc5eee2e78a596f80a547c7a05b8ceb72a674490` |
| 契约 commit | `39f7f96559abac9d4bc59d5c560e6a706ec19946` | 驱动启动横幅打印「契约 commit =」，片头卡上也印同一 SHA |
| 契约 md blob | `9579be9e70673748bae83ed30db83b7048cb9bd1` | `git -C <repo> rev-parse 39f7f965:docs/contracts/agent-api-v1.md` |

横幅或片头卡上出现别的 SHA → **停，不录**，先查 `--mock` 路径与 `--contract-sha`。

## 1. 开录前 90 秒

| # | 动作 | 检查点 |
|---|---|---|
| 1 | 终端 A 常驻驱动（见下） | 横幅出现 `mock sha256 = ee2eeb10…`、`契约 commit = 39f7f965…` |
| 2 | 终端 B：`tail -f` mock 日志 | 与终端 A 同屏可见 |
| 3 | 录制软件：1920×1080 / 30fps，全屏捕获终端 A，时钟含秒 | 时钟在画面内 |
| 4 | 片头卡：在驱动里输入 `0` | 画面出现 ASCII 片头 + 角标，**停满 3 秒** |

启动命令（一个终端窗口，保持常驻，直到 `fin`）：

```bash
cd <check-d 克隆>
python tools/m3-checks/demo_driver.py \
  --mock <7e1367c2 快照>/tools/m1-mock/tool_server.py \
  --contract-sha 39f7f96559abac9d4bc59d5c560e6a706ec19946
```

> 已实测：该命令下 `7/7 tools loaded`、`server = checkd-agent-mock 0.4.0`、`mock sha256 = ee2eeb10…`、`list_tasks` 读出 4 条任务（t_1001 实验报告 / t_1002 英语六级听力复习 / t_1003 背单词 / t_1004 线性代数复习）。

## 2. 开场两句（必须逐字念）

**第一句**：「本段演示使用 **Mock 后端**，不是真实业务端点，不产生真实写入。」

**第二句**：「WorkBuddy 任务窗尚未接入 Mock，下面由驱动脚本直接向同一个 Mock 发起调用，屏幕上看到的是真实返回的 `request_id` 与响应体，不是回放。」

> 第二句不能省。省略会被理解成任务窗已接通，属误述。

## 3. 8 镜逐镜卡

| 镜 | 时长 | 输入 | 画面必须出现 | 口播（照念） |
|---|---|---|---|---|
| 1 | 20s | `1` | `checkd-agent-mock 0.4.0`、`tools loaded 7/7`、`mock sha256`、7 个工具名 | 「教育场景：一周学习计划，含固定课程与一次临时会议。工具已加载 7 个。」 |
| 2 | 30s | `2` | 两次调用各自的 `request_id`、`tasks 4 条`、课程 1 门、固定事件数 | 「这两个是只读调用，不是我编的提示词；每条都带独立 `request_id`。」 |
| 3 | 50s | `3` | `proposal_id`、`status=draft`、`changes` 分类计数、`blocks` 块数与合计分钟、`unplanned_tasks`、`explanations`、`expires_at` | 「这是**提案**，不是写入。排不下的进 `unplanned_tasks` 并给 `reason_code`，不硬塞、不静默丢弃。提案会过期，`expires_at` 就是它的寿命。」 |
| 4 | 40s | `4` | `validation_status`、`proposal_status`、`approval_status`、`violations` 计数 | 「冲突要说清**哪一条**违规、**为什么**。违规码是 **8 值闭集，含 `BLOCK_OVERLAP`**，集外即越界。」 |
| 5 | 40s | `5` | `approval_id`、`status=pending`、`approval_url`、`expires_at`；轮询 `approval_token` 为 `(none)` | 「用户不在审批页点确认，数据库一个字节都不变。此时拿不到 Token。」 |
| 5a | 20s | `5a` | `status=approved`、打码 Token（`xxxxxxxx********xxxx`）、`token_expires_at` | 「Token 只在批准后首次交付，且**一次性**；屏幕已打码。」 |
| 6 | 40s | `6` | `code=READBACK_PENDING`、`retryable=true`、`details.proposal_status=applying`、`delta 0`、`[PASS]` | 「写入次数只有一次。重复点、换键、执行中重试，都拿到零写入的确定性错误。」+「**这是 Mock 按契约给出的断言，不代表真实端点已验证。**」 |
| 7 | 40s | `7` | `逐条一致 n/4`、`发生变化的条目 0 条`、`服务端写入计数` | 「回读一致才叫成功。」+「崩溃路径停在 `applying`、同键只回 `IDEMPOTENCY_IN_PROGRESS`，**这条路径没有收敛**，我不说成已收敛。」 |
| 8 | 30s | `8` | 同键 `IDEMPOTENCY_IN_PROGRESS`（409）、换新键 `READBACK_PENDING` 且 delta 0 | 「这就是防重复写入的三道闸：同键幂等、换键仍拦、执行中不二次写。」 |

选做（不计入 8 镜，时间够才拍，拍了要说明是补充）：
- `3u` 窗口压到 20:00–22:30 → `unplanned_tasks` 与 `reason_code`；
- `5x` 另一条提案被拒 → `APPROVAL_REJECTED`、写入增量 0。

**收尾**（`fin`，必须念）：「以上全部为 Mock 环境流程演示；真实写入、真实审批、生产回读仍为 **BLOCKED**，待 A 轨补录。」

## 4. 录完立刻自检（8 条，缺一条重录）

1. 片头卡（`0`）是否**停满 ≥3 秒**？
2. 全程右下角/每屏角标 `[MOCK · 非真实写入]` 是否一直在，无裁切、无遮挡？
3. 「Mock 后端、不是真实业务端点」是否说了**至少两次**（片头 + 收尾）？
4. 有没有任何一句把 Mock 说成「真实写入 / 生产闭环 / 真实回读通过」？
5. 镜 6 的 `details.proposal_status` 是否为 `applying`（真实返回，不是硬编码）？
6. 镜 7 是否**明确说出「这条路径没有收敛」**？
7. 是否一次连续录制、无剪辑拼接、无中途换窗口导致时间轴断裂？
8. Token / 姓名 / 学号 / 手机号是否全部打码或用虚拟数据？

## 5. 归档（录完 10 分钟内）

| 项 | 命名 / 位置 |
|---|---|
| 视频 | `docs/demo/evidence/b-track-8shots-20261103.mp4`（4–5 分钟） |
| 关键帧 | `docs/demo/evidence/b-track-20261103/01…08.png`（每镜一张，含镜 6 的 `details`、镜 7 的逐条对比） |
| 每镜说明 | 镜号 / 起止时间戳 / 画面要点 / 实际输出关键值 |
| 必附 SHA | 代码 `7e1367c2e22f03cebc29770b44a87c6f0c71066e`；契约 `39f7f96559abac9d4bc59d5c560e6a706ec19946` |
| 交付 | 按 M0 第五节六项：8 镜是否全完成 / 逐镜通过失败 / 两个 SHA / 证据路径 / 异常与重试 / 最终结论 |

## 6. 现在**不能**说的话

- ❌「真实写入成功」「已经写进数据库」
- ❌「真实审批、真实 Token 已验证」
- ❌「回读一致，闭环完成」
- ❌「崩溃路径已收敛」
- ❌「A 轨已完成 / 可上线」
- ❌ 把 8 镜说成「端到端生产验证」

## 7. 中途失败怎么办

不删现场、不补拍掩盖。念一句「这一镜失败，我保留现场继续」，把失败日志留在画面里，接着往下拍；交付时在第五节第 5 项写明失败镜号、原因、是否重试。

---

编制：钟钰芬（C / M3）｜2026-11-03｜依据 M0 04:47:51Z 开录授权
