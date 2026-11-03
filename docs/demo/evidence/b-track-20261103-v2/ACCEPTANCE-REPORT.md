# B 轨 v2 录制验收报告（M3 自检）

- 录制时间：2026-11-03 15:54–15:58 (+08)（录制者：用户本人，M3/C）
- 验收时间：2026-11-03 16:05 (+08)
- 验收手段：ffmpeg 抽帧（fps=1/6，33 帧）+ 音轨完整转写 + SHA256 + `--log` 日志核对
- 触发：M0 2026-11-03T06:42:38Z 裁定选 (a)，重录补 `trace_id` 可见性；v1 全部材料保留不覆盖

## 一、视频本体

| 项 | v2 实测 | v1 对照 |
|---|---|---|
| 文件 | `b-track-20261103-v2-recording.mp4` | `b-track-20261103-recording.mp4` |
| 大小 | **91,046,570 B** | 84,970,376 B |
| 时长 | **3 分 19.87 秒** | 3 分 06.94 秒 |
| 分辨率 / 帧率 | 1920×1016 / 30 fps | 同 |
| 音轨 | AAC 48 kHz 立体声 | 同 |
| SHA256 | `a565b1699aac008f4eea13e4fded532ddae6758dbf7fe884ee3698ff8d438bfd` | `6dedbcb5ec0a67ce3b89441656a274e36b6469c71712d71666f438e4efb8c1d1` |
| 归档 | `docs/demo/evidence/b-track-20261103-v2/`（未推远端） | `docs/demo/evidence/b-track-20261103/`（未推远端） |

时长比 v1 长 12.93 秒，来源：本次从 30 秒启动倒计时完整入镜（v1 从倒计时中段开始录）。镜次部分节奏与 v1 一致。

## 二、本次重录的唯一目的：trace_id 上屏 —— 已达成

逐帧核验（关键帧见 `keyframes/`）：

| 镜 | 关键帧 | trace_id 实测 |
|---|---|---|
| 镜 2 | f011 | `<- trace_id=trace_efb4219753d54cde (response.status=success)` 与 `request_id=req_32e3ca5526e5`、响应体同屏 |
| 镜 6 | f023 | `<- trace_id=trace_6e79e7961355bd47a (response.status=error code=READBACK_PENDING retryable=True)` |
| 镜 7 | f026 | `<- trace_id=trace_262b0e818de4f43`，同屏 `逐条一致 4/4` |
| 镜 8 | f030 | 同键 `trace_02f4de76d2c14c47`（IDEMPOTENCY_IN_PROGRESS）+ 换键 `trace_08e49b73dd5f4177`（READBACK_PENDING） |

`--log` 日志（`run.log`，28,482 B）：**11 次工具调用 → 11 行 trace_id + 11 行 request_id**，每行与画面一致。M0 第 3 条「画面同时出现 request_id、trace_id、响应体」满足。

## 三、逐镜结果（与 v1 零差异）

| 镜 | 内容 | 结果 |
|---|---|---|
| 0 | 片头 MOCK 声明 + 双 SHA 横幅 | ✅ 0:32.8 开口，横幅印 `ee2eeb10…` 与 `39f7f965…` |
| 1 | 连接就绪 | ✅ tools 7/7、mock sha256 `ee2eeb10…`、server checkd-agent-mock 0.4.0 |
| 2 | 只读调用 | ✅ 4 条任务 + 1 门课程 + 1 个固定事件 |
| 3 | 生成方案 | ✅ 10 段 / 510 分钟 |
| 4 | 校验 | ✅ 无冲突无违规 |
| 5 | 确认环节 | ✅ approval_token (none)，含 Mock 演示声明 |
| 5a | 凭证下发 | ✅ 已遮蔽 |
| 6 | 写入 | ✅ `[PASS]`：READBACK_PENDING / retryable=true / applying / delta=0 |
| 7 | 回读 | ✅ 逐条一致 4/4、变化 0、`同键只回 IDEMPOTENCY_IN_PROGRESS` 如实展示 |
| 8 | 重复提交 | ✅ 同键拒绝 + 换键拒绝，均 delta=0 |
| fin | 收尾 | ✅ 「真实写入、真实审批、生产回读仍为 BLOCKED，待 A 轨补录」 |

## 四、旁白转写核对

- 转写全文：`narration-transcript.txt`（12 段，含时间轴）
- 必说句：镜 5「不涉及任何真实身份认证，也不构成真实用户授权」——**完整说出** ✅
- 禁语（写入成功/已写入数据库/闭环完成/已恢复/可上线）：**0 次** ✅（镜 6「系统没有返回成功」为否定句式，不算）
- 镜 7 如实表述：「该路径尚未恢复，不作已恢复表述」✅
- 备注：1:42.3 有一声语气词「呀」（镜 4→镜 5 过渡处），非禁语、非内容错误，如实记录

## 五、固定组合核对

- 代码 `7e1367c2`（mock sha256 `ee2eeb10defb6b59c820cd30bc5eee2e78a596f80a547c7a05b8ceb72a674490`，52,477 B）——片头横幅与镜 1 均印出
- 契约 `39f7f96559abac9d4bc59d5c560e6a706ec19946`（46,684 B）——片头横幅印出
- 驱动 `3ce0817` 版 `demo_driver.py`（sha256 `45af7bd1…bd4a7a`，33,593 B），录制未改动
- 预检报告：`docs/reviews/2026-11-03-b-track-v2-preflight-M3.md`（本地 64f7b4d）

## 六、交付物清单（本目录）

1. `b-track-20261103-v2-recording.mp4` — 91,046,570 B，SHA256 见上
2. `run.log` — 逐镜终端日志（11 次调用全量请求/响应/trace_id）
3. `keyframes/` — 33 张抽帧（每 6 秒一张）
4. `narration-track.mp3` — 音轨
5. `narration-transcript.txt` — 转写
6. `ACCEPTANCE-REPORT.md` — 本报告

## 七、结论

v2 录制完成，重录目的（trace_id 可见性）达成，逐镜结果与 v1 零差异，旁白禁语 0、必说句完整。**建议提交 M0 做最终验收。** v1（SHA256 `6dedbcb5…`）按 M0 要求原样保留于 v1 目录。
