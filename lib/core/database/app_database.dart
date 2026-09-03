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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(localTasks, localTasks.notes);
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
        await migrator.addColumn(localTasks, localTasks.iconName);
      }
      if (from < 5) {
        if (from >= 2) {
          await migrator.addColumn(
            oneTimeReminderRecords,
            oneTimeReminderRecords.isTimed,
          );
          await migrator.addColumn(
            taskCompletionRecords,
            taskCompletionRecords.targetReached,
          );
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
        await migrator.addColumn(localTasks, localTasks.tagId);
        if (from >= 3) {
          await migrator.addColumn(
            timerSessionRecords,
            timerSessionRecords.tagId,
          );
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
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
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
