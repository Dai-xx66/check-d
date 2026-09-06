import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_queue_service.dart';
import '../domain/course_models.dart';

class SemesterRepository {
  SemesterRepository({
    required AppDatabase database,
    required SyncQueueService syncQueue,
    required String userId,
  }) : _database = database,
       _syncQueue = syncQueue,
       _userId = userId;

  final AppDatabase _database;
  final SyncQueueService _syncQueue;
  final String _userId;
  final Uuid _uuid = const Uuid();

  Stream<List<SemesterDetails>> watchSemesters() async* {
    final query = _database.select(_database.semesterRecords)
      ..where((row) => row.userId.equals(_userId) & row.deletedAt.isNull())
      ..orderBy([
        (row) => OrderingTerm.desc(row.isCurrent),
        (row) => OrderingTerm.desc(row.firstWeekStartDate),
      ]);
    List<SemesterDetails> map(List<SemesterRecord> rows) =>
        rows.map(_toDetails).toList();
    yield map(await query.get());
    yield* query.watch().map(map);
  }

  Stream<SemesterDetails?> watchCurrentSemester() {
    final query = _database.select(_database.semesterRecords)
      ..where(
        (row) =>
            row.userId.equals(_userId) &
            row.deletedAt.isNull() &
            row.isCurrent.equals(true),
      )
      ..limit(1);
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : _toDetails(row),
    );
  }

  Future<String> saveSemester(SemesterDraft draft, {String? semesterId}) async {
    _validate(draft);
    if (draft.scheduleTemplateId != null) {
      final template =
          await (_database.select(_database.scheduleTemplateRecords)..where(
                (row) =>
                    row.id.equals(draft.scheduleTemplateId!) &
                    row.userId.equals(_userId) &
                    row.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (template == null) throw ArgumentError('请选择有效的作息模板');
    }
    final now = DateTime.now().toUtc();
    final id = semesterId ?? _uuid.v4();
    await _database.transaction(() async {
      if (draft.isCurrent) {
        await (_database.update(_database.semesterRecords)..where(
              (row) =>
                  row.userId.equals(_userId) &
                  row.id.equals(id).not() &
                  row.deletedAt.isNull(),
            ))
            .write(
              SemesterRecordsCompanion(
                isCurrent: const Value(false),
                updatedAt: Value(now),
              ),
            );
      }
      await _database
          .into(_database.semesterRecords)
          .insertOnConflictUpdate(
            SemesterRecordsCompanion.insert(
              id: id,
              userId: _userId,
              name: draft.name.trim(),
              firstWeekStartDate: _dateOnlyUtc(draft.firstWeekStartDate),
              totalWeeks: draft.totalWeeks,
              scheduleTemplateId: Value(draft.scheduleTemplateId),
              isCurrent: Value(draft.isCurrent),
              createdAt: now,
              updatedAt: now,
            ),
          );
    });
    await _syncQueue.enqueue(
      entityType: 'semesters',
      entityId: id,
      operation: SyncOperationType.upsert,
      payload: {
        'id': id,
        'name': draft.name.trim(),
        'first_week_start_date': _dateOnlyUtc(
          draft.firstWeekStartDate,
        ).toIso8601String(),
        'total_weeks': draft.totalWeeks,
        'schedule_template_id': draft.scheduleTemplateId,
        'is_current': draft.isCurrent,
        'updated_at': now.toIso8601String(),
      },
      userId: _userId,
    );
    return id;
  }

  Future<void> setCurrentSemester(String semesterId) async {
    final semester =
        await (_database.select(_database.semesterRecords)..where(
              (row) =>
                  row.id.equals(semesterId) &
                  row.userId.equals(_userId) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (semester == null) throw StateError('找不到该学期');
    await saveSemester(
      SemesterDraft(
        name: semester.name,
        firstWeekStartDate: semester.firstWeekStartDate.toLocal(),
        totalWeeks: semester.totalWeeks,
        scheduleTemplateId: semester.scheduleTemplateId,
        isCurrent: true,
      ),
      semesterId: semester.id,
    );
  }

  SemesterDetails _toDetails(SemesterRecord row) => SemesterDetails(
    id: row.id,
    name: row.name,
    firstWeekStartDate: row.firstWeekStartDate.toLocal(),
    totalWeeks: row.totalWeeks,
    scheduleTemplateId: row.scheduleTemplateId,
    isCurrent: row.isCurrent,
    createdAt: row.createdAt.toLocal(),
    updatedAt: row.updatedAt.toLocal(),
  );

  DateTime _dateOnlyUtc(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  void _validate(SemesterDraft draft) {
    if (draft.name.trim().isEmpty) {
      throw ArgumentError.value(draft.name, 'name', '请填写学期名称');
    }
    if (draft.totalWeeks <= 0 || draft.totalWeeks > 60) {
      throw ArgumentError.value(
        draft.totalWeeks,
        'totalWeeks',
        '总周数需在 1 到 60 周之间',
      );
    }
  }
}
