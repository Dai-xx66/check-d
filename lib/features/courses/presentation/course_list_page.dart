import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/course_providers.dart';
import '../domain/course_models.dart';
import 'course_form_page.dart';
import 'course_schedule_import_page.dart';

class CourseListPage extends ConsumerWidget {
  const CourseListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(coursesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('课程管理'),
        actions: [
          IconButton(
            tooltip: '从课程表导入',
            onPressed: () => Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => const CourseScheduleImportPage(),
              ),
            ),
            icon: const Icon(Icons.document_scanner_outlined),
          ),
          IconButton(
            tooltip: '添加课程',
            onPressed: () => _openForm(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: courses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('课程加载失败：$error')),
        data: (items) => items.isEmpty
            ? _EmptyCourses(
                onAdd: () => _openForm(context),
                onImport: () => Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const CourseScheduleImportPage(),
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _CourseCard(
                  course: items[index],
                  onEdit: () => _openForm(context, items[index]),
                  onArchive: () => _archive(context, ref, items[index]),
                ),
              ),
      ),
      floatingActionButton: courses.maybeWhen(
        data: (items) => items.isNotEmpty
            ? FloatingActionButton.extended(
                onPressed: () => _openForm(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加课程'),
              )
            : null,
        orElse: () => null,
      ),
    );
  }

  void _openForm(BuildContext context, [CourseDetails? course]) {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CourseFormPage(initialCourse: course)),
    );
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    CourseDetails course,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('归档课程？'),
        content: Text('“${course.name}”将从课程列表和今日安排中隐藏，历史记录会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('归档'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(courseRepositoryProvider).archiveCourse(course.id);
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.course,
    required this.onEdit,
    required this.onArchive,
  });

  final CourseDetails course;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final color = Color(course.colorValue);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: color.withValues(alpha: .16),
                  child: Icon(Icons.school_rounded, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if ([course.teacher, course.classroom, course.semester]
                          .whereType<String>()
                          .any((value) => value.trim().isNotEmpty))
                        Text(
                          [course.teacher, course.classroom, course.semester]
                              .whereType<String>()
                              .where((value) => value.trim().isNotEmpty)
                              .join(' · '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (course.semesterStartsOn != null ||
                          course.semesterEndsOn != null)
                        Text(
                          '学期：${_dateLabel(course.semesterStartsOn)} 至 ${_dateLabel(course.semesterEndsOn)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '更多操作',
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'archive') onArchive();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑')),
                    PopupMenuItem(value: 'archive', child: Text('归档')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (course.rules.isEmpty)
              const Text('还没有课程安排')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: course.rules
                    .map(
                      (rule) => InputChip(
                        avatar: Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: color,
                        ),
                        label: Text(_ruleLabel(rule)),
                        onPressed: onEdit,
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  String _ruleLabel(CourseScheduleRule rule) {
    final start = _formatMinute(rule.startsAtMinute);
    final end = _formatMinute(rule.endsAtMinute);
    final week = switch (rule.weekRuleType) {
      CourseWeekRuleType.everyWeek => '每周',
      CourseWeekRuleType.oddWeeks => '单周',
      CourseWeekRuleType.evenWeeks => '双周',
      CourseWeekRuleType.everyNWeeks => '每${rule.intervalWeeks ?? 1}周',
      CourseWeekRuleType.custom => '自定义周次',
    };
    return '${_weekday(rule.weekday)} $start-$end · $week';
  }

  String _weekday(int day) =>
      const ['一', '二', '三', '四', '五', '六', '日'][day - 1];

  String _dateLabel(DateTime? date) => date == null
      ? '未设置'
      : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _formatMinute(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
}

class _EmptyCourses extends StatelessWidget {
  const _EmptyCourses({required this.onAdd, required this.onImport});
  final VoidCallback onAdd;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.school_outlined, size: 56, color: AppColors.primary),
          const SizedBox(height: 12),
          const Text('还没有课程'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('添加第一门课程'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('从课程表导入'),
          ),
        ],
      ),
    ),
  );
}
