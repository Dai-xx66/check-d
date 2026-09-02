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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

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
