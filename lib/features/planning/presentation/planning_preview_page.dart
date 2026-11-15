import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../application/planning_providers.dart';
import '../data/planning_plan_repository.dart';
import '../data/planning_preview_client.dart';

class PlanningPreviewPage extends ConsumerStatefulWidget {
  const PlanningPreviewPage({super.key});

  @override
  ConsumerState<PlanningPreviewPage> createState() =>
      _PlanningPreviewPageState();
}

class _PlanningPreviewPageState extends ConsumerState<PlanningPreviewPage> {
  late final PlanningDateRange _range;
  Map<String, Object?>? _delayResult;
  Map<String, Object?>? _previewSnapshot;
  Map<String, Object?>? _previewResult;
  Map<String, Object?>? _riskResult;
  String? _delayTaskId;
  String? _delayError;
  bool _delayLoading = false;
  bool _savingPlan = false;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _range = PlanningDateRange(
      from: DateTime(today.year, today.month, today.day),
      through: DateTime(today.year, today.month, today.day + 6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(planningPreviewProvider(_range));
    return Scaffold(
      appBar: AppBar(title: const Text('智能规划预览')),
      body: SafeArea(
        child: preview.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorView(
            message: error is PlanningPreviewException
                ? _friendlyError(error.code)
                : '本地规划预览暂时不可用，请重新读取。',
            onRetry: () => ref.invalidate(planningPreviewProvider(_range)),
          ),
          data: (value) => _buildResult(context, value),
        ),
      ),
    );
  }

  Widget _buildResult(BuildContext context, PlanningPreviewResult value) {
    final snapshot = _previewSnapshot ?? value.snapshot;
    final result = _previewResult ?? value.result;
    final tasks = _maps(snapshot['tasks']);
    final missing = result['missing_data'];
    final schedule = result['schedule'];
    final blocks = _maps(schedule is Map ? schedule['blocks'] : null);
    final risks = _maps((_riskResult ?? value.riskResult)['risks']);
    final syncState = snapshot['sync_state'] as String? ?? 'unknown';
    final provisional = snapshot['provisional'] == true;
    final savedPlans = ref.watch(savedPlanningPlansProvider(_range));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本地数据状态',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(_syncLabel(syncState, provisional)),
                Text('快照版本：${snapshot['version'] ?? '未知'}'),
                Text('数据来源：${snapshot['source'] ?? '未知'}'),
                const SizedBox(height: 8),
                const Text('以下结果仅用于预览，不会修改任务或日程。云端最新状态尚未确认，不能用于自动执行。'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (!value.calculationAvailable)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('本地规划器无法处理当前快照；请检查输入数据。'),
            ),
          )
        else ...[
          _SectionCard(
            title: '可行性',
            child: Text(_outcomeLabel(result['outcome'] as String?)),
          ),
          if (result['outcome'] == 'found_feasible' && blocks.isNotEmpty)
            _SectionCard(
              title: '保存本地计划',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('保存前会再次核对任务与课程快照。此操作只保存到本机，不会同步云端或修改任务排期。'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _savingPlan
                        ? null
                        : () =>
                              _confirmAndSave(snapshot, result, tasks, blocks),
                    icon: _savingPlan
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(_savingPlan ? '正在保存…' : '查看差异并确认保存'),
                  ),
                ],
              ),
            ),
          savedPlans.when(
            loading: () =>
                const Card(child: ListTile(title: Text('正在读取已保存的本地计划…'))),
            error: (_, _) =>
                const Card(child: ListTile(title: Text('已保存计划暂时无法读取。'))),
            data: (plans) => _savedPlansCard(plans, tasks),
          ),
          _SectionCard(
            title: '候选时间块',
            child: blocks.isEmpty
                ? const Text('当前没有可展示的候选时间块。请检查任务截止时间、剩余工作量和可用时间数据。')
                : Column(
                    children: [
                      for (final block in blocks)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_taskName(tasks, block['task_id'])),
                          subtitle: Text(
                            '${_formatInstant(block['starts_at'])} – ${_formatInstant(block['ends_at'])}',
                          ),
                          leading: const Icon(Icons.schedule_rounded),
                        ),
                    ],
                  ),
          ),
          _SectionCard(
            title: '数据限制',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _limitations(missing),
                if (value.calculationAvailable)
                  for (final taskId in _missingTaskIds(missing))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _collectTemporaryInputs(
                          snapshot,
                          _task(tasks, taskId),
                        ),
                        icon: const Icon(Icons.edit_calendar_outlined),
                        label: Text('为「${_taskName(tasks, taskId)}」补充本次预览参数'),
                      ),
                    ),
                if (_previewSnapshot != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('已使用你刚刚输入的临时参数；这些值仅用于本次计算，未写入任务。'),
                  ),
              ],
            ),
          ),
          _SectionCard(
            title: '风险说明',
            child: risks.isEmpty
                ? const Text('当前快照未计算出明确风险；这不代表云端风险为零。')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final risk in risks)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '• ${risk['risk_type'] ?? risk['code'] ?? '风险'}：${risk['message'] ?? risk['severity'] ?? '请复核任务安排'}',
                          ),
                        ),
                    ],
                  ),
          ),
          _SectionCard(
            title: '延期模拟',
            child: tasks.isEmpty
                ? const Text('当前范围没有可模拟的一次性任务。')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final task in tasks)
                        OutlinedButton.icon(
                          onPressed: _delayLoading
                              ? null
                              : () => _simulateDelay(snapshot, task),
                          icon: const Icon(Icons.update_rounded),
                          label: Text('模拟「${task['name'] ?? '任务'}」明天再做'),
                        ),
                      if (_delayLoading)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (_delayError != null)
                        Text(
                          _delayError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (_delayResult != null) _delayComparison(_delayResult!),
                    ],
                  ),
          ),
        ],
      ],
    );
  }

  Widget _savedPlansCard(
    List<SavedLocalPlan> plans,
    List<Map<String, Object?>> tasks,
  ) {
    final visible = plans
        .where(
          (plan) =>
              plan.status == LocalPlanStatus.confirmed ||
              plan.status == LocalPlanStatus.applied,
        )
        .toList();
    return _SectionCard(
      title: '已保存计划（本机）',
      child: visible.isEmpty
          ? const Text('当前日期范围还没有已确认的本地计划。')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final plan in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '版本 ${plan.revision} · ${plan.status.name} · ${plan.blocks.length} 个时间块',
                        ),
                        for (final block in plan.blocks)
                          Text(
                            '• ${_taskName(tasks, block.taskId)}：${_formatInstant(block.startsAt.toIso8601String())} – ${_formatInstant(block.endsAt.toIso8601String())}',
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _confirmAndSave(
    Map<String, Object?> snapshot,
    Map<String, Object?> result,
    List<Map<String, Object?>> tasks,
    List<Map<String, Object?>> rawBlocks,
  ) async {
    if (_savingPlan) return;
    final blocks = <CandidatePlanBlock>[];
    try {
      for (final block in rawBlocks) {
        final start = DateTime.parse(block['starts_at']! as String).toUtc();
        final end = DateTime.parse(block['ends_at']! as String).toUtc();
        final seconds = block['planned_seconds'];
        if (seconds is! int) {
          throw const FormatException('planned seconds missing');
        }
        blocks.add(
          CandidatePlanBlock(
            taskId: block['task_id']! as String,
            startsAt: start,
            endsAt: end,
            plannedSeconds: seconds,
          ),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('候选时间块数据无效，尚未保存。')));
      }
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认保存本地计划？'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '以下是当前安排与候选计划的差异。确认后保存到此设备的 CheckD 数据库；不会修改任务本身、TimerSession 或云端数据。若你在本次预览中明确补充了剩余工时，该数值会保存在独立的本地规划估算记录中。',
                ),
                const SizedBox(height: 12),
                for (final block in blocks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '• ${_taskName(tasks, block.taskId)}：${_formatInstant(block.startsAt.toIso8601String())} – ${_formatInstant(block.endsAt.toIso8601String())}（${_oldPlannedTime(tasks, block.taskId)}）',
                    ),
                  ),
                const SizedBox(height: 4),
                const Text('计划将标记为“已确认（本地）”；尚未获得云端版本授权，不能自动执行或同步。'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认保存'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;

    setState(() => _savingPlan = true);
    try {
      final sourceVersion = snapshot['version']! as String;
      final repository = ref.read(planningPlanRepositoryProvider);
      await repository.confirmPlan(
        expectedSnapshotVersion: sourceVersion,
        readCurrentSnapshotVersion: () async {
          final fresh = await ref
              .read(planningContextRepositoryProvider)
              .load(
                from: _range.from,
                through: _range.through,
                now: DateTime.now(),
              );
          return fresh['version']! as String;
        },
        startsOn: _range.from,
        endsOn: _range.through,
        rulesVersion: 'local-edf-v1',
        blocks: blocks,
        confirmedRemainingSeconds: {
          for (final task in tasks)
            if (task['effort_source'] == 'ephemeral_user_input' &&
                task['remaining_seconds'] is int)
              task['task_id']! as String: task['remaining_seconds']! as int,
        },
      );
      if (!mounted) return;
      ref.invalidate(savedPlanningPlansProvider(_range));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('本地计划已保存，可在本页重新读取。')));
    } on LocalPlanSnapshotChanged {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('任务或课程数据已变化，旧方案未保存。请重新计算后确认。')),
      );
      setState(() {
        _previewSnapshot = null;
        _previewResult = null;
        _riskResult = null;
      });
      ref.invalidate(planningPreviewProvider(_range));
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('计划保存失败；没有显示成功状态，请检查数据后重试。')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPlan = false);
    }
  }

  String _oldPlannedTime(List<Map<String, Object?>> tasks, String taskId) {
    final task = _task(tasks, taskId);
    final old = task['planned_at'];
    return old is String ? '原执行时间 ${_formatInstant(old)}' : '原先未设执行时间';
  }

  Future<void> _simulateDelay(
    Map<String, Object?> snapshot,
    Map<String, Object?> task,
  ) async {
    setState(() {
      _delayLoading = true;
      _delayError = null;
      _delayResult = null;
      _delayTaskId = task['task_id'] as String?;
    });
    try {
      final current = DateTime.parse(snapshot['now'] as String);
      final result = ref
          .read(localPlanningEngineProvider)
          .simulateDelay(
            snapshot,
            taskId: _delayTaskId!,
            until: current.add(const Duration(days: 1)),
          );
      if (mounted) setState(() => _delayResult = result);
    } on PlanningPreviewException catch (error) {
      if (mounted) setState(() => _delayError = _friendlyError(error.code));
    } on Object {
      if (mounted) setState(() => _delayError = '延期模拟失败；原任务和计划未发生变化。');
    } finally {
      if (mounted) setState(() => _delayLoading = false);
    }
  }

  Widget _delayComparison(Map<String, Object?> response) {
    final analysis = response['delay_analysis'];
    if (analysis is! Map) return const Text('服务没有返回可比较的延期结果。');
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('延期任务：${_delayTaskId ?? '当前任务'}'),
          Text(
            '延期前：${_feasibilityLabel(analysis['before_feasible'], analysis['status'])}',
          ),
          Text(
            '延期后：${_feasibilityLabel(analysis['after_feasible'], analysis['status'])}',
          ),
          Text('缓冲变化：${analysis['slack_change_seconds'] ?? '未知'} 秒'),
          ..._renderSchedule('延期前候选安排', analysis['before']),
          ..._renderSchedule('延期后候选安排', analysis['after']),
          const Text('排程由启发式算法生成；未找到方案不等于数学上无解。'),
        ],
      ),
    );
  }

  List<Widget> _renderSchedule(String title, Object? raw) {
    if (raw is! Map) return const [];
    final schedule = raw['schedule'];
    final blocks = _maps(schedule is Map ? schedule['blocks'] : null);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('$title：${blocks.length} 个时间块'),
      ),
      for (final block in blocks)
        Text(
          '${_formatInstant(block['starts_at'])} – ${_formatInstant(block['ends_at'])}',
        ),
    ];
  }

  Widget _limitations(Object? rawMissing) {
    if (rawMissing is! Map || rawMissing.isEmpty) {
      return const Text('当前快照没有报告缺失字段。');
    }
    const labels = {
      'unknown_effort_task_ids': '剩余工作量未知',
      'missing_deadline_task_ids': '截止时间缺失',
      'existing_plan_needing_effort_task_ids': '已有排期但缺少时长',
      'unmodeled_recurring_occurrence_ids': '周期任务 occurrence 未纳入排程',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in rawMissing.entries)
          if (entry.value is List && (entry.value as List).isNotEmpty)
            Text(
              '• ${labels[entry.key] ?? entry.key}：${(entry.value as List).length} 项',
            ),
        const Text('未知值不会被补成默认时长或截止日期。'),
      ],
    );
  }

  Future<void> _collectTemporaryInputs(
    Map<String, Object?> originalSnapshot,
    Map<String, Object?> task,
  ) async {
    final input = await showDialog<_TemporaryPlanningInput>(
      context: context,
      builder: (_) => _TemporaryPlanningInputDialog(
        taskName: task['name']?.toString() ?? '任务',
        needsEffort: task['remaining_seconds'] == null,
        needsDeadline:
            task['deadline_date'] == null && task['deadline_at'] == null,
      ),
    );
    if (input == null || !mounted) return;
    final snapshot = (jsonDecode(jsonEncode(originalSnapshot)) as Map)
        .cast<String, Object?>();
    final rows = (snapshot['tasks'] as List).cast<Map>();
    for (final row in rows) {
      if (row['task_id'] != task['task_id']) continue;
      if (input.remainingMinutes case final minutes?) {
        row['remaining_seconds'] = minutes * 60;
        row['remaining_effort_state'] = 'known';
        row['effort_source'] = 'ephemeral_user_input';
      }
      if (input.deadline case final deadline?) {
        row['deadline_date'] = DateFormat('yyyy-MM-dd').format(deadline);
        row['deadline_at'] = null;
      }
    }
    setState(() => _delayLoading = true);
    try {
      final engine = ref.read(localPlanningEngineProvider);
      final result = engine.preview(snapshot);
      final risks = engine.assessRisks(snapshot);
      if (!mounted) return;
      setState(() {
        _previewSnapshot = snapshot;
        _previewResult = result;
        _riskResult = risks;
        _delayResult = null;
        _delayError = null;
      });
    } on PlanningPreviewException catch (error) {
      if (mounted) setState(() => _delayError = _friendlyError(error.code));
    } on Object {
      if (mounted) setState(() => _delayError = '计算失败；原有任务和计划没有变化。');
    } finally {
      if (mounted) setState(() => _delayLoading = false);
    }
  }
}

class _TemporaryPlanningInput {
  const _TemporaryPlanningInput({this.remainingMinutes, this.deadline});

  final int? remainingMinutes;
  final DateTime? deadline;
}

class _TemporaryPlanningInputDialog extends StatefulWidget {
  const _TemporaryPlanningInputDialog({
    required this.taskName,
    required this.needsEffort,
    required this.needsDeadline,
  });
  final String taskName;
  final bool needsEffort;
  final bool needsDeadline;

  @override
  State<_TemporaryPlanningInputDialog> createState() =>
      _TemporaryPlanningInputDialogState();
}

class _TemporaryPlanningInputDialogState
    extends State<_TemporaryPlanningInputDialog> {
  final _minutesController = TextEditingController();
  DateTime? _deadline;

  @override
  void dispose() {
    _minutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('本次预览：${widget.taskName}'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('请输入本次计算缺少的信息。不会保存到 CheckD。'),
          if (widget.needsEffort) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _minutesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '剩余分钟数'),
            ),
          ],
          if (widget.needsDeadline) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _chooseDeadline,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _deadline == null
                    ? '选择截止日期'
                    : DateFormat('yyyy-MM-dd').format(_deadline!),
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _confirm, child: const Text('仅用于本次预览')),
    ],
  );

  Future<void> _chooseDeadline() async {
    final now = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime(now.year, now.month, now.day + 1),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (chosen != null) setState(() => _deadline = chosen);
  }

  void _confirm() {
    final minutes = widget.needsEffort
        ? int.tryParse(_minutesController.text.trim())
        : null;
    if ((widget.needsEffort &&
            (minutes == null || minutes < 1 || minutes > 1440)) ||
        (widget.needsDeadline && _deadline == null)) {
      return;
    }
    Navigator.pop(
      context,
      _TemporaryPlanningInput(
        remainingMinutes: minutes,
        deadline: widget.needsDeadline ? _deadline : null,
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('重新读取')),
        ],
      ),
    ),
  );
}

List<Map<String, Object?>> _maps(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map) item.cast<String, Object?>(),
  ];
}

Map<String, Object?> _task(List<Map<String, Object?>> tasks, String id) =>
    tasks.firstWhere(
      (task) => task['task_id'] == id,
      orElse: () => {'task_id': id, 'name': '任务'},
    );

List<String> _missingTaskIds(Object? value) {
  if (value is! Map) return const [];
  return {
    for (final key in [
      'unknown_effort_task_ids',
      'missing_deadline_task_ids',
      'existing_plan_needing_effort_task_ids',
    ])
      if (value[key] is List) ...((value[key] as List).whereType<String>()),
  }.toList();
}

String _syncLabel(String state, bool provisional) => switch (state) {
  'pending_local_changes' => '有待同步的本地变更；结果为暂定建议。',
  'current' when !provisional => '快照标记为 current；仍需服务端确认后才能申请执行。',
  _ => '云端同步状态未知；结果为暂定建议。',
};

String _outcomeLabel(String? outcome) => switch (outcome) {
  'found_feasible' => '当前输入下找到可行候选安排。',
  'no_solution_found' => '启发式算法在当前约束下未找到方案；这不证明数学上无解。',
  'unknown_due_to_missing_data' => '关键输入缺失，无法完整判断可行性。',
  'invalid_input' => '规划输入无效，请检查日期和任务数据。',
  _ => '规划结果未知。',
};

String _feasibilityLabel(Object? value, Object? status) {
  if (status == 'unknown_due_to_missing_data' || value == null) {
    return '数据不足，无法判断';
  }
  return value == true ? '找到可行安排' : '启发式未找到安排';
}

String _taskName(List<Map<String, Object?>> tasks, Object? id) =>
    tasks
        .cast<Map<String, Object?>>()
        .firstWhere(
          (task) => task['task_id'] == id,
          orElse: () => {'name': id ?? '任务'},
        )['name']
        ?.toString() ??
    '任务';

String _formatInstant(Object? value) {
  if (value is! String) return '时间未知';
  try {
    return DateFormat('M月d日 HH:mm').format(DateTime.parse(value).toLocal());
  } on Object {
    return '时间无效';
  }
}

String _friendlyError(String code) => switch (code) {
  'AUTH_REQUIRED' => '本地规划服务未授权；请检查开发预览令牌。',
  'SNAPSHOT_STALE' => '数据快照已变化，请重新读取后再预览。',
  'SNAPSHOT_UNAVAILABLE' => '当前用户的本地规划数据暂时不可用。',
  'INVALID_INPUT' => '部分任务或日程字段无效，未生成可执行方案。',
  _ => '规划服务暂时不可用（$code）。',
};
