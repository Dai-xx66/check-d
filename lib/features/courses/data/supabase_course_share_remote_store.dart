import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'course_share_repository.dart';

class SupabaseCourseShareRemoteStore implements CourseShareRemoteStore {
  const SupabaseCourseShareRemoteStore(this._client);

  final SupabaseClient? _client;

  @override
  bool get canCreate => _client?.auth.currentUser != null;

  @override
  Future<bool> create({
    required String code,
    required int schemaVersion,
    required String payload,
    required DateTime expiresAt,
  }) async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) return false;
    try {
      final response = await client.rpc(
        'create_course_share',
        params: {
          'p_code': code,
          'p_schema_version': schemaVersion,
          'p_payload': jsonDecode(payload),
          'p_expires_at': expiresAt.toIso8601String(),
        },
      );
      final result = _map(response);
      return result['status'] == 'ok';
    } catch (error) {
      if (error is PostgrestException && error.code == '23505') return false;
      throw _translate(error);
    }
  }

  @override
  Future<CourseShareRemoteRecord> fetch(String code) async {
    final client = _client;
    if (client == null) {
      throw const CourseShareRemoteException(networkUnavailable: false);
    }
    try {
      final response = await client.rpc(
        'fetch_course_share',
        params: {'p_code': code},
      );
      final result = _map(response);
      final status = switch (result['status']) {
        'ok' => CourseShareRemoteStatus.found,
        'expired' => CourseShareRemoteStatus.expired,
        _ => CourseShareRemoteStatus.notFound,
      };
      return CourseShareRemoteRecord(
        status: status,
        code: result['code'] as String?,
        expiresAt: DateTime.tryParse('${result['expires_at'] ?? ''}'),
        payload: result['payload'] == null
            ? null
            : jsonEncode(result['payload']),
      );
    } catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<void> delete(String code) async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) return;
    try {
      await client.rpc('delete_course_share', params: {'p_code': code});
    } catch (error) {
      throw _translate(error);
    }
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const CourseShareRemoteException(networkUnavailable: false);
  }

  CourseShareRemoteException _translate(Object error) {
    final text = error.toString().toLowerCase();
    final network =
        text.contains('socket') ||
        text.contains('network') ||
        text.contains('clientexception') ||
        text.contains('failed host lookup');
    return CourseShareRemoteException(networkUnavailable: network);
  }
}
