import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

abstract final class TaskIconKey {
  static const target = 'target';
  static const check = 'check';
  static const headphones = 'headphones';
  static const book = 'book';
  static const fitness = 'fitness';
  static const alarm = 'alarm';
  static const water = 'water';
  static const medication = 'medication';
  static const meditation = 'meditation';
  static const bed = 'bed';
  static const work = 'work';
  static const school = 'school';
  static const event = 'event';
  static const flight = 'flight';
  static const cake = 'cake';
  static const health = 'health';
}

class TaskIconOption {
  const TaskIconOption(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}

const taskIconOptions = [
  TaskIconOption(TaskIconKey.target, '目标', Icons.flag_outlined),
  TaskIconOption(TaskIconKey.check, '打卡', Icons.task_alt_rounded),
  TaskIconOption(TaskIconKey.headphones, '听力', Icons.headphones_rounded),
  TaskIconOption(TaskIconKey.book, '阅读', Icons.menu_book_rounded),
  TaskIconOption(TaskIconKey.fitness, '运动', Icons.fitness_center_rounded),
  TaskIconOption(TaskIconKey.alarm, '早起', Icons.alarm_rounded),
  TaskIconOption(TaskIconKey.water, '喝水', Icons.water_drop_outlined),
  TaskIconOption(TaskIconKey.medication, '健康', Icons.medication_outlined),
  TaskIconOption(TaskIconKey.meditation, '冥想', Icons.self_improvement_rounded),
  TaskIconOption(TaskIconKey.bed, '作息', Icons.bedtime_outlined),
  TaskIconOption(TaskIconKey.work, '工作', Icons.work_outline_rounded),
  TaskIconOption(TaskIconKey.school, '学习', Icons.school_outlined),
  TaskIconOption(TaskIconKey.event, '日程', Icons.event_note_outlined),
  TaskIconOption(TaskIconKey.flight, '出行', Icons.flight_rounded),
  TaskIconOption(TaskIconKey.cake, '生日', Icons.cake_outlined),
  TaskIconOption(TaskIconKey.health, '体检', Icons.favorite_outline_rounded),
];

IconData taskIconData(String key) {
  return taskIconOptions
          .where((option) => option.key == key)
          .map((option) => option.icon)
          .firstOrNull ??
      Icons.flag_outlined;
}

class TaskIconPicker extends StatelessWidget {
  const TaskIconPicker({
    required this.selectedKey,
    required this.color,
    required this.onSelected,
    super.key,
  });

  final String selectedKey;
  final Color color;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('任务图案', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in taskIconOptions)
              Tooltip(
                message: option.label,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelected(option.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: selectedKey == option.key
                          ? color.withValues(alpha: 0.14)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selectedKey == option.key
                            ? color
                            : AppColors.border,
                        width: selectedKey == option.key ? 2 : 1,
                      ),
                    ),
                    child: Icon(
                      option.icon,
                      color: selectedKey == option.key
                          ? color
                          : AppColors.muted,
                      size: 21,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
