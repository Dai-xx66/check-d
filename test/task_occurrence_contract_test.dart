import 'dart:convert';

import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/holiday/holiday_calendar.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/planning/data/task_occurrence_publish_service.dart';
import 'package:check_d/features/planning/data/task_occurrence_remote.dart';
import 'package:check_d/features/planning/data/task_occurrence_snapshot.dart';
import 'package:check_d/features/schedule/data/day_schedule_repository.dart';
import 'package:check_d/features/schedule/domain/day_schedule_models.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _owner = '11111111-1111-4111-8111-111111111111';
const _other = '22222222-2222-4222-8222-222222222222';
const _otherTask = '33333333-3333-4333-8333-333333333333';
const _secondDevice = '44444444-4444-4444-8444-444444444444';
const _url = 'https://checkd-contract.example.test';
const _table = 'agent_task_occurrence_snapshots';
const _rpc = 'publish_agent_task_occurrence_snapshot';
const _window = ('2026-11-24', '2026-12-24');
final _day = DateTime.utc(2026, 11, 24);

// These tests exercise Flutter and the HTTP contract with a synthetic model of
// the M3 backend. PostgreSQL, RLS, deployment flags, and MCP run in staging.
void main() {
  late _ContractServer server;
  late AppDatabase database;
  late SyncQueueService queue;
  late MockClient httpClient;
  late SupabaseClient client;
  late SupabaseTaskOccurrenceRemotePublisher remote;
  late DriftTaskOccurrenceSnapshotRepository builder;
  late TaskOccurrencePublishService service;
  late DayScheduleRepository schedule;
  late String taskId;
  late String overrideId;
  late SyncDeviceCheckpoint checkpoint;

  Future<TaskOccurrencePublishReceipt> publishPayload(
    Map<String, Object?> payload,
  ) => remote.publish(
    userId: _owner,
    deviceId: payload['device_id'] as String,
    snapshot: payload,
  );

  Future<String> saveInterval(int start, int end, {String? id}) =>
      schedule.saveDailyOverride(
        DailyItemOverrideDraft(
          itemType: DayItemType.recurring,
          itemId: taskId,
          localDate: _day,
          action: DayOverrideAction.reschedule,
          plannedStartMinute: start,
          plannedEndMinute: end,
        ),
        overrideId: id,
      );

  Future<SyncDeviceCheckpoint> settleAndAcknowledge() async {
    // Model the existing business outbox transport and its successful ACK.
    final operations = await queue.loadRetryableForUser(_owner);
    for (final operation in operations) {
      await queue.markCompleted(operation.id);
    }
    final settled = (await queue.settledCheckpoint(_owner))!;
    expect(await queue.markCheckpointAcknowledged(settled), isTrue);
    server.acknowledge(_owner, settled.deviceId, settled.localGeneration);
    return (await queue.settledCheckpoint(_owner))!;
  }

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    queue = SyncQueueService(database);
    server = _ContractServer();
    httpClient = MockClient(server.handle);
    client = await _signIn(httpClient, _owner);
    remote = SupabaseTaskOccurrenceRemotePublisher(client);
    builder = DriftTaskOccurrenceSnapshotRepository(
      database: database,
      syncQueue: queue,
      holidayCalendar: const _NoHolidays(),
      clock: () => _day,
    );
    service = TaskOccurrencePublishService(
      queue: queue,
      buildSnapshot: builder.build,
      remote: remote,
      currentSyncEpoch: (userId) =>
          client.auth.currentUser?.id == userId ? 1 : null,
    );
    final tasks = TaskRepository(
      database: database,
      syncQueue: queue,
      userId: _owner,
    );
    taskId = await tasks.saveRecurringTask(
      RecurringTaskDraft(
        name: 'Synthetic recurring contract task',
        colorValue: 0,
        executionMode: RecurringExecutionMode.untimed,
        schedulePreset: SchedulePreset.daily,
        weekdays: {_day.weekday},
        startsOn: _day,
        endsOn: _day,
        holidayPause: false,
      ),
    );
    schedule = DayScheduleRepository(
      database: database,
      syncQueue: queue,
      userId: _owner,
    );
    overrideId = await saveInterval(540, 570);
    server.taskOwners[taskId] = _owner;
    server.taskOwners[_otherTask] = _other;
    checkpoint = await settleAndAcknowledge();
  });

  tearDown(() async {
    await client.dispose();
    httpClient.close();
    await database.close();
  });

  test('modeled owner-only read and foreign-task rejection', () async {
    expect(await service.publish(checkpoint), isTrue);
    final accepted = await client.from(_table).select('task_data_version');
    expect(accepted, hasLength(1));

    final otherClient = await _signIn(httpClient, _other);
    addTearDown(otherClient.dispose);
    expect(await otherClient.from(_table).select(), isEmpty);
    final anonymous = await httpClient.get(Uri.parse('$_url/rest/v1/$_table'));
    expect(anonymous.statusCode, 401);

    final snapshot = await builder.build(checkpoint);
    final foreignOccurrence = {
      ...snapshot.occurrences.single,
      'task_id': _otherTask,
      'occurrence_id': 'task:$_otherTask:${_window.$1}',
    };
    await expectLater(
      publishPayload({
        ...snapshot.toJson(),
        'occurrences': [foreignOccurrence],
      }),
      throwsA(_nonRetryable('42501')),
    );
    expect(server.lastError, 'OCCURRENCE_RESOURCE_NOT_OWNED');
    expect(server.snapshots.values.single.occurrences, snapshot.occurrences);
  });

  test(
    'modeled replay is idempotent and stale generation cannot overwrite',
    () async {
      final first = await builder.build(checkpoint);
      expect(await service.publish(checkpoint), isTrue);
      final saved = server.snapshots.values.single;
      final replay = await publishPayload(first.toJson());
      expect(replay.serverDataVersion, saved.serverVersion);
      expect(replay.occurrenceDigest, saved.digest);
      expect(server.snapshots.values.single, same(saved));

      await saveInterval(600, 630, id: overrideId);
      server.currentVersion++;
      final next = await settleAndAcknowledge();
      expect(await service.publish(next), isTrue);
      final newer = server.snapshots.values.single;
      expect(newer.generation, greaterThan(saved.generation));
      expect(newer.serverVersion, greaterThan(saved.serverVersion));
      expect(newer.taskDataVersion, isNot(saved.taskDataVersion));
      expect(newer.digest, isNot(saved.digest));
      expect(newer.occurrences.single['start_minute'], 600);
      expect(
        newer.occurrences.single['occurrence_id'],
        saved.occurrences.single['occurrence_id'],
      );

      await publishPayload(first.toJson());
      expect(server.snapshots.values.single, same(newer));
    },
  );

  test(
    'modeled readiness requires an enabled, current, trusted device set',
    () async {
      expect(server.readiness(_owner, _window), (
        ready: false,
        reason: 'missing_task_snapshot_for_device',
      ));
      expect(await service.publish(checkpoint), isTrue);
      expect(server.readiness(_owner, _window), _ready);
      server.enabled = false;
      expect(server.readiness(_owner, _window), (
        ready: false,
        reason: 'task_occurrence_evidence_disabled',
      ));
      server.enabled = true;
      server.trusted = false;
      expect(server.readiness(_owner, _window), (
        ready: false,
        reason: 'freshness_not_trusted',
      ));
      server.trusted = true;
      server.acknowledge(
        _owner,
        checkpoint.deviceId,
        checkpoint.localGeneration + 1,
      );
      expect(server.readiness(_owner, _window), (
        ready: false,
        reason: 'task_generation_mismatch',
      ));
      server.currentVersion++;
      expect(server.readiness(_owner, _window), (
        ready: false,
        reason: 'task_snapshot_version_behind',
      ));
    },
  );

  test(
    'modeled readiness blocks missing or inconsistent device digests',
    () async {
      expect(await service.publish(checkpoint), isTrue);
      final snapshot = await builder.build(checkpoint);
      final secondPayload = {...snapshot.toJson(), 'device_id': _secondDevice};
      server.acknowledge(_owner, _secondDevice, checkpoint.localGeneration);
      expect(server.readiness(_owner, _window), (
        ready: false,
        reason: 'missing_task_snapshot_for_device',
      ));

      await publishPayload(secondPayload);
      expect(server.readiness(_owner, _window), _ready);

      // Model disagreement between devices without changing the first snapshot.
      await publishPayload({
        ...secondPayload,
        'occurrences': [
          {...snapshot.occurrences.single, 'start_minute': 545},
        ],
      });
      expect(server.readiness(_owner, _window), (
        ready: false,
        reason: 'task_digest_mismatch',
      ));
    },
  );

  test(
    'modeled readiness blocks empty data and rejects invalid intervals',
    () async {
      final snapshot = await builder.build(checkpoint);
      await publishPayload({...snapshot.toJson(), 'occurrences': []});
      expect(server.readiness(_owner, _window), (
        ready: false,
        reason: 'task_occurrences_empty',
      ));
      expect(server.readiness(_other, _window), (
        ready: false,
        reason: 'no_active_device_watermark',
      ));
      await expectLater(
        publishPayload({
          ...snapshot.toJson(),
          'occurrences': [
            {...snapshot.occurrences.single, 'end_minute': -1},
          ],
        }),
        throwsA(_nonRetryable('22023')),
      );
      expect(server.snapshots.values.single.occurrences, isEmpty);
      expect(server.lastError, 'INVALID_OCCURRENCE_RANGE');
    },
  );
}

Matcher _nonRetryable(String code) => isA<TaskOccurrencePublishFailure>()
    .having((error) => error.code, 'code', code)
    .having((error) => error.retryable, 'retryable', isFalse);

String _token(String userId) => 'test-only-$userId';

Future<SupabaseClient> _signIn(http.Client transport, String userId) async {
  final client = SupabaseClient(
    _url,
    'test-only-publishable-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: transport,
  );
  await client.auth.setInitialSession(
    jsonEncode({
      'user': {'id': userId},
      'token_type': 'bearer',
      'access_token': _token(userId),
    }),
  );
  return client;
}

typedef _Window = (String, String);
typedef _SnapshotKey = (String, String, _Window);
typedef _DeviceKey = (String, String);
typedef _Readiness = ({bool ready, String reason});
const _ready = (ready: true, reason: 'task_occurrences_version_current');

_Readiness _blocked(String reason) => (ready: false, reason: reason);

class _ContractServer {
  final taskOwners = <String, String>{};
  final checkpoints = <_DeviceKey, ({int generation, int version})>{};
  final snapshots = <_SnapshotKey, _StoredSnapshot>{};
  bool enabled = true;
  bool trusted = true;
  int currentVersion = 41;
  String? lastError;

  void acknowledge(String owner, String device, int generation) {
    checkpoints[(owner, device)] = (
      generation: generation,
      version: currentVersion,
    );
  }

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    final bearer = request.headers['authorization'];
    final String owner;
    if (bearer == 'Bearer ${_token(_owner)}') {
      owner = _owner;
    } else if (bearer == 'Bearer ${_token(_other)}') {
      owner = _other;
    } else {
      return _failure(401, '42501', 'AUTH_REQUIRED');
    }
    if (path == '/rest/v1/$_table' && request.method == 'GET') {
      return _json(200, [
        for (final entry in snapshots.entries)
          if (entry.key.$1 == owner)
            {'task_data_version': entry.value.taskDataVersion},
      ], request: request);
    }
    if (path != '/rest/v1/rpc/$_rpc' || request.method != 'POST') {
      return _failure(404, 'PGRST202', 'UNKNOWN_FIXTURE_ROUTE');
    }

    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final device = body['p_device_id'] as String;
    final snapshot = body['p_snapshot'] as Map<String, dynamic>;
    final rows = (snapshot['occurrences'] as List).cast<Map<String, Object?>>();
    if (rows.any((row) => taskOwners[row['task_id']] != owner)) {
      return _failure(403, '42501', 'OCCURRENCE_RESOURCE_NOT_OWNED');
    }
    if (rows.any((row) {
      final start = row['start_minute'] as int;
      final end = row['end_minute'] as int;
      return start < 0 || end <= start || end > 1440;
    })) {
      return _failure(400, '22023', 'INVALID_OCCURRENCE_RANGE');
    }

    final window = (
      snapshot['from_date'] as String,
      snapshot['through_date'] as String,
    );
    final key = (owner, device, window);
    final prior = snapshots[key];
    final generation = snapshot['local_generation'] as int;
    if (prior != null && prior.generation > generation) {
      // The documented upsert predicate skips stale updates. The fixture
      // returns the retained row here without imposing a staging status.
      return _receipt(prior);
    }
    final active = checkpoints[(owner, device)];
    if (active?.generation != generation || active?.version != currentVersion) {
      return _failure(409, '40001', 'MODELED_GENERATION_CONFLICT');
    }
    final payload = jsonEncode(snapshot);
    if (prior?.payload == payload && prior?.serverVersion == currentVersion) {
      return _receipt(prior!);
    }
    // The model uses fixture JSON bytes. PostgreSQL canonicalizes JSONB using
    // its own encoder, so this checks digest behavior, rather than byte parity.
    final saved = _StoredSnapshot(
      payload: payload,
      generation: generation,
      serverVersion: currentVersion,
      taskDataVersion: snapshot['task_data_version'] as String,
      digest: sha256.convert(utf8.encode(jsonEncode(rows))).toString(),
      occurrences: rows,
    );
    snapshots[key] = saved;
    return _receipt(saved);
  }

  _Readiness readiness(String owner, _Window window) {
    if (!taskOwners.containsValue(owner)) {
      return (ready: true, reason: 'no_recurring_tasks');
    }
    if (!enabled) return _blocked('task_occurrence_evidence_disabled');
    if (!trusted) return _blocked('freshness_not_trusted');
    final active = checkpoints.entries.where((item) => item.key.$1 == owner);
    if (active.isEmpty) return _blocked('no_active_device_watermark');
    final digests = <String>{};
    for (final device in active) {
      final snapshot = snapshots[(owner, device.key.$2, window)];
      if (snapshot == null) return _blocked('missing_task_snapshot_for_device');
      if (snapshot.serverVersion != currentVersion) {
        return _blocked('task_snapshot_version_behind');
      }
      if (snapshot.generation != device.value.generation) {
        return _blocked('task_generation_mismatch');
      }
      if (snapshot.occurrences.isEmpty) {
        return _blocked('task_occurrences_empty');
      }
      digests.add(snapshot.digest);
    }
    return digests.length == 1 ? _ready : _blocked('task_digest_mismatch');
  }

  http.Response _failure(int status, String code, String message) {
    lastError = message;
    return _json(status, {'code': code, 'message': message});
  }

  http.Response _receipt(_StoredSnapshot row) => _json(200, {
    'ok': true,
    'server_data_version': row.serverVersion,
    'occurrence_digest': row.digest,
  });

  http.Response _json(int status, Object data, {http.Request? request}) =>
      http.Response(
        jsonEncode(data),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );
}

class _StoredSnapshot {
  const _StoredSnapshot({
    required this.payload,
    required this.generation,
    required this.serverVersion,
    required this.taskDataVersion,
    required this.digest,
    required this.occurrences,
  });

  final String payload;
  final int generation;
  final int serverVersion;
  final String taskDataVersion;
  final String digest;
  final List<Map<String, Object?>> occurrences;
}

class _NoHolidays implements HolidayCalendar {
  const _NoHolidays();

  @override
  Future<ChinaDayKind> kindFor(DateTime date) async => ChinaDayKind.unknown;
}
