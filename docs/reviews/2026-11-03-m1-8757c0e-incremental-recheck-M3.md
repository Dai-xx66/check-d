# M1 增量三验：PR #3 `8757c0e`（M3）

- 核验时间：2026-11-03
- 对象：`8757c0e5542f9c11b73f6933bf2683ca01082334`（PR #3 head，Open 未合并）
- 触发：M0 2026-11-03 11:26 邮件（EX-15/17/18 计数器 + 生成器 `bool()` 保真）；M1 同日 11:35 交付
- 上一轮：`c5818ee` → 契约冲突 0 / A 类 0 / B 类 3（EX-15、EX-17、EX-18）

## 一、结论

**两项均已闭合，三验通过，exit 0。**

```
证据文件: docs/contracts/reviews/m1-evidence-c9dda83.json
契约基准: c9dda83（21 个错误码）
结果条目: 35（core 15 + examples 20）
自述通过: 35 / 35
契约冲突: 0
未测 A（READBACK_* 缺必填 raw 字段）: 0
未测 B（零写入类缺计数器）: 0
需说明: 1  （EX-01 fixture 差异，沿用，非新增）
VERIFY_EXIT=0
```

核验器先跑 9 项反例自检（删 `raw` 留文本、`retryable="false"`、`retryable=1`、
`writes_delta="0"`、`writes_delta=2`、非法 `proposal_status` 等）全部按预期判负，
确认核验器本身没有被「改绿」——反例 9 项失败 0 项。

## 二、三验逐条

| 用例 | 错误码 | `raw.writes_delta` | 其他计数器 | 类型 |
|---|---|---|---|---|
| EX-15 | ALREADY_APPLIED | `0` | `first_apply_writes_delta: 8` | int / int |
| EX-17 | APPROVAL_CONSUMED | `0` | `first_apply_writes_delta: 0` | int / int |
| EX-18 | APPROVAL_EXPIRED | `0` | `retryable: false` | int / **bool** |

- 三处 `writes_delta` 均为 JSON 整数，非字符串、非 bool；`EX-18.retryable` 为 JSON 布尔 `false`。
- 取数方式可核：`run_evidence_c53.py` 中 `ex_already_applied` / `ex_consumed` / `ex_token_expired`
  各自在调用前后读 `writes()` 计数器取差，差值直接写进 `raw`，不经文本或 `pass` 标志。

## 三、生成器 `bool()` 保真

`grep -n "bool(" tools/m1-mock/run_evidence_c53.py` 现只剩 `strict_bool` 自身的定义与调用，
无任何强制转换。实现属实：

```python
def strict_bool(value, where):
    if not isinstance(value, bool):
        raise SystemExit("证据生成失败：%s 应为 bool，实际是 %s(%r)；拒绝强制转换。"
                         % (where, type(value).__name__, value))
    return value
```

替换点核对：`raw_of`(L88)、T1(L290)、T2.step2(L306)、T3.step1(L325)、T3.step2(L330)、EX-18(L598)，
与 M1 邮件自述一致。（M0 邮件里的 L88/282/298/317/322 是 `c5818ee` 的行号，行号随插入代码位移，属正常。）

## 四、B 轨闸门复跑（`8757c0e`）

```
[PASS] G0 四条 READBACK_PENDING 的 details 均非空
[PASS] G1 details 使用 proposal_status 字段名
[PASS] G2 applying 路径 proposal_status = applying
[PASS] G3 readback_pending 路径 proposal_status = readback_pending
[PASS] G4 四条 READBACK_PENDING 的 retryable 均为 true
[PASS] G5 写前路径含 business_write_count_delta=0
[PASS] G6 写前路径服务端写入增量 = 0
结论：7/7 通过 → GATE_EXIT=0
```

`tool_server.py` sha256 前 16 位 `0ff37fe2940cdfe3`，与 `e7dd43b1d` 字节相同 —— 本轮只动生成器与证据，
没碰服务端，所以闸门结果与上轮一致；同时也意味着 **D4-B1 的 P1 块间重叠仍未修**（见
`2026-11-03-d4-b1-mock-block-overlap-M3.md` §8）。

## 五、一条观察（不要求返工）

EX-17 是 `first_apply_writes_delta: 0` → `writes_delta: 0`。这条 0→0 只能证明**第二次调用零写入**，
区分不了「被 `APPROVAL_CONSUMED` 拦住」和「这条路径本来就不写」。结论没错，但计数器的信息量偏低；
真正承担区分的是 `code=APPROVAL_CONSUMED` 本身。若想让计数器更有判别力，可加一条
「先成功 apply 一次（写 8 条），再用同一 token 换新键」的变体，把 8→0 锁住。属可选增强。

## 六、边界

- 只核「记录是否足以支撑其结论」，不重跑 M1 的 mock 全量用例；不采信其 `pass` 标志。
- B 轨 Mock 结论，与 A 轨真实端点、真实审批、生产回读无关。
- 本文件不构成对 PR #3 的合并意见；PR #3 保持 Open。

---

编制：钟钰芬（C / M3）｜2026-11-03
