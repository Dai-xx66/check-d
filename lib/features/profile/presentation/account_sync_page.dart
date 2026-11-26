import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/app_providers.dart';
import '../../../core/sync/sync_account_service.dart';
import '../../../core/sync/sync_bootstrap_service.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/sync/sync_queue_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/check_d_design.dart';
import '../../auth/presentation/auth_controller.dart';

class AccountSyncPage extends ConsumerWidget {
  const AccountSyncPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final client = ref.watch(supabaseClientProvider);
    final user = client?.auth.currentUser;
    final sync = ref.watch(syncAccountStatusProvider);
    final health = ref.watch(syncOperationHealthProvider).value;
    final diagnostics = ref.watch(syncFailureDiagnosticsProvider);
    final offline = ref.watch(offlineDataSummaryProvider);
    final busy =
        sync.phase == SyncAccountPhase.restoring ||
        sync.phase == SyncAccountPhase.syncing;

    return Scaffold(
      appBar: AppBar(title: const Text('账号与同步')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CheckDSurface(
            level: CheckDSurfaceLevel.raised,
            radius: BorderRadius.circular(20),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '当前账号',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(user?.email ?? '未登录'),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Icon(_statusIcon(sync), color: _statusColor(sync)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _statusLabel(sync),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _statusDetail(sync, health),
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  sync.lastSuccessAt == null
                      ? '尚无成功同步记录'
                      : '上次成功同步：${DateFormat('yyyy年M月d日 HH:mm').format(sync.lastSuccessAt!.toLocal())}',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: busy || user == null
                        ? null
                        : () => ref
                              .read(syncAccountCoordinatorProvider)
                              ?.syncNow(user.id),
                    icon: const Icon(Icons.sync),
                    label: Text(busy ? '正在同步' : '立即同步'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          offline.when(
            data: (summary) => summary.isEmpty
                ? const SizedBox.shrink()
                : _OfflineDataCard(
                    summary: summary,
                    onMerge: user == null
                        ? null
                        : () => _confirmMerge(context, ref, user.id, summary),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          _SyncDiagnosticsCard(diagnostics: diagnostics),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: auth.isSubmitting
                ? null
                : () => ref.read(authControllerProvider.notifier).signOut(),
            child: const Text('退出登录'),
          ),
          if (auth.errorMessage case final message?) ...[
            const SizedBox(height: 8),
            Text(message, style: TextStyle(color: AppColors.red)),
          ],
          const SizedBox(height: 8),
          Text(
            '退出登录不会删除本机数据或云端数据。',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  static Future<void> _confirmMerge(
    BuildContext context,
    WidgetRef ref,
    String userId,
    OfflineDataSummary summary,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('合并本机未同步数据？'),
        content: Text(
          '课程 ${summary.courses}\n任务 ${summary.tasks}\n'
          '计时记录 ${summary.timerSessions}\n完成记录 ${summary.completions}\n'
          '其他关联记录 ${summary.otherRecords}\n\n'
          '合并会保留实体 ID；如检测到归属冲突，将取消整个事务。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('暂不处理'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('合并到当前账号'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(offlineDataMergeServiceProvider).mergeInto(userId);
      ref.invalidate(offlineDataSummaryProvider);
      await ref.read(syncAccountCoordinatorProvider)?.syncNow(userId);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('本机数据已合并并进入同步队列。')));
      }
    } on OfflineDataConflict catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('合并没有完成，本机原数据保持不变。')));
      }
    }
  }

  static String _statusLabel(SyncAccountState state) => switch (state.phase) {
    SyncAccountPhase.idle => '等待同步',
    SyncAccountPhase.restoring => '正在恢复云端数据',
    SyncAccountPhase.syncing => '正在同步',
    SyncAccountPhase.synced => '已同步',
    SyncAccountPhase.failed => state.partialFailure ? '部分同步失败' : '同步失败',
  };

  static String _statusDetail(
    SyncAccountState state,
    SyncOperationHealth? health,
  ) {
    if (state.message != null) return state.message!;
    final failed = health?.failed ?? 0;
    final pending = health?.pending ?? 0;
    if (failed > 0) return '$failed 项同步失败，可点击立即同步重试';
    if (pending > 0) return '$pending 项等待上传';
    return '本机数据与云端保持一致';
  }

  static IconData _statusIcon(SyncAccountState state) => switch (state.phase) {
    SyncAccountPhase.restoring || SyncAccountPhase.syncing => Icons.sync,
    SyncAccountPhase.failed => Icons.cloud_off_outlined,
    SyncAccountPhase.synced => Icons.cloud_done_outlined,
    SyncAccountPhase.idle => Icons.cloud_outlined,
  };

  static Color _statusColor(SyncAccountState state) =>
      state.phase == SyncAccountPhase.failed
      ? AppColors.primaryStrong
      : AppColors.accentMint;
}

class _SyncDiagnosticsCard extends StatelessWidget {
  const _SyncDiagnosticsCard({required this.diagnostics});

  final AsyncValue<List<SyncFailureDiagnostic>> diagnostics;

  @override
  Widget build(BuildContext context) => CheckDSurface(
    level: CheckDSurfaceLevel.raised,
    radius: BorderRadius.circular(20),
    padding: EdgeInsets.zero,
    child: Material(
      type: MaterialType.transparency,
      child: ExpansionTile(
        leading: const Icon(Icons.bug_report_outlined),
        title: const Text('同步诊断（开发）'),
        subtitle: const Text('仅显示当前账号的脱敏失败信息'),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        children: [
          diagnostics.when(
            data: (items) => items.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '当前账号没有失败操作',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  )
                : Column(
                    children: [
                      for (var index = 0; index < items.length; index++) ...[
                        if (index > 0) const Divider(height: 20),
                        _SyncDiagnosticRow(item: items[index]),
                      ],
                    ],
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            ),
            error: (_, _) => Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '诊断信息暂时无法读取',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SyncDiagnosticRow extends StatelessWidget {
  const _SyncDiagnosticRow({required this.item});

  final SyncFailureDiagnostic item;

  @override
  Widget build(BuildContext context) {
    final failedAt = DateFormat(
      'yyyy年M月d日 HH:mm',
    ).format(item.lastFailureAt.toLocal());
    final stage = switch (item.failureStage) {
      'prepare' => '准备上传',
      'upsert' => '写入云端',
      'clear_active_flag' => '更新活动状态',
      'replace_plan_tasks' => '更新计划关联',
      null => '历史错误信息不足',
      final value => value,
    };
    final table = item.failureTable ?? '历史错误信息不足';
    final code = item.errorCode ?? '未提供';
    return Semantics(
      label: '同步失败诊断',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '失败操作：${item.entityType}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('失败阶段：$stage'),
          const SizedBox(height: 4),
          Text('失败表名：$table'),
          const SizedBox(height: 4),
          Text('错误代码：$code'),
          const SizedBox(height: 4),
          Text('错误类别：${item.errorCategory}'),
          const SizedBox(height: 4),
          Text(
            '已重试 ${item.retryCount} 次 · 最近失败 $failedAt',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _OfflineDataCard extends StatelessWidget {
  const _OfflineDataCard({required this.summary, required this.onMerge});

  final OfflineDataSummary summary;
  final VoidCallback? onMerge;

  @override
  Widget build(BuildContext context) => CheckDSurface(
    level: CheckDSurfaceLevel.raised,
    radius: BorderRadius.circular(20),
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('发现本机未同步数据', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          '课程 ${summary.courses} · 任务 ${summary.tasks} · '
          '计时 ${summary.timerSessions} · 其他 ${summary.otherRecords}',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 14),
        OutlinedButton(onPressed: onMerge, child: const Text('合并到当前账号')),
      ],
    ),
  );
}
