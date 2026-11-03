# B（M2）第三轮 · 群消息草稿

> 用途：完成后发群里，可直接粘贴。长版 + 极简版。

## 长版

```
B（M2）第三轮增量修订完成，SHA d8a5ab9（回填 7a47dd9），已推 PR #2。

1. B19/G1/G2 —— 已锁死并加三态守卫用例
   remaining_minutes_today 三态：null=按完整目标排；0=不排、不进 unplanned、产出
   ALREADY_DONE_TODAY、不进兜底；正数=折算成当天剩余且标 task_target。
   40 分钟样例：完整目标 120 也只排 40；0 样例：不排不记。

2. input_digest —— horizon 一条可执行证据（digest 由服务端算，M2 恒不构造）
   只改 horizonEnd 输出就不同（1 块 vs 3 块），故 digest 必须含 horizon 起止。
   时区结论已撤回：契约固定 Asia/Shanghai、无区分度（C 指正），M2 不做时区转换。

3. Proposal 只出内部 DTO —— 加递归守卫，5 个服务端字段任意层级不出现。
   base_version 目前是"原样带回"，请 M0 回一句：回声保留还是也删。

4. B18 / R1 —— M2 无实现可改（已举证：10 个关键字逐一检索，命中全为枚举符号名和注释）。
   这两条是契约条文，需要 M1 mock 实现 + M0 落笔 §6.5/§6.7。
   我已给出可直接落笔的判定顺序：
   X1 换键 → 一律 READBACK_PENDING + 零写入；R1 Token 过期 → 旧审批终结、
   未终结集合={approval_pending, token_issued}、Proposal 未过期可建新 approval_id。

5. explanations 映射表已交付：explanations-code-map.md
   9 个实际码（7 公共 + 2 repair 专用）+ 已删的 NO_VALID_DURATION + 4 个 reason_code，
   全部标触发条件/是否对外/推荐公共码。

6. 测试（分开报告，不合并）
   隔离 dart test：38/38 通过。
   宿主 flutter test：本轮加载即失败（flutter_tester WebSocket），一行未执行，
   与上轮 sqlite3 502 不是同一原因，不记通过也不记失败。

待 M0：§6.5/§6.7 落笔 + base_version 回声确认 + 时区规范化。
```

## 极简版

```
B（M2）第三轮完成，SHA d8a5ab9。
B19/G1/G2 三态已锁死（0 不排、40 只排 40、都标 task_target，判据用 2400s）；digest 已给
horizon 证据（时区结论撤回）；Proposal 只出内部 DTO（5 个服务端字段递归守卫）。
B18/R1 举证 M2 无实现可改，判定顺序已给出，需 M1 mock 实现 + M0 落笔 §6.5/§6.7。
explanations 映射表已交付。隔离 38/38；宿主 flutter test 未执行（WebSocket，分开报告）。
```

## 发群建议

- 贴**长版**，末尾补一句：`@队长 @M0 待落笔 §6.5/§6.7 与 base_version 确认；@C 映射表供验收引用`。
- 如果群里只认极简，贴**极简版**即可，SHA 和两个待办是必须留住的。
- 不必再解释邮箱：GitHub 评论会自动推通知邮件到订阅者 QQ 邮箱（之前 PR #3 那条就是例子）。
