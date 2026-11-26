import 'dart:convert';

import 'package:check_d/core/sync/sync_download_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('restore reads all rows when the server caps each response', () async {
    final cursors = <String?>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: MockClient((request) async {
        expect(request.url.queryParameters['user_id'], 'eq.user-1');
        expect(request.url.queryParameters['offset'], isNull);
        final filters = request.url.queryParametersAll['id'] ?? const [];
        cursors.add(
          filters.where((value) => value.startsWith('gt.')).firstOrNull,
        );
        final ascending =
            request.url.queryParameters['order']?.contains('.desc.') != true;
        final rows = List.generate(5, (i) => 'task-$i');
        final filtered = (ascending ? rows : rows.reversed).where((id) {
          return filters.every((filter) {
            final value = filter.split('.').last;
            return filter.startsWith('gt.')
                ? id.compareTo(value) > 0
                : id.compareTo(value) <= 0;
          });
        }).toList();
        final limit = int.parse(request.url.queryParameters['limit'] ?? '2');
        final page = filtered
            .take(limit.clamp(0, 2))
            .map((id) => {'id': id})
            .toList();
        return http.Response(
          jsonEncode(page),
          200,
          request: request,
          headers: {
            'content-type': 'application/json',
            'content-range': '0-${page.length - 1}/${filtered.length}',
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
    cursors.clear();

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
    expect(cursors, [null, null, 'gt.task-1', 'gt.task-3']);
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

  for (final insertBeforeCursor in [true, false]) {
    test(
      'restore keeps its position when a preceding row is ${insertBeforeCursor ? 'inserted' : 'deleted'} between pages',
      () async {
        final requests = <Uri>[];
        final client = SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          httpClient: MockClient((request) async {
            final url = request.url;
            requests.add(url);
            final ids = requests.length == 1
                ? ['b', 'd', 'f', 'g']
                : insertBeforeCursor
                ? ['a', 'b', 'd', 'f', 'g']
                : ['d', 'f', 'g'];
            final descending = url.queryParameters['order']!.contains('.desc.');
            final filtered = (descending ? ids.reversed : ids).where((id) {
              for (final filter in url.queryParametersAll['id'] ?? const []) {
                final value = filter.split('.').last;
                if (filter.startsWith('gt.') && id.compareTo(value) <= 0) {
                  return false;
                }
                if (filter.startsWith('lte.') && id.compareTo(value) > 0) {
                  return false;
                }
              }
              return true;
            }).toList();
            final offset = int.parse(url.queryParameters['offset'] ?? '0');
            final limit = int.parse(url.queryParameters['limit'] ?? '2');
            final page = filtered.skip(offset).take(limit.clamp(0, 2));
            return http.Response(
              jsonEncode(page.map((id) => {'id': id}).toList()),
              200,
              request: request,
              headers: {
                'content-type': 'application/json',
                'content-range':
                    '$offset-${offset + page.length - 1}/${filtered.length}',
              },
            );
          }),
        );
        addTearDown(client.dispose);

        final rows = await SupabaseSyncRemoteReader(
          client,
        ).readTable('tasks', userId: 'user-1');

        expect(rows.map((row) => row['id']), ['b', 'd', 'f', 'g']);
        expect(
          requests
              .skip(1)
              .any(
                (request) =>
                    request.queryParametersAll['id']?.contains('gt.d') ?? false,
              ),
          isTrue,
        );
      },
    );
  }

  test('restore uses both key columns and stops at the upper bound', () async {
    final rows = [
      {'plan_id': 'plan-a', 'task_id': 'task-1'},
      {'plan_id': 'plan-a', 'task_id': 'task-2'},
      {'plan_id': 'plan-a', 'task_id': 'task-3'},
      {'plan_id': 'plan-b', 'task_id': 'task-1'},
      {'plan_id': 'plan-b', 'task_id': 'task-2'},
    ];
    var reads = 0;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: MockClient((request) async {
        final query = request.url.queryParameters;
        final page = switch (reads++) {
          0 => rows.take(2).toList(),
          1 => [rows.last],
          2 => [rows[2], rows[3]],
          3 => [
            rows[4],
            {'plan_id': 'plan-b', 'task_id': 'task-3'},
          ],
          _ => throw StateError('Unexpected request past the upper bound'),
        };
        if (reads == 2) {
          expect(
            query['order'],
            'plan_id.desc.nullslast,task_id.desc.nullslast',
          );
        } else if (reads > 2) {
          expect(query['plan_id'], 'lte.plan-b');
          final plan = reads == 3 ? 'plan-a' : 'plan-b';
          final task = reads == 3 ? 'task-2' : 'task-1';
          expect(
            query['or'],
            '(plan_id.gt.$plan,and(plan_id.eq.$plan,task_id.gt.$task))',
          );
        }
        return http.Response(
          jsonEncode(page),
          200,
          request: request,
          headers: {
            'content-type': 'application/json',
            'content-range': '0-${page.length - 1}/5',
          },
        );
      }),
    );
    addTearDown(client.dispose);

    final result = await SupabaseSyncRemoteReader(
      client,
    ).readTable('plan_tasks', userId: 'user-1');

    expect(result, rows);
    expect(reads, 4);
  });
}
