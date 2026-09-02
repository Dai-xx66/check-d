import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../tags/presentation/tag_picker.dart';
import '../application/task_providers.dart';
import '../domain/task_models.dart';
import 'task_color_picker.dart';
import 'task_icon_picker.dart';

class LongTermTaskFormPage extends ConsumerStatefulWidget {
  const LongTermTaskFormPage({this.initialTask, super.key});

  final TaskDetails? initialTask;

  @override
  ConsumerState<LongTermTaskFormPage> createState() =>
      _LongTermTaskFormPageState();
}

class _LongTermTaskFormPageState extends ConsumerState<LongTermTaskFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  late final TextEditingController _durationController;
  late final TextEditingController _targetDaysController;
  late int _colorValue;
  late String _iconName;
  String? _tagId;
  late LongTermCheckMode _checkMode;
  late SchedulePreset _schedulePreset;
  late Set<int> _weekdays;
  late bool _holidayPause;
  bool _isSaving = false;

  TaskDetails? get _initial => widget.initialTask;

  @override
  void initState() {
    super.initState();
    _tagId = _initial?.tagId;
    _nameController = TextEditingController(text: _initial?.name ?? '');
    _notesController = TextEditingController(text: _initial?.notes ?? '');
    _durationController = TextEditingController(
      text: _initial?.targetDurationSeconds == null
          ? '30'
          : (_initial!.targetDurationSeconds! ~/ 60).toString(),
    );
    _targetDaysController = TextEditingController(
      text: _initial?.targetDays?.toString() ?? '',
    );
    _colorValue = _initial?.colorValue ?? taskColorValues.first;
    _iconName = _initial?.iconName ?? TaskIconKey.check;
    _checkMode = _initial?.checkMode ?? LongTermCheckMode.simple;
    _schedulePreset = _initial?.schedule?.preset ?? SchedulePreset.daily;
    _weekdays = _initial?.schedule == null
        ? WeekdayMask.toDays(WeekdayMask.everyDay)
        : WeekdayMask.toDays(_initial!.schedule!.weekdaysMask);
    _holidayPause = _initial?.holidayPause ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _durationController.dispose();
    _targetDaysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_initial == null ? '创建长期任务' : '编辑长期任务'),
        backgroundColor: AppColors.background,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Section(
                      title: '基本信息',
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nameController,
                            autofocus: _initial == null,
                            maxLength: 100,
                            decoration: const InputDecoration(
                              labelText: '任务名称',
                              hintText: '例如：英语听力',
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? '请输入任务名称'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TaskColorPicker(
                            selectedValue: _colorValue,
                            onSelected: (value) =>
                                setState(() => _colorValue = value),
                          ),
                          const SizedBox(height: 18),
                          TaskIconPicker(
                            selectedKey: _iconName,
                            color: Color(_colorValue),
                            onSelected: (value) =>
                                setState(() => _iconName = value),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Section(
                      title: '执行方式',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) =>
                                SegmentedButton<LongTermCheckMode>(
                                  direction: constraints.maxWidth < 420
                                      ? Axis.vertical
                                      : Axis.horizontal,
                                  segments: const [
                                    ButtonSegment(
                                      value: LongTermCheckMode.simple,
                                      icon: Icon(
                                        Icons.check_circle_outline_rounded,
                                      ),
                                      label: Text('点击完成'),
                                    ),
                                    ButtonSegment(
                                      value: LongTermCheckMode.freeTimer,
                                      icon: Icon(Icons.timer_outlined),
                                      label: Text('自由计时'),
                                    ),
                                    ButtonSegment(
                                      value: LongTermCheckMode.targetTimer,
                                      icon: Icon(Icons.track_changes_rounded),
                                      label: Text('目标计时'),
                                    ),
                                  ],
                                  selected: {_checkMode},
                                  onSelectionChanged: (selection) => setState(
                                    () => _checkMode = selection.first,
                                  ),
                                ),
                          ),
                          if (_checkMode == LongTermCheckMode.targetTimer) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _durationController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '每日目标时长',
                                suffixText: '分钟',
                              ),
                              validator: (value) {
                                if (_checkMode !=
                                    LongTermCheckMode.targetTimer) {
                                  return null;
                                }
                                final minutes = int.tryParse(value ?? '');
                                return minutes == null || minutes <= 0
                                    ? '请输入大于 0 的分钟数'
                                    : null;
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Section(
                      title: '执行周期',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final preset in SchedulePreset.values)
                                ChoiceChip(
                                  label: Text(_scheduleLabel(preset)),
                                  selected: _schedulePreset == preset,
                                  onSelected: (_) => _selectSchedule(preset),
                                ),
                            ],
                          ),
                          if (_schedulePreset == SchedulePreset.custom) ...[
                            const SizedBox(height: 18),
                            const Text(
                              '选择星期',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (var day = 1; day <= 7; day++)
                                  FilterChip(
                                    label: Text(_weekdayLabel(day)),
                                    selected: _weekdays.contains(day),
                                    onSelected: (selected) =>
                                        _toggleWeekday(day, selected),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('中国法定节假日暂停'),
                            subtitle: const Text('暂停日不计失败，也不打断连续天数'),
                            value: _holidayPause,
                            onChanged: (value) =>
                                setState(() => _holidayPause = value),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Section(
                      title: '长期目标与备注',
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _targetDaysController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '目标坚持天数（可选）',
                              hintText: '例如：365',
                              suffixText: '天',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return null;
                              }
                              final days = int.tryParse(value);
                              return days == null || days <= 0
                                  ? '请输入大于 0 的天数'
                                  : null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _notesController,
                            minLines: 3,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              labelText: '备注（可选）',
                              alignLabelWithHint: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_checkMode != LongTermCheckMode.simple) ...[
                      const SizedBox(height: 16),
                      TagPicker(
                        value: _tagId,
                        onChanged: (value) => setState(() => _tagId = value),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: const Icon(Icons.check_rounded),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Text(_initial == null ? '创建任务' : '保存修改'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectSchedule(SchedulePreset preset) {
    setState(() {
      _schedulePreset = preset;
      _weekdays = switch (preset) {
        SchedulePreset.daily => WeekdayMask.toDays(WeekdayMask.everyDay),
        SchedulePreset.weekdays => WeekdayMask.toDays(WeekdayMask.weekdays),
        SchedulePreset.weekends => WeekdayMask.toDays(WeekdayMask.weekends),
        SchedulePreset.custom =>
          _weekdays.isEmpty ? {DateTime.now().weekday} : _weekdays,
      };
    });
  }

  void _toggleWeekday(int day, bool selected) {
    setState(() {
      if (selected) {
        _weekdays.add(day);
      } else if (_weekdays.length > 1) {
        _weekdays.remove(day);
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final minutes = int.tryParse(_durationController.text);
      final targetDays = int.tryParse(_targetDaysController.text);
      final draft = LongTermTaskDraft(
        name: _nameController.text,
        colorValue: _colorValue,
        iconName: _iconName,
        tagId: _checkMode == LongTermCheckMode.simple ? null : _tagId,
        notes: _notesController.text,
        checkMode: _checkMode,
        targetDurationSeconds: _checkMode == LongTermCheckMode.targetTimer
            ? minutes! * 60
            : null,
        targetDays: targetDays,
        schedulePreset: _schedulePreset,
        weekdays: _weekdays,
        startsOn: _initial?.schedule?.startsOn ?? DateTime.now(),
        endsOn: _initial?.schedule?.endsOn,
        holidayPause: _holidayPause,
      );
      await ref
          .read(taskRepositoryProvider)
          .saveLongTermTask(draft, taskId: _initial?.id);
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请检查输入后重试')));
        setState(() => _isSaving = false);
      }
    }
  }

  String _scheduleLabel(SchedulePreset preset) {
    return switch (preset) {
      SchedulePreset.daily => '每天',
      SchedulePreset.weekdays => '工作日',
      SchedulePreset.weekends => '周末',
      SchedulePreset.custom => '自定义',
    };
  }

  String _weekdayLabel(int weekday) {
    return const ['一', '二', '三', '四', '五', '六', '日'][weekday - 1];
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}
