/// M2 智能调度在确定提案阶段使用的数据结构。
///
/// 这里是纯粹的提案形状（DTO），不是数据库表，也不对应任何 Drift 实体。
/// M0 负责把真实的 Task / Course / Calendar / 单日例外映射成这里的结构，
/// 本模块只负责计算。
///
/// 团队 Global Constraints 在本模块中的落点：
/// - Course 与会议属于硬约束，[ScheduleFixedBlock] 永远不可被移动。
/// - 日期型截止与精确截止分别建模（[ScheduleDeadline]），
///   绝不为「只有日期」的截止伪造一个 23:59 的时刻。
/// - [ProposedBlock] 只表示未来安排的建议，永远不是 TimerSession 事实，
///   也不代表手动完成。
/// - 引擎不得读取当前时间，所有时间基准来自 [ScheduleInput.now]，
///   这保证相同输入必然得到相同输出。
library;

/// 硬约束的来源类型。
enum ScheduleOwnerType {
  /// 课程。课程只是日程状态，不参与打卡，也不进入专注时长。
  course,

  /// 外部固定事件，例如突发会议。对应契约中的 `external_fixed_event`。
  event,
}

/// [ScheduleOwnerType] 的契约编码。
extension ScheduleOwnerTypeCode on ScheduleOwnerType {
  String get code => switch (this) {
    ScheduleOwnerType.course => 'course',
    ScheduleOwnerType.event => 'external_fixed_event',
  };
}

/// 任务类型，取值与契约 `task_kind` 一致。
enum ScheduleTaskKind {
  /// 周期任务
  recurring,

  /// 单次事项
  oneTime,
}

/// [ScheduleTaskKind] 的契约编码。
extension ScheduleTaskKindCode on ScheduleTaskKind {
  String get code => switch (this) {
    ScheduleTaskKind.recurring => 'recurring',
    ScheduleTaskKind.oneTime => 'one_time',
  };
}

/// 提案状态机，取值与契约 `schedule_proposal.status` 一致。
///
/// 方案 A（c53b1a9 起）：`status` 是**服务端权威字段**，M2 纯调度函数不产出、
/// 不序列化它。这里保留枚举只是作为契约状态机的进程内参照（例如给服务端包装层
/// 或验收矩阵对齐状态名），[ScheduleProposal] 本身不再携带 `status`。
enum ScheduleProposalStatus {
  draft,
  pendingApproval,
  applying,
  readbackPending,
  applied,
  rejected,
  expired,
  failed,
}

extension ScheduleProposalStatusCode on ScheduleProposalStatus {
  String get code => switch (this) {
    ScheduleProposalStatus.draft => 'draft',
    ScheduleProposalStatus.pendingApproval => 'pending_approval',
    ScheduleProposalStatus.applying => 'applying',
    ScheduleProposalStatus.readbackPending => 'readback_pending',
    ScheduleProposalStatus.applied => 'applied',
    ScheduleProposalStatus.rejected => 'rejected',
    ScheduleProposalStatus.expired => 'expired',
    ScheduleProposalStatus.failed => 'failed',
  };
}

/// 调度偏好。对应契约 `generate_schedule.input.preferences`。
///
/// 偏好只能约束纯粹属于用户意愿的部分，**永远不能覆盖硬约束**。
class SchedulePreferences {
  const SchedulePreferences({
    this.dayStartMinute = 8 * 60,
    this.dayEndMinute = 22 * 60,
    this.minimumBlockMinutes = 15,
  });

  /// 每天允许排程的最早分钟数，0..1439。
  final int dayStartMinute;

  /// 每天允许排程的最晚分钟数，1..1440，必须晚于开始。
  final int dayEndMinute;

  /// 少于该长度的碎片不再参与排程。
  final int minimumBlockMinutes;
}

/// 截止时间的契约联合类型。
///
/// `date_only` 只能带 `date`，`exact` 只能带 `at`，
/// 与契约第 3.1 节完全一致。
extension ScheduleDeadlineJson on ScheduleDeadline {
  Map<String, dynamic> toJson() => isDateOnly
      ? {
          'kind': 'date_only',
          'date': _isoDate(dueDateOn!),
        }
      : {
          'kind': 'exact',
          'at': dueAt!.toIso8601String(),
        };
}

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// 任务没能被排进去的机器可读原因。
///
/// C 的验收表和 A 的差异文案都依赖这个枚举，不能退化成一句中文描述。
enum UnplannedReason {
  /// 找不到足够长的连续空闲窗口。
  windowInsufficient,

  /// 截止时间已过。
  pastDeadline,

  /// 可用区间被硬约束占满。
  overlapsFixed,

  /// 输入没有给出任何可用窗口。
  noAvailability,
}

/// [UnplannedReason] 的 JSON 编码，供 M0 v1 契约使用。
extension UnplannedReasonCode on UnplannedReason {
  String get code => switch (this) {
    UnplannedReason.windowInsufficient => 'WINDOW_INSUFFICIENT',
    UnplannedReason.pastDeadline => 'PAST_DEADLINE',
    UnplannedReason.overlapsFixed => 'OVERLAPS_FIXED',
    UnplannedReason.noAvailability => 'NO_AVAILABILITY',
  };
}

DateTime scheduleDayOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// 一段连续时间区间的公共形状。
class ScheduleWindow {
  const ScheduleWindow({required this.startAt, required this.endAt});

  final DateTime startAt;
  final DateTime endAt;

  bool contains(DateTime instant) =>
      !instant.isBefore(startAt) && instant.isBefore(endAt);

  bool overlaps(ScheduleWindow other) =>
      startAt.isBefore(other.endAt) && other.startAt.isBefore(endAt);

  Duration get duration => endAt.difference(startAt);

  bool get isEmpty => !endAt.isAfter(startAt);
}

/// 截止时间。
///
/// 两种形态互斥，语义与 `TaskTimeSemantics` / `TaskDeadline` 保持一致：
/// - [dateOnly]：只到某一天，那一天结束前都算没有逾期。
/// - [exact]：精确到某个时刻，过点即为逾期。
class ScheduleDeadline {
  const ScheduleDeadline._({this.dueDateOn, this.dueAt})
    : assert((dueDateOn == null) != (dueAt == null));

  factory ScheduleDeadline.dateOnly(DateTime day) =>
      ScheduleDeadline._(dueDateOn: scheduleDayOnly(day));

  factory ScheduleDeadline.exact(DateTime instant) =>
      ScheduleDeadline._(dueAt: instant);

  final DateTime? dueDateOn;
  final DateTime? dueAt;

  bool get isDateOnly => dueDateOn != null;
  bool get hasTime => dueAt != null;

  /// 排程意义上的最晚结束时刻。
  ///
  /// 日期型截止的含义是「当天结束前都算赶上」，
  /// 所以最晚可以排到当天最后一刻；这不等于宣称它的截止时刻被记录为 23:59。
  DateTime get latestEndAt {
    final exact = dueAt;
    if (exact != null) return exact;
    return scheduleDayOnly(dueDateOn!)
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
  }

  /// 是否已在 [now] 过期。
  ///
  /// 日期型：过了那一天才算逾期。
  /// 精确型：到达该时刻即逾期（`now == dueAt` 时截止已经生效）。
  bool isPast(DateTime now) {
    if (isDateOnly) {
      return scheduleDayOnly(now).isAfter(scheduleDayOnly(dueDateOn!));
    }
    return !now.toUtc().isBefore(dueAt!.toUtc());
  }
}

/// 不可移动的占用区间：课程或会议。
class ScheduleFixedBlock {
  const ScheduleFixedBlock({
    required this.ownerId,
    required this.ownerType,
    required this.startAt,
    required this.endAt,
    this.title,
  });

  final String ownerId;
  final ScheduleOwnerType ownerType;
  final DateTime startAt;
  final DateTime endAt;
  final String? title;

  ScheduleWindow get window => ScheduleWindow(startAt: startAt, endAt: endAt);
}

/// 一条待排的任务需求。
///
/// 由 M0 从周期任务或单次事项映射而来；本模块不区分二者，
/// 只用 [requiredMinutes] 与截止条件来决定怎么排。
class ScheduleTaskDemand {
  const ScheduleTaskDemand({
    required this.taskId,
    required this.title,
    required this.requiredMinutes,
    this.taskKind = ScheduleTaskKind.recurring,
    this.deadline,
    this.earliestStartAt,
    this.priority = 0,
    this.targetDurationSeconds,
    this.remainingMinutesToday,
  });

  final String taskId;
  final String title;

  /// 服务端**可信快照**给出的估算分钟数，是契约时长优先级的第二级。
  ///
  /// 这个值只能由服务端包装层从一致性快照折算后填入，**不接受 LLM 直接提供的
  /// 伪可信估算**（M0 2026-10-31 决定）。它是进程内 DTO 字段，
  /// **不是** `generate_schedule` 远程请求参数。
  final int requiredMinutes;

  /// 周期任务与单次事项分别建模，它决定区块最终能怎么持久化。
  final ScheduleTaskKind taskKind;

  /// 为空表示没有截止限制。
  final ScheduleDeadline? deadline;

  /// 早于该时刻不可开始，通常由 `availableFrom` 映射而来。
  final DateTime? earliestStartAt;

  /// 数值越大越优先，仅在截止条件相同时参与排序。
  final int priority;

  /// 任务自带时长目标。只有传入它，`duration_source` 才是 `task_target`；
  /// 否则调度器给出的是估算，不得被描述成任务固有属性。
  final int? targetDurationSeconds;

  /// 当天剩余待做量（分钟），对应契约 `remaining_minutes_today`。
  ///
  /// **只属于服务端可信调度快照**，是进程内 DTO 字段，
  /// **不得作为 `generate_schedule` 的 LLM 远程请求参数**（M0 2026-10-31 决定）。
  ///
  /// 仅对周期任务有意义，且只能由服务端可信快照给出：
  /// `= 0` 是特殊情况，**不走时长兜底**（兜底只补给"没有任何时长依据"的任务，
  /// 而这里恰恰是"已经做完"）。
  /// - 非空且 > 0：本次就排这么多，优先于 [targetDurationSeconds]；
  /// - 等于 0：当天不再排程（已做完），不生成 block，
  ///   也不进入 `unplanned_tasks`——未安排不等于完成，这里恰恰是完成；
  /// - 为空：按完整的 [targetDurationSeconds] 排。
  final int? remainingMinutesToday;
}

/// 上一版提案中已存在的柔性安排。
///
/// [repairSchedule] 用它来判断哪些块可以被保留，从而实现最小扰动。
class SchedulePlacement {
  const SchedulePlacement({
    required this.taskId,
    required this.startAt,
    required this.endAt,
  });

  final String taskId;
  final DateTime startAt;
  final DateTime endAt;

  int get minutes => endAt.difference(startAt).inMinutes;
}

/// 排程输入。
///
/// [now] 必须显式传入，引擎内部不允许自行读取系统时间。
class ScheduleInput {
  const ScheduleInput({
    required this.now,
    required this.horizonStart,
    required this.horizonEnd,
    required this.baseVersion,
    this.timezone = 'Asia/Shanghai',
    this.preferences = const SchedulePreferences(),
    this.availability = const [],
    this.fixedBlocks = const [],
    this.demands = const [],
    this.existingPlacements = const [],
  });

  /// 排程基准时刻：任何块都不能排在它之前。
  final DateTime now;

  final DateTime horizonStart;
  final DateTime horizonEnd;

  /// 提案所依据的数据版本，用于承接 M0 的版本校验。
  ///
  /// 生产环境的 `base_version` 必须由可信服务产生，
  /// 进程内调用传入的值只用于测试，不得被当作可信版本使用。
  final String baseVersion;

  final String timezone;

  /// 每天允许排程的时间段等纯偏好。不能覆盖硬约束。
  final SchedulePreferences preferences;

  /// 用户允许被排程的时间窗口。
  ///
  /// 为空时会退化为由 [preferences] 的 `dayStartMinute` / `dayEndMinute` 推导。
  final List<ScheduleWindow> availability;

  /// 硬约束：课程与会议。
  final List<ScheduleFixedBlock> fixedBlocks;

  final List<ScheduleTaskDemand> demands;

  final List<SchedulePlacement> existingPlacements;
}

/// 提案中的一块展示用安排。未被批准前它只是建议。
///
/// 对应契约第 5.6 节的 `schedule_block`。它**只是提案 DTO**，
/// 不代表数据库里存在 ScheduleBlock 表，也不是持久化的目标形状。
/// 真正能落库的形态见 [ScheduleOneTimeChange] 与 [UpsertDailyOverrideChange]。
class ProposedBlock {
  const ProposedBlock({
    required this.taskId,
    required this.title,
    required this.startAt,
    required this.endAt,
    this.taskKind = ScheduleTaskKind.recurring,
    this.movedFromPreviousPlan = false,
    this.hasDurationTarget = false,
  });

  final String taskId;
  final String title;
  final DateTime startAt;
  final DateTime endAt;

  /// 周期任务或单次事项。它决定本块最终用哪种 change 持久化。
  final ScheduleTaskKind taskKind;

  /// 相对上一版提案是否被重排过，供 A 展示差异时使用。
  final bool movedFromPreviousPlan;

  /// 时长是否来自任务自身的 `duration_target_seconds`。
  final bool hasDurationTarget;

  int get minutes => endAt.difference(startAt).inMinutes;

  int get durationSeconds => endAt.difference(startAt).inSeconds;

  ScheduleWindow get window => ScheduleWindow(startAt: startAt, endAt: endAt);

  /// 提案内部 ID，不是数据库 ID。同一任务在一个提案中最多一块，故用任务 ID 派生。
  String get blockId => 'blk-$taskId';

  /// 契约固定值。
  String get source => 'proposal';

  /// 本块能怎么落库：单次事项走 `one_time_schedule`，周期任务走 `daily_override`。
  String get persistableAs => taskKind == ScheduleTaskKind.oneTime
      ? 'one_time_schedule'
      : 'daily_override';

  /// 时长是任务自带目标还是调度估算。估算不得被写回或描述成任务固有属性。
  String get durationSource =>
      hasDurationTarget ? 'task_target' : 'scheduler_estimate';

  Map<String, dynamic> toJson() => {
    'block_id': blockId,
    'task_id': taskId,
    'task_kind': taskKind.code,
    'start_at': startAt.toIso8601String(),
    'end_at': endAt.toIso8601String(),
    'source': source,
    'persistable_as': persistableAs,
    'duration_source': durationSource,
    'duration_seconds': durationSeconds,
  };
}

/// 白名单变更的共同形状：永远带 `change_id` 与 `type`。
abstract class ProposedScheduleChange {
  const ProposedScheduleChange();

  String get changeId;
  String get type;
  Map<String, dynamic> toJson();
}

/// 设置单次事项的唯一计划日期，并可设置同日的具体时间。
///
/// 契约约束：Task 必须是 `one_time`，具体时间必须与计划日期同日，
/// 一个提案中同一 Task 最多一条。
class ScheduleOneTimeChange extends ProposedScheduleChange {
  const ScheduleOneTimeChange({
    required this.changeId,
    required this.taskId,
    required this.plannedDate,
    this.scheduledAt,
  });

  @override
  final String changeId;

  final String taskId;
  final DateTime plannedDate;
  final DateTime? scheduledAt;

  @override
  String get type => 'schedule_one_time';

  @override
  Map<String, dynamic> toJson() => {
    'change_id': changeId,
    'type': type,
    'task_id': taskId,
    'planned_date': _isoDate(plannedDate),
    if (scheduledAt != null) 'scheduled_at': scheduledAt!.toIso8601String(),
  };
}

/// 为一个周期任务或单次事项在单个日期写入 `reschedule` 例外及分钟范围。
///
/// 契约 v1 暂定只允许 `reschedule`，不得用它修改课程规则或长期周期规则。
class UpsertDailyOverrideChange extends ProposedScheduleChange {
  const UpsertDailyOverrideChange({
    required this.changeId,
    required this.itemKind,
    required this.itemId,
    required this.localDate,
    required this.plannedStartMinute,
    required this.plannedEndMinute,
    this.existingOverrideId,
  });

  @override
  final String changeId;

  final ScheduleTaskKind itemKind;
  final String itemId;
  final DateTime localDate;
  final int plannedStartMinute;
  final int plannedEndMinute;

  /// 只能由可信读取服务提供，模型不得猜测。
  final String? existingOverrideId;

  @override
  String get type => 'upsert_daily_override';

  String get action => 'reschedule';

  @override
  Map<String, dynamic> toJson() => {
    'change_id': changeId,
    'type': type,
    'item_type': itemKind.code,
    'item_id': itemId,
    'local_date': _isoDate(localDate),
    'action': action,
    'planned_start_minute': plannedStartMinute,
    'planned_end_minute': plannedEndMinute,
    if (existingOverrideId != null) 'existing_override_id': existingOverrideId,
  };
}

/// 没能排进去的任务及其原因。
class UnplannedTask {
  const UnplannedTask({
    required this.taskId,
    required this.title,
    required this.remainingMinutes,
    required this.reason,
    required this.reasonText,
  });

  final String taskId;
  final String title;

  /// 还剩多少分钟没有被安排。
  final int remainingMinutes;

  final UnplannedReason reason;
  final String reasonText;

  /// 契约第 5.7 节要求每项至少含 `task_id`、`reason_code`、`remaining_minutes`
  /// 与 `message`。这里的键集合被限制为恰好这四项：
  /// `title` 保留在 Dart 对象里供进程内展示使用，但不进 JSON——
  /// 契约没有列出它，`additionalProperties: false` 时会整份提案被拒。
  Map<String, dynamic> toJson() => {
    'task_id': taskId,
    'remaining_minutes': remainingMinutes,
    'reason_code': reason.code,
    'message': reasonText,
  };
}

/// 一条解释。
///
/// 契约第 5.7 节：`explanations` 是**对象数组**，每项含机器可读 `code` 与
/// 安全的 `message`，可选 `related_task_ids`。不再允许字符串与对象混用。
/// [taskId] 非空时会被映射成单元素 `related_task_ids`。
/// M0 2026-10-31 定下的 v1 **公共** `explanations[].code` 枚举（封闭）。
///
/// 只有落在这个集合里的码才允许出现在 v1 远程响应中。
const Set<String> kPublicExplanationCodes = <String>{
  'PRESERVED_FIXED_EVENTS',
  'ESTIMATED_DURATION',
  'FIXED_BLOCKS_OVERLAP',
  'NO_AVAILABILITY_WINDOW',
  'AVAILABILITY_SATURATED',
  'ALREADY_DONE_TODAY',
  'SCHEDULED',
};

/// 只允许出现在**进程内 repair 结果**里的码，未经批准不得进入 v1 远程响应。
///
/// 服务端序列化 Proposal 时（方案 A）必须先把这些码滤掉。
const Set<String> kRepairOnlyExplanationCodes = <String>{
  'DISPLACED_BY_FIXED',
  'REPAIR_SUMMARY',
};

class ScheduleNote {
  const ScheduleNote({
    required this.code,
    required this.message,
    this.taskId,
  });

  final String code;
  final String message;

  /// 该解释关联的任务；为空表示这是全局说明，此时不输出 `related_task_ids`。
  final String? taskId;

  /// 该码是否允许进入 v1 远程响应。
  bool get isPublic => kPublicExplanationCodes.contains(code);

  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    if (taskId != null) 'related_task_ids': <String>[taskId!],
  };
}

/// 提案。它永远不会直接改写任何任务、日历、计时或完成记录。
///
/// 与契约第 5.7 节的对应关系：
/// - [blocks] 是可展示但**不可直接持久化**的时间块；
/// - [changes] 才是允许落库的白名单变更，只有两种形态。
///
/// **方案 A（M0 2026-10-31 决定，c53b1a9 起明确写进契约 §5.7）**：
/// 完整 Proposal 由服务端序列化。M2 纯调度函数**只输出内部调度结果**，
/// 即 `blocks` / `changes` / `unplanned_tasks` / `explanations` 四部分；
/// 不得生成或输出 `proposal_id`、`snapshot_ref`、`base_version`、
/// `input_digest`、`generated_at`、`expires_at`、`status` 等服务端权威字段。
/// 服务端包装层负责生成并持久化这些字段，再把内部四部分组装成完整 Proposal。
class ScheduleProposal {
  const ScheduleProposal({
    this.blocks = const [],
    this.changes = const [],
    this.unplannedTasks = const [],
    this.notes = const [],
  });

  /// 展示用时间块，对应 `blocks`。
  final List<ProposedBlock> blocks;

  /// 允许持久化的白名单变更，对应 `changes`。
  final List<ProposedScheduleChange> changes;

  final List<UnplannedTask> unplannedTasks;
  final List<ScheduleNote> notes;

  int get totalPlannedMinutes =>
      blocks.fold(0, (total, block) => total + block.minutes);

  /// 允许进入 v1 远程响应的解释：滤掉 repair 专用码与任何枚举外的码。
  ///
  /// 服务端序列化 Proposal（方案 A）时应以这个列表为准。
  List<ScheduleNote> get publicExplanations =>
      notes.where((note) => note.isPublic).toList();

  /// 方案 A 下 M2 只序列化内部四部分，服务端权威字段一律不输出。
  Map<String, dynamic> toJson() => {
    'blocks': blocks.map((block) => block.toJson()).toList(),
    'changes': changes.map((change) => change.toJson()).toList(),
    'unplanned_tasks': unplannedTasks.map((task) => task.toJson()).toList(),
    'explanations': notes.map((note) => note.toJson()).toList(),
  };
}

/// 当天从 00:00 起算的分钟数，用于生成 `planned_start_minute` 等契约字段。
int minuteOfDay(DateTime value) => value.hour * 60 + value.minute;
