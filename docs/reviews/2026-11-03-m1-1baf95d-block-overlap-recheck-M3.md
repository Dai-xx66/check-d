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
