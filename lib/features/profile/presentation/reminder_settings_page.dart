import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_providers.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_theme.dart';
import '../application/reminder_defaults_providers.dart';
import '../data/reminder_defaults_repository.dart';

class ReminderSettingsPage extends ConsumerStatefulWidget {
  const ReminderSettingsPage({super.key});

  @override
  ConsumerState<ReminderSettingsPage> createState() =>
      _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends ConsumerState<ReminderSettingsPage> {
  ReminderDefaults _defaults = const ReminderDefaults();
  bool _loadingDefaults = true;
  bool _savingDefaults = false;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    final value = await ref.read(reminderDefaultsRepositoryProvider).load();
    if (mounted) {
      setState(() {
        _defaults = value;
        _loadingDefaults = false;
      });
    }
  }

  Future<void> _saveDefaults() async {
    setState(() => _savingDefaults = true);
    try {
      await ref.read(reminderDefaultsRepositoryProvider).save(_defaults);
      ref.invalidate(reminderDefaultsProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('默认提醒已保存')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('默认提醒保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _savingDefaults = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permission = ref.watch(notificationPermissionStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('提醒设置')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: permission.when(
                loading: () => const Row(
                  children: [
                    SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('正在检查通知权限'),
                  ],
                ),
                error: (_, _) => _PermissionMessage(
                  title: '无法读取通知权限',
                  action: '重试',
                  onPressed: () =>
                      ref.invalidate(notificationPermissionStateProvider),
                ),
                data: (state) => switch (state) {
                  NotificationPermissionState.granted =>
                    const _PermissionMessage(
                      title: '通知权限已开启',
                      detail: '未来的提前提醒和到点提醒会按计划发送。',
                    ),
                  NotificationPermissionState.denied => _PermissionMessage(
                    title: '通知权限未开启',
                    detail: '提醒设置会保存，但系统不会发送通知。',
                    action: '开启通知权限',
                    onPressed: () async {
                      await ref
                          .read(notificationServiceProvider)
                          .requestPermissions();
                      ref.invalidate(notificationPermissionStateProvider);
                    },
                  ),
                  _ => const _PermissionMessage(
                    title: '当前平台暂不支持通知权限查询',
                    detail: '提醒配置会保存；平台支持后会自动尝试调度。',
                  ),
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _loadingDefaults
                  ? const SizedBox(
                      height: 64,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.notifications_active_outlined,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 8),
                            Text('默认提醒'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('默认提前提醒'),
                          value: _defaults.advanceEnabled,
                          onChanged: (value) => setState(
                            () => _defaults = _defaults.copyWith(
                              advanceEnabled: value,
                            ),
                          ),
                        ),
                        if (_defaults.advanceEnabled)
                          DropdownButtonFormField<int>(
                            value: _defaults.advanceMinutes,
                            decoration: const InputDecoration(
                              labelText: '提前时间',
                            ),
                            items: const [5, 10, 15, 30, 60]
                                .map(
                                  (minutes) => DropdownMenuItem(
                                    value: minutes,
                                    child: Text('提前 $minutes 分钟'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => setState(
                              () => _defaults = _defaults.copyWith(
                                advanceMinutes: value ?? 10,
                              ),
                            ),
                          ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('默认到点提醒'),
                          value: _defaults.atTimeEnabled,
                          onChanged: (value) => setState(
                            () => _defaults = _defaults.copyWith(
                              atTimeEnabled: value,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '默认提醒仅用于新建内容，不会修改已有课程或事项。',
                          style: TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: _savingDefaults ? null : _saveDefaults,
                          child: Text(_savingDefaults ? '保存中…' : '保存默认提醒'),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.alarm_outlined, color: AppColors.lavender),
              title: Text('强提醒能力'),
              subtitle: Text('会根据设备平台逐步提供；本阶段仅使用普通通知。'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionMessage extends StatelessWidget {
  const _PermissionMessage({
    required this.title,
    this.detail,
    this.action,
    this.onPressed,
  });
  final String title;
  final String? detail;
  final String? action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      if (detail != null) ...[
        const SizedBox(height: 6),
        Text(detail!, style: const TextStyle(color: AppColors.muted)),
      ],
      if (action != null) ...[
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onPressed, child: Text(action!)),
      ],
    ],
  );
}
