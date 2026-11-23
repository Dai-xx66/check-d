import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../shared/widgets/check_d_design.dart';
import '../../../shared/widgets/mascot.dart';
import '../application/agent_providers.dart';
import '../application/agent_reminder_providers.dart';
import '../data/agent_attachment_service.dart';
import '../domain/agent_models.dart';
import 'agent_school_page.dart';

class AgentEntryCard extends StatelessWidget {
  const AgentEntryCard({this.compact = false, super.key});
  final bool compact;
  @override
  Widget build(BuildContext context) => CheckDSurface(
    level: CheckDSurfaceLevel.glassSoft,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    child: Material(
      color: Colors.transparent,
      child: ListTile(
        dense: compact,
        visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          Icons.auto_awesome_outlined,
          color: AppColors.primaryStrong,
        ),
        title: const Text(
          '和智能体一起安排',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: compact ? null : const Text('聊目标、看课表，也能修改真实日程'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => openCheckDAgent(context),
      ),
    ),
  );
}

Future<void> openCheckDAgent(BuildContext context) => Navigator.of(
  context,
).push<void>(checkDPageRoute<void>(builder: (_) => const AgentPage()));

Future<T?> _showSettledDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(context: context, builder: builder);
  final result = await navigator.push(route);
  // A pop result arrives before the reverse animation disposes its fields.
  await route.completed;
  return result;
}

class AgentPage extends ConsumerStatefulWidget {
  const AgentPage({this.initialRequest = '', super.key});
  final String initialRequest;
  @override
  ConsumerState<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends ConsumerState<AgentPage> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  int _view = 0;
  bool _readingAttachment = false;
  @override
  void initState() {
    super.initState();
    _composer.text = widget.initialRequest;
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(agentOwnerProvider, (before, after) {
      if (before == null || before == after) return;
      _composer.clear();
      final pageRoute = ModalRoute.of(context);
      if (pageRoute != null) {
        Navigator.of(context).popUntil((route) => route == pageRoute);
      }
    });
    final workspace = ref.watch(agentWorkspaceProvider);
    final interaction = ref.watch(agentInteractionProvider);
    final local = ref.watch(agentUsesLocalGatewayProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('CheckD 智能体'),
        actions: [
          IconButton(
            tooltip: '检查连接',
            onPressed: interaction.busy
                ? null
                : () => ref.read(agentInteractionProvider.notifier).diagnose(),
            icon: const Icon(Icons.wifi_tethering_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: '智能体选项',
            onSelected: (value) async {
              if (value == 'profile') {
                await _profile(workspace.value ?? const AgentWorkspace());
              }
              if (value == 'clear') {
                await _clearConversation();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: Text('作息与时间预算')),
              PopupMenuItem(value: 'clear', child: Text('清空当前账号的对话')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1000;
            final content = workspace.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('智能体资料暂时无法读取。'),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(agentWorkspaceProvider),
                      child: const Text('重新读取'),
                    ),
                  ],
                ),
              ),
              data: (value) => _view == 1
                  ? _resources(value)
                  : _view == 2
                  ? _history(value)
                  : wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 300,
                          child: _resources(value, compact: true),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: _chat(value, interaction)),
                      ],
                    )
                  : _chat(value, interaction),
            );
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '把想法变成可执行的安排',
                                style: TextStyle(color: AppColors.muted),
                              ),
                            ),
                            _Pill(
                              local ? '本机联调' : '共享云端',
                              color: AppColors.primaryStrong,
                            ),
                          ],
                        ),
                      ),
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: 0,
                            icon: Icon(Icons.chat_bubble_outline_rounded),
                            label: Text('对话'),
                          ),
                          ButtonSegment(
                            value: 1,
                            icon: Icon(Icons.flag_outlined),
                            label: Text('目标与资料'),
                          ),
                          ButtonSegment(
                            value: 2,
                            icon: Icon(Icons.history_rounded),
                            label: Text('变更记录'),
                          ),
                        ],
                        selected: {_view},
                        onSelectionChanged: (values) =>
                            setState(() => _view = values.first),
                      ),
                      const SizedBox(height: 12),
                      if (interaction.connection case final connection?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _Notice(
                            connection,
                            icon: Icons.check_circle_outline_rounded,
                            color: AppColors.accentMint,
                          ),
                        ),
                      if (interaction.error case final error?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _Notice(
                            error,
                            icon: Icons.info_outline_rounded,
                            color: AppColors.red,
                          ),
                        ),
                      if (interaction.appliedSummary case final summary?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: CheckDSurface(
                            level: CheckDSurfaceLevel.glassSoft,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                Expanded(child: Text('已应用：$summary')),
                                TextButton(
                                  onPressed: interaction.busy
                                      ? null
                                      : () async {
                                          final result = await ref
                                              .read(
                                                agentInteractionProvider
                                                    .notifier,
                                              )
                                              .undo();
                                          if (result != null && mounted) {
                                            _snack(result.summary);
                                          }
                                        },
                                  child: const Text('撤销上次修改'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Expanded(child: content),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _chat(
    AgentWorkspace workspace,
    AgentInteractionState interaction,
  ) => Column(
    children: [
      Expanded(
        child: CheckDSurface(
          level: CheckDSurfaceLevel.glassSoft,
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            children: [
              if (workspace.messages.isEmpty) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const CheckDSheep(
                      state: SheepState.idle,
                      size: 74,
                      framed: false,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '先说说，你想完成什么？',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '我会结合你的课程和已有安排。涉及修改时，先给你看清楚再执行。',
                            style: TextStyle(
                              color: AppColors.muted,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _suggestion('根据课表安排本周学习'),
                    _suggestion('总结本周的真实进度'),
                    _suggestion('帮我修改一项任务'),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              for (final message in workspace.messages)
                _MessageBubble(message: message),
              if (workspace.notices.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final notice in workspace.notices.reversed.take(3))
                  _Notice(
                    '${notice['message'] ?? notice['text'] ?? notice['title'] ?? ''}',
                    icon: Icons.notifications_none_rounded,
                    color: AppColors.accentBlue,
                  ),
              ],
              if (interaction.pending case final proposal?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _proposal(proposal, interaction),
                ),
              if (interaction.busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Expanded(child: Text('正在核对资料与安排…')),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      _composerPanel(interaction),
    ],
  );

  Widget _suggestion(String text) => ActionChip(
    label: Text(text),
    onPressed: () {
      _composer.text = text;
      _composer.selection = TextSelection.collapsed(offset: text.length);
    },
  );

  Widget _composerPanel(AgentInteractionState interaction) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: CheckDSurface(
      level: CheckDSurfaceLevel.raised,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (interaction.attachments.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < interaction.attachments.length; i++)
                  InputChip(
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        interaction.attachments[i].name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    avatar: Icon(
                      interaction.attachments[i].images.isEmpty
                          ? Icons.description_outlined
                          : Icons.image_outlined,
                      size: 18,
                    ),
                    onPressed: () =>
                        _previewAttachment(interaction.attachments[i]),
                    onDeleted: interaction.busy
                        ? null
                        : () => ref
                              .read(agentInteractionProvider.notifier)
                              .removeAttachment(i),
                    deleteButtonTooltipMessage: '移除附件',
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            key: const ValueKey('agent-composer'),
            controller: _composer,
            enabled: !interaction.busy,
            minLines: 1,
            maxLines: 4,
            maxLength: 12000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: '想安排、查询或修改什么？',
              hintText: '例如：今晚临时有事，把未完成的学习往后调整',
              counterText: '',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 2,
            children: [
              IconButton(
                tooltip: '添加附件',
                onPressed: interaction.busy || _readingAttachment
                    ? null
                    : _pickAttachments,
                icon: _readingAttachment
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.attach_file_rounded),
              ),
              IconButton(
                tooltip: '导入教务网页',
                onPressed: interaction.busy ? null : _school,
                icon: const Icon(Icons.language_rounded),
              ),
              TextButton.icon(
                onPressed: interaction.busy ? null : _busyPeriod,
                icon: const Icon(Icons.event_busy_outlined, size: 18),
                label: const Text('临时有事'),
              ),
              TextButton.icon(
                onPressed: interaction.busy ? null : _feedback,
                icon: const Icon(Icons.edit_note_rounded, size: 19),
                label: const Text('反馈进度'),
              ),
              FilledButton.icon(
                key: const ValueKey('agent-send'),
                onPressed: interaction.busy || _readingAttachment
                    ? null
                    : _send,
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                label: const Text('发送'),
              ),
            ],
          ),
          if (interaction.attachments.isNotEmpty)
            Text(
              '附件先在本机解析，发送才上传；点附件查看提取内容、页数与截断说明。',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
        ],
      ),
    ),
  );

  Widget _proposal(AgentProposal proposal, AgentInteractionState interaction) =>
      CheckDSurface(
        level: CheckDSurfaceLevel.glassActive,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_outlined, color: AppColors.primaryStrong),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '待确认的改动 · ${proposal.operations.length} 项',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('以下改动尚未执行。确认后才会更新你的 CheckD 数据。'),
            for (final warning in proposal.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(warning, style: TextStyle(color: AppColors.orange)),
              ),
            const SizedBox(height: 10),
            for (final operation in proposal.operations)
              _OperationPreview(
                operation: operation,
                names: interaction.entityNames,
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('agent-confirm'),
                  onPressed: interaction.busy
                      ? null
                      : () async {
                          final result = await ref
                              .read(agentInteractionProvider.notifier)
                              .apply();
                          if (result != null && mounted) _snack(result.summary);
                        },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('确认应用这些改动'),
                ),
                TextButton(
                  onPressed: interaction.busy
                      ? null
                      : ref
                            .read(agentInteractionProvider.notifier)
                            .dismissProposal,
                  child: const Text('暂不应用'),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _resources(
    AgentWorkspace workspace, {
    bool compact = false,
  }) => ListView(
    padding: EdgeInsets.only(
      bottom: 24,
      left: compact ? 0 : 4,
      right: compact ? 0 : 4,
    ),
    children: [
      _section(
        '我的时间预算',
        action: TextButton(
          onPressed: () => _profile(workspace),
          child: const Text('编辑'),
        ),
      ),
      CheckDSurface(
        level: CheckDSurfaceLevel.glassSoft,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '所有目标共用 ${((workspace.profile['learningShare'] as num? ?? .2) * 100).round()}% 闲暇时间',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              '闲暇时间会先扣除课程、睡眠、生活预留和临时占用；未知课时长度会先询问。',
              style: TextStyle(fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 8),
            Text(
              '睡眠 ${_time(workspace.profile['sleepStartMinute'] as int? ?? 0)}—${_time(workspace.profile['sleepEndMinute'] as int? ?? 450)}\n每日生活预留 ${workspace.profile['livingMinutesPerDay'] ?? 180} 分钟',
              style: TextStyle(color: AppColors.muted, height: 1.6),
            ),
            const SizedBox(height: 8),
            Text(
              workspace.profile['confirmedThrough'] == null
                  ? '课表覆盖范围尚未确认，排程前请补充。'
                  : '已确认课表：${workspace.profile['confirmedFrom']} 至 ${workspace.profile['confirmedThrough']}',
              style: TextStyle(
                color: workspace.profile['confirmedThrough'] == null
                    ? AppColors.orange
                    : AppColors.primaryStrong,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _ReminderCapability(
        enabled: workspace.profile['remindersEnabled'] == true,
      ),
      const SizedBox(height: 14),
      _section(
        '目标与规划',
        action: TextButton.icon(
          onPressed: () => _goal(),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('添加'),
        ),
      ),
      if (!workspace.goals.any((goal) => goal['archived'] != true))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '可以从一个目标开始。长期、月度和周期安排会随实际进展更新。',
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
        ),
      for (final goal in workspace.goals.where(
        (goal) => goal['archived'] != true,
      ))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CheckDSurface(
            level: CheckDSurfaceLevel.raised,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${goal['name'] ?? goal['title'] ?? '目标'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '目标选项',
                      onSelected: (value) => value == 'edit'
                          ? _goal(goal)
                          : _preview([
                              AgentOperation(
                                action: 'archive_goal',
                                entityId: goal['id'] as String?,
                              ),
                            ], '归档这个目标，已有任务及历史记录会保留。'),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('修改目标')),
                        PopupMenuItem(value: 'archive', child: Text('归档目标')),
                      ],
                    ),
                  ],
                ),
                if (goal['deadline'] != null)
                  Text(
                    '期望完成：${goal['deadline']}',
                    style: TextStyle(color: AppColors.muted),
                  ),
                if ('${goal['purpose'] ?? ''}'.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Text('${goal['purpose']}'),
                  ),
                for (final key in ['roadmap', 'notes', 'materials'])
                  if ('${goal[key] ?? ''}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SelectableText(
                        _value(goal[key]),
                        style: TextStyle(height: 1.6, color: AppColors.muted),
                      ),
                    ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 8),
      _section('一起复盘'),
      CheckDSurface(
        level: CheckDSurfaceLevel.glassSoft,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '未反馈不等于没学习。自报反馈与计时、完成记录会分别看待。',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _feedback,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('记录一次真实反馈'),
            ),
            TextButton(
              onPressed: () {
                setState(() => _view = 0);
                _composer.text = '请根据本周真实计时、打卡和我的反馈做一次周复盘。缺数据标记未反馈，给出下周最多三个重点。';
              },
              child: const Text('开始本周复盘'),
            ),
          ],
        ),
      ),
      if (workspace.taskLinks.any(
        (link) => (link['needsScheduling'] ?? link['unscheduled']) == true,
      )) ...[
        const SizedBox(height: 14),
        _section('待安排'),
        for (final link in workspace.taskLinks.where(
          (link) => (link['needsScheduling'] ?? link['unscheduled']) == true,
        ))
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: Text('${link['title'] ?? '暂时排不下的事项'}'),
            subtitle: const Text('事项已保留，补充空闲时间后可继续安排。'),
          ),
      ],
    ],
  );

  Widget _history(AgentWorkspace workspace) => ListView(
    padding: const EdgeInsets.all(4),
    children: [
      _section(
        '最近的计划变更',
        action: TextButton.icon(
          onPressed:
              workspace.history.isEmpty ||
                  ref.watch(agentInteractionProvider).busy
              ? null
              : () async {
                  final result = await ref
                      .read(agentInteractionProvider.notifier)
                      .undo();
                  if (result != null && mounted) _snack(result.summary);
                },
          icon: const Icon(Icons.undo_rounded),
          label: const Text('撤销上次改动'),
        ),
      ),
      Text(
        '最多保留 20 次可撤销的变更。撤销不会回滚真实计时和打卡；存在后续修改时会先阻止覆盖。',
        style: TextStyle(color: AppColors.muted, height: 1.5),
      ),
      const SizedBox(height: 14),
      if (workspace.history.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('确认应用第一份提案后，记录会出现在这里。'),
        ),
      for (final entry in workspace.history.reversed)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CheckDSurface(
            level: CheckDSurfaceLevel.raised,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry['summary'] ?? entry['reply'] ?? '计划变更'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '${entry['createdAt'] ?? ''}',
                  style: TextStyle(color: AppColors.muted),
                ),
                if (entry['operations'] is List)
                  Text('${(entry['operations'] as List).length} 项改动'),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _section(String title, {Widget? action}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?action,
      ],
    ),
  );

  Future<void> _send() async {
    final original = _composer.text;
    if (await ref.read(agentInteractionProvider.notifier).send(original)) {
      if (!mounted) return;
      if (_composer.text == original) _composer.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _pickAttachments() async {
    final owner = ref.read(agentOwnerProvider);
    setState(() => _readingAttachment = true);
    try {
      final selection = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: AgentAttachmentService.supportedExtensions,
      );
      if (!mounted || selection == null) return;
      final items = <AgentAttachment>[];
      for (final file in selection.files) {
        final bytes = file.bytes;
        if (bytes == null) throw const FormatException('文件未能读取，请重新选择。');
        items.add(await AgentAttachmentService().read(file.name, bytes));
      }
      if (_stillOwner(owner)) {
        ref.read(agentInteractionProvider.notifier).addAttachments(items);
      }
    } on Object catch (error) {
      if (mounted) {
        _snack(error is FormatException ? error.message : '附件读取失败，请重试或换一种格式。');
      }
    } finally {
      if (mounted) setState(() => _readingAttachment = false);
    }
  }

  Future<void> _school() async {
    final owner = ref.read(agentOwnerProvider);
    final attachment = await Navigator.of(context).push<AgentAttachment>(
      checkDPageRoute<AgentAttachment>(builder: (_) => const AgentSchoolPage()),
    );
    if (attachment != null && _stillOwner(owner)) {
      ref.read(agentInteractionProvider.notifier).addAttachments([attachment]);
    }
  }

  Future<void> _previewAttachment(AgentAttachment attachment) =>
      _showSettledDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(attachment.name),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (attachment.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        attachment.note,
                        style: TextStyle(color: AppColors.orange),
                      ),
                    ),
                  if (attachment.text.isNotEmpty)
                    SelectableText(attachment.text),
                  for (final data in attachment.images)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Image.memory(
                        base64Decode(data.substring(data.indexOf(',') + 1)),
                        semanticLabel: attachment.name,
                        errorBuilder: (_, _, _) =>
                            const Text('图片预览不可用，请重新选择文件。'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );

  Future<void> _profile(AgentWorkspace workspace) async {
    final owner = ref.read(agentOwnerProvider);
    final form = GlobalKey<FormState>();
    final share = TextEditingController(
      text:
          '${((workspace.profile['learningShare'] as num? ?? .2) * 100).round()}',
    );
    final sleep = TextEditingController(
      text: _time(workspace.profile['sleepStartMinute'] as int? ?? 0),
    );
    final wake = TextEditingController(
      text: _time(workspace.profile['sleepEndMinute'] as int? ?? 450),
    );
    final living = TextEditingController(
      text: '${workspace.profile['livingMinutesPerDay'] ?? 180}',
    );
    final from = TextEditingController(
      text: '${workspace.profile['confirmedFrom'] ?? ''}',
    );
    final through = TextEditingController(
      text: '${workspace.profile['confirmedThrough'] ?? ''}',
    );
    final notes = TextEditingController(
      text: '${workspace.profile['notes'] ?? ''}',
    );
    var reminders = workspace.profile['remindersEnabled'] == true;
    var autoApply = workspace.profile['autoApply'] == true;
    var saving = false;
    String? error;
    await _showSettledDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('作息与时间预算'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('以下是规划约束；初始作息和生活预留是估计，请核对。所有目标共用同一份预算。'),
                    const SizedBox(height: 14),
                    _formText(
                      share,
                      '用于目标学习的闲暇比例（%）',
                      number: true,
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return n == null || n < 0 || n > 100
                            ? '请输入 0—100'
                            : null;
                      },
                    ),
                    _formText(sleep, '入睡时间（24 小时）', validator: _timeValidator),
                    _formText(wake, '起床时间（24 小时）', validator: _timeValidator),
                    _formText(
                      living,
                      '每天必要生活预留（分钟）',
                      number: true,
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return n == null || n < 0 || n > 720
                            ? '请输入 0—720 分钟'
                            : null;
                      },
                    ),
                    _formText(
                      from,
                      '已核对课表的开始日期',
                      hint: 'YYYY-MM-DD；未知可留空',
                      validator: _dateValidator,
                    ),
                    _formText(
                      through,
                      '已核对课表的结束日期',
                      hint: 'YYYY-MM-DD；未知可留空',
                      validator: _dateValidator,
                    ),
                    _formText(
                      notes,
                      '其他约束与已有材料',
                      hint: '例如：周三晚上保留社团活动',
                      maxLines: 3,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('开启智能体学习提醒与进度核对'),
                      subtitle: const Text(
                        '开始后5分钟内提醒；最后一段结束10分钟后核对；周日20:30–21:00复盘。原有手工提醒仍在事项详情管理。',
                      ),
                      value: reminders,
                      onChanged: saving
                          ? null
                          : (value) => update(() => reminders = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('自动应用非课程修改'),
                      subtitle: const Text(
                        '默认关闭。开启后，无待澄清问题的非课程提案会直接写入，可撤销最近20次。含课程的整批修改始终先预览。',
                      ),
                      value: autoApply,
                      onChanged: saving
                          ? null
                          : (value) => update(() => autoApply = value),
                    ),
                    const Text('当前统一使用北京时间。课表范围之外只规划方向，不猜测空闲时间。'),
                    if (error != null)
                      Text(error!, style: TextStyle(color: AppColors.red)),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      if (!_stillOwner(owner)) {
                        update(() => error = '账号已变化，请关闭后重新编辑。');
                        return;
                      }
                      if (from.text.isEmpty != through.text.isEmpty ||
                          (from.text.isNotEmpty &&
                              through.text.compareTo(from.text) < 0)) {
                        update(() => error = '请同时填写有效的课表起止日期。');
                        return;
                      }
                      update(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await ref.read(agentRepositoryProvider).saveProfile({
                          ...workspace.profile,
                          'timezone': 'Asia/Shanghai',
                          'learningShare': int.parse(share.text) / 100,
                          'sleepStartMinute': _parseTime(sleep.text),
                          'sleepEndMinute': _parseTime(wake.text),
                          'livingMinutesPerDay': int.parse(living.text),
                          'confirmedFrom': from.text.isEmpty ? null : from.text,
                          'confirmedThrough': through.text.isEmpty
                              ? null
                              : through.text,
                          'notes': notes.text.trim(),
                          'remindersEnabled': reminders,
                          'autoApply': autoApply,
                        });
                        if (context.mounted) Navigator.pop(context);
                      } on Object {
                        if (context.mounted) {
                          update(() {
                            saving = false;
                            error = '资料未保存，请核对后重试。';
                          });
                        }
                      }
                    },
              child: const Text('保存资料'),
            ),
          ],
        ),
      ),
    );
    for (final controller in [
      share,
      sleep,
      wake,
      living,
      from,
      through,
      notes,
    ]) {
      controller.dispose();
    }
  }

  Future<void> _goal([Map<String, Object?>? existing]) async {
    final owner = ref.read(agentOwnerProvider);
    final form = GlobalKey<FormState>();
    final title = TextEditingController(
      text: '${existing?['name'] ?? existing?['title'] ?? ''}',
    );
    final purpose = TextEditingController(
      text: '${existing?['purpose'] ?? ''}',
    );
    final deadline = TextEditingController(
      text: '${existing?['deadline'] ?? ''}',
    );
    final notes = TextEditingController(text: '${existing?['notes'] ?? ''}');
    final accepted = await _showSettledDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? '添加一个目标' : '修改目标'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _formText(
                    title,
                    '目标名称',
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请填写目标名称' : null,
                  ),
                  _formText(purpose, '为什么想完成它', maxLines: 2),
                  _formText(
                    deadline,
                    '期望完成日期',
                    hint: 'YYYY-MM-DD；待定可留空',
                    validator: _dateValidator,
                  ),
                  _formText(notes, '起点、材料与规划', maxLines: 4),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('查看改动预览'),
          ),
        ],
      ),
    );
    if (accepted == true && _stillOwner(owner)) {
      await _preview([
        AgentOperation(
          action: 'upsert_goal',
          entityId: existing?['id'] as String?,
          data: {
            'name': title.text.trim(),
            'purpose': purpose.text.trim(),
            'deadline': deadline.text.isEmpty ? null : deadline.text,
            'notes': notes.text.trim(),
          },
        ),
      ], existing == null ? '新增目标，其余目标和日程保持原样。' : '更新这个目标的资料。');
    }
    for (final controller in [title, purpose, deadline, notes]) {
      controller.dispose();
    }
  }

  Future<void> _busyPeriod() async {
    final owner = ref.read(agentOwnerProvider);
    final now = DateTime.now();
    final date = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(now),
    );
    final start = TextEditingController(
      text: _time(now.hour * 60 + now.minute),
    );
    final duration = TextEditingController(text: '30');
    final reason = TextEditingController();
    final form = GlobalKey<FormState>();
    final accepted = await _showSettledDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('临时有事，重新安排'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('只调整受影响的未完成安排，已发生的计时和完成记录保持原样；排不下的事项进入待安排。'),
                  _formText(
                    reason,
                    '临时事项',
                    hint: '例如：去取快递、临时开会',
                    validator: (v) => (v ?? '').trim().isEmpty ? '请填写事项' : null,
                  ),
                  _formText(
                    date,
                    '日期',
                    validator: (v) =>
                        (v ?? '').isEmpty ? '请选择日期' : _dateValidator(v),
                  ),
                  _formText(start, '开始时间', validator: _timeValidator),
                  _formText(
                    duration,
                    '预计占用（分钟）',
                    number: true,
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 5 || n > 480
                          ? '请输入 5—480 分钟，跨夜请分开填写'
                          : null;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('预览重排'),
          ),
        ],
      ),
    );
    if (accepted == true && _stillOwner(owner)) {
      await _preview([
        AgentOperation(
          action: 'add_busy_period',
          data: {
            'date': date.text,
            'startMinute': _parseTime(start.text),
            'durationMinutes': int.parse(duration.text),
            'reason': reason.text.trim(),
          },
        ),
      ], '加入临时占用，并核对受影响的未完成日程。');
    }
    for (final controller in [date, start, duration, reason]) {
      controller.dispose();
    }
  }

  Future<void> _feedback() async {
    final owner = ref.read(agentOwnerProvider);
    final form = GlobalKey<FormState>();
    final date = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
    final minutes = TextEditingController();
    final content = TextEditingController();
    final evidence = TextEditingController();
    String? selectedTask;
    final links = {
      for (final row
          in ref.read(agentWorkspaceProvider).value?.taskLinks ??
              const <Map<String, Object?>>[])
        if (row['taskId'] is String) row['taskId'] as String: row,
    };
    final accepted = await _showSettledDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('记录真实学习反馈'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('这份自报反馈会与软件计时、打卡分开记录，不自动记为任务完成。'),
                  if (links.isNotEmpty)
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '对应学习事项（可选）',
                      ),
                      items: [
                        for (final entry in links.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(
                              '${entry.value['title'] ?? entry.value['name'] ?? '学习事项'}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => selectedTask = value,
                    ),
                  _formText(
                    date,
                    '日期',
                    validator: (v) =>
                        (v ?? '').isEmpty ? '请填写日期' : _dateValidator(v),
                  ),
                  _formText(
                    minutes,
                    '实际学习分钟（不确定可留空）',
                    number: true,
                    validator: (v) {
                      if ((v ?? '').isEmpty) return null;
                      final n = int.tryParse(v!);
                      return n == null || n < 0 || n > 1440
                          ? '请输入 0—1440 分钟'
                          : null;
                    },
                  ),
                  _formText(
                    content,
                    '完成内容与最卡的一点',
                    maxLines: 3,
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? '请写下实际反馈' : null,
                  ),
                  _formText(evidence, '正确数、作文或其他可核对产出', maxLines: 3),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('查看记录预览'),
          ),
        ],
      ),
    );
    if (accepted == true && _stillOwner(owner)) {
      await _preview([
        AgentOperation(
          action: 'record_feedback',
          data: {
            'date': date.text,
            'actualMinutes': minutes.text.isEmpty
                ? null
                : int.parse(minutes.text),
            'content': content.text.trim(),
            'taskId': ?selectedTask,
            'evidence': evidence.text.trim(),
            'source': 'selfReported',
          },
        ),
      ], '记录这次自报反馈，不修改真实计时或打卡。');
    }
    for (final controller in [date, minutes, content, evidence]) {
      controller.dispose();
    }
  }

  Future<void> _preview(List<AgentOperation> operations, String message) async {
    setState(() => _view = 0);
    await ref
        .read(agentInteractionProvider.notifier)
        .preview(operations, message);
  }

  Future<void> _clearConversation() async {
    final owner = ref.read(agentOwnerProvider);
    final yes = await _showSettledDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空当前对话？'),
        content: const Text('只清空当前账号的聊天内容，目标、任务和变更记录会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空对话'),
          ),
        ],
      ),
    );
    if (yes == true && _stillOwner(owner)) {
      try {
        await ref.read(agentRepositoryProvider).clearConversation();
        if (mounted) _snack('当前对话已清空');
      } on Object {
        if (mounted) _snack('清空未完成，请重试。');
      }
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
  bool _stillOwner(String owner) =>
      mounted && ref.read(agentOwnerGuardProvider)(owner);
}

Widget _formText(
  TextEditingController controller,
  String label, {
  String? hint,
  int maxLines = 1,
  bool number = false,
  String? Function(String?)? validator,
}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 8),
  child: TextFormField(
    controller: controller,
    maxLines: maxLines,
    validator: validator,
    keyboardType: number
        ? TextInputType.number
        : maxLines > 1
        ? TextInputType.multiline
        : TextInputType.text,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
    ),
  ),
);
String _time(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
int _parseTime(String text) {
  final parts = text.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String? _timeValidator(String? text) =>
    RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(text ?? '')
    ? null
    : '请输入 HH:mm，例如 07:30';
String? _dateValidator(String? text) {
  if ((text ?? '').isEmpty) return null;
  final parsed = DateTime.tryParse(text!);
  return parsed == null || DateFormat('yyyy-MM-dd').format(parsed) != text
      ? '请输入有效的 YYYY-MM-DD 日期'
      : null;
}

String _value(Object? value) =>
    value is String ? value : const JsonEncoder.withIndent('  ').convert(value);

class _ReminderCapability extends ConsumerWidget {
  const _ReminderCapability({required this.enabled});
  final bool enabled;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(agentReminderPermissionProvider).value;
    final status = switch (permission) {
      NotificationPermissionState.granted => '系统通知权限已允许；送达仍受系统后台策略影响。',
      NotificationPermissionState.denied => '系统通知权限未允许，当前仅提供前台提示。',
      NotificationPermissionState.unsupported => '当前环境未验证系统定时通知，使用前台提示。',
      _ => '正在检查系统通知能力。',
    };
    return CheckDSurface(
      level: CheckDSurfaceLevel.glassSoft,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            enabled ? '学习提醒已开启' : '学习提醒未开启',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Text(
            '$status\n打开 App 时按北京时间检查，关闭 App 后不会由云端发送提醒。',
            style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.5),
          ),
          if (permission == NotificationPermissionState.denied)
            TextButton(
              onPressed: () async {
                try {
                  await ref
                      .read(notificationServiceProvider)
                      .requestPermissions();
                } on Object {
                  /* The capability text stays accurate if unavailable. */
                }
                ref.invalidate(agentReminderPermissionProvider);
              },
              child: const Text('申请系统通知权限'),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, {required this.icon, required this.color});
  final String text;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: color, height: 1.5)),
        ),
      ],
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final AgentChatMessage message;
  @override
  Widget build(BuildContext context) {
    final user = message.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: .94,
          child: CheckDSurface(
            level: user ? CheckDSurfaceLevel.raised : CheckDSurfaceLevel.plain,
            color: user ? AppColors.primary.withValues(alpha: .08) : null,
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user ? '你' : 'CheckD 智能体',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppColors.primaryStrong,
                  ),
                ),
                const SizedBox(height: 7),
                SelectableText(
                  message.text,
                  style: TextStyle(color: AppColors.ink, height: 1.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OperationPreview extends StatelessWidget {
  const _OperationPreview({required this.operation, required this.names});
  final AgentOperation operation;
  final Map<String, String> names;
  @override
  Widget build(BuildContext context) {
    const actions = {
      'create_task': '新增事项',
      'update_task': '修改事项',
      'archive_task': '归档事项',
      'reschedule_task': '调整单日安排',
      'create_course': '新增课程',
      'update_course': '修改课程',
      'archive_course': '归档课程',
      'update_course_day': '调整单日课表',
      'create_plan': '新增计划',
      'update_plan': '修改计划',
      'archive_plan': '归档计划',
      'create_tag': '新增标签',
      'update_tag': '修改标签',
      'archive_tag': '归档标签',
      'upsert_goal': '保存目标',
      'archive_goal': '归档目标',
      'update_profile': '更新规划资料',
      'add_busy_period': '加入临时占用并重排',
      'remove_busy_period': '移除临时占用',
      'record_feedback': '记录自报反馈',
      'save_review': '保存复盘',
    };
    const fields = {
      'name': '名称',
      'title': '目标/事项',
      'purpose': '目的',
      'deadline': '截止要求',
      'notes': '备注',
      'date': '日期',
      'scheduledAt': '计划时间',
      'plannedDate': '计划日期',
      'startMinute': '开始时间',
      'endMinute': '结束时间',
      'durationMinutes': '占用分钟',
      'reason': '原因',
      'actualMinutes': '自报学习分钟',
      'content': '反馈内容',
      'evidence': '可核对产出',
      'courses': '该日课程',
      'weekdays': '每周执行日',
      'startsOn': '开始日期',
      'endsOn': '结束日期',
      'goalId': '关联目标',
      'kind': '事项类型',
      'standard': '完成标准',
      'isTimed': '是否计时',
      'targetDurationSeconds': '目标秒数',
      'teacher': '教师',
      'classroom': '教室',
      'rules': '课程安排',
      'learningShare': '共享时间比例',
      'roadmap': '规划内容',
      'materials': '材料',
      'executionMode': '执行方式',
      'recurringMode': '执行方式',
      'oneTimeExecutionMode': '执行方式',
      'schedulePreset': '重复方式',
      'scheduledMinuteOfDay': '计划开始时间',
      'plannedStartMinute': '当天开始时间',
      'plannedEndMinute': '当天结束时间',
      'sleepStartMinute': '就寝时间',
      'sleepEndMinute': '起床时间',
      'livingMinutesPerDay': '每日生活预留',
      'confirmedFrom': '课表已核对起始日',
      'confirmedThrough': '课表已核对结束日',
      'remindersEnabled': '学习提醒',
      'autoApply': '自动应用非课程修改',
      'planningStartedOn': '本轮规划开始日',
      'timezone': '时区',
      'taskId': '对应学习事项',
      'segmentId': '对应学习时段',
      'weekday': '星期',
      'weekRuleType': '上课周规则',
      'weekNumbers': '指定教学周',
      'startsAtMinute': '开始时间',
      'endsAtMinute': '结束时间',
      'semesterStartsOn': '学期开始日期',
      'semesterEndsOn': '学期结束日期',
      'type': '类别',
      'availableFrom': '可开始日期',
      'holidayPause': '节假日暂停',
      'repeat': '重复安排',
      'colorValue': '显示配色',
      'goalName': '对应目标',
      'archived': '归档状态',
      'startsAt': '开始时间',
      'endsAt': '结束时间',
      'dueDate': '截止日期',
      'dueAt': '截止时间',
      'ruleId': '对应课程时段',
      'courseId': '对应课程',
      'summary': '总结',
      'happenedText': '实际发生',
      'learnedText': '收获',
      'improveText': '下次改进',
    };
    final title =
        operation.data['name'] ??
        operation.data['title'] ??
        names[operation.entityId];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 10),
          initiallyExpanded: true,
          title: Text(
            '${actions[operation.action] ?? '更新安排'}${title == null ? '' : ' · $title'}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          children: [
            for (final entry in operation.data.entries)
              if (!{'source', 'id', 'userId'}.contains(entry.key))
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: SelectableText(
                      '${fields[entry.key] ?? '补充说明'}：${_previewValue(entry.key, entry.value, fields)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.ink,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _previewValue(String key, Object? value, Map<String, String> fields) {
    const enumerations = {
      'oneTime': '单次事项',
      'one_time': '单次事项',
      'recurring': '周期任务',
      'timed': '计时',
      'untimed': '手动打卡',
      'daily': '每天',
      'weekdays': '工作日',
      'custom': '自定义',
      'weekly': '每周',
      'everyWeek': '每周',
      'oddWeeks': '单周',
      'evenWeeks': '双周',
      'customWeeks': '指定周',
      'month': '月度',
      'monthly': '月度',
      'year': '年度',
      'yearly': '年度',
      'week': '周',
      'day': '日',
      'reschedule': '调整当天时间',
      'skip': '跳过当天',
      'Asia/Shanghai': '北京时间',
      'learning': '学习',
    };
    const timeFields = {
      'startMinute',
      'endMinute',
      'plannedStartMinute',
      'plannedEndMinute',
      'scheduledMinuteOfDay',
      'startsAtMinute',
      'endsAtMinute',
      'sleepStartMinute',
      'sleepEndMinute',
      'reminderMinuteOfDay',
    };
    if (value == null) return '未指定';
    if (value is bool) return value ? '开启' : '关闭';
    if (value is int && timeFields.contains(key)) return _time(value);
    if (key == 'colorValue') return '使用提案配色';
    if (key == 'learningShare' && value is num) {
      return '${(value * 100).round()}%';
    }
    if (key == 'targetDurationSeconds' && value is num) {
      return '${(value / 60).ceil()} 分钟';
    }
    if ({
      'durationMinutes',
      'actualMinutes',
      'livingMinutesPerDay',
    }.contains(key)) {
      return '$value 分钟';
    }
    if (key == 'weekday' && value is int) return _weekday(value);
    if (key == 'weekdays' && value is List) {
      return value.map((day) => day is int ? _weekday(day) : '$day').join('、');
    }
    if (key.endsWith('Id') && value is String) {
      return names[value] ?? '本次提案关联的安排';
    }
    if (value is Map) {
      return value.entries
          .where((entry) => !{'source', 'id', 'userId'}.contains(entry.key))
          .map(
            (entry) =>
                '${fields['${entry.key}'] ?? '补充说明'}：${_previewValue('${entry.key}', entry.value, fields)}',
          )
          .join('\n');
    }
    if (value is List) {
      return value.map((item) => _previewValue(key, item, fields)).join('\n');
    }
    return enumerations[value] ?? '$value';
  }

  String _weekday(int value) => value >= 1 && value <= 7
      ? '周${const ['一', '二', '三', '四', '五', '六', '日'][value - 1]}'
      : '待确认';
}
