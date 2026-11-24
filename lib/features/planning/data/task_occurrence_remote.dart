import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class TaskOccurrenceRemotePublisher {
  Future<TaskOccurrencePublishReceipt> publish({
    required String userId,
    required String deviceId,
    required Map<String, Object?> snapshot,
  });
}

class TaskOccurrencePublishReceipt {
  const TaskOccurrencePublishReceipt({
    required this.serverDataVersion,
    required this.occurrenceDigest,
  });

  final int serverDataVersion;
  final String occurrenceDigest;
}

class TaskOccurrencePublishFailure implements Exception {
  const TaskOccurrencePublishFailure(this.code, {this.retryable = false});

  final String code;
  final bool retryable;

  @override
  String toString() => 'TaskOccurrencePublishFailure($code)';
}

class SupabaseTaskOccurrenceRemotePublisher
    implements TaskOccurrenceRemotePublisher {
  const SupabaseTaskOccurrenceRemotePublisher(this._client);

  static const _rpc = 'publish_agent_task_occurrence_snapshot';
  static const _timeout = Duration(seconds: 15);
  static const _snapshotKeys = {
    'from_date',
    'through_date',
    'timezone',
    'generated_at',
    'builder_version',
    'task_data_version',
    'device_id',
    'local_generation',
    'occurrences',
  };
  static const _occurrenceKeys = {
    'task_id',
    'occurrence_id',
    'local_date',
    'start_minute',
    'end_minute',
    'timezone',
  };
  static final _sha256Hex = RegExp(r'^[0-9a-fA-F]{64}$');

  final SupabaseClient _client;

  @override
  Future<TaskOccurrencePublishReceipt> publish({
    required String userId,
    required String deviceId,
    required Map<String, Object?> snapshot,
  }) async {
    _requireOwner(userId);
    final body = _encodeRequest(deviceId, snapshot);
    final http.Response response;
    try {
      final session = await _client.auth.getSession().timeout(_timeout);
      _requireOwner(userId);
      if (session == null || session.user.id != userId) {
        throw const TaskOccurrencePublishFailure('auth_owner_changed');
      }
      response = await _post(body, session.accessToken);
    } on TimeoutException {
      _requireOwner(userId);
      throw const TaskOccurrencePublishFailure(
        'transport_timeout',
        retryable: true,
      );
    } on http.ClientException {
      _requireOwner(userId);
      throw const TaskOccurrencePublishFailure('transport', retryable: true);
    } on AuthRetryableFetchException catch (error) {
      _requireOwner(userId);
      final status = int.tryParse(error.statusCode ?? '');
      throw TaskOccurrencePublishFailure(
        'auth_transport',
        retryable: status == null || _isServerError(status),
      );
    } on AuthException {
      throw const TaskOccurrencePublishFailure('auth_session_unavailable');
    }
    _requireOwner(userId);
    return _readReceipt(response);
  }

  String _encodeRequest(String deviceId, Map<String, Object?> snapshot) {
    final occurrences = snapshot['occurrences'];
    if (deviceId.isEmpty ||
        snapshot['device_id'] != deviceId ||
        snapshot.length != _snapshotKeys.length ||
        snapshot.entries.any(
          (entry) =>
              !_snapshotKeys.contains(entry.key) ||
              (entry.key != 'occurrences' && !_isScalar(entry.value)),
        ) ||
        occurrences is! List ||
        occurrences.any(
          (row) =>
              row is! Map ||
              row.length != _occurrenceKeys.length ||
              row.entries.any(
                (entry) =>
                    !_occurrenceKeys.contains(entry.key) ||
                    !_isScalar(entry.value),
              ),
        )) {
      throw const TaskOccurrencePublishFailure('invalid_snapshot_payload');
    }

    try {
      return jsonEncode({'p_device_id': deviceId, 'p_snapshot': snapshot});
    } on JsonUnsupportedObjectError {
      throw const TaskOccurrencePublishFailure('invalid_snapshot_payload');
    }
  }

  bool _isScalar(Object? value) =>
      value == null || value is String || value is num || value is bool;

  void _requireOwner(String userId) {
    if (userId.isEmpty || _client.auth.currentSession?.user.id != userId) {
      throw const TaskOccurrencePublishFailure('auth_owner_changed');
    }
  }

  Future<http.Response> _post(String body, String accessToken) {
    final rest = _client.rest;
    final transport = rest.httpClient;
    if (transport == null) {
      throw const TaskOccurrencePublishFailure('transport_unavailable');
    }
    final abort = Completer<void>();
    // Use the Supabase REST transport directly so the HTTP status remains
    // available even when the JSON body contains a PostgreSQL error code.
    final request =
        http.AbortableRequest(
            'POST',
            Uri.parse('${rest.url}/rpc/$_rpc'),
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..headers.addAll(rest.headers)
          ..headers['Authorization'] = 'Bearer $accessToken'
          ..headers['Content-Type'] = 'application/json'
          ..headers['Content-Profile'] = 'public'
          ..body = body;
    return transport
        .send(request)
        .then(http.Response.fromStream)
        .timeout(
          _timeout,
          onTimeout: () {
            abort.complete();
            throw TimeoutException(
              'Task occurrence snapshot request timed out',
            );
          },
        );
  }

  TaskOccurrencePublishReceipt _readReceipt(http.Response response) {
    final status = response.statusCode;
    final body = _decodeBody(response);
    if (body?['ok'] == false) {
      throw const TaskOccurrencePublishFailure('publish_rejected');
    }
    if (status < 200 || status >= 300) {
      switch (body?['code']) {
        case '22P02':
          throw const TaskOccurrencePublishFailure('22P02');
        case '22023':
          throw const TaskOccurrencePublishFailure('22023');
        case '42501':
          throw const TaskOccurrencePublishFailure('42501');
        default:
          throw TaskOccurrencePublishFailure(
            'http_$status',
            retryable: _isServerError(status),
          );
      }
    }
    final version = body?['server_data_version'];
    final digest = body?['occurrence_digest'];
    if (body?['ok'] != true ||
        version is! int ||
        version < 0 ||
        digest is! String ||
        digest.length != 64 ||
        !_sha256Hex.hasMatch(digest)) {
      throw const TaskOccurrencePublishFailure('invalid_publish_receipt');
    }
    return TaskOccurrencePublishReceipt(
      serverDataVersion: version,
      occurrenceDigest: digest,
    );
  }

  Map<String, Object?>? _decodeBody(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  bool _isServerError(int status) => status >= 500 && status < 600;
}
