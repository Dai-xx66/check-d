import 'dart:convert';

import 'package:check_d/core/sync/sync_download_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('restore reads all rows when the server caps each response', () async {
    final offsets = <int>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: MockClient((request) async {
        expect(request.url.queryParameters['user_id'], 'eq.user-1');
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        offsets.add(offset);
        final rows = List.generate(5, (i) => {'id': 'task-$i'});
        final page = rows.skip(offset).take(2).toList();
        return http.Response(
          jsonEncode(page),
          200,
          request: request,
          headers: {
            'content-type': 'application/json',
            'content-range': '$offset-${offset + page.length - 1}/5',
          },
        );
      }),
    );
    addTearDown(client.dispose);

    // Confirm the pre-fix single select really is truncated by this server.
    final truncated = await client
        .from('tasks')
        .select()
        .eq('user_id', 'user-1');
    expect(truncated, hasLength(2));
    offsets.clear();

    final rows = await SupabaseSyncRemoteReader(
      client,
    ).readTable('tasks', userId: 'user-1');

    expect(rows.map((row) => row['id']), [
      'task-0',
      'task-1',
      'task-2',
      'task-3',
      'task-4',
    ]);
    expect(offsets, [0, 2, 4]);
  });

  for (final entry in const {
    'tasks': 'id.asc.nullslast',
    'long_term_tasks': 'task_id.asc.nullslast',
    'one_time_reminders': 'task_id.asc.nullslast',
    'plan_tasks': 'plan_id.asc.nullslast,task_id.asc.nullslast',
  }.entries) {
    test('restore orders ${entry.key} by its complete primary key', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        httpClient: MockClient((request) async {
          expect(request.url.queryParameters['order'], entry.value);
          return http.Response(
            '[]',
            200,
            request: request,
            headers: {
              'content-type': 'application/json',
              'content-range': '*/0',
            },
          );
        }),
      );
      addTearDown(client.dispose);

      expect(
        await SupabaseSyncRemoteReader(
          client,
        ).readTable(entry.key, userId: 'user-1'),
        isEmpty,
      );
    });
  }
}
