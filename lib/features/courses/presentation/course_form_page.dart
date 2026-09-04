import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/course_providers.dart';
import '../domain/course_models.dart';

class CourseFormPage extends ConsumerStatefulWidget {
  const CourseFormPage({super.key});

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
  bool _saving = false;

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
      appBar: AppBar(title: const Text('添加课程')),
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
            const SizedBox(height: 20),
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
        ),
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
}
