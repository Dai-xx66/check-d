import '../../courses/domain/course_models.dart';
import '../../schedule/domain/day_schedule_models.dart';
import '../../tasks/domain/task_models.dart';

class TodaySnapshot {
  const TodaySnapshot({
    required this.date,
    required this.tasks,
    required this.courses,
    required this.overrides,
  });

  final DateTime date;
  final List<TaskDetails> tasks;
  final List<TodayCourseItem> courses;
  final List<DailyItemOverride> overrides;

  List<TaskDetails> get recurringTasks =>
      tasks.where((task) => task.kind == TaskKind.recurring).toList();

  List<TaskDetails> get oneTimeTasks =>
      tasks.where((task) => task.kind == TaskKind.oneTime).toList();

  List<TodayTimelineItem> get timeline => [
    ...courses,
    ...tasks
        .where(
          (task) =>
              task.scheduledMinuteOfDay != null || task.scheduledAt != null,
        )
        .map(TodayTaskItem.new),
  ]..sort((a, b) => a.startMinute.compareTo(b.startMinute));
}

sealed class TodayTimelineItem {
  const TodayTimelineItem({required this.startMinute});

  final int startMinute;
}

class TodayTaskItem extends TodayTimelineItem {
  TodayTaskItem(this.task) : super(startMinute: _startMinute(task));

  final TaskDetails task;

  static int _startMinute(TaskDetails task) {
    if (task.kind == TaskKind.oneTime && task.scheduledAt != null) {
      return task.scheduledAt!.hour * 60 + task.scheduledAt!.minute;
    }
    return task.scheduledMinuteOfDay ?? 0;
  }
}

class TodayCourseItem extends TodayTimelineItem {
  const TodayCourseItem({
    required this.course,
    this.rule,
    required super.startMinute,
    required this.endMinute,
    this.classroom,
  });

  final CourseDetails course;
  final CourseScheduleRule? rule;
  final int endMinute;
  final String? classroom;
}
