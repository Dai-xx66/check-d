import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/course_providers.dart';
import '../domain/course_models.dart';
import 'semester_settings_page.dart';

class CourseFormPage extends ConsumerStatefulWidget {
  const CourseFormPage({super.key, this.initialCourse});
  final CourseDetails? initialCourse;

  @override
  ConsumerState<CourseFormPage> createState() => _CourseFormPageState();
}

class _CourseFormPageState extends ConsumerState<CourseFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _teacher = TextEditingController();
  final _classroom = TextEditingController();
  final _notes = TextEditingController();
  late int _colorValue;
  String? _semesterId;
  late List<_EditableRule> _rules;
  bool _saving = false;
  bool _didPickDefault = false;

  @override
  void initState() {
    super.initState();
    final course = widget.initialCourse;
    _name.text = course?.name ?? '';
    _teacher.text = course?.teacher ?? '';
    _classroom.text = course?.classroom ?? '';
    _notes.text = course?.notes ?? '';
    _colorValue = course?.colorValue ?? 0xFF8FA7F5;
    _semesterId = course?.semesterId;
    _rules = [
      for (final rule in course?.rules ?? const [])
        _EditableRule.fromRule(rule),
    ];
  }

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    _classroom.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semesters =
        ref.watch(semestersProvider).value ?? const <SemesterDetails>[];
    final templates =
        ref.watch(scheduleTemplatesProvider).value ??
        const <ScheduleTemplateDetails>[];
    final current = semesters.where((item) => item.isCurrent).firstOrNull;
    if (!_didPickDefault && _semesterId == null && current != null) {
      _didPickDefault = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _semesterId = current.id);
      });
    }
    final semester = semesters
        .where((item) => item.id == _semesterId)
        .firstOrNull;
    final template = semester?.scheduleTemplateId == null
        ? null
        : templates
              .where((item) => item.id == semester!.scheduleTemplateId)
              .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialCourse == null ? '添加课程' : '编辑课程'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: [
          Form(
            key: _formKey,
            child: TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: '课程名称 *'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请填写课程名称' : null,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: _semesterId,
            decoration: const InputDecoration(labelText: '所属学期 *'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('请选择学期'),
              ),
              ...semesters.map(
                (item) => DropdownMenuItem(
                  value: item.id,
                  child: Text(item.isCurrent ? '${item.name}（当前）' : item.name),
                ),
              ),
            ],
            onChanged: (value) {
              if (value == _semesterId) return;
              setState(() {
                _semesterId = value;
                for (final rule in _rules) {
                  if (rule.timeMode == CourseScheduleTimeMode.periods)
                    rule.clearPeriods();
                }
              });
            },
          ),
          if (semesters.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SemesterSettingsPage(),
                  ),
                ),
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text('先创建一个学期'),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _teacher,
            decoration: const InputDecoration(labelText: '授课教师（可选）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _classroom,
            decoration: const InputDecoration(labelText: '默认教室（可选）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: '课程备注（可选）'),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  '课程安排',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: semester == null
                    ? null
                    : () => _editRule(semester, template),
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加安排'),
              ),
            ],
          ),
          if (semester == null)
            const Text('选择学期后即可添加课程安排。')
          else if (_rules.isEmpty)
            const _HintCard(text: '还没有安排。可先连续添加多条星期、周次和节次规则，再一次保存课程。')
          else
            for (var index = 0; index < _rules.length; index++)
              _RuleTile(
                rule: _rules[index],
                onEdit: () => _editRule(semester, template, index: index),
                onDelete: () => setState(() => _rules.removeAt(index)),
              ),
          const SizedBox(height: 18),
          Text('课程颜色', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            children:
                [0xFFF47BA2, 0xFF8FA7F5, 0xFF7BCFA0, 0xFFF2B26B, 0xFFB59BEA]
                    .map(
                      (color) => InkWell(
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
                    )
                    .toList(),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _saving ? null : () => _save(semester),
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
    );
  }

  Future<void> _editRule(
    SemesterDetails semester,
    ScheduleTemplateDetails? template, {
    int? index,
  }) async {
    final saved = await Navigator.of(context).push<_EditableRule>(
      MaterialPageRoute(
        builder: (_) => _CourseRuleEditorPage(
          semester: semester,
          template: template,
          initial: index == null ? null : _rules[index],
        ),
      ),
    );
    if (saved != null && mounted) {
      setState(() {
        if (index == null)
          _rules.add(saved);
        else
          _rules[index] = saved;
      });
    }
  }

  Future<void> _save(SemesterDetails? semester) async {
    if (!_formKey.currentState!.validate()) return;
    if (semester == null) return _error('请选择所属学期');
    setState(() => _saving = true);
    try {
      final repo = ref.read(courseRepositoryProvider);
      final courseId = await repo.saveCourse(
        CourseDraft(
          name: _name.text,
          colorValue: _colorValue,
          teacher: _teacher.text,
          classroom: _classroom.text,
          notes: _notes.text,
          semesterId: semester.id,
          semester: semester.name,
          semesterStartsOn: semester.firstWeekStartDate,
          semesterEndsOn: semester.firstWeekStartDate.add(
            Duration(days: semester.totalWeeks * 7 - 1),
          ),
        ),
        courseId: widget.initialCourse?.id,
      );
      final retained = <String>{};
      final oldById = {
        for (final rule
            in widget.initialCourse?.rules ?? const <CourseScheduleRule>[])
          rule.id: rule,
      };
      final currentWeek = semester
          .weekNumberFor(DateTime.now())
          .clamp(1, semester.totalWeeks);
      for (final editable in _rules) {
        final old = editable.id == null ? null : oldById[editable.id];
        if (old != null && editable.matches(old)) {
          retained.add(old.id);
        } else if (old != null && currentWeek > (old.startWeek ?? 1)) {
          // Never rewrite already effective schedule time. Preserve the old
          // range then create the edited successor from the current week.
          await repo.endScheduleRuleAtWeek(old.id, currentWeek - 1);
          retained.add(old.id);
          final id = await repo.saveScheduleRule(
            editable.futureDraft(courseId, currentWeek),
          );
          retained.add(id);
        } else {
          final id = await repo.saveScheduleRule(
            editable.toDraft(courseId),
            ruleId: editable.id,
          );
          retained.add(id);
        }
      }
      for (final old
          in widget.initialCourse?.rules ?? const <CourseScheduleRule>[]) {
        if (!retained.contains(old.id)) await repo.archiveScheduleRule(old.id);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted)
        _error(
          error is ArgumentError ? error.message.toString() : '课程保存失败：$error',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _error(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _CourseRuleEditorPage extends StatefulWidget {
  const _CourseRuleEditorPage({
    required this.semester,
    required this.template,
    this.initial,
  });
  final SemesterDetails semester;
  final ScheduleTemplateDetails? template;
  final _EditableRule? initial;
  @override
  State<_CourseRuleEditorPage> createState() => _CourseRuleEditorPageState();
}

class _CourseRuleEditorPageState extends State<_CourseRuleEditorPage> {
  late _EditableRule _rule;
  final _startWeek = TextEditingController();
  final _endWeek = TextEditingController();
  final _interval = TextEditingController();
  final _classroom = TextEditingController();
  final _notes = TextEditingController();
  @override
  void initState() {
    super.initState();
    _rule = widget.initial?.copy() ?? _EditableRule();
    _startWeek.text = _rule.startWeek?.toString() ?? '';
    _endWeek.text = _rule.endWeek?.toString() ?? '';
    _interval.text = (_rule.intervalWeeks ?? 2).toString();
    _classroom.text = _rule.classroomOverride ?? '';
    _notes.text = _rule.notes ?? '';
  }

  @override
  void dispose() {
    _startWeek.dispose();
    _endWeek.dispose();
    _interval.dispose();
    _classroom.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final segments =
        (widget.template?.segments ?? const <ScheduleTemplateSegment>[])
            .where(
              (segment) => segment.segmentType == ScheduleSegmentType.classTime,
            )
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return Scaffold(
      appBar: AppBar(title: Text(widget.initial == null ? '添加课程安排' : '编辑课程安排')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<int>(
            value: _rule.weekday,
            decoration: const InputDecoration(labelText: '星期'),
            items: [
              for (var day = 1; day <= 7; day++)
                DropdownMenuItem(
                  value: day,
                  child: Text('星期${'一二三四五六日'[day - 1]}'),
                ),
            ],
            onChanged: (value) => setState(() => _rule.weekday = value!),
          ),
          const SizedBox(height: 12),
          SegmentedButton<CourseScheduleTimeMode>(
            segments: const [
              ButtonSegment(
                value: CourseScheduleTimeMode.periods,
                label: Text('按节次'),
              ),
              ButtonSegment(
                value: CourseScheduleTimeMode.customTime,
                label: Text('自定义时间'),
              ),
            ],
            selected: {_rule.timeMode},
            onSelectionChanged: (value) =>
                setState(() => _rule.timeMode = value.first),
          ),
          const SizedBox(height: 12),
          if (_rule.timeMode == CourseScheduleTimeMode.periods) ...[
            if (widget.template == null)
              const _HintCard(text: '该学期尚未选择作息模板，请先在学期设置中配置模板。')
            else ...[
              Text(
                widget.template!.name,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _rule.startSegmentId,
                decoration: const InputDecoration(labelText: '开始节次'),
                items: segments
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(
                          '${item.name} · ${_minute(item.startsAtMinute)}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _rule.startSegmentId = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _rule.endSegmentId,
                decoration: const InputDecoration(labelText: '结束节次'),
                items: segments
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(
                          '${item.name} · ${_minute(item.endsAtMinute)}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _rule.endSegmentId = value),
              ),
            ],
          ] else
            Row(
              children: [
                Expanded(
                  child: _timeButton(
                    '开始时间',
                    _rule.startsAtMinute,
                    (value) => setState(() => _rule.startsAtMinute = value),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _timeButton(
                    '结束时间',
                    _rule.endsAtMinute,
                    (value) => setState(() => _rule.endsAtMinute = value),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<CourseWeekRuleType>(
            value: _rule.weekRuleType,
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
              DropdownMenuItem(
                value: CourseWeekRuleType.custom,
                child: Text('自定义周次'),
              ),
            ],
            onChanged: (value) => setState(() => _rule.weekRuleType = value!),
          ),
          if (_rule.weekRuleType == CourseWeekRuleType.everyNWeeks ||
              _rule.weekRuleType == CourseWeekRuleType.custom) ...[
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
          if (_rule.weekRuleType == CourseWeekRuleType.everyNWeeks)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextField(
                controller: _interval,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '间隔周数（例如 2 / 3）'),
              ),
            ),
          if (_rule.weekRuleType == CourseWeekRuleType.custom)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var week = 1; week <= widget.semester.totalWeeks; week++)
                    FilterChip(
                      label: Text('$week'),
                      selected: _rule.weekNumbers.contains(week),
                      onSelected: (value) => setState(() {
                        if (value)
                          _rule.weekNumbers.add(week);
                        else
                          _rule.weekNumbers.remove(week);
                      }),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _classroom,
            decoration: const InputDecoration(labelText: '本条安排教室覆盖（可选）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: '本条安排备注（可选）'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _save(segments),
            icon: const Icon(Icons.check),
            label: const Text('保存安排'),
          ),
        ],
      ),
    );
  }

  Widget _timeButton(String label, int minute, ValueChanged<int> onChanged) =>
      OutlinedButton.icon(
        onPressed: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
          );
          if (picked != null) onChanged(picked.hour * 60 + picked.minute);
        },
        icon: const Icon(Icons.schedule_outlined),
        label: Text('$label\n${_minute(minute)}'),
      );
  void _save(List<ScheduleTemplateSegment> segments) {
    _rule.startWeek = int.tryParse(_startWeek.text);
    _rule.endWeek = int.tryParse(_endWeek.text);
    _rule.intervalWeeks = int.tryParse(_interval.text) ?? 2;
    _rule.classroomOverride = _classroom.text.trim().isEmpty
        ? null
        : _classroom.text.trim();
    _rule.notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    if (_rule.timeMode == CourseScheduleTimeMode.periods) {
      if (!_rule.selectPeriodRange(segments, widget.template?.id))
        return _message('请选择连续的开始与结束节次');
    }
    if (_rule.timeMode == CourseScheduleTimeMode.customTime &&
        _rule.endsAtMinute <= _rule.startsAtMinute)
      return _message('结束时间必须晚于开始时间');
    if (_rule.weekRuleType == CourseWeekRuleType.custom &&
        _rule.weekNumbers.isEmpty)
      return _message('请选择至少一周');
    if ((_rule.startWeek ?? 1) < 1 ||
        (_rule.endWeek ?? widget.semester.totalWeeks) >
            widget.semester.totalWeeks ||
        (_rule.endWeek != null &&
            _rule.startWeek != null &&
            _rule.endWeek! < _rule.startWeek!))
      return _message('周次需在 1 到 ${widget.semester.totalWeeks} 之间');
    Navigator.pop(context, _rule);
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _EditableRule {
  _EditableRule({
    this.id,
    this.weekday = 1,
    this.weekRuleType = CourseWeekRuleType.everyWeek,
    this.timeMode = CourseScheduleTimeMode.periods,
    this.startsAtMinute = 480,
    this.endsAtMinute = 580,
    this.startWeek,
    this.endWeek,
    this.intervalWeeks,
    Set<int>? weekNumbers,
    List<String>? sectionIds,
    this.scheduleTemplateId,
    this.startSegmentId,
    this.endSegmentId,
    this.classroomOverride,
    this.notes,
  }) : weekNumbers = weekNumbers ?? {},
       sectionIds = sectionIds ?? [];
  factory _EditableRule.fromRule(CourseScheduleRule rule) {
    final ids = rule.sectionIds;
    return _EditableRule(
      id: rule.id,
      weekday: rule.weekday,
      weekRuleType: rule.weekRuleType,
      timeMode: rule.timeMode,
      startsAtMinute: rule.startsAtMinute,
      endsAtMinute: rule.endsAtMinute,
      startWeek: rule.startWeek,
      endWeek: rule.endWeek,
      intervalWeeks: rule.intervalWeeks,
      weekNumbers: {...rule.weekNumbers},
      sectionIds: [...ids],
      scheduleTemplateId: rule.scheduleTemplateId,
      startSegmentId: ids.isEmpty ? null : ids.first,
      endSegmentId: ids.isEmpty ? null : ids.last,
      classroomOverride: rule.classroomOverride,
      notes: rule.notes,
    );
  }
  final String? id;
  int weekday;
  CourseWeekRuleType weekRuleType;
  CourseScheduleTimeMode timeMode;
  int startsAtMinute;
  int endsAtMinute;
  int? startWeek;
  int? endWeek;
  int? intervalWeeks;
  Set<int> weekNumbers;
  List<String> sectionIds;
  String? scheduleTemplateId;
  String? startSegmentId;
  String? endSegmentId;
  String? classroomOverride;
  String? notes;
  _EditableRule copy() => _EditableRule(
    id: id,
    weekday: weekday,
    weekRuleType: weekRuleType,
    timeMode: timeMode,
    startsAtMinute: startsAtMinute,
    endsAtMinute: endsAtMinute,
    startWeek: startWeek,
    endWeek: endWeek,
    intervalWeeks: intervalWeeks,
    weekNumbers: {...weekNumbers},
    sectionIds: [...sectionIds],
    scheduleTemplateId: scheduleTemplateId,
    startSegmentId: startSegmentId,
    endSegmentId: endSegmentId,
    classroomOverride: classroomOverride,
    notes: notes,
  );
  void clearPeriods() {
    sectionIds = [];
    scheduleTemplateId = null;
    startSegmentId = null;
    endSegmentId = null;
  }

  bool selectPeriodRange(
    List<ScheduleTemplateSegment> segments,
    String? templateId,
  ) {
    final start = segments.indexWhere((item) => item.id == startSegmentId);
    final end = segments.indexWhere((item) => item.id == endSegmentId);
    if (templateId == null || start < 0 || end < start) return false;
    sectionIds = segments
        .sublist(start, end + 1)
        .map((item) => item.id)
        .toList();
    scheduleTemplateId = templateId;
    startsAtMinute = segments[start].startsAtMinute;
    endsAtMinute = segments[end].endsAtMinute;
    return true;
  }

  CourseScheduleRuleDraft toDraft(String courseId) => CourseScheduleRuleDraft(
    courseId: courseId,
    weekday: weekday,
    weekRuleType: weekRuleType,
    startsAtMinute: startsAtMinute,
    endsAtMinute: endsAtMinute,
    startWeek: startWeek,
    endWeek: endWeek,
    intervalWeeks: weekRuleType == CourseWeekRuleType.everyNWeeks
        ? intervalWeeks
        : null,
    weekNumbers: weekNumbers,
    scheduleTemplateId: timeMode == CourseScheduleTimeMode.periods
        ? scheduleTemplateId
        : null,
    sectionIds: sectionIds,
    timeMode: timeMode,
    classroomOverride: classroomOverride,
    notes: notes,
  );

  CourseScheduleRuleDraft futureDraft(String courseId, int effectiveWeek) {
    final remainingWeeks = weekRuleType == CourseWeekRuleType.custom
        ? weekNumbers.where((week) => week >= effectiveWeek).toSet()
        : weekNumbers;
    return CourseScheduleRuleDraft(
      courseId: courseId,
      weekday: weekday,
      weekRuleType: weekRuleType,
      startsAtMinute: startsAtMinute,
      endsAtMinute: endsAtMinute,
      startWeek: effectiveWeek,
      endWeek: endWeek,
      intervalWeeks: weekRuleType == CourseWeekRuleType.everyNWeeks
          ? intervalWeeks
          : null,
      weekNumbers: remainingWeeks,
      scheduleTemplateId: timeMode == CourseScheduleTimeMode.periods
          ? scheduleTemplateId
          : null,
      sectionIds: sectionIds,
      timeMode: timeMode,
      classroomOverride: classroomOverride,
      notes: notes,
    );
  }

  bool matches(CourseScheduleRule rule) =>
      weekday == rule.weekday &&
      weekRuleType == rule.weekRuleType &&
      timeMode == rule.timeMode &&
      startsAtMinute == rule.startsAtMinute &&
      endsAtMinute == rule.endsAtMinute &&
      startWeek == rule.startWeek &&
      endWeek == rule.endWeek &&
      intervalWeeks == rule.intervalWeeks &&
      _sameSet(weekNumbers, rule.weekNumbers) &&
      _sameList(sectionIds, rule.sectionIds) &&
      scheduleTemplateId == rule.scheduleTemplateId &&
      classroomOverride == rule.classroomOverride &&
      notes == rule.notes;
}

bool _sameSet<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);
bool _sameList<T>(List<T> a, List<T> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((value) => value);

class _RuleTile extends StatelessWidget {
  const _RuleTile({
    required this.rule,
    required this.onEdit,
    required this.onDelete,
  });
  final _EditableRule rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onEdit,
      leading: const Icon(Icons.schedule_rounded),
      title: Text(
        '星期${'一二三四五六日'[rule.weekday - 1]} · ${rule.timeMode == CourseScheduleTimeMode.periods ? '按节次 · ${rule.sectionIds.length} 节' : '${_minute(rule.startsAtMinute)}–${_minute(rule.endsAtMinute)}'}',
      ),
      subtitle: Text(_weekLabel(rule)),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline_rounded),
        onPressed: onDelete,
        tooltip: '删除安排',
      ),
    ),
  );
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    ),
  );
}

String _minute(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
String _weekLabel(_EditableRule rule) => switch (rule.weekRuleType) {
  CourseWeekRuleType.everyWeek => '每周',
  CourseWeekRuleType.oddWeeks => '单周',
  CourseWeekRuleType.evenWeeks => '双周',
  CourseWeekRuleType.everyNWeeks => '每 ${rule.intervalWeeks ?? 2} 周',
  CourseWeekRuleType.custom => '自定义 ${rule.weekNumbers.toList()..sort()}',
};
