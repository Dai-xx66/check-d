import '../../tasks/domain/task_models.dart';

enum StatisticsPeriod { day, week, month, year }

class StatisticsRange {
  StatisticsRange(StatisticsPeriod period, DateTime anchor)
    : start = switch (period) {
        StatisticsPeriod.day => dateOnly(anchor),
        StatisticsPeriod.week => DateTime(
          anchor.year,
          anchor.month,
          anchor.day - anchor.weekday + 1,
        ),
        StatisticsPeriod.month => DateTime(anchor.year, anchor.month),
        StatisticsPeriod.year => DateTime(anchor.year),
      } {
    end = switch (period) {
      StatisticsPeriod.day => DateTime(start.year, start.month, start.day + 1),
      StatisticsPeriod.week => DateTime(start.year, start.month, start.day + 7),
      StatisticsPeriod.month => DateTime(start.year, start.month + 1),
      StatisticsPeriod.year => DateTime(start.year + 1),
    };
  }
  final DateTime start;
  late final DateTime end;
  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(end);
}

class TimeTag {
  const TimeTag(this.id, this.name, this.colorValue);
  final String? id;
  final String name;
  final int colorValue;
  static const other = TimeTag(null, '其它', 0xFF8793A6);
}

class TimeEntry {
  const TimeEntry({
    required this.taskId,
    required this.tagId,
    required this.start,
    required this.end,
    required this.durationSeconds,
    required this.running,
  });
  final String taskId;
  final String? tagId;
  final DateTime start;
  final DateTime? end;
  final int durationSeconds;
  final bool running;

  int secondsBetween(DateTime from, DateTime until, DateTime now) {
    final stop = running
        ? now
        : end ?? start.add(Duration(seconds: durationSeconds));
    final cappedStop = stop.isAfter(now) ? now : stop;
    final overlapStart = start.isAfter(from) ? start : from;
    final overlapEnd = cappedStop.isBefore(until) ? cappedStop : until;
    if (!overlapEnd.isAfter(overlapStart)) return 0;
    if (running) return overlapEnd.difference(overlapStart).inSeconds;
    // Allocate the stored duration across calendar boundaries without losing seconds.
    final wall = stop.difference(start).inMicroseconds;
    if (wall <= 0) return 0;
    final a = overlapStart.difference(start).inMicroseconds;
    final b = overlapEnd.difference(start).inMicroseconds;
    return ((durationSeconds * b) ~/ wall) - ((durationSeconds * a) ~/ wall);
  }
}

class ExecutionDay {
  const ExecutionDay({
    required this.date,
    required this.success,
    required this.targetSeconds,
    required this.storedTargetReached,
  });
  final DateTime date;
  final bool success;
  final int? targetSeconds;
  final bool storedTargetReached;
}

class StatisticsTask {
  const StatisticsTask({
    required this.id,
    required this.name,
    required this.iconName,
    required this.colorValue,
    required this.days,
  });
  final String id;
  final String name;
  final String iconName;
  final int colorValue;
  final List<ExecutionDay> days;
}

class TaskStatistics {
  TaskStatistics(this.task);
  final StatisticsTask task;
  int expected = 0;
  int completed = 0;
  int targetReached = 0;
  int seconds = 0;
  int totalSuccess = 0;
  int currentStreak = 0;
  int longestStreak = 0;
  double get rate => expected == 0 ? 0 : completed / expected;
}

class TimeBucket {
  TimeBucket(this.start, this.end, this.label);
  final DateTime start;
  final DateTime end;
  final String label;
  final Map<String?, int> secondsByTag = {};
  int get seconds => secondsByTag.values.fold(0, (a, b) => a + b);
}

class StatisticsReport {
  StatisticsReport({
    required this.range,
    required this.tags,
    required this.buckets,
    required this.tasks,
    required this.remindersCompleted,
  });
  final StatisticsRange range;
  final List<TimeTag> tags;
  final List<TimeBucket> buckets;
  final List<TaskStatistics> tasks;
  final int remindersCompleted;
  int get seconds => buckets.fold(0, (sum, bucket) => sum + bucket.seconds);
  int get expected => tasks.fold(0, (sum, task) => sum + task.expected);
  int get completed => tasks.fold(0, (sum, task) => sum + task.completed);
  int get targetReached =>
      tasks.fold(0, (sum, task) => sum + task.targetReached);
  double get rate => expected == 0 ? 0 : completed / expected;
  int secondsForTag(String? id) =>
      buckets.fold(0, (sum, b) => sum + (b.secondsByTag[id] ?? 0));

  SmartSummary get smartSummary {
    if (expected == 0) {
      return const SmartSummary(
        title: '本期暂无应执行任务',
        message: '可以先建立一个周期任务，再从统计中观察自己的节奏。',
        tone: SmartSummaryTone.neutral,
      );
    }
    if (rate < 0.3) {
      return const SmartSummary(
        title: '先把目标调得更可持续',
        message: '最近完成率较低，可以考虑降低每日目标时长，使坚持更容易发生。',
        tone: SmartSummaryTone.attention,
      );
    }
    if (rate < 0.5) {
      return const SmartSummary(
        title: '目标可能偏高',
        message: '当前目标可以根据实际情况适当减少，给稳定执行留出空间。',
        tone: SmartSummaryTone.attention,
      );
    }
    if (rate < 0.7) {
      return const SmartSummary(
        title: '正在形成节奏',
        message: '完成情况不错，继续保持，稳定的重复会逐渐形成习惯。',
        tone: SmartSummaryTone.positive,
      );
    }
    return const SmartSummary(
      title: '保持得很好',
      message: '本阶段完成情况非常好，继续保持这份节奏。',
      tone: SmartSummaryTone.positive,
    );
  }
}

enum SmartSummaryTone { neutral, attention, positive }

class SmartSummary {
  const SmartSummary({
    required this.title,
    required this.message,
    required this.tone,
  });
  final String title;
  final String message;
  final SmartSummaryTone tone;
}

class StatisticsData {
  const StatisticsData({
    required this.tags,
    required this.sessions,
    required this.tasks,
    required this.reminderCompletions,
  });
  final List<TimeTag> tags;
  final List<TimeEntry> sessions;
  final List<StatisticsTask> tasks;
  final List<DateTime> reminderCompletions;

  StatisticsReport report(
    StatisticsPeriod period,
    DateTime anchor,
    DateTime now,
  ) {
    final range = StatisticsRange(period, anchor);
    final buckets = <TimeBucket>[];
    for (var day = range.start; day.isBefore(range.end);) {
      final end = period == StatisticsPeriod.year
          ? DateTime(day.year, day.month + 1)
          : DateTime(day.year, day.month, day.day + 1);
      final label = switch (period) {
        StatisticsPeriod.week => const [
          '一',
          '二',
          '三',
          '四',
          '五',
          '六',
          '日',
        ][day.weekday - 1],
        StatisticsPeriod.year => '${day.month}月',
        _ => '${day.day}',
      };
      buckets.add(TimeBucket(day, end, label));
      day = end;
    }
    final knownIds = tags.map((tag) => tag.id).toSet();
    for (final session in sessions) {
      final tagId = knownIds.contains(session.tagId) ? session.tagId : null;
      for (final bucket in buckets) {
        final seconds = session.secondsBetween(bucket.start, bucket.end, now);
        if (seconds > 0) {
          bucket.secondsByTag.update(
            tagId,
            (v) => v + seconds,
            ifAbsent: () => seconds,
          );
        }
      }
    }
    final taskStats = <TaskStatistics>[];
    final today = dateOnly(now);
    for (final task in tasks) {
      final result = TaskStatistics(task);
      final taskSessions = sessions
          .where((session) => session.taskId == task.id)
          .toList();
      result.seconds = taskSessions.fold(
        0,
        (sum, session) =>
            sum + session.secondsBetween(range.start, range.end, now),
      );
      var streak = 0;
      for (final day in task.days) {
        if (day.date.isAfter(today)) continue;
        if (day.success) {
          result.totalSuccess++;
          streak++;
          if (streak > result.longestStreak) result.longestStreak = streak;
        } else if (day.date.isBefore(today)) {
          streak = 0;
        }
        if (!range.contains(day.date)) continue;
        result.expected++;
        if (day.success) result.completed++;
        final end = DateTime(day.date.year, day.date.month, day.date.day + 1);
        final duration = taskSessions.fold(
          0,
          (sum, s) => sum + s.secondsBetween(day.date, end, now),
        );
        if (day.storedTargetReached ||
            (day.targetSeconds != null && duration >= day.targetSeconds!)) {
          result.targetReached++;
        }
      }
      result.currentStreak = streak;
      taskStats.add(result);
    }
    return StatisticsReport(
      range: range,
      tags: [...tags, TimeTag.other],
      buckets: buckets,
      tasks: taskStats,
      remindersCompleted: reminderCompletions
          .where((date) => range.contains(date) && !date.isAfter(now))
          .length,
    );
  }
}
