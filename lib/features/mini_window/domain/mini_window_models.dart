import '../../tasks/domain/task_models.dart';
import '../../calendar/domain/calendar_models.dart';

enum MiniTimerKind { task, adHoc }

class MiniTimerItem {
  const MiniTimerItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.status,
    required this.elapsedSeconds,
    required this.lastActivity,
    this.targetSeconds,
  });

  final String id;
  final MiniTimerKind kind;
  final String title;
  final TimerStatus status;
  final int elapsedSeconds;
  final int? targetSeconds;
  final DateTime lastActivity;

  bool get isRunning => status == TimerStatus.running;

  MiniTimerQuickAction? get hoverAction => switch (status) {
    TimerStatus.running => MiniTimerQuickAction.pause,
    TimerStatus.paused => MiniTimerQuickAction.resume,
    TimerStatus.idle => null,
  };
}

enum MiniTimerQuickAction { pause, resume }

enum MiniCoursePhase { active, breakTime }

class MiniCourseItem {
  const MiniCourseItem({
    required this.id,
    required this.title,
    required this.date,
    required this.startMinute,
    required this.endMinute,
    required this.phase,
    required this.progress,
    required this.timing,
    required this.currentPhase,
    this.nextSegmentMinute,
    this.classroom,
  });

  final String id;
  final String title;
  final DateTime date;
  final int startMinute;
  final int endMinute;
  final MiniCoursePhase phase;
  final double progress;
  final CourseOccurrenceTiming timing;
  final CourseOccurrencePhase currentPhase;
  final int? nextSegmentMinute;
  final String? classroom;
}

class MiniPendingItem {
  const MiniPendingItem({
    required this.id,
    required this.title,
    this.targetSeconds,
    this.plannedMinute,
  });

  final String id;
  final String title;
  final int? targetSeconds;
  final int? plannedMinute;
}

/// A read-only, precisely scheduled task used by companion surfaces.
///
/// This preserves the Today projection's distinction between timed timeline
/// items and untimed pending items without introducing any new task rule.
class MiniScheduledItem {
  const MiniScheduledItem({
    required this.id,
    required this.title,
    required this.plannedMinute,
  });

  final String id;
  final String title;
  final int plannedMinute;
}

class MiniWindowSnapshot {
  const MiniWindowSnapshot({
    required this.now,
    required this.currentCourses,
    required this.timers,
    this.pendingItems = const [],
    this.completedTaskCount = 0,
    this.totalTaskCount = 0,
    this.nextCourse,
    this.nextScheduledItem,
  });

  final DateTime now;
  final List<MiniCourseItem> currentCourses;
  final List<MiniTimerItem> timers;
  final List<MiniPendingItem> pendingItems;
  final int completedTaskCount;
  final int totalTaskCount;
  final MiniCourseItem? nextCourse;
  final MiniScheduledItem? nextScheduledItem;

  List<MiniTimerItem> get runningTimers =>
      timers.where((item) => item.status == TimerStatus.running).toList();
  List<MiniTimerItem> get pausedTimers =>
      timers.where((item) => item.status == TimerStatus.paused).toList();
  bool get isIdle => currentCourses.isEmpty && timers.isEmpty;
}

class MiniWindowPreferences {
  const MiniWindowPreferences({this.compact = false, this.x, this.y});

  final bool compact;
  final double? x;
  final double? y;

  MiniWindowPreferences copyWith({bool? compact, double? x, double? y}) =>
      MiniWindowPreferences(
        compact: compact ?? this.compact,
        x: x ?? this.x,
        y: y ?? this.y,
      );
}
