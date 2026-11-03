# M1 `1baf95d` 块间重叠复核（M3）

- 复核人：M3 钟钰芬（C）
- 时间：2026-11-03 12:0x
- 被测 HEAD：`1baf95d0b353139315dfdb5b6b96cf36ae05113b`（PR #3，Open 未合并）
- 父提交：`a343f3089`（本轮只动 `tool_server.py` 与 `test_block_overlap.py`）
- `tool_server.py` sha256：`b01387ef7b57f2c45a89998dbb76cd98a30db8449485023c14aaa5de48603f5f`
  上一版 `a343f30` 为 `1366dcb8bcc32d6cbe71be0b92f105f274c4e1d3798277c2714eb8d15dcd6167` → 服务端确实改了，不是只改测试。
- 契约基准：`docs/contracts/agent-api-v1.md` @ `c9dda83`（`feat/m0-api-contract` 分支 head）

## 一、M0 11:55 五项清单逐项结论

| # | 要求 | 实测 | 结论 |
|---|---|---|---|
| 1 | 正常生成 10 块、块间重叠 0 | 10 块 / 510 分钟；重叠 0 对；`unplanned_tasks=[]` | PASS |
| 2 | 注入重叠 → `validation_status=invalid` + `violations[].code=BLOCK_OVERLAP` | `status=success`、`validation_status=invalid`、codes=`['BLOCK_OVERLAP']` | PASS |
| 3 | `related_block_ids` 指向双方 | `['b_0001','b_0021']`，与自算重叠对完全一致；另带 `message` 与 `related_task_ids` | PASS |
| 4 | 固定事件冲突仍报 `FIXED_EVENT_CONFLICT` | 单块压固定事件 → 仅 `FIXED_EVENT_CONFLICT`；两块重叠且压固定事件 → `['BLOCK_OVERLAP','FIXED_EVENT_CONFLICT']` 两条都在 | PASS |
| 5 | 闸门 G0–G6 与 35 条证据不回退 | `GATE_EXIT=0`（7/7）；证据 35 条，契约冲突 0 / A 类 0 / B 类 0 / 需说明 1（EX-01 沿用）；核验器 9 项反例自检 9/9 | PASS |
| 6 | 远端文件与 M1 自述 SHA256 一致 | 远端 raw @1baf95d / M1 自述 / 本地解包三方逐字节相同：`tool_server.py` `b01387ef7b57f2c4…`、`test_block_overlap.py` `1b213d53dc3bd2ab…` | PASS |

三项状态字段（M0 04:02 复核清单外的补充核对，与 M1 自述一致）：

| 路径 | validation_status | approval_status | proposal_status | violations |
|---|---|---|---|---|
| 正常提案 | `valid` | `pending_approval` | `pending_approval` | 0 条 |
| 注入重叠 | `invalid` | `not_approvable` | `draft` | 1 条 `BLOCK_OVERLAP` |

## 二、逐块时间（正常路径，用于录制镜头 3 对画面）

```
b_0001 t_1001  10-29 09:40→11:10     b_0013 t_1004  10-29 12:40→13:40
b_0003 t_1002  10-29 11:10→12:10     b_0015 t_1004  10-30 08:30→09:30
b_0005 t_1003  10-29 12:10→12:40     b_0017 t_1004  10-31 08:30→09:30
b_0007 t_1003  10-30 08:00→08:30     b_0019 t_1004  11-01 08:30→09:30
b_0009 t_1003  10-31 08:00→08:30
b_0011 t_1003  11-01 08:00→08:30
```

10-29 四块首尾相接，无同起点堆积（修复前四块同起点 09:40、重叠 9 对）。

## 三、顺序回归（我此前担心的点，已排除）

`check_hard_constraints()` 把块间检测放在 violations 列表最前，但仍**追加后继续**原有循环，没有 `raise`/`return`。
构造「b_1 09:00–10:30、b_2 10:00–11:00、固定事件 09:30–09:45」：
`codes=['BLOCK_OVERLAP','FIXED_EVENT_CONFLICT']` → 两条共存，块 vs 块只报一条，未被新码盖掉。

因此先前提醒的「插在固定事件检查前会碰坏 T1.4」在本实现下不成立；T1.4 是单块 vs 固定事件，块间检测不参与。

## 四、8 镜全链（`0 1 2 3 3u 4 5 5a 5x 6 7 8 fin`）

- 全程 0 异常、进程正常退出（`FULL_EXIT=0`）；
- 镜头 3：10 块 / 510 分钟，`t_1001 09:40→11:10`、`t_1002 11:10→12:10`、`t_1003 12:10→12:40`，无重叠；
- 镜头 3u：压窄窗口 → 2 条 `NO_AVAILABILITY`（缺 30 / 60 分钟），不硬塞；
- 镜头 4：`validation_status=valid` / `violations` 0 条（这次 0 是真的）；
- 镜头 5/5a/5x：审批 pending → 外部批准发一次性 Token → 取消路径 `APPROVAL_REJECTED` 且写入增量 0；
- 镜头 6/7：`READBACK_PENDING` / `applying`；回读逐条一致 4/4、变化 0 条、服务端写入计数 0，如实说「这条路径没有完成收敛」；
- 镜头 8：同键 `IDEMPOTENCY_IN_PROGRESS`、换新键仍 `READBACK_PENDING`、`business_write_count_delta=0` 三道闸齐；
- 每镜均打 `[MOCK · 非真实写入]` 角标。

## 五、一处残留：契约本体还没补码（属 M0 范围，不是 M1 的返工项）

M1 已按裁定 A 输出 `BLOCK_OVERLAP`，但契约 `@ c9dda83` 的 §5.8 公开闭集仍是 7 值，**不含** `BLOCK_OVERLAP`，
且同节规定「未知 code 必须以 `PROPOSAL_INVALID` 拒绝、不得作为扩展解释透传」。

实测核对：`feat/m0-api-contract` head = `c9dda83195a9af4b9ca762d8556fdd0e8d43010a`，
`docs/contracts/agent-api-v1.md` sha256 前 16 位 `dd70432acb218c88`，全文 `BLOCK_OVERLAP` 出现次数 = 0。

因此严格讲：**代码侧符合裁定 A 的形态，契约侧尚未生效**。这一条不阻塞 8 镜录制（镜头 4 走正常提案，不含该码），
但决定「交付 HEAD 是否为契约最终形态」。需要 M0 在 §5.8 加一行并给出新 SHA；我把 `--contract` 指过去复跑一次即可。

我这侧的处理：`verify_m1_evidence.py` 已按裁定把 `BLOCK_OVERLAP` 加入非错误码白名单（提交 `ad17fc6`）；
这是**本地放行**，不等于契约已改，报告中如实标注。

## 六、边界

- 注入路径由 mock 测试开关 `MOCK_TEST_FLAGS` 驱动（`inject_overlapping_blocks`），非契约工具参数；
  它只用于证明「拒绝形态」，8 镜画面不经过它。
- 以上均为 Mock 行为，不构成真实端点、真实审批、生产回读的证据。
- A 轨、第二账号继续 BLOCKED；PR #3 保持 Open，不评论合并。

## 七、复现命令

```bash
# 独立探针（自算重叠、自定期望值，不复用 M1 断言）
python tools/m3-checks/probe_block_overlap_1baf95d.py <path>/tools/m1-mock/tool_server.py

# 闸门
python tools/m3-checks/assert_brail_contract.py <path>/tools/m1-mock/tool_server.py   # GATE_EXIT=0

# 证据（契约动态读取）
python tools/m3-checks/verify_m1_evidence.py \
  --evidence <path>/docs/contracts/reviews/m1-evidence-c9dda83.json --contract c9dda83

# 8 镜全链
printf '0\n1\n2\n3\n3u\n4\n5\n5a\n5x\n6\n7\n8\nfin\nq\n' | \
  python tools/m3-checks/demo_driver.py --mock <path>/tools/m1-mock/tool_server.py
```

## 八、追加复核：`7e1367c2`（按 M0 第 5 点收敛检测顺序）

M1 于 12:04 推送 `7e1367c2e22f03cebc29770b44a87c6f0c71066e`（PR #3 head，父 `1baf95d0`），
只做一件事：把块间重叠循环整体移到「块时间合法性 + 块 vs 固定事件」之后，并新增 T1.5 混合场景。
**本版取代 1baf95d 成为录制候选 HEAD。**

文件自证：`tool_server.py` `ee2eeb10defb6b59…`、`test_block_overlap.py` `95ea739720f0182f…`，
远端 raw 与 M1 自述一致。

| 项 | 实测（7e1367c2） | 结论 |
|---|---|---|
| 正常生成 | 10 块 / 510 分钟，重叠 0 对，`unplanned=[]`，10-29 四块首尾相接 09:40→13:40 | PASS |
| 正常校验 | `valid` / `violations=[]` | PASS |
| 注入重叠 | `success` envelope、`invalid`、1 条 `BLOCK_OVERLAP`、`related_block_ids=['b_0001','b_0021']`、`related_task_ids=['t_1001']` | PASS |
| 码序（M0 第 5 点） | 混合场景 `codes=['FIXED_EVENT_CONFLICT','BLOCK_OVERLAP']`——固定事件在前，未被新码抢占 | PASS |
| 单块 vs 固定事件 | 仅 `FIXED_EVENT_CONFLICT`，不误报 `BLOCK_OVERLAP` | PASS |
| 闸门 | G0–G6 7/7，`GATE_EXIT=0` | PASS |
| 证据 | 35 条，契约冲突 0 / A 0 / B 0 / 需说明 1（EX-01 沿用），`VERIFY_EXIT=0` | PASS |
| 8 镜全链 | `0 1 2 3 3u 4 5 5a 5x 6 7 8 fin` 全程 0 异常；镜头 3 无重叠、镜头 4 `valid`/0、镜头 6 写入 delta 0 | PASS |
| M1 自测 | `test_block_overlap.py` 11/11（T1.1–1.5、T2.1–2.6），exit 0 | PASS |

我的独立探针 `probe_block_overlap_1baf95d.py` 在本版 16/16 通过（同一脚本，未为适配新版本改断言）。

**结论：代码侧已可作录制 HEAD。** 契约 §5.8 仍未补 `BLOCK_OVERLAP`（`c9dda83`），
按 M0 04:02 口径，最终以「代码 SHA + 契约 SHA 两者一致」为准；M0 给出新契约 SHA 后，
我用 `--contract` 指过去复跑一次即闭合，不重跑 8 镜。

## 九、附注：M1 推送路径的 CRLF 分叉（不影响本报告结论）

M1 于 04:13Z 主动撤回了他上一封"本地 3d90bf8 内容等同 7e1367c2"的说法，
并给出可核验口径。我逐条实核（拉远端 raw 自行数 `\r\n`）：

| 声明 | 实测 | 结论 |
|---|---|---|
| 远端 tree = `08a1917bb443f75e…` | 一致 | PASS |
| 文件数 388 | 一致 | PASS |
| 15 个 blob 仅行尾不同，清单完整 | 15 个全部含 CRLF（52 / 15 / 97 / 134 / 352 / 47 / 553 / 52 / 1142 / 62 / 87 / 16 / 390 / 652 / 478） | PASS |
| `.gitignore` 703B − 52 = 651B（本地） | 差 0 | PASS |
| `run_evidence_c53.py` 30685B − 652 = 30033B（本地） | 差 0 | PASS |

一处未圆上的口径（已回信请其收敛）：远端 `tool_server.py` 含 **1156 个 CRLF**，
与"该文件本地 blob 与远端 blob 完全相同"及"提交时归一为 LF、上传的是工作区 CRLF"
这两句话只能成立一个。不影响本报告判定——本报告全部结论用的是**远端字节**
（GitHub tarball / raw），`tool_server.py` sha256 `ee2eeb10defb6b59…` 即远端真值。

本侧同源核查：M3 分支远端 head 与本地 HEAD 同为 `964b9bc930afd26d…`，
逐字相同，故本报告及此前记录中的 SHA 均可直接作远端 SHA 引用。
原因是 `push_via_api5.py` L74 用 `git cat-file blob HEAD:<path>` 取提交内 blob，
不读工作区磁盘字节。
