import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/features/planning/data/planning_plan_repository.dart';

void main() {
  late AppDatabase database;
  final now = DateTime.utc(2026, 11, 15, 1);

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database
        .into(database.localTasks)
        .insert(
          LocalTasksCompanion.insert(
            id: 'task-a',
            userId: const Value('user-a'),
            name: '合成任务',
            taskType: 'one_time',
            colorValue: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.localTasks)
        .insert(
          LocalTasksCompanion.insert(
            id: 'task-b',
            userId: const Value('user-b'),
            name: '另一用户任务',
            taskType: 'one_time',
            colorValue: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() => database.close());

  test(
    'confirmed multi-block plan is persisted and idempotent per owner',
    () async {
      final repository = PlanningPlanRepository(
        database: database,
        userId: 'user-a',
      );
      var versionReads = 0;
      Future<String> currentVersion() async {
        versionReads++;
        return 'snapshot-1';
      }

      final blocks = [
        CandidatePlanBlock(
          taskId: 'task-a',
          startsAt: now.add(const Duration(hours: 1)),
          endsAt: now.add(const Duration(hours: 1, minutes: 30)),
          plannedSeconds: 1800,
        ),
        CandidatePlanBlock(
          taskId: 'task-a',
          startsAt: now.add(const Duration(hours: 3)),
          endsAt: now.add(const Duration(hours: 3, minutes: 30)),
          plannedSeconds: 1800,
        ),
      ];
      final saved = await repository.confirmPlan(
        expectedSnapshotVersion: 'snapshot-1',
        readCurrentSnapshotVersion: currentVersion,
        startsOn: DateTime.utc(2026, 11, 15),
        endsOn: DateTime.utc(2026, 11, 21),
        rulesVersion: 'local-edf-v1',
        blocks: blocks,
        confirmedRemainingSeconds: const {'task-a': 3600},
        now: now,
      );
      final retry = await repository.confirmPlan(
        expectedSnapshotVersion: 'snapshot-1',
        readCurrentSnapshotVersion: currentVersion,
        startsOn: DateTime.utc(2026, 11, 15),
        endsOn: DateTime.utc(2026, 11, 21),
        rulesVersion: 'local-edf-v1',
        blocks: blocks,
        confirmedRemainingSeconds: const {'task-a': 3600},
        now: now,
      );

      expect(saved.id, retry.id);
      expect(saved.status, LocalPlanStatus.confirmed);
      expect(saved.blocks, hasLength(2));
      expect(versionReads, 1);
      expect(
        await database.select(database.taskPlanVersionRecords).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.plannedTimeBlockRecords).get(),
        hasLength(2),
      );
      final effort = await database
          .select(database.taskEffortRecords)
          .getSingle();
      expect(effort.userId, 'user-a');
      expect(effort.remainingSeconds, 3600);
      // Estimates and plans are local planning data; actual timer facts remain separate.
      expect(
        await database.select(database.timerSessionRecords).get(),
        isEmpty,
      );
      expect(await database.select(database.syncOperations).get(), isEmpty);

      await database
          .into(database.timerSessionRecords)
          .insert(
            TimerSessionRecordsCompanion.insert(
              id: 'actual-session-a',
              taskId: 'task-a',
              userId: 'user-a',
              startedAt: now.add(const Duration(hours: 1)),
              endedAt: Value(now.add(const Duration(hours: 1, minutes: 25))),
              durationSeconds: const Value(1500),
              state: 'finished',
              createdAt: now,
              updatedAt: now,
            ),
          );
      final firstBlock = await database
          .select(database.plannedTimeBlockRecords)
          .get()
          .then((rows) => rows.first);
      await repository.linkTimerSession(
        plannedBlockId: firstBlock.id,
        timerSessionId: 'actual-session-a',
        linkedAt: now.add(const Duration(hours: 1, minutes: 26)),
      );
      expect(
        await database.select(database.plannedBlockTimerLinks).get(),
        hasLength(1),
      );
      final actualSession = await database
          .select(database.timerSessionRecords)
          .getSingle();
      expect(actualSession.durationSeconds, 1500);
      expect(actualSession.state, 'finished');
    },
  );

  test('stale snapshot rejects before any plan or effort write', () async {
    final repository = PlanningPlanRepository(
      database: database,
      userId: 'user-a',
    );
    await expectLater(
      repository.confirmPlan(
        expectedSnapshotVersion: 'old-version',
        readCurrentSnapshotVersion: () async => 'new-version',
        startsOn: DateTime.utc(2026, 11, 15),
        endsOn: DateTime.utc(2026, 11, 15),
        rulesVersion: 'local-edf-v1',
        blocks: [
          CandidatePlanBlock(
            taskId: 'task-a',
            startsAt: now.add(const Duration(hours: 1)),
            endsAt: now.add(const Duration(hours: 2)),
            plannedSeconds: 3600,
          ),
        ],
        confirmedRemainingSeconds: const {'task-a': 3600},
        now: now,
      ),
      throwsA(isA<LocalPlanSnapshotChanged>()),
    );
    expect(
      await database.select(database.taskPlanVersionRecords).get(),
      isEmpty,
    );
    expect(
      await database.select(database.plannedTimeBlockRecords).get(),
      isEmpty,
    );
    expect(await database.select(database.taskEffortRecords).get(), isEmpty);
  });

  test('owner cannot save or read another owner task plan', () async {
    final repository = PlanningPlanRepository(
      database: database,
      userId: 'user-a',
    );
    await expectLater(
      repository.confirmPlan(
        expectedSnapshotVersion: 'snapshot-1',
        readCurrentSnapshotVersion: () async => 'snapshot-1',
        startsOn: DateTime.utc(2026, 11, 15),
        endsOn: DateTime.utc(2026, 11, 15),
        rulesVersion: 'local-edf-v1',
        blocks: [
          CandidatePlanBlock(
            taskId: 'task-b',
            startsAt: now.add(const Duration(hours: 1)),
            endsAt: now.add(const Duration(hours: 2)),
            plannedSeconds: 3600,
          ),
        ],
        now: now,
      ),
      throwsA(isA<LocalPlanInputInvalid>()),
    );
    expect(
      await repository.loadPlans(
        startsOnOrBefore: DateTime.utc(2026, 11, 21),
        endsOnOrAfter: DateTime.utc(2026, 11, 15),
      ),
      isEmpty,
    );
  });

  test(
    'block tombstone is idempotent and excluded from restored plan',
    () async {
      final repository = PlanningPlanRepository(
        database: database,
        userId: 'user-a',
      );
      final saved = await repository.confirmPlan(
        expectedSnapshotVersion: 'snapshot-1',
        readCurrentSnapshotVersion: () async => 'snapshot-1',
        startsOn: DateTime.utc(2026, 11, 15),
        endsOn: DateTime.utc(2026, 11, 15),
        rulesVersion: 'local-edf-v1',
        blocks: [
          CandidatePlanBlock(
            taskId: 'task-a',
            startsAt: now.add(const Duration(hours: 1)),
            endsAt: now.add(const Duration(hours: 2)),
            plannedSeconds: 3600,
          ),
        ],
        now: now,
      );
      final blockId =
          (await database.select(database.plannedTimeBlockRecords).getSingle())
              .id;

      expect(await repository.tombstoneBlock(blockId, now: now), isTrue);
      expect(await repository.tombstoneBlock(blockId, now: now), isFalse);
      expect(
        (await repository.loadPlans(
          startsOnOrBefore: DateTime.utc(2026, 11, 15),
          endsOnOrAfter: DateTime.utc(2026, 11, 15),
        )).single.blocks,
        isEmpty,
      );
      expect(
        (await database.select(database.plannedTimeBlockRecords).getSingle())
            .deletedAt!
            .isAtSameMomentAs(now),
        isTrue,
      );
      expect(saved.blocks, hasLength(1));
    },
  );

  test(
    'replacement preserves prior version and records supersession edge',
    () async {
      final repository = PlanningPlanRepository(
        database: database,
        userId: 'user-a',
      );
      Future<SavedLocalPlan> save(String snapshot) => repository.confirmPlan(
        expectedSnapshotVersion: snapshot,
        readCurrentSnapshotVersion: () async => snapshot,
        startsOn: DateTime.utc(2026, 11, 15),
        endsOn: DateTime.utc(2026, 11, 15),
        rulesVersion: 'local-edf-v1',
        blocks: [
          CandidatePlanBlock(
            taskId: 'task-a',
            startsAt: now.add(const Duration(hours: 1)),
            endsAt: now.add(const Duration(hours: 2)),
            plannedSeconds: 3600,
          ),
        ],
        now: now,
      );
      final first = await save('snapshot-1');
      final second = await save('snapshot-2');
      final versions = await database
          .select(database.taskPlanVersionRecords)
          .get();

      expect(versions, hasLength(2));
      expect(
        versions.firstWhere((row) => row.id == first.id).status,
        'superseded',
      );
      expect(
        versions
            .firstWhere((row) => row.id == second.id)
            .supersedesVersionIdsJson,
        '["${first.id}"]',
      );
      expect(second.revision, first.revision + 1);
    },
  );

  test('schema 19 upgrades additively and preserves existing tasks', () async {
    final directory = await Directory.systemTemp.createTemp('checkd_plan_v20_');
    final file = File('${directory.path}/upgrade.sqlite');
    final first = AppDatabase.forTesting(NativeDatabase(file));
    await first
        .into(first.localTasks)
        .insert(
          LocalTasksCompanion.insert(
            id: 'preserved-task',
            userId: const Value('user-a'),
            name: 'must remain',
            taskType: 'one_time',
            colorValue: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await first.customStatement('DROP TABLE planned_block_timer_links');
    await first.customStatement('DROP TABLE planned_time_block_records');
    await first.customStatement('DROP TABLE task_plan_version_records');
    await first.customStatement('DROP TABLE task_effort_records');
    await first.customStatement('PRAGMA user_version = 19');
    await first.close();

    final upgraded = AppDatabase.forTesting(NativeDatabase(file));
    expect(
      (await (upgraded.select(
        upgraded.localTasks,
      )..where((row) => row.id.equals('preserved-task'))).getSingle()).name,
      'must remain',
    );
    for (final table in [
      'task_effort_records',
      'task_plan_version_records',
      'planned_time_block_records',
      'planned_block_timer_links',
    ]) {
      await upgraded.customSelect('SELECT 1 FROM $table LIMIT 1').get();
    }
    await upgraded.close();
    await directory.delete(recursive: true);
  });

  test('schema 20 adds tombstone lineage and conflict records', () async {
    final directory = await Directory.systemTemp.createTemp('checkd_plan_v21_');
    final file = File('${directory.path}/upgrade.sqlite');
    final first = AppDatabase.forTesting(NativeDatabase(file));
    await first.customStatement('DROP TABLE planning_sync_conflicts');
    await first.customStatement(
      'ALTER TABLE task_effort_records DROP COLUMN deleted_at',
    );
    await first.customStatement(
      'ALTER TABLE task_plan_version_records DROP COLUMN supersedes_version_ids_json',
    );
    await first.customStatement(
      'ALTER TABLE planned_time_block_records DROP COLUMN deleted_at',
    );
    await first.customStatement('PRAGMA user_version = 20');
    await first.close();

    final upgraded = AppDatabase.forTesting(NativeDatabase(file));
    final columns = await upgraded
        .customSelect('PRAGMA table_info(planned_time_block_records)')
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      contains('deleted_at'),
    );
    expect(
      await upgraded.select(upgraded.planningSyncConflicts).get(),
      isEmpty,
    );
    await upgraded.close();
    await directory.delete(recursive: true);
  });
}
