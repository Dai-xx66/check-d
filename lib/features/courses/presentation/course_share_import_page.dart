import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/course_providers.dart';
import '../domain/course_import_models.dart';
import '../domain/course_models.dart';
import '../domain/course_share_models.dart';
import 'course_share_scanner_page.dart';
import 'course_import_copy.dart';
import 'semester_settings_page.dart';

class CourseShareImportPage extends ConsumerStatefulWidget {
  const CourseShareImportPage({super.key, this.initialCode});

  final String? initialCode;

  @override
  ConsumerState<CourseShareImportPage> createState() =>
      _CourseShareImportPageState();
}

class _CourseShareImportPageState extends ConsumerState<CourseShareImportPage> {
  late final TextEditingController _code = TextEditingController(
    text: widget.initialCode ?? '',
  );
  FetchedCourseShare? _share;
  CourseImportDraft? _draft;
  String? _semesterId;
  bool _loading = false;
  bool _confirming = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialCode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final semesters = await ref.read(semestersProvider.future);
        final templates = await ref.read(scheduleTemplatesProvider.future);
        if (mounted) await _fetch(semesters, templates);
      });
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semesters =
        ref.watch(semestersProvider).value ?? const <SemesterDetails>[];
    final templates =
        ref.watch(scheduleTemplatesProvider).value ??
        const <ScheduleTemplateDetails>[];
    final selectedSemester = semesters
        .where((item) => item.id == _semesterId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('导入 Check D 分享')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: [
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: '分享口令',
              hintText: 'AB7K-4M2Q',
            ),
            onSubmitted: (_) => _fetch(semesters, templates),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _loading
                      ? null
                      : () => _fetch(semesters, templates),
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(_loading ? '正在获取…' : '获取分享内容'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: '扫描二维码',
                onPressed: _loading ? null : () => _scan(semesters, templates),
                icon: const Icon(Icons.qr_code_scanner_rounded),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_share case final share?) ...[
            const SizedBox(height: 24),
            Text('分享内容', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '来源：${courseImportSourceLabel(CourseImportSourceType.shareCode)} · ${share.package.payload.courses.length} 门课程\n'
              '发送方学期：${share.package.payload.semester?.name ?? '未指定'}',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _semesterId,
              decoration: const InputDecoration(labelText: '导入到学期 *'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('请选择目标学期'),
                ),
                for (final semester in semesters)
                  DropdownMenuItem(
                    value: semester.id,
                    child: Text(
                      semester.isCurrent
                          ? '${semester.name}（当前）'
                          : semester.name,
                    ),
                  ),
              ],
              onChanged: (value) async {
                setState(() => _semesterId = value);
                await _prepare(semesters, templates);
              },
            ),
            if (semesters.isEmpty)
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SemesterSettingsPage(),
                  ),
                ),
                icon: const Icon(Icons.school_outlined),
                label: const Text('先创建学期'),
              ),
          ],
          if (_draft case final draft?) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '选择课程',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => _selectAll(true),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: () => _selectAll(false),
                  child: const Text('全不选'),
                ),
              ],
            ),
            for (var index = 0; index < draft.courses.length; index++)
              _ShareCourseDraftCard(
                course: draft.courses[index],
                onSelected: (value) => _replaceCourse(
                  index,
                  draft.courses[index].copyWith(selected: value),
                ),
                onEditCourse: () => _editCourse(index, draft.courses[index]),
                onEditRule: (ruleIndex) =>
                    _editRule(index, ruleIndex, draft.courses[index]),
              ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed:
                  _confirming || selectedSemester == null || !draft.canConfirm
                  ? null
                  : () => _confirm(selectedSemester, templates),
              icon: _confirming
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_confirming ? '正在导入…' : '确认导入所选课程'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _fetch(
    List<SemesterDetails> semesters,
    List<ScheduleTemplateDetails> templates,
  ) async {
    setState(() {
      _loading = true;
      _error = null;
      _share = null;
      _draft = null;
    });
    try {
      final share = await ref
          .read(courseShareRepositoryProvider)
          .fetchShare(_code.text);
      final semantic = share.package.payload.semester;
      final matched = semantic == null
          ? null
          : semesters
                .where(
                  (semester) =>
                      semester.name.trim() == semantic.name.trim() &&
                      _sameDate(
                        semester.firstWeekStartDate,
                        semantic.firstWeekStartDate,
                      ) &&
                      semester.totalWeeks == semantic.totalWeeks,
                )
                .firstOrNull;
      final fallback =
          matched ?? semesters.where((item) => item.isCurrent).firstOrNull;
      if (!mounted) return;
      setState(() {
        _share = share;
        _semesterId = fallback?.id;
      });
      await _prepare(semesters, templates);
    } on CourseShareException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '无法获取分享内容：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scan(
    List<SemesterDetails> semesters,
    List<ScheduleTemplateDetails> templates,
  ) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CourseShareScannerPage()),
    );
    if (code == null || !mounted) return;
    _code.text = CourseShareCode.display(code);
    await _fetch(semesters, templates);
  }

  Future<void> _prepare(
    List<SemesterDetails> semesters,
    List<ScheduleTemplateDetails> templates,
  ) async {
    final share = _share;
    final semester = semesters
        .where((item) => item.id == _semesterId)
        .firstOrNull;
    if (share == null || semester == null) {
      if (mounted) setState(() => _draft = null);
      return;
    }
    final template = _templateFor(semester, templates);
    try {
      final result = await ref
          .read(courseScheduleImportServiceProvider)
          .prepareShare(
            package: share.package,
            semester: semester,
            template: template,
          );
      if (mounted) setState(() => _draft = result.draft);
    } catch (error) {
      if (mounted) setState(() => _error = '无法准备分享草稿：$error');
    }
  }

  void _selectAll(bool selected) {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      _draft = draft.copyWith(
        courses: [
          for (final course in draft.courses)
            course.copyWith(selected: selected),
        ],
      );
    });
  }

  void _replaceCourse(int index, CourseImportCourseDraft course) {
    final draft = _draft;
    if (draft == null) return;
    final courses = [...draft.courses]..[index] = course;
    setState(() => _draft = draft.copyWith(courses: courses));
  }

  Future<void> _editCourse(int index, CourseImportCourseDraft course) async {
    final title = TextEditingController(text: course.title);
    final teacher = TextEditingController(text: course.teacher ?? '');
    final classroom = TextEditingController(text: course.classroom ?? '');
    final updated = await showDialog<CourseImportCourseDraft>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑课程'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: '课程名'),
              ),
              TextField(
                controller: teacher,
                decoration: const InputDecoration(labelText: '教师'),
              ),
              TextField(
                controller: classroom,
                decoration: const InputDecoration(labelText: '教室'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              CourseImportCourseDraft(
                importKey: course.importKey,
                title: title.text.trim(),
                teacher: _clean(teacher.text),
                classroom: _clean(classroom.text),
                colorValue: course.colorValue,
                note: course.note,
                selected: course.selected,
                scheduleRules: course.scheduleRules,
                issues: course.issues
                    .where(
                      (issue) => issue.state == CourseImportFieldState.conflict,
                    )
                    .toList(),
              ),
            ),
            child: const Text('完成'),
          ),
        ],
      ),
    );
    title.dispose();
    teacher.dispose();
    classroom.dispose();
    if (updated != null) _replaceCourse(index, updated);
  }

  Future<void> _editRule(
    int courseIndex,
    int ruleIndex,
    CourseImportCourseDraft course,
  ) async {
    final rule = course.scheduleRules[ruleIndex];
    final start = TextEditingController(text: _time(rule.startsAtMinute));
    final end = TextEditingController(text: _time(rule.endsAtMinute));
    final startWeek = TextEditingController(text: '${rule.startWeek ?? ''}');
    final endWeek = TextEditingController(text: '${rule.endWeek ?? ''}');
    final interval = TextEditingController(text: '${rule.intervalWeeks ?? ''}');
    final customWeeks = TextEditingController(
      text: (rule.customWeeks.toList()..sort()).join(','),
    );
    var weekday = rule.weekday ?? DateTime.monday;
    var weekRule = rule.weekRuleType ?? CourseWeekRuleType.everyWeek;
    final updated = await showDialog<CourseImportScheduleRuleDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('编辑课程安排'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: weekday,
                  decoration: const InputDecoration(labelText: '星期'),
                  items: [
                    for (var day = 1; day <= 7; day++)
                      DropdownMenuItem(
                        value: day,
                        child: Text('星期${'一二三四五六日'[day - 1]}'),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => weekday = value ?? weekday),
                ),
                TextField(
                  controller: start,
                  decoration: const InputDecoration(labelText: '开始时间 HH:mm'),
                ),
                TextField(
                  controller: end,
                  decoration: const InputDecoration(labelText: '结束时间 HH:mm'),
                ),
                DropdownButtonFormField<CourseWeekRuleType>(
                  initialValue: weekRule,
                  decoration: const InputDecoration(labelText: '周次规则'),
                  items: [
                    for (final value in CourseWeekRuleType.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(_weekRuleLabel(value)),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => weekRule = value ?? weekRule),
                ),
                TextField(
                  controller: startWeek,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '开始周'),
                ),
                TextField(
                  controller: endWeek,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '结束周'),
                ),
                if (weekRule == CourseWeekRuleType.everyNWeeks)
                  TextField(
                    controller: interval,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '间隔周数'),
                  ),
                if (weekRule == CourseWeekRuleType.custom)
                  TextField(
                    controller: customWeeks,
                    decoration: const InputDecoration(labelText: '自定义周次（逗号分隔）'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final startMinute = _parseTime(start.text);
                final endMinute = _parseTime(end.text);
                if (startMinute == null ||
                    endMinute == null ||
                    startMinute >= endMinute) {
                  return;
                }
                Navigator.pop(
                  context,
                  CourseImportScheduleRuleDraft(
                    weekday: weekday,
                    startsAtMinute: startMinute,
                    endsAtMinute: endMinute,
                    weekRuleType: weekRule,
                    startWeek: int.tryParse(startWeek.text),
                    endWeek: int.tryParse(endWeek.text),
                    intervalWeeks: weekRule == CourseWeekRuleType.everyNWeeks
                        ? int.tryParse(interval.text)
                        : null,
                    customWeeks: weekRule == CourseWeekRuleType.custom
                        ? customWeeks.text
                              .split(RegExp(r'[,，\s]+'))
                              .map(int.tryParse)
                              .whereType<int>()
                              .toSet()
                        : const {},
                    timeMode: CourseScheduleTimeMode.customTime,
                    segments: const [],
                    classroomOverride: rule.classroomOverride,
                    note: rule.note,
                    issues: rule.issues
                        .where(
                          (issue) =>
                              issue.state == CourseImportFieldState.conflict,
                        )
                        .toList(),
                  ),
                );
              },
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
    start.dispose();
    end.dispose();
    startWeek.dispose();
    endWeek.dispose();
    interval.dispose();
    customWeeks.dispose();
    if (updated == null) return;
    final rules = [...course.scheduleRules]..[ruleIndex] = updated;
    _replaceCourse(courseIndex, course.copyWith(scheduleRules: rules));
  }

  Future<void> _confirm(
    SemesterDetails semester,
    List<ScheduleTemplateDetails> templates,
  ) async {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      final count = await ref
          .read(courseScheduleImportServiceProvider)
          .confirmDraft(
            draft: draft,
            semester: semester,
            template: _templateFor(semester, templates),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入 $count 门课程')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = '导入失败：$error');
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  ScheduleTemplateDetails? _templateFor(
    SemesterDetails semester,
    List<ScheduleTemplateDetails> templates,
  ) => semester.scheduleTemplateId == null
      ? null
      : templates
            .where((item) => item.id == semester.scheduleTemplateId)
            .firstOrNull;

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  String? _clean(String value) => value.trim().isEmpty ? null : value.trim();
  String _time(int? minute) => minute == null
      ? ''
      : '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  int? _parseTime(String value) {
    final parts = value.trim().split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }
}

class _ShareCourseDraftCard extends StatelessWidget {
  const _ShareCourseDraftCard({
    required this.course,
    required this.onSelected,
    required this.onEditCourse,
    required this.onEditRule,
  });

  final CourseImportCourseDraft course;
  final ValueChanged<bool> onSelected;
  final VoidCallback onEditCourse;
  final ValueChanged<int> onEditRule;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: course.selected,
                onChanged: (value) => onSelected(value ?? false),
              ),
              Expanded(
                child: Text(
                  course.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: '编辑课程',
                onPressed: onEditCourse,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          if ([course.teacher, course.classroom].whereType<String>().isNotEmpty)
            Text(
              [
                course.teacher,
                course.classroom,
              ].whereType<String>().join(' · '),
            ),
          for (var index = 0; index < course.scheduleRules.length; index++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(_ruleLabel(course.scheduleRules[index])),
              trailing: IconButton(
                tooltip: '编辑安排',
                onPressed: () => onEditRule(index),
                icon: const Icon(Icons.schedule_rounded),
              ),
            ),
          for (final issue in [
            ...course.issues,
            ...course.scheduleRules.expand((rule) => rule.issues),
          ])
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                courseImportIssueLabel(issue),
                style: TextStyle(
                  color: issue.state == CourseImportFieldState.conflict
                      ? Colors.orange.shade800
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  String _ruleLabel(CourseImportScheduleRuleDraft rule) =>
      '星期${rule.weekday == null ? '?' : '一二三四五六日'[rule.weekday! - 1]} · '
      '${_format(rule.startsAtMinute)}-${_format(rule.endsAtMinute)} · '
      '${_weekRuleLabel(rule.weekRuleType)}'
      '${rule.startWeek == null && rule.endWeek == null ? '' : ' · ${rule.startWeek ?? '?'}-${rule.endWeek ?? '?'}周'}';
  String _format(int? minute) => minute == null
      ? '--:--'
      : '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
}

String _weekRuleLabel(CourseWeekRuleType? type) => switch (type) {
  CourseWeekRuleType.everyWeek => '每周',
  CourseWeekRuleType.oddWeeks => '单周',
  CourseWeekRuleType.evenWeeks => '双周',
  CourseWeekRuleType.everyNWeeks => '每 N 周',
  CourseWeekRuleType.custom => '自定义周次',
  null => '周次待确认',
};
