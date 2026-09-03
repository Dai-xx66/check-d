import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/page_header.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/domain/task_models.dart';
import '../../tasks/presentation/task_color_picker.dart';
import '../../tasks/presentation/task_icon_picker.dart';
import '../application/plan_providers.dart';
import '../domain/plan_models.dart';

class PlansPage extends ConsumerWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('计划'),
        backgroundColor: AppColors.background,
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '新建计划',
        onPressed: () => _openForm(context),
        child: const Icon(Icons.add_rounded),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: plans.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => const Center(child: Text('计划加载失败')),
            data: (items) => ListView(
              children: [
                const PageHeader(title: '计划', subtitle: '把周期任务汇总到月度和年度目标'),
                const SizedBox(height: 22),
                if (items.isEmpty)
                  const EmptyState(
                    icon: Icons.flag_outlined,
                    title: '还没有计划',
                    message: '新建月度或年度计划，并关联要坚持的周期任务。',
                  )
                else
                  ...items.map(
                    (plan) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PlanCard(plan: plan),
                    ),
                  ),
                const SizedBox(height: 96),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openForm(BuildContext context, {PlanDetails? initial}) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (context) => PlanFormPage(initial: initial)),
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.plan});
  final PlanDetails plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(plan.colorValue);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (context) => PlanFormPage(initial: plan)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      plan.type == PlanType.month
                          ? Icons.calendar_month_outlined
                          : Icons.flag_outlined,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${plan.type == PlanType.month ? '月度' : '年度'}计划 · ${plan.taskIds.length} 个周期任务',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${plan.progressPercent}%',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '更多',
                    onSelected: (value) async {
                      if (value != 'archive') return;
                      await ref.read(planRepositoryProvider).archive(plan.id);
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'archive', child: Text('归档计划')),
                    ],
                  ),
                ],
              ),
              if (plan.goal != null) ...[
                const SizedBox(height: 14),
                Text(
                  plan.goal!,
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: plan.progress,
                minHeight: 8,
                color: color,
                backgroundColor: const Color(0xFFE9EBEF),
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 9),
              Text(
                '${plan.completedCount}/${plan.dueCount} 次应执行任务已完成 · ${DateFormat('yyyy.M.d').format(plan.startsOn)} - ${DateFormat('yyyy.M.d').format(plan.endsOn)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlanFormPage extends ConsumerStatefulWidget {
  const PlanFormPage({this.initial, super.key});
  final PlanDetails? initial;

  @override
  ConsumerState<PlanFormPage> createState() => _PlanFormPageState();
}

class _PlanFormPageState extends ConsumerState<PlanFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameFocus = FocusNode();
  late final TextEditingController _name;
  late final TextEditingController _goal;
  late PlanType _type;
  late DateTime _startsOn;
  late DateTime _endsOn;
  late int _colorValue;
  late Set<String> _taskIds;
  bool _saving = false;

  PlanDetails? get _initial => widget.initial;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _name = TextEditingController(text: _initial?.name ?? '');
    _goal = TextEditingController(text: _initial?.goal ?? '');
    _type = _initial?.type ?? PlanType.month;
    _startsOn = _initial?.startsOn ?? DateTime(now.year, now.month, 1);
    _endsOn = _initial?.endsOn ?? DateTime(now.year, now.month + 1, 0);
    _colorValue = _initial?.colorValue ?? taskColorValues.first;
    _taskIds = {...?_initial?.taskIds};
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _name.dispose();
    _goal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksByStatusProvider(TaskLifecycle.active));
    return Scaffold(
      appBar: AppBar(
        title: Text(_initial == null ? '新建计划' : '编辑计划'),
        backgroundColor: AppColors.background,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
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
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FormSection(
                      title: '基本信息',
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _name,
                            focusNode: _nameFocus,
                            autofocus: _initial == null,
                            maxLength: 100,
                            decoration: const InputDecoration(
                              labelText: '计划名称',
                              hintText: '例如：九月学习计划',
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? '请填写计划名称'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          TaskColorPicker(
                            selectedValue: _colorValue,
                            onSelected: (value) =>
                                setState(() => _colorValue = value),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _goal,
                            maxLength: 200,
                            decoration: const InputDecoration(
                              labelText: '计划目标（可选）',
                              hintText: '例如：完成本月阅读计划',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _FormSection(
                      title: '周期',
                      child: Column(
                        children: [
                          SegmentedButton<PlanType>(
                            segments: const [
                              ButtonSegment(
                                value: PlanType.month,
                                icon: Icon(Icons.calendar_month_outlined),
                                label: Text('月度'),
                              ),
                              ButtonSegment(
                                value: PlanType.year,
                                icon: Icon(Icons.flag_outlined),
                                label: Text('年度'),
                              ),
                            ],
                            selected: {_type},
                            onSelectionChanged: (value) => setState(() {
                              _type = value.first;
                              _applyPeriodPreset();
                            }),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _DateButton(
                                  label: '开始日期',
                                  value: _startsOn,
                                  onPressed: () => _pickDate(true),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _DateButton(
                                  label: '结束日期',
                                  value: _endsOn,
                                  onPressed: () => _pickDate(false),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _FormSection(
                      title: '关联周期任务',
                      child: tasks.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (error, stackTrace) => const Text('任务加载失败'),
                        data: (items) {
                          final recurring = items
                              .where((task) => task.kind == TaskKind.recurring)
                              .toList();
                          if (recurring.isEmpty) {
                            return const Text('还没有可关联的周期任务');
                          }
                          return Column(
                            children: [
                              for (final task in recurring)
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: _taskIds.contains(task.id),
                                  onChanged: (selected) => setState(() {
                                    if (selected ?? false) {
                                      _taskIds.add(task.id);
                                    } else {
                                      _taskIds.remove(task.id);
                                    }
                                  }),
                                  secondary: Icon(
                                    taskIconData(task.iconName),
                                    color: Color(task.colorValue),
                                  ),
                                  title: Text(task.name),
                                  controlAffinity:
                                      ListTileControlAffinity.trailing,
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.check_rounded),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Text(_initial == null ? '创建计划' : '保存修改'),
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

  void _applyPeriodPreset() {
    final base = DateTime(_startsOn.year, _startsOn.month, _startsOn.day);
    if (_type == PlanType.month) {
      _startsOn = DateTime(base.year, base.month, 1);
      _endsOn = DateTime(base.year, base.month + 1, 0);
    } else {
      _startsOn = DateTime(base.year, 1, 1);
      _endsOn = DateTime(base.year, 12, 31);
    }
  }

  Future<void> _pickDate(bool starts) async {
    final current = starts ? _startsOn : _endsOn;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (starts) {
        _startsOn = picked;
      } else {
        _endsOn = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      _nameFocus.requestFocus();
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(planRepositoryProvider)
          .save(
            PlanDraft(
              name: _name.text,
              type: _type,
              colorValue: _colorValue,
              goal: _goal.text,
              startsOn: _startsOn,
              endsOn: _endsOn,
              taskIds: _taskIds,
            ),
            planId: _initial?.id,
          );
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请检查日期和关联任务')));
      }
    }
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onPressed,
  });
  final String label;
  final DateTime value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.calendar_today_outlined),
    label: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        Text(DateFormat('yyyy.M.d').format(value)),
      ],
    ),
  );
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
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
