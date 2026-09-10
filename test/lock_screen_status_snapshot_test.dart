import 'package:check_d/features/calendar/domain/calendar_models.dart';
import 'package:check_d/features/lock_screen/domain/lock_screen_status_snapshot.dart';
import 'package:check_d/features/mini_window/domain/mini_window_models.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 10, 8, 50);

void main() {
  test('course teaching remains primary and includes a running timer', () {
    final course = _course(_now, atMinute: 8 * 60 + 20);
    final snapshot = LockScreenStatusSnapshot.fromMiniWindow(
      MiniWindowSnapshot(
        now: _now,
        currentCourses: [course],
        timers: [_runningTimer('背单词'), _pausedTimer('英语阅读')],
        nextCourse: _nextCourse(_now),
      ),
    );

    expect(snapshot.mode, LockScreenStatusMode.courseTeaching);
    expect(snapshot.course?.title, '高等数学');
    expect(snapshot.course?.segments, hasLength(3));
    expect(snapshot.timer?.title, '背单词');
    expect(snapshot.timer?.status, TimerStatus.running);
    expect(snapshot.additionalTimerCount, 1);
    expect(snapshot.nextCourse?.title, '数据库原理');
  });

  test('multi-segment course exposes an actual derived break', () {
    final course = _course(_now, atMinute: 8 * 60 + 50);
    final snapshot = LockScreenStatusSnapshot.fromMiniWindow(
      MiniWindowSnapshot(now: _now, currentCourses: [course], timers: const []),
    );

    expect(snapshot.mode, LockScreenStatusMode.courseBreak);
    expect(snapshot.course?.phase, CourseOccurrencePhaseKind.breakTime);
    expect(
      snapshot.course?.segments[1].kind,
      CourseOccurrencePhaseKind.breakTime,
    );
  });

  test(
    'running timer wins over paused timers with stable additional count',
    () {
      final snapshot = LockScreenStatusSnapshot.fromMiniWindow(
        MiniWindowSnapshot(
          now: _now,
          currentCourses: const [],
          timers: [_runningTimer('数据库作业'), _pausedTimer('英语阅读')],
        ),
      );

      expect(snapshot.mode, LockScreenStatusMode.timerRunning);
      expect(snapshot.timer?.title, '数据库作业');
      expect(snapshot.additionalTimerCount, 1);
      expect(
        snapshot.timer?.runningSince,
        _now.subtract(const Duration(minutes: 25)),
      );
    },
  );

  test(
    'paused timer preserves accumulated time without a running timestamp',
    () {
      final snapshot = LockScreenStatusSnapshot.fromMiniWindow(
        MiniWindowSnapshot(
          now: _now,
          currentCourses: const [],
          timers: [_pausedTimer('英语单词')],
        ),
      );

      expect(snapshot.mode, LockScreenStatusMode.timerPaused);
      expect(snapshot.timer?.elapsedSeconds, 35 * 60);
      expect(snapshot.timer?.runningSince, isNull);
    },
  );

  test('finished course and timer reconcile to idle and serialize safely', () {
    final snapshot = LockScreenStatusSnapshot.fromMiniWindow(
      MiniWindowSnapshot(now: _now, currentCourses: const [], timers: const []),
    );

    expect(snapshot.isIdle, isTrue);
    expect(snapshot.toJson()['mode'], 'idle');
    expect(snapshot.toJson()['schemaVersion'], 1);
  });

  test('course with only a paused timer includes paused summary', () {
    final snapshot = LockScreenStatusSnapshot.fromMiniWindow(
      MiniWindowSnapshot(
        now: _now,
        currentCourses: [_course(_now, atMinute: 8 * 60 + 20)],
        timers: [_pausedTimer('英语听力')],
      ),
    );

    expect(snapshot.mode, LockScreenStatusMode.courseTeaching);
    expect(snapshot.timer?.title, '英语听力');
    expect(snapshot.timer?.status, TimerStatus.paused);
    expect(snapshot.additionalTimerCount, 0);
  });

  test('course with multiple running timers preserves primary and count', () {
    final snapshot = LockScreenStatusSnapshot.fromMiniWindow(
      MiniWindowSnapshot(
        now: _now,
        currentCourses: [_course(_now, atMinute: 8 * 60 + 20)],
        timers: [_runningTimer('数据库作业'), _runningTimer('算法练习')],
      ),
    );

    expect(snapshot.mode, LockScreenStatusMode.courseTeaching);
    expect(snapshot.timer?.title, '数据库作业');
    expect(snapshot.additionalTimerCount, 1);
  });

  test('course break remains primary while exposing a running timer', () {
    final snapshot = LockScreenStatusSnapshot.fromMiniWindow(
      MiniWindowSnapshot(
        now: _now,
        currentCourses: [_course(_now, atMinute: 8 * 60 + 50)],
        timers: [_runningTimer('数据库作业')],
      ),
    );

    expect(snapshot.mode, LockScreenStatusMode.courseBreak);
    expect(snapshot.timer?.status, TimerStatus.running);
  });

  test('course without a timer remains a course-only projection', () {
    final snapshot = LockScreenStatusSnapshot.fromMiniWindow(
      MiniWindowSnapshot(
        now: _now,
        currentCourses: [_course(_now, atMinute: 8 * 60 + 20)],
        timers: const [],
      ),
    );

    expect(snapshot.mode, LockScreenStatusMode.courseTeaching);
    expect(snapshot.timer, isNull);
    expect(snapshot.additionalTimerCount, 0);
  });

  test('timer without a course keeps timer as the primary state', () {
    final snapshot = LockScreenStatusSnapshot.fromMiniWindow(
      MiniWindowSnapshot(
        now: _now,
        currentCourses: const [],
        timers: [_runningTimer('数据库作业')],
      ),
    );

    expect(snapshot.mode, LockScreenStatusMode.timerRunning);
    expect(snapshot.course, isNull);
    expect(snapshot.timer?.title, '数据库作业');
  });

  test('course and timer projection is read-only', () {
    final course = _course(_now, atMinute: 8 * 60 + 20);
    final timer = _runningTimer('数据库作业');
    LockScreenStatusSnapshot.fromMiniWindow(
      MiniWindowSnapshot(now: _now, currentCourses: [course], timers: [timer]),
    );

    expect(course.phase, MiniCoursePhase.active);
    expect(timer.status, TimerStatus.running);
    expect(timer.elapsedSeconds, 25 * 60);
  });
}

MiniCourseItem _course(DateTime date, {required int atMinute}) {
  final timing = CourseOccurrenceTiming.fromTeachingSegments(const [
    CourseTeachingSegment(
      id: 'first',
      label: '第 1 节',
      startMinute: 8 * 60,
      endMinute: 8 * 60 + 45,
      index: 0,
      total: 2,
    ),
    CourseTeachingSegment(
      id: 'second',
      label: '第 2 节',
      startMinute: 8 * 60 + 55,
      endMinute: 9 * 60 + 40,
      index: 1,
      total: 2,
    ),
  ]);
  final phase = timing.phaseAt(atMinute);
  return MiniCourseItem(
    id: 'math',
    title: '高等数学',
    date: date,
    startMinute: timing.startMinute,
    endMinute: timing.endMinute,
    phase: phase.kind == CourseOccurrencePhaseKind.breakTime
        ? MiniCoursePhase.breakTime
        : MiniCoursePhase.active,
    progress: timing.overallProgressAt(atMinute),
    timing: timing,
    currentPhase: phase,
    classroom: '教学楼 A203',
  );
}

MiniCourseItem _nextCourse(DateTime date) => MiniCourseItem(
  id: 'database',
  title: '数据库原理',
  date: date,
  startMinute: 10 * 60,
  endMinute: 10 * 60 + 40,
  phase: MiniCoursePhase.active,
  progress: 0,
  timing: CourseOccurrenceTiming.single(
    startMinute: 10 * 60,
    endMinute: 10 * 60 + 40,
  ),
  currentPhase: CourseOccurrenceTiming.single(
    startMinute: 10 * 60,
    endMinute: 10 * 60 + 40,
  ).phaseAt(10 * 60),
  classroom: '教三 205',
);

MiniTimerItem _runningTimer(String title) => MiniTimerItem(
  id: title,
  kind: MiniTimerKind.task,
  title: title,
  status: TimerStatus.running,
  elapsedSeconds: 25 * 60,
  lastActivity: _now,
);

MiniTimerItem _pausedTimer(String title) => MiniTimerItem(
  id: title,
  kind: MiniTimerKind.task,
  title: title,
  status: TimerStatus.paused,
  elapsedSeconds: 35 * 60,
  lastActivity: _now,
);
