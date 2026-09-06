import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class LocalTasks extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get taskType => text()();
  IntColumn get colorValue => integer()();
  TextColumn get iconName => text().withDefault(const Constant('target'))();
  TextColumn get tagId => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncVersion => integer().withDefault(const Constant(0))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LongTermTaskRecords extends Table {
  TextColumn get taskId =>
      text().references(LocalTasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get userId => text()();
  TextColumn get checkMode => text()();
  IntColumn get targetDurationSeconds => integer().nullable()();
  IntColumn get targetDays => integer().nullable()();
  BoolColumn get holidayPause => boolean().withDefault(const Constant(false))();
  IntColumn get scheduledMinuteOfDay => integer().nullable()();
  IntColumn get reminderMinuteOfDay => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {taskId};
}

class TaskScheduleRecords extends Table {
  TextColumn get id => text()();
  TextColumn get taskId =>
      text().references(LocalTasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get userId => text()();
  TextColumn get scheduleType => text()();
  IntColumn get weekdaysMask => integer()();
  TextColumn get startsOn => text()();
  TextColumn get endsOn => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class OneTimeReminderRecords extends Table {
  TextColumn get taskId =>
      text().references(LocalTasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get userId => text()();
  DateTimeColumn get scheduledAt => dateTime()();
  BoolColumn get hasScheduledDate =>
      boolean().withDefault(const Constant(true))();
  IntColumn get remindBeforeMinutes => integer().nullable()();
  BoolColumn get isTimed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {taskId};
}

class TaskCompletionRecords extends Table {
  TextColumn get id => text()();
  TextColumn get taskId =>
      text().references(LocalTasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get userId => text()();
  TextColumn get localDate => text()();
  IntColumn get actualDurationSeconds =>
      integer().withDefault(const Constant(0))();
  RealColumn get progressPercent => real().withDefault(const Constant(0))();
  BoolColumn get targetReached =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isSuccess => boolean().withDefault(const Constant(false))();
  TextColumn get exclusionReason => text().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {taskId, localDate},
  ];
}

class TimerSessionRecords extends Table {
  TextColumn get id => text()();
  TextColumn get taskId =>
      text().references(LocalTasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get userId => text()();
  TextColumn get tagId => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  // Recurring completion belongs to the local day on which the timer began.
  TextColumn get logicalDate => text().nullable()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  TextColumn get state => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TaskRevisionRecords extends Table {
  TextColumn get id => text()();
  TextColumn get taskId =>
      text().references(LocalTasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get userId => text()();
  TextColumn get beforeJson => text().nullable()();
  TextColumn get afterJson => text()();
  DateTimeColumn get changedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SyncOperations extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class TagRecords extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  IntColumn get colorValue => integer()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TagRevisionRecords extends Table {
  TextColumn get id => text()();
  TextColumn get tagId => text().references(TagRecords, #id)();
  TextColumn get userId => text()();
  TextColumn get snapshotJson => text()();
  DateTimeColumn get changedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PlanRecords extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get type => text()();
  IntColumn get colorValue => integer()();
  TextColumn get goal => text().nullable()();
  TextColumn get startsOn => text()();
  TextColumn get endsOn => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PlanTaskRecords extends Table {
  TextColumn get planId =>
      text().references(PlanRecords, #id, onDelete: KeyAction.cascade)();
  TextColumn get taskId =>
      text().references(LocalTasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get userId => text()();
  RealColumn get weight => real().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {planId, taskId};
}

class ReviewRecords extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get reviewType => text()();
  TextColumn get periodStart => text()();
  TextColumn get periodEnd => text()();
  TextColumn get happenedText => text().nullable()();
  TextColumn get learnedText => text().nullable()();
  TextColumn get improveText => text().nullable()();
  IntColumn get mood => integer().nullable()();
  TextColumn get objectiveSnapshotJson =>
      text().withDefault(const Constant('{}'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {userId, reviewType, periodStart},
  ];
}

class CourseRecords extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  IntColumn get colorValue => integer()();
  TextColumn get teacher => text().nullable()();
  TextColumn get classroom => text().nullable()();
  TextColumn get semester => text().nullable()();
  // Nullable for courses created before the dedicated Semester model.
  TextColumn get semesterId => text().nullable()();
  DateTimeColumn get semesterStartsOn => dateTime().nullable()();
  DateTimeColumn get semesterEndsOn => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CourseScheduleRuleRecords extends Table {
  TextColumn get id => text()();
  TextColumn get courseId =>
      text().references(CourseRecords, #id, onDelete: KeyAction.cascade)();
  TextColumn get userId => text()();
  IntColumn get weekday => integer()();
  TextColumn get weekRuleType => text()();
  IntColumn get startWeek => integer().nullable()();
  IntColumn get endWeek => integer().nullable()();
  IntColumn get intervalWeeks => integer().nullable()();
  TextColumn get weekNumbersJson => text().withDefault(const Constant('[]'))();
  TextColumn get scheduleTemplateId => text().nullable()();
  TextColumn get sectionIdsJson => text().withDefault(const Constant('[]'))();
  TextColumn get timeMode => text().withDefault(const Constant('customTime'))();
  IntColumn get startsAtMinute => integer()();
  IntColumn get endsAtMinute => integer()();
  TextColumn get classroomOverride => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get remindBeforeMinutes => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ScheduleTemplateRecords extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get timezone =>
      text().withDefault(const Constant('Asia/Shanghai'))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ScheduleTemplateSegmentRecords extends Table {
  TextColumn get id => text()();
  TextColumn get templateId => text().references(
    ScheduleTemplateRecords,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  IntColumn get startsAtMinute => integer()();
  IntColumn get endsAtMinute => integer()();
  TextColumn get segmentType =>
      text().withDefault(const Constant('classTime'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SemesterRecords extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  DateTimeColumn get firstWeekStartDate => dateTime()();
  IntColumn get totalWeeks => integer()();
  TextColumn get scheduleTemplateId => text().nullable()();
  BoolColumn get isCurrent => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class DailyItemOverrideRecords extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get itemType => text()();
  TextColumn get itemId => text()();
  TextColumn get localDate => text()();
  TextColumn get action => text()();
  IntColumn get plannedStartMinute => integer().nullable()();
  IntColumn get plannedEndMinute => integer().nullable()();
  IntColumn get reminderMinuteOfDay => integer().nullable()();
  IntColumn get targetDurationSeconds => integer().nullable()();
  TextColumn get temporaryClassroom => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {userId, itemType, itemId, localDate},
  ];
}

class ReminderRuleRecords extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get ownerType => text()();
  TextColumn get ownerId => text()();
  TextColumn get reminderKind => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get scheduledMinuteOfDay => integer().nullable()();
  IntColumn get remindBeforeMinutes => integer().nullable()();
  TextColumn get localDate => text().nullable()();
  TextColumn get timezone =>
      text().withDefault(const Constant('Asia/Shanghai'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AlarmRuleRecords extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get ownerType => text()();
  TextColumn get ownerId => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();
  TextColumn get behavior => text().withDefault(const Constant('once'))();
  TextColumn get soundName => text().nullable()();
  IntColumn get snoozeMinutes => integer().nullable()();
  IntColumn get repeatIntervalMinutes => integer().nullable()();
  IntColumn get maxRingSeconds => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AdHocTimerRecords extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get title => text()();
  TextColumn get tagId => text().nullable()();
  IntColumn get colorValue => integer()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  TextColumn get timerStatus => text().withDefault(const Constant('idle'))();
  IntColumn get accumulatedDurationSeconds =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get currentStartedAt => dateTime().nullable()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Each row is one active interval of an ad-hoc timer. The parent timer keeps
/// its current UI state and cached elapsed duration; these rows are the source
/// of truth for pause-aware, cross-day statistics.
class AdHocTimerIntervalRecords extends Table {
  TextColumn get id => text()();
  TextColumn get timerId => text()();
  TextColumn get userId => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    LocalTasks,
    LongTermTaskRecords,
    TaskScheduleRecords,
    OneTimeReminderRecords,
    TaskCompletionRecords,
    TimerSessionRecords,
    TaskRevisionRecords,
    SyncOperations,
    AppSettings,
    TagRecords,
    TagRevisionRecords,
    PlanRecords,
    PlanTaskRecords,
    ReviewRecords,
    CourseRecords,
    CourseScheduleRuleRecords,
    ScheduleTemplateRecords,
    ScheduleTemplateSegmentRecords,
    SemesterRecords,
    DailyItemOverrideRecords,
    ReminderRuleRecords,
    AlarmRuleRecords,
    AdHocTimerRecords,
    AdHocTimerIntervalRecords,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 19;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    onUpgrade: (migrator, from, to) async {
      Future<bool> hasColumn(String table, String column) async {
        final columns = await customSelect('PRAGMA table_info($table)').get();
        return columns.any((row) => row.read<String>('name') == column);
      }

      Future<bool> hasTable(String table) async {
        final rows = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          variables: [Variable<String>(table)],
        ).get();
        return rows.isNotEmpty;
      }

      if (from < 2) {
        if (!await hasColumn('local_tasks', 'notes')) {
          await migrator.addColumn(localTasks, localTasks.notes);
        }
        await migrator.createTable(longTermTaskRecords);
        await migrator.createTable(taskScheduleRecords);
        await migrator.createTable(oneTimeReminderRecords);
        await migrator.createTable(taskCompletionRecords);
        await migrator.createTable(taskRevisionRecords);
      }
      if (from < 3) {
        await migrator.createTable(timerSessionRecords);
      }
      if (from < 4) {
        if (!await hasColumn('local_tasks', 'icon_name')) {
          await migrator.addColumn(localTasks, localTasks.iconName);
        }
      }
      if (from < 5) {
        if (from >= 2) {
          if (!await hasColumn('one_time_reminder_records', 'is_timed')) {
            await migrator.addColumn(
              oneTimeReminderRecords,
              oneTimeReminderRecords.isTimed,
            );
          }
          if (!await hasColumn('task_completion_records', 'target_reached')) {
            await migrator.addColumn(
              taskCompletionRecords,
              taskCompletionRecords.targetReached,
            );
          }
        }
        await customStatement(
          "UPDATE long_term_task_records SET check_mode = 'targetTimer' "
          "WHERE check_mode = 'timer'",
        );
        await customStatement(
          'UPDATE task_completion_records '
          'SET target_reached = CASE WHEN actual_duration_seconds >= '
          '(SELECT target_duration_seconds FROM long_term_task_records '
          'WHERE task_id = task_completion_records.task_id) THEN 1 ELSE 0 END '
          'WHERE task_id IN (SELECT task_id FROM long_term_task_records '
          "WHERE check_mode = 'targetTimer')",
        );
      }
      if (from < 6) {
        await migrator.createTable(tagRecords);
        await migrator.createTable(tagRevisionRecords);
        if (!await hasColumn('local_tasks', 'tag_id')) {
          await migrator.addColumn(localTasks, localTasks.tagId);
        }
        if (from >= 3) {
          if (!await hasColumn('timer_session_records', 'tag_id')) {
            await migrator.addColumn(
              timerSessionRecords,
              timerSessionRecords.tagId,
            );
          }
        }
      }
      if (from < 7) {
        // Preserve old records while unifying the public recurring-task model.
        final taskColumns = await customSelect(
          'PRAGMA table_info(local_tasks)',
        ).get();
        if (taskColumns.any((row) => row.read<String>('name') == 'task_type')) {
          await customStatement(
            "UPDATE local_tasks SET task_type = 'recurring' "
            "WHERE task_type IN ('longTerm', 'long_term')",
          );
        }
        final recurringColumns = await customSelect(
          'PRAGMA table_info(long_term_task_records)',
        ).get();
        if (recurringColumns.any(
          (row) => row.read<String>('name') == 'check_mode',
        )) {
          await customStatement(
            "UPDATE long_term_task_records SET check_mode = 'timed' "
            "WHERE check_mode IN ('timer', 'targetTimer', 'target_timer', "
            "'freeTimer', 'free_timer')",
          );
          await customStatement(
            "UPDATE long_term_task_records SET check_mode = 'untimed' "
            "WHERE check_mode = 'simple'",
          );
        }
      }
      if (from < 8) {
        await migrator.createTable(planRecords);
        await migrator.createTable(planTaskRecords);
      }
      if (from < 9) {
        await migrator.createTable(reviewRecords);
      }
      if (from < 10) {
        if (await hasColumn('long_term_task_records', 'task_id') &&
            !await hasColumn(
              'long_term_task_records',
              'scheduled_minute_of_day',
            )) {
          await migrator.addColumn(
            longTermTaskRecords,
            longTermTaskRecords.scheduledMinuteOfDay,
          );
        }
        if (await hasColumn('one_time_reminder_records', 'task_id') &&
            !await hasColumn(
              'one_time_reminder_records',
              'has_scheduled_date',
            )) {
          await migrator.addColumn(
            oneTimeReminderRecords,
            oneTimeReminderRecords.hasScheduledDate,
          );
        }
      }
      if (from < 11) {
        await migrator.createTable(courseRecords);
        await migrator.createTable(courseScheduleRuleRecords);
        await migrator.createTable(scheduleTemplateRecords);
        await migrator.createTable(scheduleTemplateSegmentRecords);
        await migrator.createTable(dailyItemOverrideRecords);
        await migrator.createTable(reminderRuleRecords);
        await migrator.createTable(alarmRuleRecords);
        await migrator.createTable(adHocTimerRecords);
      }
      if (from < 12) {
        // Version 11 creates the course table from the current schema. Older
        // databases still need these fields, so add each one only when absent.
        final courseColumns = await customSelect(
          'PRAGMA table_info(course_records)',
        ).get();
        final courseColumnNames = courseColumns
            .map((row) => row.read<String>('name'))
            .toSet();
        if (!courseColumnNames.contains('semester_starts_on')) {
          await migrator.addColumn(
            courseRecords,
            courseRecords.semesterStartsOn,
          );
        }
        if (!courseColumnNames.contains('semester_ends_on')) {
          await migrator.addColumn(courseRecords, courseRecords.semesterEndsOn);
        }
      }
      if (from < 13) {
        final adHocColumns = await customSelect(
          'PRAGMA table_info(ad_hoc_timer_records)',
        ).get();
        final adHocColumnNames = adHocColumns
            .map((row) => row.read<String>('name'))
            .toSet();
        if (!adHocColumnNames.contains('timer_status')) {
          await migrator.addColumn(
            adHocTimerRecords,
            adHocTimerRecords.timerStatus,
          );
        }
        if (!adHocColumnNames.contains('accumulated_duration_seconds')) {
          await migrator.addColumn(
            adHocTimerRecords,
            adHocTimerRecords.accumulatedDurationSeconds,
          );
        }
        if (!adHocColumnNames.contains('current_started_at')) {
          await migrator.addColumn(
            adHocTimerRecords,
            adHocTimerRecords.currentStartedAt,
          );
        }
      }
      if (from < 14) {
        // This table is additive. Existing ad-hoc rows retain their cached
        // duration and remain readable; intervals are recorded from now on.
        await migrator.createTable(adHocTimerIntervalRecords);
      }
      if (from < 15 &&
          !await hasColumn('timer_session_records', 'logical_date')) {
        await migrator.addColumn(
          timerSessionRecords,
          timerSessionRecords.logicalDate,
        );
      }
      if (from < 16 && !await hasTable('semester_records')) {
        await migrator.createTable(semesterRecords);
      }
      if (from < 17 && !await hasColumn('course_records', 'semester_id')) {
        await migrator.addColumn(courseRecords, courseRecords.semesterId);
      }
      if (from < 18) {
        if (!await hasColumn('course_schedule_rule_records', 'time_mode')) {
          await migrator.addColumn(
            courseScheduleRuleRecords,
            courseScheduleRuleRecords.timeMode,
          );
        }
        if (!await hasColumn(
          'course_schedule_rule_records',
          'classroom_override',
        )) {
          await migrator.addColumn(
            courseScheduleRuleRecords,
            courseScheduleRuleRecords.classroomOverride,
          );
        }
        if (!await hasColumn('course_schedule_rule_records', 'notes')) {
          await migrator.addColumn(
            courseScheduleRuleRecords,
            courseScheduleRuleRecords.notes,
          );
        }
      }
      // A released v17 build could carry the schema version forward without
      // the interval table that was introduced for Multi Timer in v14. Keep
      // this repair as a later, idempotent migration so those IndexedDB users
      // are upgraded safely too.
      if (from < 19) {
        if (!await hasTable('ad_hoc_timer_records')) {
          await migrator.createTable(adHocTimerRecords);
        }
        if (!await hasTable('ad_hoc_timer_interval_records')) {
          await migrator.createTable(adHocTimerIntervalRecords);
        }
        if (await hasTable('ad_hoc_timer_records')) {
          if (!await hasColumn('ad_hoc_timer_records', 'timer_status')) {
            await migrator.addColumn(
              adHocTimerRecords,
              adHocTimerRecords.timerStatus,
            );
          }
          if (!await hasColumn(
            'ad_hoc_timer_records',
            'accumulated_duration_seconds',
          )) {
            await migrator.addColumn(
              adHocTimerRecords,
              adHocTimerRecords.accumulatedDurationSeconds,
            );
          }
          if (!await hasColumn('ad_hoc_timer_records', 'current_started_at')) {
            await migrator.addColumn(
              adHocTimerRecords,
              adHocTimerRecords.currentStartedAt,
            );
          }
        }
        if (await hasTable('timer_session_records') &&
            !await hasColumn('timer_session_records', 'logical_date')) {
          await migrator.addColumn(
            timerSessionRecords,
            timerSessionRecords.logicalDate,
          );
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // Drift only runs onUpgrade when the stored schema version changes. A
      // historical Web release could nevertheless mark a database upgraded
      // while omitting this Multi Timer table. Repair that state on every
      // open; CREATE IF NOT EXISTS is safe for fresh and correct databases.
      await customStatement('''
        CREATE TABLE IF NOT EXISTS ad_hoc_timer_interval_records (
          id TEXT NOT NULL PRIMARY KEY,
          timer_id TEXT NOT NULL,
          user_id TEXT NOT NULL,
          started_at INTEGER NOT NULL,
          ended_at INTEGER NULL,
          duration_seconds INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await customStatement(
        'CREATE INDEX IF NOT EXISTS ad_hoc_timer_interval_timer_idx '
        'ON ad_hoc_timer_interval_records (timer_id)',
      );
    },
  );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'check_d',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
      native: const DriftNativeOptions(shareAcrossIsolates: true),
    );
  }
}
