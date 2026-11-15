import 'dart:convert';

import 'package:http/http.dart' as http;

class PlanningPreviewException implements Exception {
  const PlanningPreviewException({
    required this.statusCode,
    required this.code,
    this.safeDiagnostic,
  });

  final int statusCode;
  final String code;
  final String? safeDiagnostic;

  @override
  String toString() =>
      'Planning preview failed ($statusCode, $code${safeDiagnostic == null ? '' : ', $safeDiagnostic'}).';
}

/// HTTP client for the opt-in loopback Flutter-to-Python preview bridge.
/// It sends the current read-only Drift snapshot and has no write method.
class PlanningPreviewClient {
  PlanningPreviewClient({
    required String baseUrl,
    required String token,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUri = Uri.parse(baseUrl),
       _token = token,
       _client = client ?? http.Client() {
    if (!_baseUri.hasScheme || !_baseUri.hasAuthority) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'must be an absolute URL');
    }
    if (_token.length < 24) {
      throw ArgumentError.value(token, 'token', 'must contain 24+ characters');
    }
  }

  final Uri _baseUri;
  final String _token;
  final http.Client _client;
  final Duration timeout;
  bool _closed = false;

  Future<Map<String, Object?>> preview(
    Map<String, Object?> snapshot, {
    String? expectedVersion,
  }) => _post('/v0/preview', {
    'snapshot': snapshot,
    'expected_version': ?expectedVersion,
  });

  Future<Map<String, Object?>> risks(Map<String, Object?> snapshot) =>
      _post('/v0/risks', {'snapshot': snapshot});

  Future<Map<String, Object?>> simulateDelay({
    required Map<String, Object?> snapshot,
    required String taskId,
    required DateTime until,
  }) => _post('/v0/delay', {
    'snapshot': snapshot,
    'task_id': taskId,
    'until': until.toIso8601String(),
  });

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> payload,
  ) async {
    if (_closed) throw StateError('PlanningPreviewClient is closed.');
    final uri = _baseUri.resolve(path);
    final response = await _client
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $_token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(timeout);
    Map<String, Object?> decoded;
    try {
      decoded = (jsonDecode(response.body) as Map).cast<String, Object?>();
    } on Object {
      throw PlanningPreviewException(
        statusCode: response.statusCode,
        code: 'INVALID_RESPONSE',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      final code = error is Map ? error['code'] : null;
      final details = error is Map ? error['details'] : null;
      final diagnostic = details is Map ? details['validation_error'] : null;
      throw PlanningPreviewException(
        statusCode: response.statusCode,
        code: code is String ? code : 'SERVICE_ERROR',
        safeDiagnostic: diagnostic is String ? diagnostic : null,
      );
    }
    if (decoded['ok'] != true) {
      final error = decoded['error'];
      final code = error is Map ? error['code'] : null;
      final details = error is Map ? error['details'] : null;
      final diagnostic = details is Map ? details['validation_error'] : null;
      throw PlanningPreviewException(
        statusCode: response.statusCode,
        code: code is String ? code : 'SERVICE_ERROR',
        safeDiagnostic: diagnostic is String ? diagnostic : null,
      );
    }
    return decoded;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}
