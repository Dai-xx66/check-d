import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_queue_service.dart';
import '../../calendar/domain/calendar_occurrence_builder.dart';
import '../../calendar/domain/calendar_models.dart';
import '../../courses/data/course_repository.dart';
import '../../courses/data/semester_repository.dart';
import '../../courses/domain/course_models.dart';
import '../../plans/data/plan_repository.dart';
import '../../plans/domain/plan_models.dart';
import '../../reviews/data/review_repository.dart';
import '../../reviews/domain/review_models.dart';
import '../../schedule/data/day_schedule_repository.dart';
import '../../schedule/domain/day_schedule_models.dart';
import '../../statistics/data/statistics_repository.dart';
import '../../statistics/domain/statistics_models.dart';
import '../../tags/data/tag_repository.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/domain/task_models.dart';
import '../domain/agent_models.dart';
import '../domain/agent_schedule_engine.dart';

/// Account-scoped local workspace and the only writer for agent proposals.
/// Model text never reaches a SQL statement or a timer/completion writer.
class AgentRepository {
  AgentRepository({
    required AppDatabase database,
    required this.userId,
    DateTime Function()? clock,
    bool Function()? isCurrentOwner,
  }) : _database = database,
       _clock = clock ?? DateTime.now,
       _isCurrentOwner = isCurrentOwner ?? (() => true),
       _queue = SyncQueueService(database);

  final AppDatabase _database;
  final String userId;
  final DateTime Function() _clock;
  final bool Function() _isCurrentOwner;
  final SyncQueueService _queue;
  static const _uuid = Uuid();
  String get _key => 'agent.v1:$userId:workspace';

  TaskRepository get _tasks =>
      TaskRepository(database: _database, syncQueue: _queue, userId: userId);
  CourseRepository get _courses =>
      CourseRepository(database: _database, syncQueue: _queue, userId: userId);
  SemesterRepository get _semesters => SemesterRepository(
    database: _database,
    syncQueue: _queue,
    userId: userId,
  );
  DayScheduleRepository get _schedule => DayScheduleRepository(
    database: _database,
    syncQueue: _queue,
    userId: userId,
  );
  PlanRepository get _plans =>
      PlanRepository(database: _database, syncQueue: _queue, userId: userId);
  ReviewRepository get _reviews =>
      ReviewRepository(database: _database, syncQueue: _queue, userId: userId);
  TagRepository get _tags => TagRepository(_database, userId, _queue);

  void _assertOwner() {
    if (userId.isEmpty || !_isCurrentOwner()) {
      throw const AgentException('账号已变化，请重新打开智能体。', code: 'account_changed');
    }
  }

  Future<AgentWorkspace> loadWorkspace() async {
    _assertOwner();
    final row = await (_database.select(
      _database.appSettings,
    )..where((row) => row.key.equals(_key))).getSingleOrNull();
    if (row == null) return AgentWorkspace(profile: _profile(const {}));
    try {
      final workspace = AgentWorkspace.fromJson(
        Map<String, dynamic>.from(jsonDecode(row.value) as Map),
      );
      return workspace.copyWith(profile: _profile(workspace.profile));
    } on Object {
      throw const AgentException(
        '本机智能体档案无法读取，请先保留数据再检查。',
        code: 'invalid_workspace',
      );
    }
  }

  Stream<AgentWorkspace> watchWorkspace() =>
      (_database.select(_database.appSettings)
            ..where((row) => row.key.equals(_key)))
          .watchSingleOrNull()
          .asyncMap((_) => loadWorkspace());

  Future<void> _save(AgentWorkspace workspace) async {
    _assertOwner();
    await _database
        .into(_database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _key,
            value: jsonEncode(workspace.toJson()),
            updatedAt: _clock().toUtc(),
          ),
        );
  }

  Future<void> saveProfile(Map<String, Object?> profile) =>
      _database.transaction(() async {
        final workspace = await loadWorkspace();
        await _save(
          workspace.copyWith(
            profile: _profile({...workspace.profile, ...profile}),
          ),
        );
      });

  Future<void> appendMessage(AgentChatMessage message) =>
      _database.transaction(() async {
        if (!{'user', 'assistant'}.contains(message.role) ||
            message.text.trim().isEmpty ||
            message.text.length > 24000) {
          throw const AgentException('消息内容无效或过长。');
        }
        final workspace = await loadWorkspace();
        final messages = [...workspace.messages, message];
        await _save(
          workspace.copyWith(
            messages: messages.length > 100
                ? messages.sublist(messages.length - 100)
                : messages,
          ),
        );
      });

  Future<void> clearConversation() => _database.transaction(() async {
    final workspace = await loadWorkspace();
    await _save(workspace.copyWith(messages: const []));
  });

  Map<String, Object?> _profile(Map<String, Object?> input) {
    final value = <String, Object?>{
      'timezone': 'Asia/Shanghai',
      'learningShare': .2,
      'sleepStartMinute': 0,
      'sleepEndMinute': 450,
      'livingMinutesPerDay': 180,
      'remindersEnabled': false,
      'autoApply': false,
      ...input,
    };
    if (value['timezone'] != 'Asia/Shanghai') {
      throw const AgentException('当前提醒时区为 Asia/Shanghai，请使用北京时间。');
    }
    final share = value['learningShare'];
    if (share is! num || !share.isFinite || share <= 0 || share > 1) {
      throw const AgentException('学习比例应大于 0 且不超过 1。');
    }
    for (final key in ['sleepStartMinute', 'sleepEndMinute']) {
      final minute = value[key];
      if (minute is! int || minute < 0 || minute > 1439) {
        throw const AgentException('请填写有效的作息时间。');
      }
    }
    if (value['sleepStartMinute'] == value['sleepEndMinute']) {
      throw const AgentException('睡眠开始和结束不能相同，请确认真实睡眠时段。');
    }
    final living = value['livingMinutesPerDay'];
    if (living is! int || living < 0 || living > 960) {
      throw const AgentException('生活预留时间应为 0–960 分钟。');
    }
    if (value['remindersEnabled'] is! bool) {
      throw const AgentException('提醒开关无效。');
    }
    if (value['autoApply'] is! bool) {
      throw const AgentException('自动应用开关无效。');
    }
    for (final key in ['confirmedFrom', 'confirmedThrough']) {
      final date = value[key];
      if (date != null &&
          date != '' &&
          (date is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date))) {
        throw const AgentException('课表确认范围请使用 YYYY-MM-DD 日期。');
      }
    }
    final from = _dateOrNull(value['confirmedFrom']);
    final through = _dateOrNull(value['confirmedThrough']);
    if (from != null && through != null && through.isBefore(from)) {
      throw const AgentException('确认结束日期不能早于开始日期。');
    }
    if (jsonEncode(value).length > 100000) {
      throw const AgentException('档案内容过长，请精简后保存。');
    }
    return value;
  }

  static const _planningTables = <String, List<String>>{
    'local_tasks': ['id'],
    'long_term_task_records': ['task_id'],
    'task_schedule_records': ['id'],
    'one_time_reminder_records': ['task_id'],
    'course_records': ['id'],
    'course_schedule_rule_records': ['id'],
    'daily_item_override_records': ['id'],
    'reminder_rule_records': ['id'],
    'alarm_rule_records': ['id'],
    'plan_records': ['id'],
    'plan_task_records': ['plan_id', 'task_id'],
    'tag_records': ['id'],
    'review_records': ['id'],
  };

  Future<List<Map<String, Object?>>> _rows(String table) async =>
      (await _database
              .customSelect(
                'SELECT * FROM $table WHERE user_id = ?',
                variables: [Variable<String>(userId)],
              )
              .get())
          .map((row) => Map<String, Object?>.from(row.data))
          .toList();

  Future<Map<String, List<Map<String, Object?>>>> _snapshot() async => {
    for (final table in _planningTables.keys) table: await _rows(table),
  };

  Future<AgentContext> buildContext() => _database.transaction(() async {
    _assertOwner();
    final workspace = await loadWorkspace();
    final snapshot = await _snapshot();
    final facts = <String, List<Map<String, Object?>>>{
      for (final table in [
        'timer_session_records',
        'task_completion_records',
        'ad_hoc_timer_records',
        'ad_hoc_timer_interval_records',
      ])
        table: await _rows(table),
    };
    final templates = await _courses.watchScheduleTemplates().first;
    final semesters = await _semesters.watchSemesters().first;
    final courses = await _courses.loadCourses();
    final today = dateOnly(_clock());
    final requestedThrough = _dateOrNull(workspace.profile['confirmedThrough']);
    final maximumThrough = today.add(const Duration(days: 59));
    final through =
        requestedThrough == null || requestedThrough.isAfter(maximumThrough)
        ? maximumThrough
        : requestedThrough.isBefore(today)
        ? today
        : requestedThrough;
    final links = {
      for (final link in workspace.taskLinks) link['taskId']: link,
    };
    final days = <Map<String, Object?>>[];
    for (
      var day = today;
      !day.isAfter(through);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final tasks = await _tasks.watchTasksForDate(day).first;
      final overrides = await _schedule.loadOverridesForDate(day);
      final occurrences = buildCalendarOccurrencesForDate(
        date: day,
        tasks: tasks,
        courses: courses,
        overrides: overrides,
        templates: templates,
        semesters: semesters,
      );
      var unknown = false;
      final events = <Map<String, Object?>>[];
      for (final event in occurrences) {
        final start = event.startMinute;
        var end = event.endMinute;
        final task = event.task;
        final managed = task != null && links.containsKey(task.id);
        final linkDuration = managed
            ? links[task.id]!['durationMinutes']
            : null;
        final seconds = task?.targetDurationSeconds;
        if (end == null && start != null) {
          final duration = linkDuration is int
              ? linkDuration
              : seconds == null
              ? null
              : (seconds / 60).ceil();
          if (duration != null && duration > 0) end = start + duration;
        }
        if (start != null &&
            end == null &&
            !(task?.isCompleted ?? false) &&
            !managed) {
          unknown = true;
        }
        events.add({
          'id': event.id,
          'entityId': task?.id ?? event.course?.id,
          if (event.courseRule != null) 'ruleId': event.courseRule!.id,
          'type': event.type == CalendarOccurrenceType.course
              ? 'course'
              : 'task',
          'title': event.title,
          'startMinute': start,
          'endMinute': end,
          'completed': task?.isCompleted ?? false,
          'managed': managed,
          if (managed) 'goalId': links[task.id]!['goalId'],
        });
      }
      days.add({
        'date': localDateKey(day),
        'events': events,
        'unknownDuration': unknown,
      });
    }
    final taskRows = snapshot['local_tasks']!;
    final goalsByTask = {
      for (final row in snapshot['long_term_task_records']!)
        row['task_id']: row,
    };
    final schedulesByTask = {
      for (final row in snapshot['task_schedule_records']!) row['task_id']: row,
    };
    final remindersByTask = {
      for (final row in snapshot['one_time_reminder_records']!)
        row['task_id']: row,
    };
    final taskData = [
      for (final row in taskRows)
        {
          ..._contextRow(row),
          'kind': row['task_type'],
          if (goalsByTask[row['id']] case final goal?) ..._contextRow(goal),
          if (schedulesByTask[row['id']] case final schedule?)
            ..._contextRow(schedule),
          if (remindersByTask[row['id']] case final reminder?)
            ..._contextRow(reminder),
          'id': row['id'],
        },
    ];
    final stable = <String, Object?>{
      'ownerId': userId,
      'today': localDateKey(today),
      'profile': workspace.profile,
      'goals': workspace.goals,
      'busyPeriods': workspace.busyPeriods,
      'feedback': workspace.feedback,
      'taskLinks': workspace.taskLinks,
      'tables': snapshot,
      'facts': facts,
      'templates': templates
          .map(
            (t) => {
              'id': t.id,
              'name': t.name,
              'segments': [
                for (final s in t.segments)
                  {
                    'id': s.id,
                    'startMinute': s.startsAtMinute,
                    'endMinute': s.endsAtMinute,
                  },
              ],
            },
          )
          .toList(),
      'semesters': semesters
          .map(
            (s) => {
              'id': s.id,
              'firstWeekStartDate': s.firstWeekStartDate.toIso8601String(),
              'totalWeeks': s.totalWeeks,
            },
          )
          .toList(),
    };
    final stats = await StatisticsRepository(
      _database,
      userId,
    ).load(now: _clock());
    final weekly = stats.report(StatisticsPeriod.week, today, _clock());
    _assertOwner();
    final data = <String, Object?>{
      'now': _clock().toIso8601String(),
      'timezone': 'Asia/Shanghai',
      'profile': workspace.profile,
      'goals': workspace.goals,
      'busyPeriods': workspace.busyPeriods,
      'feedback': workspace.feedback,
      'taskLinks': workspace.taskLinks,
      'tasks': taskData,
      'courses': [
        for (final row in snapshot['course_records']!)
          {
            ..._contextRow(row),
            'rules': [
              for (final rule
                  in snapshot['course_schedule_rule_records']!.where(
                    (r) => r['course_id'] == row['id'],
                  ))
                _contextRow(rule),
            ],
          },
      ],
      'semesters': [
        for (final semester in semesters)
          {
            'id': semester.id,
            'name': semester.name,
            'firstWeekStartDate': semester.firstWeekStartDate.toIso8601String(),
            'totalWeeks': semester.totalWeeks,
          },
      ],
      'templates': [
        for (final template in templates)
          {
            'id': template.id,
            'name': template.name,
            'segments': [
              for (final segment in template.segments)
                {
                  'id': segment.id,
                  'name': segment.name,
                  'startsAtMinute': segment.startsAtMinute,
                  'endsAtMinute': segment.endsAtMinute,
                  'segmentType': segment.segmentType.name,
                },
            ],
          },
      ],
      'overrides': snapshot['daily_item_override_records']!
          .map(_contextRow)
          .toList(),
      'plans': snapshot['plan_records']!.map(_contextRow).toList(),
      'tags': snapshot['tag_records']!.map(_contextRow).toList(),
      'reviews': snapshot['review_records']!.map(_contextRow).toList(),
      'timerSessions': facts['timer_session_records']!
          .map(_contextRow)
          .toList(),
      'completions': facts['task_completion_records']!
          .map(_contextRow)
          .toList(),
      'adHocTimers': facts['ad_hoc_timer_records']!.map(_contextRow).toList(),
      'adHocIntervals': facts['ad_hoc_timer_interval_records']!
          .map(_contextRow)
          .toList(),
      'statistics': {
        'weekFocusSeconds': weekly.focusSeconds,
        'weekCompleted': weekly.completedItems,
        'weekExpected': weekly.expectedItems,
      },
      'executionTotals': {
        'timerSessionCount': facts['timer_session_records']!.length,
        'completionCount': facts['task_completion_records']!.length,
        'adHocTimerCount': facts['ad_hoc_timer_records']!.length,
        'adHocIntervalCount': facts['ad_hoc_timer_interval_records']!.length,
        'allTimeFocusSeconds': _focusSeconds(
          stats.sessions,
          DateTime(1970),
          _clock(),
        ),
        'measuredThrough': _clock().toIso8601String(),
      },
      'calendarDays': days,
      'calendarThrough': localDateKey(through),
      'calendarTruncated':
          requestedThrough != null && requestedThrough.isAfter(maximumThrough),
    };
    return AgentContext(
      ownerId: userId,
      revision: _fingerprint(stable),
      data: data,
      cloudData: _boundedCloudContext(data),
    );
  });

  /// Keep local validation complete while bounding disclosure and model input.
  /// Counts and measured totals cover all facts, not just the selected samples.
  static Map<String, Object?> _boundedCloudContext(Map<String, Object?> full) {
    Object? compact(Object? value, [int depth = 0]) {
      if (value is String) {
        return value.length <= 1200
            ? value
            : '${value.substring(0, 1200)}…[正文截断]';
      }
      if (depth > 7) return '[嵌套详情未发送]';
      if (value is Map) {
        return {
          for (final entry in value.entries.take(60))
            entry.key.toString(): compact(entry.value, depth + 1),
        };
      }
      if (value is List) {
        return value.take(100).map((v) => compact(v, depth + 1)).toList();
      }
      return value;
    }

    const limits = {
      'tasks': 100,
      'courses': 40,
      'goals': 20,
      'busyPeriods': 80,
      'feedback': 20,
      'taskLinks': 100,
      'semesters': 8,
      'templates': 8,
      'overrides': 100,
      'plans': 20,
      'tags': 40,
      'reviews': 8,
      'timerSessions': 40,
      'completions': 40,
      'adHocTimers': 20,
      'adHocIntervals': 40,
      'calendarDays': 21,
    };
    final bounded = <String, Object?>{
      for (final key in [
        'now',
        'timezone',
        'profile',
        'statistics',
        'executionTotals',
        'calendarThrough',
        'calendarTruncated',
      ])
        key: compact(full[key]),
    };
    final totals = <String, int>{};
    for (final entry in limits.entries) {
      final rows = (full[entry.key] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, Object?>.from(row))
          .toList();
      totals[entry.key] = rows.length;
      final activeOnly = {
        'tasks',
        'courses',
        'goals',
        'plans',
        'tags',
        'overrides',
      }.contains(entry.key);
      final selected = rows
          .where(
            (row) =>
                !activeOnly ||
                (row['deletedAt'] == null &&
                    row['archived'] != true &&
                    row['status'] != 'archived'),
          )
          .toList();
      if (entry.key != 'calendarDays') {
        String stamp(Map<String, Object?> row) =>
            (row['startedAt'] ?? row['createdAt'] ?? row['localDate'] ?? '')
                .toString();
        selected.sort((a, b) => stamp(b).compareTo(stamp(a)));
      }
      bounded[entry.key] = selected.take(entry.value).map((row) {
        if (entry.key == 'calendarDays') {
          final events = row['events'] as List? ?? const [];
          return <String, Object?>{
            ...row,
            'events': events.take(40).map((v) => compact(v)).toList(),
            if (events.length > 40) 'eventsOmitted': events.length - 40,
            if (events.length > 40) 'unknownDuration': true,
          };
        }
        return compact(row);
      }).toList();
    }
    // Large accounts still have a hard bound. Omitted rows are explicitly
    // counted below; the full revision and local conflict checks are retained.
    while (jsonEncode(bounded).length > 168000) {
      final candidates =
          limits.keys.where((key) => (bounded[key] as List).isNotEmpty).toList()
            ..sort(
              (a, b) => jsonEncode(
                bounded[b],
              ).length.compareTo(jsonEncode(bounded[a]).length),
            );
      if (candidates.isEmpty) break;
      (bounded[candidates.first] as List).removeLast();
    }
    bounded['contextCoverage'] = {
      'selection': 'bounded_active_and_recent_records',
      'records': {
        for (final key in limits.keys)
          key: {
            'total': totals[key],
            'sent': (bounded[key] as List).length,
            'omitted': totals[key]! - (bounded[key] as List).length,
          },
      },
      'note':
          '仅发送有限活动记录和近期事实样本；executionTotals与statistics依据全量事实计算。未发送不代表不存在或时长为0，不得据此推断空闲或捏造历史；缺少所需实体/日期时请询问。正文和嵌套详情可能截断。所有变更仍在本机用完整数据复核。',
    };
    return bounded;
  }

  Future<AgentProposal> prepareProposal(AgentProposal proposal) async {
    final context = await buildContext();
    if (proposal.contextRevision != context.revision) {
      throw const AgentException('日程或档案已变化，请重新生成提案。', code: 'stale_proposal');
    }
    return AgentScheduleEngine.prepare(
      context: context,
      workspace: await loadWorkspace(),
      proposal: proposal,
      now: _clock(),
    );
  }

  Future<AgentApplyResult> applyProposal(AgentProposal proposal) =>
      _database.transaction(() async {
        _assertOwner();
        _proposalId(proposal.id);
        final appliedKey = 'agent.v1:$userId:applied:${proposal.id}';
        final applied = await (_database.select(
          _database.appSettings,
        )..where((row) => row.key.equals(appliedKey))).getSingleOrNull();
        if (applied != null) {
          return const AgentApplyResult(
            summary: '该提案已经应用，无需重复确认。',
            changedCount: 0,
            alreadyApplied: true,
          );
        }
        if (proposal.questions.isNotEmpty) {
          throw const AgentException(
            '提案仍有待确认信息，请先补充后重新生成。',
            code: 'needs_answers',
          );
        }
        final prepared = await prepareProposal(proposal);
        if (prepared.operations.length > 80) {
          throw const AgentException('单次调整过多，请分批确认。');
        }
        if (prepared.operations.isEmpty) {
          return const AgentApplyResult(summary: '没有需要写入的变更。', changedCount: 0);
        }
        final before = await _snapshot();
        var workspace = await loadWorkspace();
        final workspaceBefore = _planningWorkspace(workspace);
        final aliases = <String, String>{};
        for (final operation in prepared.operations) {
          _assertOwner();
          _rejectFacts(operation.data);
          workspace = await _execute(operation, workspace, aliases);
        }
        final after = await _snapshot();
        final delta = _delta(before, after);
        final history = [
          ...workspace.history,
          <String, Object?>{
            'id': proposal.id,
            'createdAt': _clock().toIso8601String(),
            'summary': proposal.reply,
            'changedCount': prepared.operations.length,
            'changes': delta,
            'workspaceBefore': workspaceBefore,
            'workspaceAfter': _planningWorkspace(workspace),
            'undone': false,
          },
        ];
        workspace = workspace.copyWith(
          history: history.length > 20
              ? history.sublist(history.length - 20)
              : history,
        );
        _assertOwner();
        await _save(workspace);
        await _database
            .into(_database.appSettings)
            .insert(
              AppSettingsCompanion.insert(
                key: appliedKey,
                value: 'applied',
                updatedAt: _clock().toUtc(),
              ),
            );
        return AgentApplyResult(
          summary: '已应用 ${prepared.operations.length} 项调整。',
          changedCount: prepared.operations.length,
        );
      });

  Future<AgentApplyResult> undoLast() => _database.transaction(() async {
    _assertOwner();
    var workspace = await loadWorkspace();
    final index = workspace.history.lastIndexWhere(
      (entry) => entry['undone'] != true,
    );
    if (index < 0) throw const AgentException('没有可以撤销的历史。', code: 'no_history');
    final history = [
      for (final row in workspace.history) Map<String, Object?>.from(row),
    ];
    final entry = history[index];
    if (_canonical(_planningWorkspace(workspace)) !=
        _canonical(entry['workspaceAfter'])) {
      throw const AgentException(
        '档案在此次调整后已被修改，无法安全覆盖；请生成新的调整。',
        code: 'undo_conflict',
      );
    }
    final changes = (entry['changes'] as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList();
    final current = await _snapshot();
    for (final change in changes) {
      final table = change['table'] as String;
      if (!_planningTables.containsKey(table)) {
        throw const AgentException('历史数据格式无效。');
      }
      final after = Map<String, Object?>.from(
        change['after'] as Map? ?? const {},
      );
      final identity = change['identity'] as String;
      final actual = current[table]!
          .where((row) => _identity(table, row) == identity)
          .firstOrNull;
      if (_canonical(_undoComparable(actual)) !=
          _canonical(_undoComparable(after.isEmpty ? null : after))) {
        throw const AgentException(
          '记录已有新的修改或执行事实，未撤销任何内容。',
          code: 'undo_conflict',
        );
      }
    }
    final affectedTasks = <String>{};
    final outbox = <String, Set<String>>{};
    for (final change in changes) {
      final table = change['table'] as String;
      final before = Map<String, Object?>.from(
        change['before'] as Map? ?? const {},
      );
      final after = Map<String, Object?>.from(
        change['after'] as Map? ?? const {},
      );
      if (before.isNotEmpty) {
        await _restoreRow(table, before);
      } else if (after.isNotEmpty) {
        await _archiveNewRow(table, after);
      }
      final row = before.isNotEmpty ? before : after;
      final target = _outboxTarget(table, row);
      if (target != null) {
        outbox.putIfAbsent(target.$1, () => {}).add(target.$2);
      }
      if (table == 'local_tasks') affectedTasks.add(row['id'] as String);
      if ({
        'long_term_task_records',
        'one_time_reminder_records',
        'task_schedule_records',
      }.contains(table)) {
        affectedTasks.add(row['task_id'] as String);
      }
    }
    for (final id in affectedTasks) {
      final task = await _tasks.getTask(id);
      if (task != null) await _recordTaskRestoration(task);
    }
    for (final type in outbox.keys) {
      for (final id in outbox[type]!) {
        await (_database.update(_database.syncOperations)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.entityType.equals(type) &
                  row.entityId.equals(id) &
                  (row.status.equals('pending') | row.status.equals('failed')),
            ))
            .write(const SyncOperationsCompanion(status: Value('superseded')));
        await _queue.enqueue(
          entityType: type,
          entityId: id,
          operation: SyncOperationType.upsert,
          payload: {'id': id, 'updated_at': _clock().toUtc().toIso8601String()},
          userId: userId,
        );
      }
    }
    final previous = Map<String, Object?>.from(entry['workspaceBefore'] as Map);
    history[index] = {
      ...entry,
      'undone': true,
      'undoneAt': _clock().toIso8601String(),
    };
    workspace = _withPlanningWorkspace(
      workspace,
      previous,
    ).copyWith(history: history);
    _assertOwner();
    await _save(workspace);
    return AgentApplyResult(
      summary: '已撤销最近一次调整，真实计时和完成记录保持不变。',
      changedCount: changes.length,
    );
  });

  Future<AgentWorkspace> _execute(
    AgentOperation op,
    AgentWorkspace workspace,
    Map<String, String> aliases,
  ) async {
    if (!agentActions.contains(op.action)) {
      throw const AgentException('不支持的智能体操作。');
    }
    final data = Map<String, Object?>.from(op.data);
    String resolve(String id) => aliases[id] ?? id;
    String requiredId() {
      if (op.entityId == null || op.entityId!.isEmpty) {
        throw const AgentException('这项操作缺少记录编号。');
      }
      return resolve(op.entityId!);
    }

    switch (op.action) {
      case 'create_task':
      case 'update_task':
        final isNew = op.action == 'create_task';
        final task = isNew ? null : await _requireTask(requiredId());
        if (task != null) await _protectTask(task);
        if (isNew && op.entityId != null) {
          await _assertAliasFree(op.entityId!, aliases);
        }
        final merged = <String, Object?>{
          if (task != null) ..._taskData(task),
          ...data,
        };
        final tag = merged['tagId'];
        if (tag is String) {
          merged['tagId'] = resolve(tag);
          await _requireRow('tag_records', merged['tagId'] as String);
        }
        final kind = _string(merged, 'kind', fallback: 'oneTime');
        if (task != null && kind != task.kind.name) {
          throw const AgentException('请另建新类型的事项，再确认是否归档原事项。');
        }
        late String id;
        if (kind == 'recurring') {
          final weekdays = _ints(merged['weekdays'] ?? [1, 2, 3, 4, 5, 6, 7]);
          id = await _tasks.saveRecurringTask(
            RecurringTaskDraft(
              name: _string(merged, 'name'),
              colorValue: _int(merged, 'colorValue', fallback: 0xFF9B7AE5),
              iconName: _string(merged, 'iconName', fallback: 'target'),
              tagId: merged['tagId'] as String?,
              notes: merged['notes'] as String?,
              executionMode: _enum(
                RecurringExecutionMode.values,
                merged['executionMode'] ?? 'timed',
              ),
              schedulePreset: _enum(
                SchedulePreset.values,
                merged['schedulePreset'] ?? 'custom',
              ),
              weekdays: weekdays.toSet(),
              startsOn: _date(merged['startsOn'] ?? localDateKey(_clock())),
              endsOn: _dateOrNull(merged['endsOn']),
              holidayPause: merged['holidayPause'] == true,
              targetDurationSeconds: merged['targetDurationSeconds'] as int?,
              targetDays: merged['targetDays'] as int?,
              scheduledMinuteOfDay: merged['scheduledMinuteOfDay'] as int?,
              reminderMinuteOfDay: merged['reminderMinuteOfDay'] as int?,
            ),
            taskId: task?.id,
          );
        } else if (kind == 'oneTime') {
          id = await _tasks.saveOneTimeReminder(
            OneTimeReminderDraft(
              name: _string(merged, 'name'),
              colorValue: _int(merged, 'colorValue', fallback: 0xFF8BA9F0),
              iconName: _string(merged, 'iconName', fallback: 'event'),
              tagId: merged['tagId'] as String?,
              notes: merged['notes'] as String?,
              scheduledAt: _dateOrNull(merged['scheduledAt']),
              plannedDate: _dateOrNull(merged['plannedDate']),
              availableFrom: _dateOrNull(merged['availableFrom']),
              deadline: _deadline(merged),
              executionMode: _enum(
                OneTimeExecutionMode.values,
                merged['executionMode'] ?? 'timed',
              ),
              remindBeforeMinutes: merged['remindBeforeMinutes'] as int?,
            ),
            taskId: task?.id,
          );
        } else {
          throw const AgentException('任务类型应为 recurring 或 oneTime。');
        }
        if (isNew && op.entityId != null) aliases[op.entityId!] = id;
        final goal = data['goalId'];
        if (goal is String &&
            !workspace.goals.any(
              (g) => g['id'] == resolve(goal) && g['archived'] != true,
            )) {
          throw const AgentException('目标不存在。');
        }
        final previous = workspace.taskLinks
            .where((link) => link['taskId'] == id)
            .firstOrNull;
        final managesSchedule =
            isNew ||
            previous != null ||
            data.keys.any(
              {
                'durationMinutes',
                'standard',
                'goalId',
                'scheduledAt',
                'date',
                'startMinute',
                'endMinute',
                'scheduledMinuteOfDay',
              }.contains,
            );
        // Renaming a manually created task must not invent a duration or take
        // ownership of its calendar interval.
        if (!managesSchedule) return workspace;
        final duration =
            data['durationMinutes'] ??
            previous?['durationMinutes'] ??
            (merged['targetDurationSeconds'] is int
                ? ((merged['targetDurationSeconds'] as int) / 60).ceil()
                : 30);
        if (duration is! int || duration <= 0 || duration > 720) {
          throw const AgentException('任务预计时长应为 1–720 分钟。');
        }
        final link = <String, Object?>{
          ...?previous,
          'taskId': id,
          'name': merged['name'],
          'title': merged['name'],
          'durationMinutes': duration,
          if (goal is String) 'goalId': resolve(goal),
          'standard': data['standard'] ?? previous?['standard'] ?? '',
          'needsScheduling': kind == 'oneTime' && merged['scheduledAt'] == null,
          'unscheduled': kind == 'oneTime' && merged['scheduledAt'] == null,
        };
        workspace = workspace.copyWith(
          taskLinks: [
            ...workspace.taskLinks.where((l) => l['taskId'] != id),
            link,
          ],
        );
        final scheduled = _dateOrNull(merged['scheduledAt']);
        if (kind == 'oneTime' &&
            task?.scheduledAt != null &&
            scheduled == null) {
          await _softArchiveForTask(id);
        }
        if (kind == 'oneTime' && scheduled != null) {
          if (task != null && task.scheduledAt != scheduled) {
            await _softArchiveForTask(id);
          }
          final start = scheduled.hour * 60 + scheduled.minute;
          await _writeTaskSlot(id, scheduled, start, start + duration);
        }
        return workspace;
      case 'archive_task':
        final task = await _requireTask(requiredId());
        await _protectTask(task);
        await _tasks.archiveTask(task.id);
        return workspace.copyWith(
          taskLinks: workspace.taskLinks
              .where((link) => link['taskId'] != task.id)
              .toList(),
        );
      case 'reschedule_task':
        final selectedDate = data['unscheduled'] == true
            ? null
            : _date(data['date']);
        final task = await _requireTask(requiredId(), date: selectedDate);
        await _protectTask(task);
        final oldLinks = workspace.taskLinks;
        final oldLink = oldLinks
            .where((l) => l['taskId'] == task.id)
            .firstOrNull;
        if (data['unscheduled'] == true) {
          if (task.kind != TaskKind.oneTime) {
            throw const AgentException('周期任务请使用单日例外，不清除整个周期。');
          }
          await _tasks.cancelOneTimeSchedule(task.id);
          await _softArchiveForTask(task.id);
          return workspace.copyWith(
            taskLinks: [
              ...oldLinks.where((l) => l['taskId'] != task.id),
              {
                ...?oldLink,
                'taskId': task.id,
                'needsScheduling': true,
                'unscheduled': true,
                'name': task.name,
                'title': task.name,
              },
            ],
          );
        }
        final date = selectedDate!;
        final start = _int(data, 'startMinute');
        final end = _int(data, 'endMinute');
        _validRange(start, end);
        if (task.kind == TaskKind.oneTime) {
          await _tasks.scheduleOneTimeTask(
            task.id,
            DateTime(date.year, date.month, date.day, start ~/ 60, start % 60),
          );
          await _softArchiveForTask(task.id);
        }
        await _writeTaskSlot(
          task.id,
          date,
          start,
          end,
          recurring: task.kind == TaskKind.recurring,
        );
        if (oldLink != null) {
          return workspace.copyWith(
            taskLinks: [
              for (final l in oldLinks)
                if (l['taskId'] == task.id)
                  {
                    ...l,
                    'durationMinutes': end - start,
                    'needsScheduling': false,
                    'unscheduled': false,
                  }
                else
                  l,
            ],
          );
        }
        return workspace;
      case 'create_course':
      case 'update_course':
        final isNew = op.action == 'create_course';
        final existing = isNew
            ? null
            : await _requireRow('course_records', requiredId());
        if (isNew && op.entityId != null) {
          await _assertAliasFree(op.entityId!, aliases);
        }
        final merged = {
          if (existing != null) ..._contextRow(existing),
          ...data,
        };
        if (merged['semesterId'] is String) {
          await _requireRow(
            'semester_records',
            resolve(merged['semesterId'] as String),
          );
        }
        final id = await _courses.saveCourse(
          CourseDraft(
            name: _string(merged, 'name'),
            colorValue: _int(merged, 'colorValue', fallback: 0xFF8BA9F0),
            teacher: merged['teacher'] as String?,
            classroom: merged['classroom'] as String?,
            semester: merged['semester'] as String?,
            semesterId: merged['semesterId'] is String
                ? resolve(merged['semesterId'] as String)
                : null,
            semesterStartsOn: _dateOrNull(merged['semesterStartsOn']),
            semesterEndsOn: _dateOrNull(merged['semesterEndsOn']),
            notes: merged['notes'] as String?,
          ),
          courseId: existing?['id'] as String?,
        );
        if (isNew && op.entityId != null) aliases[op.entityId!] = id;
        if (data['rules'] is List) {
          final oldRules = (await _rows('course_schedule_rule_records'))
              .where((r) => r['course_id'] == id && r['deleted_at'] == null)
              .toList();
          final retained = <String>{};
          for (final ruleValue in data['rules'] as List) {
            final rule = Map<String, Object?>.from(ruleValue as Map);
            final ruleId = rule['id'] as String?;
            if (ruleId != null && !oldRules.any((r) => r['id'] == ruleId)) {
              throw const AgentException('课程规则不属于当前课程。');
            }
            final templateId = rule['scheduleTemplateId'] as String?;
            if (templateId != null) {
              await _requireRow('schedule_template_records', templateId);
            }
            final sectionIds = (rule['sectionIds'] as List? ?? const [])
                .cast<String>();
            for (final sectionId in sectionIds) {
              final section = await _requireRow(
                'schedule_template_segment_records',
                sectionId,
              );
              if (section['template_id'] != templateId) {
                throw const AgentException('节次不属于所选作息模板。');
              }
            }
            final saved = await _courses.saveScheduleRule(
              CourseScheduleRuleDraft(
                courseId: id,
                weekday: _int(rule, 'weekday'),
                weekRuleType: _enum(
                  CourseWeekRuleType.values,
                  rule['weekRuleType'] ?? 'everyWeek',
                ),
                startsAtMinute: _int(rule, 'startsAtMinute'),
                endsAtMinute: _int(rule, 'endsAtMinute'),
                startWeek: rule['startWeek'] as int?,
                endWeek: rule['endWeek'] as int?,
                intervalWeeks: rule['intervalWeeks'] as int?,
                weekNumbers: _ints(rule['weekNumbers'] ?? const []).toSet(),
                scheduleTemplateId: templateId,
                sectionIds: sectionIds,
                timeMode: _enum(
                  CourseScheduleTimeMode.values,
                  rule['timeMode'] ?? 'customTime',
                ),
                classroomOverride: rule['classroomOverride'] as String?,
                notes: rule['notes'] as String?,
                remindBeforeMinutes: rule['remindBeforeMinutes'] as int?,
              ),
              ruleId: ruleId,
            );
            retained.add(saved);
          }
          if (data['replaceRules'] == true) {
            for (final rule in oldRules.where(
              (r) => !retained.contains(r['id']),
            )) {
              await _courses.archiveScheduleRule(rule['id'] as String);
            }
          }
        }
        return workspace;
      case 'archive_course':
        final id = requiredId();
        await _requireRow('course_records', id);
        await _courses.archiveCourse(id);
        return workspace;
      case 'update_course_day':
        final id = requiredId();
        await _requireRow('course_records', id);
        final ruleId = data['ruleId'] as String?;
        if (ruleId != null) {
          final rule = await _requireRow(
            'course_schedule_rule_records',
            ruleId,
          );
          if (rule['course_id'] != id) {
            throw const AgentException('课程规则不属于所选课程。');
          }
        }
        final overrideOwner = ruleId ?? id;
        final date = _date(data['date']);
        final action = _enum(
          DayOverrideAction.values,
          data['action'] ?? 'reschedule',
        );
        if (!{
          DayOverrideAction.skip,
          DayOverrideAction.reschedule,
          DayOverrideAction.courseChange,
          DayOverrideAction.extraCourse,
        }.contains(action)) {
          throw const AgentException('课程单日调整方式无效。');
        }
        final start = data['startMinute'] as int?;
        final end = data['endMinute'] as int?;
        if (action != DayOverrideAction.skip) _validRange(start, end);
        final existing = (await _rows('daily_item_override_records'))
            .where(
              (r) =>
                  r['item_id'] == overrideOwner &&
                  r['item_type'] == 'course' &&
                  r['local_date'] == localDateKey(date),
            )
            .firstOrNull;
        final savedOverride = await _schedule.saveDailyOverride(
          DailyItemOverrideDraft(
            itemType: DayItemType.course,
            itemId: overrideOwner,
            localDate: date,
            action: action,
            plannedStartMinute: start,
            plannedEndMinute: end,
            temporaryClassroom: data['temporaryClassroom'] as String?,
            notes: data['notes'] as String?,
          ),
          overrideId: existing?['id'] as String?,
        );
        await _showOverride(savedOverride);
        return workspace;
      case 'create_plan':
      case 'update_plan':
        final isNew = op.action == 'create_plan';
        final existing = isNew
            ? null
            : await _requireRow('plan_records', requiredId());
        if (isNew && op.entityId != null) {
          await _assertAliasFree(op.entityId!, aliases);
        }
        final merged = {
          if (existing != null) ..._contextRow(existing),
          ...data,
        };
        final taskIds =
            (merged['taskIds'] as List? ??
                    (existing == null
                        ? const []
                        : (await _rows('plan_task_records'))
                              .where((r) => r['plan_id'] == existing['id'])
                              .map((r) => r['task_id'])
                              .toList()))
                .cast<String>()
                .map(resolve)
                .toSet();
        for (final id in taskIds) {
          final task = await _requireTask(id);
          if (task.kind != TaskKind.recurring) {
            throw const AgentException('现有计划只能关联周期任务。');
          }
        }
        final id = await _plans.save(
          PlanDraft(
            name: _string(merged, 'name'),
            type: _enum(PlanType.values, merged['type'] ?? 'month'),
            colorValue: _int(merged, 'colorValue', fallback: 0xFF9B7AE5),
            startsOn: _date(merged['startsOn']),
            endsOn: _date(merged['endsOn']),
            taskIds: taskIds,
            goal: merged['goal'] as String?,
          ),
          planId: existing?['id'] as String?,
        );
        if (isNew && op.entityId != null) aliases[op.entityId!] = id;
        return workspace;
      case 'archive_plan':
        final id = requiredId();
        await _requireRow('plan_records', id);
        await _plans.archive(id);
        return workspace;
      case 'create_tag':
      case 'update_tag':
        final isNew = op.action == 'create_tag';
        final existing = isNew
            ? null
            : await _requireRow('tag_records', requiredId());
        if (isNew && op.entityId != null) {
          await _assertAliasFree(op.entityId!, aliases);
        }
        final merged = {
          if (existing != null) ..._contextRow(existing),
          ...data,
        };
        final id = await _tags.save(
          id: existing?['id'] as String?,
          name: _string(merged, 'name'),
          colorValue: _int(merged, 'colorValue', fallback: 0xFF9B7AE5),
        );
        if (isNew && op.entityId != null) aliases[op.entityId!] = id;
        return workspace;
      case 'archive_tag':
        final id = requiredId();
        await _requireRow('tag_records', id);
        await _tags.setArchived(id, true);
        return workspace;
      case 'upsert_goal':
        final id = op.entityId == null ? _uuid.v4() : resolve(op.entityId!);
        final existing = workspace.goals
            .where((g) => g['id'] == id)
            .firstOrNull;
        final goal = {
          ...?existing,
          ...data,
          if (data['name'] == null && data['title'] is String)
            'name': data['title'],
          'id': id,
          'archived': false,
          'updatedAt': _clock().toIso8601String(),
        };
        _string(goal, 'name');
        return workspace.copyWith(
          goals: [...workspace.goals.where((g) => g['id'] != id), goal],
        );
      case 'archive_goal':
        final id = requiredId();
        if (!workspace.goals.any((g) => g['id'] == id)) {
          throw const AgentException('目标不存在。');
        }
        return workspace.copyWith(
          goals: [
            for (final g in workspace.goals)
              if (g['id'] == id) {...g, 'archived': true} else g,
          ],
        );
      case 'update_profile':
        return workspace.copyWith(
          profile: _profile({...workspace.profile, ...data}),
        );
      case 'add_busy_period':
        final day = data['startsAt'] == null ? _date(data['date']) : null;
        final start = data['startsAt'] == null
            ? _int(data, 'startMinute')
            : null;
        final duration = data['startsAt'] == null
            ? _int(data, 'durationMinutes')
            : null;
        if (start != null) _validRange(start, start + duration!);
        final from = data['startsAt'] != null
            ? _date(data['startsAt'])
            : DateTime(day!.year, day.month, day.day, start! ~/ 60, start % 60);
        final through = data['endsAt'] != null
            ? _date(data['endsAt'])
            : from.add(Duration(minutes: duration!));
        if (!through.isAfter(from)) {
          throw const AgentException('临时占用结束时间必须晚于开始时间。');
        }
        final id = _uuid.v4();
        if (op.entityId != null) aliases[op.entityId!] = id;
        return workspace.copyWith(
          busyPeriods: [
            ...workspace.busyPeriods,
            {
              ...data,
              'id': id,
              'startsAt': from.toIso8601String(),
              'endsAt': through.toIso8601String(),
              'date': localDateKey(from),
              'startMinute': from.hour * 60 + from.minute,
              'durationMinutes': through.difference(from).inMinutes,
            },
          ],
        );
      case 'remove_busy_period':
        final id = requiredId();
        if (!workspace.busyPeriods.any((p) => p['id'] == id)) {
          throw const AgentException('临时占用不存在。');
        }
        return workspace.copyWith(
          busyPeriods: workspace.busyPeriods
              .where((p) => p['id'] != id)
              .toList(),
        );
      case 'record_feedback':
        final minutes = data['actualMinutes'];
        if (minutes != null &&
            (minutes is! num ||
                !minutes.isFinite ||
                minutes < 0 ||
                minutes > 1440 ||
                minutes != minutes.roundToDouble())) {
          throw const AgentException('自报学习时长应为0–1440的整数分钟。');
        }
        final source = data['source'] ?? 'self_report';
        if (!{
          'self_report',
          'self_reported',
          'artifact',
          'teacher',
        }.contains(source)) {
          throw const AgentException('反馈来源应为自报、作品材料或教师反馈。');
        }
        if (data['taskId'] is String) {
          await _requireTask(resolve(data['taskId'] as String));
        }
        final feedback = [
          ...workspace.feedback,
          {
            ...data,
            if (data['taskId'] is String)
              'taskId': resolve(data['taskId'] as String),
            'id': _uuid.v4(),
            'source': source == 'self_reported' ? 'self_report' : source,
            'verification': 'unverified',
            'isExecutionFact': false,
            'createdAt': _clock().toIso8601String(),
          },
        ];
        return workspace.copyWith(
          feedback: feedback.length > 200
              ? feedback.sublist(feedback.length - 200)
              : feedback,
        );
      case 'save_review':
        final period = ReviewPeriod(
          type: _enum(ReviewType.values, data['type'] ?? 'week'),
          startsOn: _date(data['startsOn']),
          endsOn: _date(data['endsOn']),
        );
        if (period.endsOn.isBefore(period.startsOn) ||
            period.endsOn.difference(period.startsOn).inDays > 366) {
          throw const AgentException('复盘日期范围无效。');
        }
        final measured = await _reviews.loadSnapshot(period);
        final stats = await StatisticsRepository(
          _database,
          userId,
        ).load(now: _clock());
        final focus = _focusSeconds(
          stats.sessions,
          period.startsOn,
          period.endsOn.add(const Duration(days: 1)),
        );
        await _reviews.save(
          ReviewDraft(
            period: period,
            snapshot: ReviewSnapshot(
              dueCount: measured.dueCount,
              completedCount: measured.completedCount,
              timedSeconds: focus,
            ),
            happenedText: data['happenedText'] as String?,
            learnedText: data['learnedText'] as String?,
            improveText: data['improveText'] as String?,
            mood: data['mood'] as int?,
          ),
        );
        return workspace;
      default:
        throw const AgentException('不支持的智能体操作。');
    }
  }

  Future<void> _writeTaskSlot(
    String id,
    DateTime date,
    int start,
    int end, {
    bool recurring = false,
  }) async {
    _validRange(start, end);
    final type = recurring ? DayItemType.recurring : DayItemType.oneTime;
    final existing = (await _rows('daily_item_override_records'))
        .where(
          (r) =>
              r['item_id'] == id &&
              r['item_type'] == type.name &&
              r['local_date'] == localDateKey(date),
        )
        .firstOrNull;
    final savedOverride = await _schedule.saveDailyOverride(
      DailyItemOverrideDraft(
        itemType: type,
        itemId: id,
        localDate: dateOnly(date),
        action: DayOverrideAction.reschedule,
        plannedStartMinute: start,
        plannedEndMinute: end,
        targetDurationSeconds: (end - start) * 60,
      ),
      overrideId: existing?['id'] as String?,
    );
    await _showOverride(savedOverride);
  }

  Future<void> _softArchiveForTask(String id) async {
    for (final table in ['daily_item_override_records']) {
      final column = table == 'daily_item_override_records'
          ? 'item_id'
          : 'owner_id';
      final rows = (await _rows(
        table,
      )).where((r) => r[column] == id && r['deleted_at'] == null);
      for (final row in rows) {
        await _softArchive(table, row['id'] as String);
        await _queue.enqueue(
          entityType: table == 'daily_item_override_records'
              ? 'daily_item_overrides'
              : 'reminder_rules',
          entityId: row['id'] as String,
          operation: SyncOperationType.archive,
          payload: {
            'id': row['id'],
            'deleted_at': _clock().toUtc().toIso8601String(),
          },
          userId: userId,
        );
      }
    }
  }

  Future<void> _showOverride(String id) =>
      (_database.update(
        _database.dailyItemOverrideRecords,
      )..where((row) => row.id.equals(id) & row.userId.equals(userId))).write(
        const DailyItemOverrideRecordsCompanion(deletedAt: Value(null)),
      );

  Future<TaskDetails> _requireTask(String id, {DateTime? date}) async {
    final task = await _tasks.getTask(id, date: date);
    if (task == null) {
      throw const AgentException('事项不存在或不属于当前账号。', code: 'not_owned');
    }
    return task;
  }

  Future<void> _protectTask(TaskDetails task) async {
    if (task.isCompleted) {
      throw const AgentException(
        '已完成事项不会被智能体重新安排，请先明确调整。',
        code: 'completed_task',
      );
    }
    final timers = await _tasks.getUnfinishedTimers();
    if (timers.any((timer) => timer.taskId == task.id)) {
      throw const AgentException('请先结束该事项的计时，再调整安排。', code: 'active_timer');
    }
  }

  Future<Map<String, Object?>> _requireRow(String table, String id) async {
    final row = (await _rows(table)).where((r) => r['id'] == id).firstOrNull;
    if (row == null || row['deleted_at'] != null) {
      throw const AgentException('记录不存在或不属于当前账号。', code: 'not_owned');
    }
    return row;
  }

  Future<void> _assertAliasFree(
    String alias,
    Map<String, String> aliases,
  ) async {
    _proposalId(alias);
    if (aliases.containsKey(alias)) throw const AgentException('新记录编号重复。');
    for (final table in [
      'local_tasks',
      'course_records',
      'plan_records',
      'tag_records',
    ]) {
      final row = await _database
          .customSelect(
            'SELECT 1 FROM $table WHERE id = ? LIMIT 1',
            variables: [Variable<String>(alias)],
          )
          .get();
      if (row.isNotEmpty) throw const AgentException('新记录临时编号与已有记录冲突。');
    }
  }

  Map<String, Object?> _taskData(TaskDetails task) => {
    'kind': task.kind.name,
    'name': task.name,
    'colorValue': task.colorValue,
    'iconName': task.iconName,
    'tagId': task.tagId,
    'notes': task.notes,
    'executionMode': task.kind == TaskKind.recurring
        ? task.recurringMode?.name
        : task.oneTimeExecutionMode?.name,
    'targetDurationSeconds': task.targetDurationSeconds,
    'targetDays': task.targetDays,
    'holidayPause': task.holidayPause,
    'scheduledMinuteOfDay': task.scheduledMinuteOfDay,
    'reminderMinuteOfDay': task.reminderMinuteOfDay,
    if (task.schedule != null) 'schedulePreset': task.schedule!.preset.name,
    if (task.schedule != null)
      'weekdays': WeekdayMask.toDays(task.schedule!.weekdaysMask).toList(),
    if (task.schedule != null)
      'startsOn': localDateKey(task.schedule!.startsOn),
    if (task.schedule?.endsOn != null)
      'endsOn': localDateKey(task.schedule!.endsOn!),
    'scheduledAt': task.scheduledAt?.toIso8601String(),
    'plannedDate': task.plannedDate == null
        ? null
        : localDateKey(task.plannedDate!),
    'availableFrom': task.availableFrom == null
        ? null
        : localDateKey(task.availableFrom!),
    'dueDate': task.deadline?.date == null
        ? null
        : localDateKey(task.deadline!.date!),
    'dueAt': task.deadline?.at?.toIso8601String(),
    'remindBeforeMinutes': task.remindBeforeMinutes,
  };

  Map<String, Object?> _planningWorkspace(AgentWorkspace workspace) => {
    'profile': workspace.profile,
    'goals': workspace.goals,
    'busyPeriods': workspace.busyPeriods,
    'feedback': workspace.feedback,
    'taskLinks': workspace.taskLinks,
  };
  AgentWorkspace _withPlanningWorkspace(
    AgentWorkspace original,
    Map<String, Object?> data,
  ) {
    List<Map<String, Object?>> rows(String key) =>
        (data[key] as List? ?? const [])
            .map((r) => Map<String, Object?>.from(r as Map))
            .toList();
    return original.copyWith(
      profile: Map<String, Object?>.from(data['profile'] as Map),
      goals: rows('goals'),
      busyPeriods: rows('busyPeriods'),
      feedback: rows('feedback'),
      taskLinks: rows('taskLinks'),
    );
  }

  List<Map<String, Object?>> _delta(
    Map<String, List<Map<String, Object?>>> before,
    Map<String, List<Map<String, Object?>>> after,
  ) {
    final changes = <Map<String, Object?>>[];
    for (final table in _planningTables.keys) {
      final prior = {
        for (final row in before[table]!) _identity(table, row): row,
      };
      final next = {
        for (final row in after[table]!) _identity(table, row): row,
      };
      for (final key in {...prior.keys, ...next.keys}) {
        if (_canonical(prior[key]) != _canonical(next[key])) {
          changes.add({
            'table': table,
            'identity': key,
            'before': prior[key],
            'after': next[key],
          });
        }
      }
    }
    return changes;
  }

  String _identity(String table, Map<String, Object?> row) =>
      jsonEncode([for (final key in _planningTables[table]!) row[key]]);

  Future<void> _restoreRow(String table, Map<String, Object?> before) async {
    if (before['user_id'] != userId) throw const AgentException('历史记录不属于当前账号。');
    final columns =
        (await _database.customSelect('PRAGMA table_info($table)').get())
            .map((r) => r.read<String>('name'))
            .toSet();
    if (!before.keys.every(columns.contains)) {
      throw const AgentException('历史字段无效。');
    }
    final values = {
      ...before,
      if (before.containsKey('updated_at'))
        'updated_at': _clock().toUtc().millisecondsSinceEpoch ~/ 1000,
    };
    final names = values.keys.toList();
    final primary = _planningTables[table]!;
    final updateNames = names
        .where(
          (name) =>
              !primary.contains(name) &&
              name != 'user_id' &&
              !(table == 'one_time_reminder_records' && name == 'completed_at'),
        )
        .toList();
    await _database.customUpdate(
      'INSERT INTO $table (${names.join(',')}) VALUES (${List.filled(names.length, '?').join(',')}) '
      'ON CONFLICT (${primary.join(',')}) DO UPDATE SET ${updateNames.map((n) => '$n=excluded.$n').join(',')}',
      variables: [for (final name in names) _variable(values[name])],
      updates: _updatedTables,
    );
  }

  Future<void> _archiveNewRow(String table, Map<String, Object?> row) async {
    final id = row['id'] as String?;
    switch (table) {
      case 'local_tasks':
        await _tasks.archiveTask(id!);
      case 'course_records':
        await _courses.archiveCourse(id!);
      case 'plan_records':
        await _plans.archive(id!);
      case 'tag_records':
        await _tags.setArchived(id!, true);
      case 'plan_task_records':
        await _database.customUpdate(
          'DELETE FROM plan_task_records WHERE user_id = ? AND plan_id = ? AND task_id = ?',
          variables: [
            Variable<String>(userId),
            _variable(row['plan_id']),
            _variable(row['task_id']),
          ],
          updates: _updatedTables,
        );
      default:
        if (row.containsKey('deleted_at') && id != null) {
          await _softArchive(table, id);
        }
      // Task detail rows remain attached to the archived task. No timer or
      // completion fact is deleted, including facts created after planning.
    }
  }

  Future<void> _softArchive(String table, String id) async {
    await _database.customUpdate(
      'UPDATE $table SET deleted_at = ?, updated_at = ? WHERE id = ? AND user_id = ?',
      variables: [
        Variable<int>(_clock().toUtc().millisecondsSinceEpoch ~/ 1000),
        Variable<int>(_clock().toUtc().millisecondsSinceEpoch ~/ 1000),
        Variable<String>(id),
        Variable<String>(userId),
      ],
      updates: _updatedTables,
    );
  }

  Set<TableInfo<Table, Object?>> get _updatedTables => {
    _database.localTasks,
    _database.longTermTaskRecords,
    _database.taskScheduleRecords,
    _database.oneTimeReminderRecords,
    _database.courseRecords,
    _database.courseScheduleRuleRecords,
    _database.dailyItemOverrideRecords,
    _database.reminderRuleRecords,
    _database.alarmRuleRecords,
    _database.planRecords,
    _database.planTaskRecords,
    _database.tagRecords,
    _database.reviewRecords,
  };
  (String, String)? _outboxTarget(String table, Map<String, Object?> row) =>
      switch (table) {
        'local_tasks' => ('tasks', row['id'] as String),
        'long_term_task_records' ||
        'task_schedule_records' ||
        'one_time_reminder_records' => ('tasks', row['task_id'] as String),
        'course_records' => ('courses', row['id'] as String),
        'course_schedule_rule_records' => (
          'course_schedule_rules',
          row['id'] as String,
        ),
        'daily_item_override_records' => (
          'daily_item_overrides',
          row['id'] as String,
        ),
        'reminder_rule_records' => ('reminder_rules', row['id'] as String),
        'alarm_rule_records' => ('alarm_rules', row['id'] as String),
        'plan_records' => ('plans', row['id'] as String),
        'plan_task_records' => ('plan_tasks', row['plan_id'] as String),
        'tag_records' => ('tags', row['id'] as String),
        'review_records' => ('reviews', row['id'] as String),
        _ => null,
      };
  Future<void> _recordTaskRestoration(TaskDetails task) async {
    final draft = _taskData(task);
    final snapshot = {
      'id': task.id,
      'name': task.name,
      'type': task.kind.name,
      'color': task.colorValue,
      'icon_name': task.iconName,
      'tag_id': task.tagId,
      'status': task.status.name,
      'notes': task.notes,
      'check_mode': task.recurringMode?.name,
      'target_duration_seconds': task.targetDurationSeconds,
      'target_days': task.targetDays,
      'holiday_pause': task.holidayPause,
      'scheduled_minute_of_day': task.scheduledMinuteOfDay,
      'reminder_minute_of_day': task.reminderMinuteOfDay,
      'schedule_type': draft['schedulePreset'],
      'weekdays': draft['weekdays'],
      'starts_on': draft['startsOn'],
      'ends_on': draft['endsOn'],
      'scheduled_at': draft['scheduledAt'],
      'available_from': draft['availableFrom'],
      'planned_date': draft['plannedDate'],
      'due_date': draft['dueDate'],
      'due_at': draft['dueAt'],
      'is_timed': task.hasTimer,
    };
    await _database
        .into(_database.taskRevisionRecords)
        .insert(
          TaskRevisionRecordsCompanion.insert(
            id: _uuid.v4(),
            taskId: task.id,
            userId: userId,
            afterJson: jsonEncode(snapshot),
            changedAt: _clock().toUtc(),
          ),
        );
  }

  Future<List<Map<String, Object?>>> pendingNotices() async =>
      (await loadWorkspace()).notices.where((n) => n['seen'] != true).toList();
  Future<void> markNoticeSeen(String id) => _database.transaction(() async {
    final workspace = await loadWorkspace();
    await _save(
      workspace.copyWith(
        notices: [
          if (!workspace.notices.any((n) => n['id'] == id))
            {'id': id, 'seen': true},
          for (final n in workspace.notices)
            if (n['id'] == id) {...n, 'seen': true} else n,
        ],
      ),
    );
  });

  static Map<String, Object?> _contextRow(Map<String, Object?> row) {
    const times = {
      'created_at',
      'updated_at',
      'started_at',
      'ended_at',
      'scheduled_at',
      'due_at',
      'completed_at',
      'first_week_start_date',
      'semester_starts_on',
      'semester_ends_on',
      'current_started_at',
      'deleted_at',
    };
    return {
      for (final entry in row.entries)
        if (entry.key != 'user_id')
          entry.key.replaceAllMapped(
            RegExp(r'_([a-z])'),
            (match) => match[1]!.toUpperCase(),
          ): times.contains(entry.key) && entry.value is int
              ? DateTime.fromMillisecondsSinceEpoch(
                  (entry.value as int) * 1000,
                  isUtc: true,
                ).toLocal().toIso8601String()
              : entry.value,
    };
  }

  static void _rejectFacts(Map<String, Object?> data) {
    const forbidden = {
      'userId',
      'user_id',
      'sql',
      'code',
      'timerStatus',
      'completionStatus',
      'completedAt',
      'isSuccess',
      'actualDurationSeconds',
      'targetReached',
      'snapshot',
    };
    if (data.keys.any(forbidden.contains)) {
      throw const AgentException(
        '智能体不能直接写账号身份、实际计时或完成事实。',
        code: 'forbidden_fact_write',
      );
    }
  }

  static void _proposalId(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,160}$').hasMatch(id)) {
      throw const AgentException('提案或临时编号无效。');
    }
  }

  static String _string(
    Map<String, Object?> data,
    String key, {
    String? fallback,
  }) {
    final value = data[key] ?? fallback;
    if (value is! String || value.trim().isEmpty || value.length > 12000) {
      throw AgentException('请填写有效的 $key。');
    }
    return value.trim();
  }

  static int _int(Map<String, Object?> data, String key, {int? fallback}) {
    final value = data[key] ?? fallback;
    if (value is! int) throw AgentException('$key 应为整数。');
    return value;
  }

  static List<int> _ints(Object? value) {
    if (value is! List || value.any((v) => v is! int)) {
      throw const AgentException('星期或周次格式无效。');
    }
    return value.cast<int>();
  }

  static T _enum<T extends Enum>(List<T> values, Object? value) {
    final result = values.where((v) => v.name == value).firstOrNull;
    if (result == null) throw const AgentException('选项值无效。');
    return result;
  }

  static DateTime _date(Object? value) {
    final date = value is String ? DateTime.tryParse(value) : null;
    if (date == null) throw const AgentException('日期格式无效，请使用完整日期。');
    final local = date.toLocal();
    if (value is String &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
        localDateKey(local) != value) {
      throw const AgentException('日期不存在，请使用有效日期。');
    }
    return local;
  }

  static DateTime? _dateOrNull(Object? value) =>
      value == null || value == '' ? null : _date(value);
  static TaskDeadline? _deadline(Map<String, Object?> data) {
    if (data['dueAt'] != null) return TaskDeadline.exact(_date(data['dueAt']));
    if (data['dueDate'] != null) {
      return TaskDeadline.dateOnly(_date(data['dueDate']));
    }
    final deadline = data['deadline'];
    if (deadline is Map) {
      if (deadline['at'] != null) {
        return TaskDeadline.exact(_date(deadline['at']));
      }
      if (deadline['date'] != null) {
        return TaskDeadline.dateOnly(_date(deadline['date']));
      }
    }
    return null;
  }

  static void _validRange(int? start, int? end) {
    if (start == null ||
        end == null ||
        start < 0 ||
        end > 1440 ||
        end <= start) {
      throw const AgentException('时间段无效，不能跨越午夜。');
    }
  }

  static Object? _sorted(Object? value) => value is Map
      ? {
          for (final key
              in value.keys.map((k) => k.toString()).toList()..sort())
            key: _sorted(value[key]),
        }
      : value is List
      ? value.map(_sorted).toList()
      : value;
  static String _canonical(Object? value) => jsonEncode(_sorted(value));
  static Map<String, Object?>? _undoComparable(Map<String, Object?>? row) =>
      row == null
      ? null
      : {
          for (final entry in row.entries)
            if (!{'updated_at', 'sync_version'}.contains(entry.key))
              entry.key: entry.value,
        };
  static Variable _variable(Object? value) => switch (value) {
    int value => Variable<int>(value),
    double value => Variable<double>(value),
    String value => Variable<String>(value),
    bool value => Variable<bool>(value),
    null => const Variable<String>(null),
    _ => throw const AgentException('历史字段类型无效。'),
  };
  int _focusSeconds(List<TimeEntry> sessions, DateTime start, DateTime end) {
    final intervals =
        sessions
            .map((s) => s.intervalWithin(start, end, _clock()))
            .whereType<ActiveInterval>()
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    DateTime? from, through;
    var seconds = 0;
    for (final interval in intervals) {
      if (through == null || interval.start.isAfter(through)) {
        if (from != null && through != null) {
          seconds += through.difference(from).inSeconds;
        }
        from = interval.start;
        through = interval.end;
      } else if (interval.end.isAfter(through)) {
        through = interval.end;
      }
    }
    if (from != null && through != null) {
      seconds += through.difference(from).inSeconds;
    }
    return seconds;
  }

  static String _fingerprint(Object? value) {
    final encoded = utf8.encode(_canonical(value));
    var first = 0x811c9dc5, second = 5381;
    for (final byte in encoded) {
      first = ((first ^ byte) * 16777619) & 0xffffffff;
      second = ((second * 33) ^ byte) & 0xffffffff;
    }
    return '${first.toRadixString(16).padLeft(8, '0')}${second.toRadixString(16).padLeft(8, '0')}-${encoded.length}';
  }
}
