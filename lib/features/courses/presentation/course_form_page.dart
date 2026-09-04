import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/course_providers.dart';
import '../domain/course_models.dart';

class CourseFormPage extends ConsumerStatefulWidget {
  const CourseFormPage({super.key, this.initialCourse});

  final CourseDetails? initialCourse;

  @override
  ConsumerState<CourseFormPage> createState() => _CourseFormPageState();
}

class _CourseFormPageState extends ConsumerState<CourseFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _teacherController = TextEditingController();
  final _classroomController = TextEditingController();
  final _semesterController = TextEditingController();
  final _startWeekController = TextEditingController();
  final _endWeekController = TextEditingController();
  int _colorValue = 0xFFF47BA2;
  int _weekday = DateTime.monday;
  CourseWeekRuleType _weekRule = CourseWeekRuleType.everyWeek;
  TimeOfDay _startsAt = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endsAt = const TimeOfDay(hour: 9, minute: 40);
  int? _remindBeforeMinutes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final course = widget.initialCourse;
    if (course == null) return;
    _nameController.text = course.name;
    _teacherController.text = course.teacher ?? '';
    _classroomController.text = course.classroom ?? '';
    _semesterController.text = course.semester ?? '';
    _colorValue = course.colorValue;
    final rule = course.rules.isEmpty ? null : course.rules.first;
    if (rule != null) {
      _weekday = rule.weekday;
      _weekRule = rule.weekRuleType;
      _startsAt = TimeOfDay(
        hour: rule.startsAtMinute ~/ 60,
        minute: rule.startsAtMinute % 60,
      );
      _endsAt = TimeOfDay(
        hour: rule.endsAtMinute ~/ 60,
        minute: rule.endsAtMinute % 60,
      );
      _startWeekController.text = rule.startWeek?.toString() ?? '';
      _endWeekController.text = rule.endWeek?.toString() ?? '';
      _remindBeforeMinutes = rule.remindBeforeMinutes;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _teacherController.dispose();
    _classroomController.dispose();
    _semesterController.dispose();
    _startWeekController.dispose();
    _endWeekController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialCourse == null ? '添加课程' : '编辑课程'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '课程名称 *'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请填写课程名称' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _teacherController,
                    decoration: const InputDecoration(labelText: '教师'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _classroomController,
                    decoration: const InputDecoration(labelText: '教室'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _semesterController,
              decoration: const InputDecoration(labelText: '学期'),
            ),
            const SizedBox(height: 20),
            Text('课程安排', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _weekday,
              decoration: const InputDecoration(labelText: '星期'),
              items: [
                for (var day = DateTime.monday; day <= DateTime.sunday; day++)
                  DropdownMenuItem(value: day, child: Text(_weekdayLabel(day))),
              ],
              onChanged: (value) =>
                  setState(() => _weekday = value ?? _weekday),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _timeButton(
                    '开始时间',
                    _startsAt,
                    (value) => setState(() => _startsAt = value),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _timeButton(
                    '结束时间',
                    _endsAt,
                    (value) => setState(() => _endsAt = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CourseWeekRuleType>(
              value: _weekRule,
              decoration: const InputDecoration(labelText: '周次规则'),
              items: const [
                DropdownMenuItem(
                  value: CourseWeekRuleType.everyWeek,
                  child: Text('每周'),
                ),
                DropdownMenuItem(
                  value: CourseWeekRuleType.oddWeeks,
                  child: Text('单周'),
                ),
                DropdownMenuItem(
                  value: CourseWeekRuleType.evenWeeks,
                  child: Text('双周'),
                ),
                DropdownMenuItem(
                  value: CourseWeekRuleType.everyNWeeks,
                  child: Text('每 N 周'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _weekRule = value ?? _weekRule),
            ),
            if (_weekRule == CourseWeekRuleType.everyNWeeks) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _startWeekController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '起始周'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _endWeekController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '结束周'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              value: _remindBeforeMinutes,
              decoration: const InputDecoration(labelText: '课程提醒（可选）'),
              items: const [
                DropdownMenuItem<int?>(value: null, child: Text('不提醒')),
                DropdownMenuItem(value: 5, child: Text('提前 5 分钟')),
                DropdownMenuItem(value: 10, child: Text('提前 10 分钟')),
                DropdownMenuItem(value: 15, child: Text('提前 15 分钟')),
                DropdownMenuItem(value: 30, child: Text('提前 30 分钟')),
              ],
              onChanged: (value) =>
                  setState(() => _remindBeforeMinutes = value),
            ),
            const SizedBox(height: 20),
            if (widget.initialCourse != null &&
                widget.initialCourse!.rules.length > 1)
              Text(
                '已保存 ${widget.initialCourse!.rules.length} 条课程安排，保存后可继续从课程列表编辑。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (widget.initialCourse != null)
              OutlinedButton.icon(
                onPressed: _openAdditionalRule,
                icon: const Icon(Icons.add_rounded),
                label: const Text('新增另一条课程安排'),
              ),
            const SizedBox(height: 8),
            Text('课程颜色', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              children: [
                for (final color in [
                  0xFFF47BA2,
                  0xFF8FA7F5,
                  0xFF7BCFA0,
                  0xFFF2B26B,
                  0xFFB59BEA,
                ])
                  InkWell(
                    onTap: () => setState(() => _colorValue = color),
                    borderRadius: BorderRadius.circular(20),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(color),
                      child: _colorValue == color
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: const Text('保存课程'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeButton(
    String label,
    TimeOfDay value,
    ValueChanged<TimeOfDay> onChanged,
  ) {
    return OutlinedButton.icon(
      onPressed: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: value,
        );
        if (picked != null) onChanged(picked);
      },
      icon: const Icon(Icons.schedule_outlined),
      label: Text('$label\n${value.format(context)}'),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final starts = _startsAt.hour * 60 + _startsAt.minute;
    final ends = _endsAt.hour * 60 + _endsAt.minute;
    if (ends <= starts) {
      _showError('结束时间必须晚于开始时间');
      return;
    }
    final startWeek = int.tryParse(_startWeekController.text.trim());
    final endWeek = int.tryParse(_endWeekController.text.trim());
    if (_weekRule == CourseWeekRuleType.everyNWeeks &&
        (startWeek == null || endWeek == null)) {
      _showError('每 N 周规则需要填写起始周和结束周');
      return;
    }
    setState(() => _saving = true);
    try {
      final repository = ref.read(courseRepositoryProvider);
      final courseId = await repository.saveCourse(
        CourseDraft(
          name: _nameController.text,
          colorValue: _colorValue,
          teacher: _teacherController.text,
          classroom: _classroomController.text,
          semester: _semesterController.text,
        ),
        courseId: widget.initialCourse?.id,
      );
      await repository.saveScheduleRule(
        CourseScheduleRuleDraft(
          courseId: courseId,
          weekday: _weekday,
          weekRuleType: _weekRule,
          startsAtMinute: starts,
          endsAtMinute: ends,
          startWeek: startWeek,
          endWeek: endWeek,
          intervalWeeks: _weekRule == CourseWeekRuleType.everyNWeeks ? 2 : null,
          remindBeforeMinutes: _remindBeforeMinutes,
        ),
        ruleId: widget.initialCourse?.rules.isNotEmpty == true
            ? widget.initialCourse!.rules.first.id
            : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted)
        _showError(
          error is ArgumentError ? error.message.toString() : '课程保存失败，请稍后重试',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  String _weekdayLabel(int day) => const {
    1: '星期一',
    2: '星期二',
    3: '星期三',
    4: '星期四',
    5: '星期五',
    6: '星期六',
    7: '星期日',
  }[day]!;

  Future<void> _openAdditionalRule() async {
    final course = widget.initialCourse;
    if (course == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CourseRuleFormPage(courseId: course.id),
      ),
    );
    if (saved == true && mounted) setState(() {});
  }
}

class CourseRuleFormPage extends ConsumerStatefulWidget {
  const CourseRuleFormPage({
    required this.courseId,
    this.initialRule,
    super.key,
  });
  final String courseId;
  final CourseScheduleRule? initialRule;

  @override
  ConsumerState<CourseRuleFormPage> createState() => _CourseRuleFormPageState();
}

class _CourseRuleFormPageState extends ConsumerState<CourseRuleFormPage> {
  int _weekday = DateTime.monday;
  CourseWeekRuleType _weekRule = CourseWeekRuleType.everyWeek;
  TimeOfDay _startsAt = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endsAt = const TimeOfDay(hour: 9, minute: 40);
  int? _remindBeforeMinutes;
  final _startWeek = TextEditingController();
  final _endWeek = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final rule = widget.initialRule;
    if (rule == null) return;
    _weekday = rule.weekday;
    _weekRule = rule.weekRuleType;
    _startsAt = TimeOfDay(
      hour: rule.startsAtMinute ~/ 60,
      minute: rule.startsAtMinute % 60,
    );
    _endsAt = TimeOfDay(
      hour: rule.endsAtMinute ~/ 60,
      minute: rule.endsAtMinute % 60,
    );
    _startWeek.text = rule.startWeek?.toString() ?? '';
    _endWeek.text = rule.endWeek?.toString() ?? '';
    _remindBeforeMinutes = rule.remindBeforeMinutes;
  }

  @override
  void dispose() {
    _startWeek.dispose();
    _endWeek.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.initialRule == null ? '新增课程安排' : '编辑课程安排'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        DropdownButtonFormField<int>(
          value: _weekday,
          decoration: const InputDecoration(labelText: '星期'),
          items: [
            for (var day = 1; day <= 7; day++)
              DropdownMenuItem(
                value: day,
                child: Text('星期${'一二三四五六日'[day - 1]}'),
              ),
          ],
          onChanged: (value) => setState(() => _weekday = value ?? _weekday),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _timeButton(
                '开始时间',
                _startsAt,
                (v) => setState(() => _startsAt = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _timeButton(
                '结束时间',
                _endsAt,
                (v) => setState(() => _endsAt = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<CourseWeekRuleType>(
          value: _weekRule,
          decoration: const InputDecoration(labelText: '周次规则'),
          items: const [
            DropdownMenuItem(
              value: CourseWeekRuleType.everyWeek,
              child: Text('每周'),
            ),
            DropdownMenuItem(
              value: CourseWeekRuleType.oddWeeks,
              child: Text('单周'),
            ),
            DropdownMenuItem(
              value: CourseWeekRuleType.evenWeeks,
              child: Text('双周'),
            ),
            DropdownMenuItem(
              value: CourseWeekRuleType.everyNWeeks,
              child: Text('每 N 周'),
            ),
          ],
          onChanged: (value) => setState(() => _weekRule = value ?? _weekRule),
        ),
        if (_weekRule == CourseWeekRuleType.everyNWeeks) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startWeek,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '起始周'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _endWeek,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '结束周'),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(
          value: _remindBeforeMinutes,
          decoration: const InputDecoration(labelText: '课程提醒（可选）'),
          items: const [
            DropdownMenuItem<int?>(value: null, child: Text('不提醒')),
            DropdownMenuItem(value: 5, child: Text('提前 5 分钟')),
            DropdownMenuItem(value: 10, child: Text('提前 10 分钟')),
            DropdownMenuItem(value: 15, child: Text('提前 15 分钟')),
            DropdownMenuItem(value: 30, child: Text('提前 30 分钟')),
          ],
          onChanged: (value) => setState(() => _remindBeforeMinutes = value),
        ),
        const SizedBox(height: 24),
        if (widget.initialRule != null)
          OutlinedButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('删除这条安排'),
          ),
        if (widget.initialRule != null) const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check),
          label: const Text('保存安排'),
        ),
      ],
    ),
  );

  Widget _timeButton(
    String label,
    TimeOfDay value,
    ValueChanged<TimeOfDay> onChanged,
  ) => OutlinedButton.icon(
    onPressed: () async {
      final picked = await showTimePicker(context: context, initialTime: value);
      if (picked != null) onChanged(picked);
    },
    icon: const Icon(Icons.schedule_outlined),
    label: Text('$label\n${value.format(context)}'),
  );

  Future<void> _save() async {
    final starts = _startsAt.hour * 60 + _startsAt.minute;
    final ends = _endsAt.hour * 60 + _endsAt.minute;
    if (ends <= starts) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('结束时间必须晚于开始时间')));
      return;
    }
    final startWeek = int.tryParse(_startWeek.text.trim());
    final endWeek = int.tryParse(_endWeek.text.trim());
    if (_weekRule == CourseWeekRuleType.everyNWeeks &&
        (startWeek == null || endWeek == null)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('每 N 周规则需要填写起始周和结束周')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(courseRepositoryProvider)
          .saveScheduleRule(
            CourseScheduleRuleDraft(
              courseId: widget.courseId,
              weekday: _weekday,
              weekRuleType: _weekRule,
              startsAtMinute: starts,
              endsAtMinute: ends,
              startWeek: startWeek,
              endWeek: endWeek,
              intervalWeeks: _weekRule == CourseWeekRuleType.everyNWeeks
                  ? 2
                  : null,
              remindBeforeMinutes: _remindBeforeMinutes,
            ),
            ruleId: widget.initialRule?.id,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('课程安排保存失败')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条课程安排？'),
        content: const Text('课程本身和其他安排会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(courseRepositoryProvider)
          .archiveScheduleRule(widget.initialRule!.id);
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
