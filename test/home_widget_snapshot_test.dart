import 'package:check_d/features/calendar/domain/calendar_models.dart';
import 'package:check_d/features/home_widget/domain/home_widget_snapshot.dart';
import 'package:check_d/features/mini_window/domain/mini_window_models.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 10, 9, 10);

  MiniTimerItem timer({
    required String id,
    required String title,
    required TimerStatus status,
    int elapsedSeconds = 90,
  }) => MiniTimerItem(
    id: id,
    kind: MiniTimerKind.task,
    title: title,
    status: status,
    elapsedSeconds: elapsedSeconds,
    lastActivity: now,
  );

  MiniCourseItem course({MiniCoursePhase phase = MiniCoursePhase.active}) =>
      MiniCourseItem(
        id: 'course',
        title: '高等数学',
        date: now,
        startMinute: 8 * 60,
        endMinute: 9 * 60 + 45,
        phase: phase,
        progress: .5,
        timing: CourseOccurrenceTiming.single(
          id: 'course',
          label: '高等数学',
          startMinute: 8 * 60,
          endMinute: 9 * 60 + 45,
        ),
        currentPhase: const CourseOccurrencePhase(
          kind: CourseOccurrencePhaseKind.teaching,
          startMinute: 8 * 60,
          endMinute: 9 * 60 + 45,
        ),
        nextSegmentMinute: 9 * 60 + 5,
        classroom: 'A203',
      );

  MiniWindowSnapshot source({
    List<MiniCourseItem> currentCourses = const [],
    List<MiniTimerItem> timers = const [],
    List<MiniPendingItem> pending = const [],
    MiniCourseItem? nextCourse,
    MiniScheduledItem? nextScheduled,
    int completed = 0,
    int total = 0,
  }) => MiniWindowSnapshot(
    now: now,
    currentCourses: currentCourses,
    timers: timers,
    pendingItems: pending,
    nextCourse: nextCourse,
    nextScheduledItem: nextScheduled,
    completedTaskCount: completed,
    totalTaskCount: total,
  );

  test('idle snapshot has safe current and untimed pending fallback', () {
    final snapshot = HomeWidgetSnapshot.fromMiniWindow(
      source(
        pending: const [MiniPendingItem(id: 'read', title: '阅读')],
      ),
    );

    expect(snapshot.current.mode, HomeWidgetCurrentMode.idle);
    expect(snapshot.current.sheepState, 'idle');
    expect(snapshot.next?.type, HomeWidgetNextType.pendingItem);
    expect(snapshot.next?.title, '阅读');
  });

  test('course teaching is primary and keeps running timer concurrent', () {
    final snapshot = HomeWidgetSnapshot.fromMiniWindow(
      source(
        currentCourses: [course()],
        timers: [
          timer(id: 'focus', title: '数据库作业', status: TimerStatus.running),
        ],
      ),
    );

    expect(snapshot.current.mode, HomeWidgetCurrentMode.courseTeaching);
    expect(snapshot.current.sheepState, 'course');
    expect(snapshot.current.concurrentTimer?.title, '数据库作业');
  });

  test('course break remains primary and exposes paused timer', () {
    final snapshot = HomeWidgetSnapshot.fromMiniWindow(
      source(
        currentCourses: [course(phase: MiniCoursePhase.breakTime)],
        timers: [
          timer(id: 'paused', title: '英语听力', status: TimerStatus.paused),
        ],
      ),
    );

    expect(snapshot.current.mode, HomeWidgetCurrentMode.courseBreak);
    expect(snapshot.current.sheepState, 'breakTime');
    expect(snapshot.current.concurrentTimer?.status, 'paused');
  });

  test(
    'timer-only projection keeps running before paused and counts extras',
    () {
      final snapshot = HomeWidgetSnapshot.fromMiniWindow(
        source(
          timers: [
            timer(id: 'running', title: '背单词', status: TimerStatus.running),
            timer(id: 'paused', title: '临时专注', status: TimerStatus.paused),
          ],
        ),
      );

      expect(snapshot.current.mode, HomeWidgetCurrentMode.timerRunning);
      expect(snapshot.current.title, '背单词');
      expect(snapshot.current.sheepState, 'focus');
    },
  );

  test('paused timer is primary when no running timer exists', () {
    final snapshot = HomeWidgetSnapshot.fromMiniWindow(
      source(
        timers: [
          timer(id: 'paused', title: '英语听力', status: TimerStatus.paused),
        ],
      ),
    );

    expect(snapshot.current.mode, HomeWidgetCurrentMode.timerPaused);
    expect(snapshot.current.timeText, '累计 1 分钟');
  });

  test('course plus multiple timers exposes primary and extra count', () {
    final snapshot = HomeWidgetSnapshot.fromMiniWindow(
      source(
        currentCourses: [course()],
        timers: [
          timer(id: 'a', title: '数据库作业', status: TimerStatus.running),
          timer(id: 'b', title: '背单词', status: TimerStatus.running),
        ],
      ),
    );

    expect(snapshot.current.concurrentTimer?.title, '数据库作业');
    expect(snapshot.current.additionalTimerCount, 1);
  });

  test('next prioritizes course, then precise item, then untimed pending', () {
    final laterCourse = course().copyWithStart(10 * 60);
    final withCourse = HomeWidgetSnapshot.fromMiniWindow(
      source(
        nextCourse: laterCourse,
        nextScheduled: const MiniScheduledItem(
          id: 'timed',
          title: '开会',
          plannedMinute: 11 * 60,
        ),
      ),
    );
    final withScheduled = HomeWidgetSnapshot.fromMiniWindow(
      source(
        nextScheduled: const MiniScheduledItem(
          id: 'timed',
          title: '开会',
          plannedMinute: 11 * 60,
        ),
      ),
    );

    expect(withCourse.next?.type, HomeWidgetNextType.course);
    expect(withScheduled.next?.type, HomeWidgetNextType.scheduledItem);
    expect(withScheduled.next?.timeText, '11:00');
  });

  test('today summary uses task counts and never includes a course', () {
    final snapshot = HomeWidgetSnapshot.fromMiniWindow(
      source(currentCourses: [course()], completed: 2, total: 5),
    );

    expect(snapshot.today.completedCount, 2);
    expect(snapshot.today.pendingCount, 3);
  });

  test('serialization is v2, null-safe and date-specific', () {
    final snapshot = HomeWidgetSnapshot.fromMiniWindow(
      source(nextCourse: course().withoutClassroom()),
    );
    final json = snapshot.toJson();

    expect(json['schemaVersion'], 2);
    expect(json['dateKey'], '2026-09-10');
    expect((json['next'] as Map<String, dynamic>)['location'], isNull);
    expect(json['generatedAt'], contains('Z'));
  });
}

extension on MiniCourseItem {
  MiniCourseItem copyWithStart(int startMinute) => MiniCourseItem(
    id: id,
    title: title,
    date: date,
    startMinute: startMinute,
    endMinute: endMinute,
    phase: phase,
    progress: progress,
    timing: timing,
    currentPhase: currentPhase,
    nextSegmentMinute: nextSegmentMinute,
    classroom: classroom,
  );

  MiniCourseItem withoutClassroom() => MiniCourseItem(
    id: id,
    title: title,
    date: date,
    startMinute: startMinute,
    endMinute: endMinute,
    phase: phase,
    progress: progress,
    timing: timing,
    currentPhase: currentPhase,
    nextSegmentMinute: nextSegmentMinute,
  );
}
