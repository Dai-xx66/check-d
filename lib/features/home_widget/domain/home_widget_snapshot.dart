import '../../mini_window/domain/mini_window_models.dart';
import '../../tasks/domain/task_models.dart';

/// The single business projection shared by Android AppWidget and WidgetKit.
///
/// It consumes the existing MiniWindow snapshot, which already owns effective
/// course occurrences, CourseOccurrenceTiming and stable Multi Timer order.
/// Native code only decodes and presents this value.
class HomeWidgetSnapshot {
  const HomeWidgetSnapshot({
    required this.generatedAt,
    required this.date,
    required this.current,
    this.next,
    required this.today,
  });

  factory HomeWidgetSnapshot.fromMiniWindow(MiniWindowSnapshot source) {
    final primaryCourse = source.currentCourses.isEmpty
        ? null
        : source.currentCourses.first;
    final primaryTimer = source.timers.isEmpty ? null : source.timers.first;
    final current = primaryCourse == null
        ? _currentFromTimer(primaryTimer)
        : _currentFromCourse(primaryCourse, primaryTimer, source.timers.length);

    final next = source.nextCourse != null
        ? HomeWidgetNext.course(source.nextCourse!)
        : source.nextScheduledItem != null
        ? HomeWidgetNext.scheduled(source.nextScheduledItem!)
        : _untimedPending(source.pendingItems);

    return HomeWidgetSnapshot(
      generatedAt: source.now,
      date: DateTime(source.now.year, source.now.month, source.now.day),
      current: current,
      next: next,
      today: HomeWidgetTodaySummary(
        completedCount: source.completedTaskCount,
        pendingCount: (source.totalTaskCount - source.completedTaskCount)
            .clamp(0, source.totalTaskCount)
            .toInt(),
      ),
    );
  }

  final DateTime generatedAt;
  final DateTime date;
  final HomeWidgetCurrent current;
  final HomeWidgetNext? next;
  final HomeWidgetTodaySummary today;

  Map<String, dynamic> toJson() => {
    'schemaVersion': 2,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'dateKey': _dateKey(date),
    'dateText': '${date.month}月${date.day}日 ${_weekdayLabel(date.weekday)}',
    'current': current.toJson(),
    'next': next?.toJson(),
    'today': today.toJson(),
  };

  static HomeWidgetCurrent _currentFromCourse(
    MiniCourseItem course,
    MiniTimerItem? timer,
    int timerCount,
  ) {
    final isBreak = course.phase == MiniCoursePhase.breakTime;
    return HomeWidgetCurrent(
      mode: isBreak
          ? HomeWidgetCurrentMode.courseBreak
          : HomeWidgetCurrentMode.courseTeaching,
      title: course.title,
      subtitle: isBreak ? '课间休息' : '上课中',
      timeText: isBreak && course.nextSegmentMinute != null
          ? '${_minute(course.nextSegmentMinute!)} 后继续'
          : '${_minute(course.startMinute)} - ${_minute(course.endMinute)}',
      sheepState: isBreak ? 'breakTime' : 'course',
      progress: course.progress,
      concurrentTimer: timer == null ? null : HomeWidgetTimer.fromMini(timer),
      additionalTimerCount: timer == null ? 0 : timerCount - 1,
    );
  }

  static HomeWidgetCurrent _currentFromTimer(MiniTimerItem? timer) {
    if (timer == null) {
      return const HomeWidgetCurrent(
        mode: HomeWidgetCurrentMode.idle,
        title: '今天慢慢来 ♡',
        subtitle: '暂无进行中的事项',
        sheepState: 'idle',
      );
    }
    final isRunning = timer.status == TimerStatus.running;
    return HomeWidgetCurrent(
      mode: isRunning
          ? HomeWidgetCurrentMode.timerRunning
          : HomeWidgetCurrentMode.timerPaused,
      title: timer.title,
      subtitle: isRunning ? '专注进行中' : '已暂停',
      timeText:
          '${isRunning ? '已专注' : '累计'} ${_duration(timer.elapsedSeconds)}',
      sheepState: isRunning ? 'focus' : 'paused',
      concurrentTimer: HomeWidgetTimer.fromMini(timer),
    );
  }

  static HomeWidgetNext? _untimedPending(List<MiniPendingItem> items) {
    final item = items.where((item) => item.plannedMinute == null).firstOrNull;
    return item == null ? null : HomeWidgetNext.pending(item);
  }

  static String _minute(int value) =>
      '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';

  static String _duration(int seconds) {
    final minutes = seconds ~/ 60;
    return minutes >= 60 ? '${minutes ~/ 60}小时${minutes % 60}分' : '$minutes 分钟';
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _weekdayLabel(int weekday) =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];
}

enum HomeWidgetCurrentMode {
  idle,
  courseTeaching,
  courseBreak,
  timerRunning,
  timerPaused,
}

class HomeWidgetCurrent {
  const HomeWidgetCurrent({
    required this.mode,
    required this.title,
    required this.subtitle,
    required this.sheepState,
    this.timeText,
    this.progress,
    this.concurrentTimer,
    this.additionalTimerCount = 0,
  });

  final HomeWidgetCurrentMode mode;
  final String title;
  final String subtitle;
  final String? timeText;
  final String sheepState;
  final double? progress;
  final HomeWidgetTimer? concurrentTimer;
  final int additionalTimerCount;

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'title': title,
    'subtitle': subtitle,
    'timeText': timeText,
    'sheepState': sheepState,
    'progress': progress,
    'concurrentTimer': concurrentTimer?.toJson(),
    'additionalTimerCount': additionalTimerCount,
  };
}

class HomeWidgetTimer {
  const HomeWidgetTimer({
    required this.id,
    required this.title,
    required this.status,
    required this.elapsedSeconds,
  });

  factory HomeWidgetTimer.fromMini(MiniTimerItem source) => HomeWidgetTimer(
    id: source.id,
    title: source.title,
    status: source.status.name,
    elapsedSeconds: source.elapsedSeconds,
  );

  final String id;
  final String title;
  final String status;
  final int elapsedSeconds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'status': status,
    'elapsedSeconds': elapsedSeconds,
  };
}

enum HomeWidgetNextType { course, scheduledItem, pendingItem }

class HomeWidgetNext {
  const HomeWidgetNext({
    required this.type,
    required this.title,
    required this.timeText,
    this.location,
  });

  factory HomeWidgetNext.course(MiniCourseItem source) => HomeWidgetNext(
    type: HomeWidgetNextType.course,
    title: source.title,
    timeText: HomeWidgetSnapshot._minute(source.startMinute),
    location: source.classroom,
  );

  factory HomeWidgetNext.scheduled(MiniScheduledItem source) => HomeWidgetNext(
    type: HomeWidgetNextType.scheduledItem,
    title: source.title,
    timeText: HomeWidgetSnapshot._minute(source.plannedMinute),
  );

  factory HomeWidgetNext.pending(MiniPendingItem source) => HomeWidgetNext(
    type: HomeWidgetNextType.pendingItem,
    title: source.title,
    timeText: '时间未定',
  );

  final HomeWidgetNextType type;
  final String title;
  final String timeText;
  final String? location;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'title': title,
    'timeText': timeText,
    'location': location,
  };
}

class HomeWidgetTodaySummary {
  const HomeWidgetTodaySummary({
    required this.completedCount,
    required this.pendingCount,
  });

  final int completedCount;
  final int pendingCount;

  Map<String, dynamic> toJson() => {
    'completedCount': completedCount,
    'pendingCount': pendingCount,
  };
}
