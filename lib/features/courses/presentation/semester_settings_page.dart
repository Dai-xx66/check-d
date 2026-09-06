import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/course_providers.dart';
import '../domain/course_models.dart';
import 'course_form_page.dart';
import 'course_list_page.dart';

class SemesterSettingsPage extends ConsumerWidget {
  const SemesterSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final semesters = ref.watch(semestersProvider);
    final templates = ref.watch(scheduleTemplatesProvider);
    final courses = ref.watch(coursesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('学期与课程设置')),
      body: semesters.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('学期加载失败：$error')),
        data: (items) {
          final templateItems =
              templates.asData?.value ?? const <ScheduleTemplateDetails>[];
          final courseItems = courses.asData?.value ?? const <CourseDetails>[];
          final current = items.where((item) => item.isCurrent).firstOrNull;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
            children: [
              _CurrentSemesterCard(
                semester: current,
                template: _templateFor(current, templateItems),
                onCreate: () => _openEditor(context, templateItems),
                onEdit: current == null
                    ? null
                    : () => _openEditor(context, templateItems, current),
              ),
              const SizedBox(height: 24),
              _SectionHeader(
                title: '全部学期',
                actionLabel: '新建学期',
                onAction: () => _openEditor(context, templateItems),
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const _EmptyCard(
                  icon: Icons.school_outlined,
                  title: '还没有学期设置',
                  subtitle: '先创建当前学期，再把课程安排放进自己的节奏里。',
                )
              else
                ...items.map(
                  (semester) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SemesterTile(
                      semester: semester,
                      template: _templateFor(semester, templateItems),
                      onEdit: () =>
                          _openEditor(context, templateItems, semester),
                      onSetCurrent: semester.isCurrent
                          ? null
                          : () => ref
                                .read(semesterRepositoryProvider)
                                .setCurrentSemester(semester.id),
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              _SectionHeader(
                title: '课程',
                actionLabel: '添加课程',
                onAction: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const CourseFormPage()),
                ),
              ),
              const SizedBox(height: 8),
              _CourseOverview(
                courses: courseItems,
                currentSemester: current,
                onManage: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const CourseListPage()),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  ScheduleTemplateDetails? _templateFor(
    SemesterDetails? semester,
    List<ScheduleTemplateDetails> templates,
  ) {
    if (semester?.scheduleTemplateId == null) return null;
    return templates
        .where((item) => item.id == semester!.scheduleTemplateId)
        .firstOrNull;
  }

  void _openEditor(
    BuildContext context,
    List<ScheduleTemplateDetails> templates, [
    SemesterDetails? semester,
  ]) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            SemesterEditorPage(templates: templates, initialSemester: semester),
      ),
    );
  }
}

class SemesterEditorPage extends ConsumerStatefulWidget {
  const SemesterEditorPage({
    super.key,
    required this.templates,
    this.initialSemester,
  });

  final List<ScheduleTemplateDetails> templates;
  final SemesterDetails? initialSemester;

  @override
  ConsumerState<SemesterEditorPage> createState() => _SemesterEditorPageState();
}

class _SemesterEditorPageState extends ConsumerState<SemesterEditorPage> {
  final _nameController = TextEditingController();
  final _weeksController = TextEditingController();
  late DateTime _firstWeekStartDate;
  String? _templateId;
  bool _isCurrent = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final semester = widget.initialSemester;
    _nameController.text = semester?.name ?? '';
    _weeksController.text = (semester?.totalWeeks ?? 20).toString();
    _firstWeekStartDate =
        semester?.firstWeekStartDate ?? _dateOnly(DateTime.now());
    _templateId = semester?.scheduleTemplateId;
    _isCurrent = semester?.isCurrent ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weeksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialSemester == null ? '新建学期' : '编辑学期'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: '学期名称 *'),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_rounded),
            label: Text('第一周开始日期\n${_dateLabel(_firstWeekStartDate)}'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _weeksController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '总周数 *'),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String?>(
            initialValue: _templateId,
            decoration: const InputDecoration(labelText: '作息模板（可选）'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('暂不选择')),
              ...widget.templates.map(
                (template) => DropdownMenuItem<String?>(
                  value: template.id,
                  child: Text(template.name),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _templateId = value),
          ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('设为当前学期'),
            subtitle: const Text('同一时间只会保留一个当前学期'),
            value: _isCurrent,
            onChanged: (value) => setState(() => _isCurrent = value),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: const Text('保存学期'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _firstWeekStartDate,
    );
    if (picked != null && mounted) {
      setState(() => _firstWeekStartDate = _dateOnly(picked));
    }
  }

  Future<void> _save() async {
    final totalWeeks = int.tryParse(_weeksController.text.trim());
    if (_nameController.text.trim().isEmpty || totalWeeks == null) {
      _showError('请填写学期名称和总周数');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(semesterRepositoryProvider)
          .saveSemester(
            SemesterDraft(
              name: _nameController.text,
              firstWeekStartDate: _firstWeekStartDate,
              totalWeeks: totalWeeks,
              scheduleTemplateId: _templateId,
              isCurrent: _isCurrent,
            ),
            semesterId: widget.initialSemester?.id,
          );
      if (mounted) Navigator.of(context).pop();
    } on ArgumentError catch (error) {
      _showError(error.message.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class _CurrentSemesterCard extends StatelessWidget {
  const _CurrentSemesterCard({
    required this.semester,
    required this.template,
    required this.onCreate,
    this.onEdit,
  });

  final SemesterDetails? semester;
  final ScheduleTemplateDetails? template;
  final VoidCallback onCreate;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    if (semester == null) {
      return _EmptyCard(
        icon: Icons.school_outlined,
        title: '尚未设置当前学期',
        subtitle: '设置第一周日期与总周数，日历才能准确计算周次。',
        actionLabel: '设置当前学期',
        onAction: onCreate,
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.blueMist,
                  foregroundColor: AppColors.cyan,
                  child: const Icon(Icons.school_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '当前学期',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        semester!.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '编辑当前学期',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _InfoRow(
              label: '第一周开始',
              value: _dateLabel(semester!.firstWeekStartDate),
            ),
            _InfoRow(label: '总周数', value: '${semester!.totalWeeks} 周'),
            _InfoRow(label: '作息模板', value: template?.name ?? '暂未关联'),
          ],
        ),
      ),
    );
  }
}

class _SemesterTile extends StatelessWidget {
  const _SemesterTile({
    required this.semester,
    required this.template,
    required this.onEdit,
    this.onSetCurrent,
  });

  final SemesterDetails semester;
  final ScheduleTemplateDetails? template;
  final VoidCallback onEdit;
  final VoidCallback? onSetCurrent;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: semester.isCurrent
            ? AppColors.blush
            : AppColors.blueMist,
        foregroundColor: semester.isCurrent
            ? AppColors.primary
            : AppColors.cyan,
        child: Icon(
          semester.isCurrent ? Icons.star_rounded : Icons.school_outlined,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              semester.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (semester.isCurrent) const _StatusPill(label: '当前'),
        ],
      ),
      subtitle: Text(
        '${_dateLabel(semester.firstWeekStartDate)} 起 · ${semester.totalWeeks} 周${template == null ? '' : ' · ${template?.name}'}',
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) =>
            value == 'edit' ? onEdit() : onSetCurrent?.call(),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('编辑')),
          if (!semester.isCurrent)
            const PopupMenuItem(value: 'current', child: Text('设为当前学期')),
        ],
      ),
      onTap: onEdit,
    ),
  );
}

class _CourseOverview extends StatelessWidget {
  const _CourseOverview({
    required this.courses,
    required this.currentSemester,
    required this.onManage,
  });

  final List<CourseDetails> courses;
  final SemesterDetails? currentSemester;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final currentCourses = currentSemester == null
        ? courses
        : courses.where((course) {
            return course.semesterId == currentSemester!.id ||
                (course.semesterId == null &&
                    course.semester == currentSemester!.name);
          }).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentSemester == null
                  ? '已保存 ${courses.length} 门课程'
                  : '当前学期 ${currentCourses.length} 门课程',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              currentCourses.isEmpty
                  ? '还没有课程安排。'
                  : currentCourses
                        .take(3)
                        .map((course) => course.name)
                        .join('、'),
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onManage,
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('管理全部课程'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });
  final String title;
  final String actionLabel;
  final VoidCallback onAction;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      TextButton.icon(
        onPressed: onAction,
        icon: const Icon(Icons.add_rounded),
        label: Text(actionLabel),
      ),
    ],
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.cyan, size: 32),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppColors.muted)),
          if (actionLabel != null) ...[
            const SizedBox(height: 14),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.blush,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, color: AppColors.primary),
    ),
  );
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _dateLabel(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
