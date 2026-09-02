# Check D 架构基线

## 原则

- Flutter 单代码库支持 iOS、Android、macOS 和 Windows。
- 界面只通过 application/controller 层访问 repository，不直接查询云数据库。
- Drift SQLite 是客户端主要数据源，写操作先落本地，再进入同步队列。
- Supabase PostgreSQL 保存跨设备数据，所有用户业务表启用 RLS。
- 统计尽量从 TaskCompletion 和 TimerSession 等原始记录计算。
- 任务归档和软删除替代物理删除，保留历史统计能力。

## 客户端数据流

```text
Widget
  -> Riverpod controller
  -> Repository
  -> Drift transaction
  -> Sync queue
  -> Supabase
```

云端变更由同步服务拉取并写回 Drift，Widget 只订阅本地数据库的数据流。

## 时间规则

- 时间戳使用 UTC 保存。
- 每日统计同时保存用户时区和 local_date，避免跨时区后历史归属改变。
- 计时器以 started_at 和当前时间计算，不依赖 setInterval 的执行次数。
- Session 采用追加式记录，暂停或结束时固化 duration_seconds。
- 非执行日、节假日暂停日和用户暂停日不进入完成率分母。

## 同步规则

- 每次本地写入和 sync_queue 入队处于同一事务。
- 可追加历史优先追加；资料类数据使用 sync_version 与 updated_at 解决冲突。
- 删除同步为 archived 或 deleted_at，不直接清除远端历史。
- Realtime 只用于加快变更通知，不承担离线同步正确性。

## Phase 边界

Phase 1 建立可运行骨架、账号、本地数据库、服务端 schema 和同步基础设施。
Phase 2 已加入任务子类型、周期、点击打卡、修改历史和归档。
Phase 3 已加入可靠计时状态机、分段 Session、每日时长聚合、跨日拆分和实时进度。计时只在状态变化时持久化，运行中显示由 `started_at` 与当前时间推导；同一用户只允许一个 Session 处于 `running`。
