import 'dart:async';
import 'dart:convert';

import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/planning/data/task_occurrence_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const owner = '00000000-0000-4000-8000-000000000001';
  const otherOwner = '00000000-0000-4000-8000-000000000002';
  const device = '00000000-0000-4000-8000-000000000003';
  const host = 'https://checkd.example.test';
  const sessionToken = 'test-only-owner-token';
  const occurrence = <String, Object?>{
    'task_id': '00000000-0000-4000-8000-000000000004',
    'occurrence_id': 'task:00000000-0000-4000-8000-000000000004:2026-11-26',
    'local_date': '2026-11-26',
    'start_minute': 520,
    'end_minute': 550,
    'timezone': 'Asia/Shanghai',
  };
  const snapshot = <String, Object?>{
    'from_date': '2026-11-26',
    'through_date': '2026-11-26',
    'timezone': 'Asia/Shanghai',
    'generated_at': '2026-11-26T01:30:00Z',
    'builder_version': 'checkd_flutter_task_occurrence_v1',
    'task_data_version': 'test-rules-v1',
    'device_id': device,
    'local_generation': 7,
    'occurrences': [occurrence],
  };
  late MockClient httpClient;
  late SupabaseClient supabase;
  late SupabaseTaskOccurrenceRemotePublisher publisher;
  late Future<http.Response> Function(http.Request) respond;
  late List<http.Request> requests;

  setUp(() async {
    requests = [];
    httpClient = MockClient((request) {
      requests.add(request);
      return respond(request);
    });
    supabase = SupabaseClient(
      host,
      'test-only-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: httpClient,
    );
    await supabase.auth.setInitialSession(_session(owner, sessionToken));
    publisher = SupabaseTaskOccurrenceRemotePublisher(supabase);
    respond = (_) async => _ok();
  });

  tearDown(() async {
    await supabase.dispose();
    httpClient.close();
  });

  Future<TaskOccurrencePublishReceipt> publish({
    String userId = owner,
    String deviceId = device,
    Map<String, Object?> payload = snapshot,
  }) =>
      publisher.publish(userId: userId, deviceId: deviceId, snapshot: payload);

  test(
    'live watermark evidence uses the same account, device and version',
    () async {
      final checkpoint = SyncDeviceCheckpoint(
        userId: owner,
        deviceId: device,
        localGeneration: 7,
        acknowledgedGeneration: 7,
        updatedAt: DateTime.utc(2026, 11, 26),
      );
      var currentVersion = 13;
      respond = (request) async {
        expect(request.method, 'GET');
        expect(request.headers['authorization'], 'Bearer $sessionToken');
        expect(request.url.queryParameters['user_id'], 'eq.$owner');
        if (request.url.path.endsWith('/agent_device_sync_watermarks')) {
          expect(request.url.queryParameters['device_id'], 'eq.$device');
          return http.Response(
            '[{"local_generation":7,"server_data_version":13}]',
            200,
            headers: const {'content-type': 'application/json'},
            request: request,
          );
        }
        expect(request.url.path, endsWith('/agent_user_data_versions'));
        return http.Response(
          '[{"data_version":$currentVersion}]',
          200,
          headers: const {'content-type': 'application/json'},
          request: request,
        );
      };

      expect(await publisher.readCheckpointVersion(checkpoint), 13);
      currentVersion = 14;
      expect(await publisher.readCheckpointVersion(checkpoint), isNull);
      expect(requests, hasLength(4));
    },
  );

  test('posts the device snapshot with the expected owner token', () async {
    final receipt = await publish();

    expect(receipt.serverDataVersion, 13);
    expect(receipt.occurrenceDigest, _exampleDigest);
    final request = requests.single;
    expect(request.method, 'POST');
    expect(
      request.url,
      Uri.parse('$host/rest/v1/rpc/publish_agent_task_occurrence_snapshot'),
    );
    expect(request.headers['authorization'], 'Bearer $sessionToken');
    expect(request.headers['apikey'], 'test-only-publishable-key');
    expect(request.headers['content-profile'], 'public');
    expect(request.followRedirects, isFalse);
    expect(jsonDecode(request.body), {
      'p_device_id': device,
      'p_snapshot': snapshot,
    });
  });

  test('rejects client-supplied owner, digest or server version', () async {
    for (final field in [
      'user_id',
      'occurrence_digest',
      'server_data_version',
    ]) {
      await expectLater(
        publish(payload: {...snapshot, field: 'untrusted'}),
        throwsA(_failure('invalid_snapshot_payload')),
      );
    }
    await expectLater(
      publish(
        payload: {
          ...snapshot,
          'occurrences': [
            {...occurrence, 'user_id': otherOwner},
          ],
        },
      ),
      throwsA(_failure('invalid_snapshot_payload')),
    );
    await expectLater(
      publish(deviceId: 'different-device'),
      throwsA(_failure('invalid_snapshot_payload')),
    );
    expect(requests, isEmpty);
  });

  test('requires all contract fields on the snapshot and each row', () async {
    final missingSnapshotField = {...snapshot}..remove('generated_at');
    await expectLater(
      publish(payload: missingSnapshotField),
      throwsA(_failure('invalid_snapshot_payload')),
    );
    final missingOccurrenceField = {...occurrence}..remove('end_minute');
    await expectLater(
      publish(
        payload: {
          ...snapshot,
          'occurrences': [missingOccurrenceField],
        },
      ),
      throwsA(_failure('invalid_snapshot_payload')),
    );
    expect(requests, isEmpty);
  });

  test('does not send a request when the selected account changes', () async {
    final pending = publish();
    final expectation = expectLater(
      pending,
      throwsA(_failure('auth_owner_changed')),
    );
    await supabase.auth.setInitialSession(
      _session(otherOwner, 'test-only-other-token'),
    );
    await expectation;
    expect(requests, isEmpty);
  });

  test('discards a result delivered after an account change', () async {
    final sent = Completer<void>();
    final release = Completer<http.Response>();
    respond = (_) {
      sent.complete();
      return release.future;
    };
    final expectation = expectLater(
      publish(),
      throwsA(_failure('auth_owner_changed')),
    );
    await sent.future;
    expect(requests.single.headers['authorization'], 'Bearer $sessionToken');
    await supabase.auth.setInitialSession(
      _session(otherOwner, 'test-only-other-token'),
    );
    release.complete(_ok());
    await expectation;
  });

  test('marks HTTP 5xx and transport errors as retryable', () async {
    respond = (_) async =>
        http.Response('{"code":"PGRST000","message":"private detail"}', 503);
    await expectLater(
      publish(),
      throwsA(_failure('http_503', retryable: true)),
    );
    respond = (_) async => throw http.ClientException('private detail');
    await expectLater(
      publish(),
      throwsA(_failure('transport', retryable: true)),
    );
    expect(requests, hasLength(2));
  });

  test('rejects validation, permission and other 4xx as permanent', () async {
    for (final (status, code) in [
      (400, '22P02'),
      (400, '22023'),
      (403, '42501'),
      (401, 'http_401'),
      (404, 'http_404'),
      (429, 'http_429'),
    ]) {
      respond = (_) async => http.Response(
        jsonEncode({'code': code, 'message': 'private detail'}),
        status,
      );
      await expectLater(publish(), throwsA(_failure(code)));
    }
    expect(requests, hasLength(6));
  });

  test('requires explicit success and a valid receipt', () async {
    for (final status in [200, 503]) {
      respond = (_) async =>
          http.Response('{"ok":false,"message":"private detail"}', status);
      await expectLater(publish(), throwsA(_failure('publish_rejected')));
    }
    for (final malformed in [
      '[]',
      '{"server_data_version":13,"occurrence_digest":"$_exampleDigest"}',
      '{"ok":true,"server_data_version":"13","occurrence_digest":"$_exampleDigest"}',
      '{"ok":true,"server_data_version":-1,"occurrence_digest":"$_exampleDigest"}',
      '{"ok":true,"server_data_version":13,"occurrence_digest":"short"}',
      '{"ok":true,"server_data_version":13,"occurrence_digest":"${_exampleDigest.substring(1)}g"}',
    ]) {
      respond = (_) async => http.Response(malformed, 200);
      await expectLater(
        publish(),
        throwsA(_failure('invalid_publish_receipt')),
      );
    }
  });
}

Matcher _failure(String code, {bool retryable = false}) =>
    isA<TaskOccurrencePublishFailure>()
        .having((failure) => failure.code, 'code', code)
        .having((failure) => failure.retryable, 'retryable', retryable)
        .having(
          (failure) => failure.toString(),
          'safe failure',
          isNot(contains('private')),
        );

String _session(String owner, String token) => jsonEncode({
  'access_token': token,
  'token_type': 'bearer',
  'user': {'id': owner},
});

const _exampleDigest =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

http.Response _ok() => http.Response(
  '{"ok":true,"server_data_version":13,"occurrence_digest":"$_exampleDigest"}',
  200,
);
