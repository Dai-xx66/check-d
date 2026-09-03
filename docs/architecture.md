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
- 完成记录保存 local_date；时间分布按设备当前本地时区切分 Session。固定账号时区与跨时区迁移尚未实现，接入云同步时统一处理。
- 计时器以 started_at 和当前时间计算，不依赖 setInterval 的执行次数。
- Session 采用追加式记录，暂停或结束时固化 duration_seconds。
- TimerSession 只记录时间，TaskCompletion 只记录用户确认的完成状态。
- 目标时长进度和 `target_reached` 从 Session 聚合，不会自动写入任务完成。
- 周期任务和单次事项共用同一套计时状态机；计时模式可选择是否设置目标时长。
- v7 迁移保留已有完成历史，将旧执行模式统一为 timed/untimed；新旧记录都必须由用户手动确认完成。
- 当天投入时间汇总全部 Session，不受任务是否到期、是否执行或是否完成影响。
- 非执行日、节假日暂停日和用户暂停日不进入完成率分母。

## 同步规则

- 每次本地写入和 sync_queue 入队处于同一事务。
- 可追加历史优先追加；资料类数据使用 sync_version 与 updated_at 解决冲突。
- 删除同步为 archived 或 deleted_at，不直接清除远端历史。
- Realtime 只用于加快变更通知，不承担离线同步正确性。

## Phase 边界

Phase 1 建立可运行骨架、账号、本地数据库、服务端 schema 和同步基础设施。
Phase 2 已加入任务子类型、周期、点击打卡、修改历史和归档。
Phase 3 已加入可靠计时状态机、分段 Session、每日时长聚合、跨日拆分和实时进度。周期任务与单次事项均支持计时或不计时，计时目标可选。计时只在状态变化时持久化，运行中显示由 `started_at` 与当前时间推导；同一用户只允许一个 Session 处于 `running`。
Phase 4 已加入从任务周期、TaskCompletion 和 TimerSession 动态生成的月度日历快照。每日完成度只根据用户确认的完成状态计算，时间投入和目标达成单独展示；非执行日不产生任务实例，归档任务仅保留归档日期及以前的历史展示。

任务图案以稳定的语义键 `icon_name` 保存，UI 层负责映射到平台图标。这样同步数据不依赖 Flutter `IconData` 编码，也便于后续替换图标集。

## Phase 5 标签与统计

- v6 新增 TagRecords、TagRevisionRecords，以及 LocalTasks.tagId 和 TimerSessionRecords.tagId。旧记录保持不变，无标签的历史 Session 归入「其它」。
- 标签修改保留 ID，归档不删除引用，历史名称/颜色变更写入修订表。报表使用标签当前名称与颜色；任务改标签只影响此后开始或继续的新片段。
- StatisticsRepository 在只读事务内加载当前用户原始数据，StatisticsData 独立负责周期、跨日时间切分和完成率计算。统计页订阅数据库并实时更新运行中的计时。
- 每周从周一开始；日/周/月按天分桶，年按月分桶。已结束片段使用保存的 durationSeconds，跨日按时间交集分配，运行片段按时间戳计算。
- 周期任务完成率只计算截至今天的应执行日；TaskCompletion.exclusionReason 非空的日期排除。通过 TaskRevision 的前后快照恢复历史执行周期。归档/暂停从次日停止产生应执行记录。
- 当前连续天数在今天尚未完成时暂不打断，今天结束后才计失败；非执行日不打断。累计与最长天数始终是全历史指标，周期完成率是选中周期指标。
- 单次事项完成数量独立展示，按实际完成时间归属；单次计时无论是否到期/完成均计入时间分布。
- 法定节假日自动生成排除记录仍在 Phase 8；本阶段不猜测休假日期。云端新增迁移待配置 Supabase 后执行，同步队列仍为基础设施，不代表已完成跨设备同步。

## Phase 6 计划

- Drift v8 新增 PlanRecords 与 PlanTaskRecords；它们映射既有 Supabase `plans` 和 `plan_tasks` 结构，并通过同步队列记录本地变更。
- 计划可为月度或年度，保存名称、颜色、说明、起止日期与关联周期任务。计划归档使用 `deleted_at`，不删除关联任务或历史完成记录。
- 计划进度只统计计划日期内、截至今天的关联周期任务应执行日；TaskCompletion 的 `isSuccess` 为真才计入完成数。计时投入和目标达成不会绕过手动完成规则。
