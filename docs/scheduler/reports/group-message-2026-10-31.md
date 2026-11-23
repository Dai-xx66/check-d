# 群消息草稿：B（M2）第二轮增量复审结果

> 日期：2026-10-31　提交人：B（M2）　对象：@队长 @所有人
> 对应的完整论证：`docs/scheduler/reports/incremental-alignment-m2-2c48579-examples.md`
> commit `6d0a05f`　分支 `feat/m2-scheduler-basic`（PR #2）
>
> 说明：以下为可直接粘贴的正文，未夹带任何未经本机执行的结果。

## 正文（长版）

```
B（M2）增量复审已完成，以正式固定 SHA 为准，commit 6d0a05f 已推 PR #2。

1. SHA 已核实
   2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6 —— 它就是 feat/m0-api-contract 的 HEAD，
   已用 merge-base 验证。与我上一轮推断的相同，上一份报告不作废。

2. 本轮的增量不在 md，在多出来的那份 agent-api-v1.examples.json（20 个示例）
   同一 commit 内 diff 是 0 行，靠 diff 查不出来。这条我记成教训了：
   diff 为 0 只能说明文件内容没变，不能说明基准没变。
   已把差异助手扩到两份文件，并规定文件清单缺失时必须报"基准已失效"而不是静默通过。

3. 修掉一个我自己的缺陷（不是契约变了）
   契约 §5.6 的时长优先级第三级兜底写死是 max(minimum_block_minutes, 30) 分钟，
   我的 _durationOf 注释写着"目标 > 估算 > 兜底"，代码却返回 0 —— 等于静默丢弃该任务。
   前几轮我自称"时长优先级已对齐"时只冻结了前两级，而我的冻结目标文档里早就抄对了这一行，
   文档与代码脱节没人发现。现已补齐并加守卫：偏好 15 → 兜底 30；偏好 45 → 兜底 45，
   两者都标 scheduler_estimate。测试 30/30。
   反过来说这也是个可能越界的地方：若 M0 的用意是"第三级只该由服务端快照兜底、
   纯函数不该自己兜"，那就是我代做了服务端的活，请回一句我删掉。

4. 需要 M0 三个答复（都不是我能替他决定的）

   P2　explanations[].code 的封闭枚举。现在是三套零交集的词汇：
       md §5.7 只说"机器可读"，一个取值都没枚举；示例用了 PRESERVED_FIXED_EVENTS 和
       ESTIMATED_DURATION，这两个值在 md 全文出现 0 次；我自己又是另外 8 个码。
       枚举出来之前我不照抄示例 —— 那只是把"猜我的"换成"猜别人的"，不产生正确性。
       这条直接卡着 C 的"数据"判定项。

   P3　请补两个示例：remaining_minutes_today = 0（不排也不计未安排）和 = 40（折算后排 40 分钟）。
       这两个字段在示例文件里出现 0 次，没有任何示例演示它们的行为，C 拿不到构造用例的依据。

   P4　Proposal 的序列化职责归属，请明文写二选一：
       (a) Proposal 由服务端序列化，调度器输出只是构件；或 (b) 给进程内单列一个
       不含服务端字段的 DTO。示例里的完整 Proposal 含 snapshot_ref / input_digest /
       generated_at / expires_at 四个字段，而契约同时又规定这四项不得由模型构造 ——
       两边叠起来，调度器的输出结构上永远过不了完整 Proposal 的 Schema required。
       不写明的话，A 跑 Schema 校验会失败，且失败原因归不到任何人头上。

5. 给 C 的一条正面确认
   示例里 apply_approved_changes 成功的 applied_changes 逐字段复用提案的 change 形状，
   且是响应中唯一的写入汇总位置 —— "写入次数 = changes.length" 从此不只是我的静态推算，
   有契约示例佐证了，可直接用于写入次数判定。
   另外 EX19 的 READBACK_PENDING 只覆盖了"同幂等键回读"，没覆盖"换键"，
   我上轮提的 X1（applying/readback_pending 时换键的行为未定义）仍然空着，
   那还是唯一一条可能二次写入的通道。

6. 边界（避免误会）
   本轮只改了我自己的 schedule_engine.dart、test 与 docs/scheduler。
   没改 M0 契约本体，没重跑 M1 mock，没生成 tools.candidate.json，没碰他人文件。
   测试 30/30 是在隔离验证工程用 dart test 跑的；宿主 flutter test 因本机缺 Windows
   开发人员模式仍未复跑，我不替它声称通过。
   A 的 26/26 是 Mock 用例数，与我的 30/30 不是一个东西，汇报时不要合并。

仍未闭环的旧账照旧：input_digest 未含 horizon 与时区、状态机 R1 死锁。
本轮这两条无变化，不重复贴。
```

## 极简版（群里要求精简时用）

```
B（M2）增量复审完成，commit 6d0a05f 已推 PR #2。
· 固定 SHA 2c48579 已核实，就是契约分支 HEAD，上一份报告不作废。
· 本轮核对的是新增的第二份契约文件 examples.json —— 同一 commit 内 diff 为 0，
  靠 diff 查不出来，差异助手已扩到两份文件。
· 修掉一个我自己的缺陷：契约第三级兜底 max(minimum_block_minutes, 30)，
  我代码里写成了返回 0（静默丢弃任务）。已补齐，测试 30/30。
· 请 M0 答复三件事：① explanations[].code 的封闭枚举（现在三套词汇零交集，
  卡住 C 的数据判定）；② 补 remaining_minutes_today = 0 与 = 40 两个示例；
  ③ 明文 Proposal 的序列化职责归属。
· C 可直接用的一条：applied_changes 逐字段复用提案 change，
  "写入次数 = changes.length" 现在有契约示例佐证。
```
