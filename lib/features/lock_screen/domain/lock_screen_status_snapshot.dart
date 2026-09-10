import '../../calendar/domain/calendar_models.dart';
import '../../mini_window/domain/mini_window_models.dart';
import '../../tasks/domain/task_models.dart';

/// A native-display-only projection of the existing course and timer state.
///
/// It deliberately consumes the MiniWindow snapshot because that is already
/// the shared projection for effective courses, course timing and Multi Timer
/// ordering. Native platforms receive this data and never infer recurrences.
enum LockScreenStatusMode {
  idle,
  courseTeaching,
  courseBreak,
  timerRunning,
  timerPaused,
}

class LockScreenStatusSnapshot {
  const LockScreenStatusSnapshot({
    required this.generatedAt,
    required this.mode,
    this.course,
    this.timer,
    this.nextCourse,
    this.additionalTimerCount = 0,
  });

  factory LockScreenStatusSnapshot.fromMiniWindow(MiniWindowSnapshot source) {
    final primaryTimer = source.timers.firstOrNull;
    final timer = primaryTimer == null
        ? null
        : LockScreenTimerStatus.fromMini(primaryTimer, source.now);
    final additionalTimerCount = source.timers.length - (timer == null ? 0 : 1);
    final currentCourse = source.currentCourses.firstOrNull;
    if (currentCourse != null) {
      return LockScreenStatusSnapshot(
        generatedAt: source.now,
        mode: currentCourse.phase == MiniCoursePhase.breakTime
            ? LockScreenStatusMode.courseBreak
            : LockScreenStatusMode.courseTeaching,
        course: LockScreenCourseStatus.fromMini(currentCourse),
        timer: timer,
        nextCourse: source.nextCourse == null
            ? null
            : LockScreenNextCourse.fromMini(source.nextCourse!),
        additionalTimerCount: additionalTimerCount,
      );
    }

    if (primaryTimer != null) {
      return LockScreenStatusSnapshot(
        generatedAt: source.now,
        mode: primaryTimer.status == TimerStatus.running
            ? LockScreenStatusMode.timerRunning
            : LockScreenStatusMode.timerPaused,
        timer: timer,
        nextCourse: source.nextCourse == null
            ? null
            : LockScreenNextCourse.fromMini(source.nextCourse!),
        additionalTimerCount: additionalTimerCount,
      );
    }

    return LockScreenStatusSnapshot(
      generatedAt: source.now,
      mode: LockScreenStatusMode.idle,
      nextCourse: source.nextCourse == null
          ? null
          : LockScreenNextCourse.fromMini(source.nextCourse!),
    );
  }

  final DateTime generatedAt;
  final LockScreenStatusMode mode;
  final LockScreenCourseStatus? course;
  final LockScreenTimerStatus? timer;
  final LockScreenNextCourse? nextCourse;
  final int additionalTimerCount;

  bool get isIdle => mode == LockScreenStatusMode.idle;

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'generatedAtEpochMs': generatedAt.millisecondsSinceEpoch,
    'mode': mode.name,
    'course': course?.toJson(),
    'timer': timer?.toJson(),
    'nextCourse': nextCourse?.toJson(),
    'additionalTimerCount': additionalTimerCount,
  };
}

class LockScreenCourseStatus {
  const LockScreenCourseStatus({
    required this.id,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.phase,
    required this.progress,
    required this.segments,
    this.classroom,
  });

  factory LockScreenCourseStatus.fromMini(MiniCourseItem source) {
    DateTime dateAt(int minute) => DateTime(
      source.date.year,
      source.date.month,
      source.date.day,
      minute ~/ 60,
      minute % 60,
    );
    return LockScreenCourseStatus(
      id: source.id,
      title: source.title,
      startAt: dateAt(source.startMinute),
      endAt: dateAt(source.endMinute),
      phase: source.currentPhase.kind,
      progress: source.progress,
      segments: source.timing.phases
          .map(
            (phase) => LockScreenCourseSegment(
              kind: phase.kind,
              startAt: dateAt(phase.startMinute),
              endAt: dateAt(phase.endMinute),
            ),
          )
          .toList(),
      classroom: source.classroom,
    );
  }

  final String id;
  final String title;
  final DateTime startAt;
  final DateTime endAt;
  final CourseOccurrencePhaseKind phase;
  final double progress;
  final List<LockScreenCourseSegment> segments;
  final String? classroom;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'startAtEpochMs': startAt.millisecondsSinceEpoch,
    'endAtEpochMs': endAt.millisecondsSinceEpoch,
    'phase': phase.name,
    'progress': progress,
    'segments': segments.map((segment) => segment.toJson()).toList(),
    'classroom': classroom,
  };
}

class LockScreenCourseSegment {
  const LockScreenCourseSegment({
    required this.kind,
    required this.startAt,
    required this.endAt,
  });

  final CourseOccurrencePhaseKind kind;
  final DateTime startAt;
  final DateTime endAt;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'startAtEpochMs': startAt.millisecondsSinceEpoch,
    'endAtEpochMs': endAt.millisecondsSinceEpoch,
  };
}

class LockScreenTimerStatus {
  const LockScreenTimerStatus({
    required this.id,
    required this.title,
    required this.status,
    required this.elapsedSeconds,
    this.runningSince,
    this.targetSeconds,
  });

  factory LockScreenTimerStatus.fromMini(
    MiniTimerItem source,
    DateTime now,
  ) => LockScreenTimerStatus(
    id: source.id,
    title: source.title,
    status: source.status,
    elapsedSeconds: source.elapsedSeconds,
    // The projection uses a synthetic epoch only for the native chronometer.
    // It does not persist or alter TimerSession records.
    runningSince: source.status == TimerStatus.running
        ? now.subtract(Duration(seconds: source.elapsedSeconds))
        : null,
    targetSeconds: source.targetSeconds,
  );

  final String id;
  final String title;
  final TimerStatus status;
  final int elapsedSeconds;
  final DateTime? runningSince;
  final int? targetSeconds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'status': status.name,
    'elapsedSeconds': elapsedSeconds,
    'runningSinceEpochMs': runningSince?.millisecondsSinceEpoch,
    'targetSeconds': targetSeconds,
  };
}

class LockScreenNextCourse {
  const LockScreenNextCourse({
    required this.title,
    required this.startAt,
    this.classroom,
  });

  factory LockScreenNextCourse.fromMini(MiniCourseItem source) =>
      LockScreenNextCourse(
        title: source.title,
        startAt: DateTime(
          source.date.year,
          source.date.month,
          source.date.day,
          source.startMinute ~/ 60,
          source.startMinute % 60,
        ),
        classroom: source.classroom,
      );

  final String title;
  final DateTime startAt;
  final String? classroom;

  Map<String, dynamic> toJson() => {
    'title': title,
    'startAtEpochMs': startAt.millisecondsSinceEpoch,
    'classroom': classroom,
  };
}
