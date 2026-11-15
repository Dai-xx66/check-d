import 'package:check_d/features/planning/domain/local_planning_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = LocalPlanningEngine();

  test(
    'generates a deterministic candidate that avoids a course occurrence',
    () {
      final input = _snapshot(
        tasks: [
          _task('report', seconds: 3600, deadline: '2026-11-15T13:00:00+08:00'),
        ],
        courses: [
          _block('2026-11-15T10:00:00+08:00', '2026-11-15T11:00:00+08:00'),
        ],
      );
      final result = engine.preview(input);
      expect(result['outcome'], 'found_feasible');
      expect(result['execution_eligible'], isFalse);
      final schedule = result['schedule'] as Map;
      final block = (schedule['blocks'] as List).single as Map;
      final start = DateTime.parse(block['starts_at'] as String);
      final end = DateTime.parse(block['ends_at'] as String);
      expect(
        start.isBefore(DateTime.parse('2026-11-15T11:00:00+08:00')) &&
            DateTime.parse('2026-11-15T10:00:00+08:00').isBefore(end),
        isFalse,
      );
      expect(engine.preview(input), result);
    },
  );

  test('date-only deadline includes the complete Shanghai calendar date', () {
    final input = _snapshot(
      now: '2026-11-16T23:00:00+08:00',
      horizon: '2026-11-17T00:00:00+08:00',
      tasks: [_task('date-task', seconds: 3600, deadlineDate: '2026-11-16')],
    );
    final result = engine.preview(input);
    expect(result['outcome'], 'found_feasible');
    final block = ((result['schedule'] as Map)['blocks'] as List).single as Map;
    expect(
      block['ends_at'],
      DateTime.parse('2026-11-17T00:00:00+08:00').toUtc().toIso8601String(),
    );
  });

  test(
    'exact deadline is a time instant and is not expanded to end of day',
    () {
      final result = engine.preview(
        _snapshot(
          tasks: [
            _task(
              'exact',
              seconds: 3600,
              deadline: '2026-11-15T09:45:00+08:00',
            ),
          ],
        ),
      );
      expect(result['outcome'], 'no_solution_found');
      expect(((result['schedule'] as Map)['blocks'] as List), isEmpty);
      expect(((result['schedule'] as Map)['optimality_proven']), isFalse);
    },
  );

  test(
    'unknown effort and deadline remain unknown instead of being invented',
    () {
      final result = engine.preview(
        _snapshot(
          tasks: [_task('unknown', seconds: null, deadlineDate: null)],
          sync: 'pending_local_changes',
        ),
      );
      expect(result['outcome'], 'unknown_due_to_missing_data');
      expect(result['provisional'], isTrue);
      final missing = result['missing_data'] as Map;
      expect(missing['unknown_effort_task_ids'], ['unknown']);
      expect(missing['missing_deadline_task_ids'], ['unknown']);
      expect(((result['schedule'] as Map)['blocks'] as List), isEmpty);
    },
  );

  test('delay can remain feasible and does not mutate the input snapshot', () {
    final input = _snapshot(
      horizon: '2026-11-17T18:00:00+08:00',
      tasks: [_task('report', seconds: 3600, deadlineDate: '2026-11-17')],
    );
    final beforeJson = input.toString();
    final result = engine.simulateDelay(
      input,
      taskId: 'report',
      until: DateTime.parse('2026-11-16T09:00:00+08:00'),
    );
    final analysis = result['delay_analysis'] as Map;
    expect(analysis['before_feasible'], isTrue);
    expect(analysis['after_feasible'], isTrue);
    expect(analysis['optimality_proven'], isFalse);
    expect(input.toString(), beforeJson);
  });

  test('delay after the deadline reports heuristic no-solution found', () {
    final input = _snapshot(
      tasks: [_task('report', seconds: 1800, deadlineDate: '2026-11-15')],
    );
    final result = engine.simulateDelay(
      input,
      taskId: 'report',
      until: DateTime.parse('2026-11-16T09:00:00+08:00'),
    );
    final analysis = result['delay_analysis'] as Map;
    expect(analysis['before_feasible'], isTrue);
    expect(analysis['after_feasible'], isFalse);
    expect(analysis['optimality_proven'], isFalse);
    expect(((analysis['after'] as Map)['unplanned_tasks'] as List), isNotEmpty);
  });

  test('risk analysis reports missed plans and excludes completed tasks', () {
    final input = _snapshot(
      now: '2026-11-15T12:00:00+08:00',
      tasks: [
        _task('missed', seconds: 3600, deadlineDate: '2026-11-15')
          ..['planned_at'] = '2026-11-15T10:00:00+08:00',
        _task('done', seconds: 3600, deadlineDate: '2026-11-15')
          ..['completion_status'] = 'completed',
      ],
    );
    final risks = engine.assessRisks(input)['risks'] as List;
    expect(risks, isNotEmpty);
    expect(
      risks.every((risk) => (risk as Map)['affected_task_ids'] != ['done']),
      isTrue,
    );
    expect(
      risks.any((risk) => (risk as Map)['risk_type'] == 'plan_missed'),
      isTrue,
    );
  });

  test('priority and EDF tie ordering are deterministic', () {
    final result = engine.preview(
      _snapshot(
        tasks: [
          _task('late', seconds: 1800, deadline: '2026-11-15T14:00:00+08:00'),
          _task('early', seconds: 1800, deadline: '2026-11-15T11:00:00+08:00'),
        ],
      ),
    );
    final blocks = ((result['schedule'] as Map)['blocks'] as List).cast<Map>();
    expect(blocks.first['task_id'], 'early');
  });

  test(
    'invalid intervals, bad dates, wrong timezone and caller user id fail closed',
    () {
      final cases = [
        _snapshot(
          courses: [
            _block('2026-11-15T11:00:00+08:00', '2026-11-15T10:00:00+08:00'),
          ],
        ),
        _snapshot(
          tasks: [_task('bad-date', seconds: 60, deadlineDate: '2026-02-30')],
        ),
        _snapshot()..['timezone'] = 'UTC',
        _snapshot()..['user_id'] = 'spoofed',
        _snapshot(now: '2026-11-15T09:00:00', tasks: []),
      ];
      for (final input in cases) {
        expect(engine.preview(input)['error'], isA<Map>());
      }
    },
  );

  test(
    'snapshot version change rejects reuse and delay task access is scoped',
    () {
      final input = _snapshot(
        tasks: [_task('own', seconds: 1800, deadlineDate: '2026-11-15')],
      );
      expect(
        engine.preview(input, expectedVersion: 'stale')['error'],
        isA<Map>(),
      );
      expect(
        engine.simulateDelay(
          input,
          taskId: 'other-users-task',
          until: DateTime.parse('2026-11-15T10:00:00+08:00'),
        )['error'],
        isA<Map>(),
      );
    },
  );
}

Map<String, Object?> _snapshot({
  String now = '2026-11-15T09:00:00+08:00',
  String horizon = '2026-11-15T18:00:00+08:00',
  String sync = 'current',
  List<Map<String, Object?>> tasks = const [],
  List<Map<String, Object?>> courses = const [],
  List<Map<String, Object?>> occupied = const [],
}) => {
  'schema_version': 'checkd.planning.snapshot.v1',
  'subject_ref': 'user-a',
  'source': 'flutter_drift_test',
  'captured_at': now,
  'version': 'snapshot-v1',
  'sync_state': sync,
  'provisional': sync != 'current',
  'timezone': 'Asia/Shanghai',
  'now': now,
  'horizon_end': horizon,
  'tasks': tasks,
  'course_occurrences': courses,
  'occupied_blocks': occupied,
  'unmodeled_recurring_occurrence_ids': <String>[],
};

Map<String, Object?> _task(
  String id, {
  required int? seconds,
  String? deadline,
  String? deadlineDate,
}) => {
  'task_id': id,
  'name': id,
  'kind': 'one_time',
  'completion_status': 'pending',
  'remaining_seconds': seconds,
  'remaining_effort_state': seconds == null ? 'unknown' : 'known',
  'deadline_at': deadline,
  'deadline_date': deadlineDate,
  'earliest_start': '2026-11-15T09:00:00+08:00',
  'planned_at': null,
  'splittable': true,
  'minimum_block_minutes': 30,
  'priority': 0,
};

Map<String, Object?> _block(String start, String end) => {
  'starts_at': start,
  'ends_at': end,
  'kind': 'course',
};
