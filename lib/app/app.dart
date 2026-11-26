import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_skin.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/appearance_controller.dart';
import '../core/notifications/reminder_scheduler_providers.dart';
import '../core/platform/desktop_mini_window.dart';
import '../core/sync/offline_data_merge_prompt.dart';
import '../core/sync/sync_account_service.dart';
import '../core/sync/sync_download_service.dart';
import '../core/sync/sync_providers.dart';
import '../core/sync/sync_upload_host.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/home_widget/presentation/home_widget_host.dart';
import '../features/lock_screen/presentation/lock_screen_status_host.dart';
import '../features/shell/presentation/app_shell.dart';
import 'app_providers.dart';

class CheckDApp extends ConsumerStatefulWidget {
  const CheckDApp({super.key});

  @override
  ConsumerState<CheckDApp> createState() => _CheckDAppState();
}

class _CheckDAppState extends ConsumerState<CheckDApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final _router = GoRouter(
    navigatorKey: _navigatorKey,
    routes: [GoRoute(path: '/', builder: (context, state) => const _AppGate())],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      authControllerProvider.select((auth) => (auth.status, auth.userId)),
      (_, _) {
        // Imperative detail/settings routes otherwise survive a root gate
        // rebuild and can keep the previous account's screen on top.
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
        _router.go('/');
      },
    );
    // 皮肤：优先用已加载的偏好，首帧（偏好尚未读出）用启动时写好的运行时值。
    final skinId =
        ref.watch(appearanceControllerProvider).value?.skin ??
        AppSkinHost.current.id;

    return DesktopMainWindowSyncHost(
      onRefresh: () => ref.read(miniWindowDataRevisionProvider.notifier).bump(),
      child: SyncUploadHost(
        child: LockScreenStatusHost(
          child: HomeWidgetHost(
            child: ReminderSchedulerHost(
              child: MaterialApp.router(
                title: 'Check D',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.build(AppSkin.of(skinId)),
                routerConfig: _router,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppGate extends ConsumerWidget {
  const _AppGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    return switch (authState.status) {
      AuthStatus.initializing => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      AuthStatus.signedOut => const LoginPage(),
      AuthStatus.authenticated => const AuthenticatedSyncGate(),
      AuthStatus.offline => const AppShell(),
    };
  }
}

class AuthenticatedSyncGate extends ConsumerWidget {
  const AuthenticatedSyncGate({super.key, this.shell});

  final Widget? shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncAccountStatusProvider);
    if (!sync.initialRestoreComplete) {
      if (sync.phase == SyncAccountPhase.failed) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 40),
                  const SizedBox(height: 16),
                  Text(sync.message ?? '云端数据恢复失败。'),
                  if (_safeRestoreDetail(sync) case final detail?) ...[
                    const SizedBox(height: 8),
                    Text(
                      detail,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      final userId = ref
                          .read(supabaseClientProvider)
                          ?.auth
                          .currentUser
                          ?.id;
                      if (userId != null) {
                        ref
                            .read(syncAccountCoordinatorProvider)
                            ?.syncNow(userId);
                      }
                    },
                    child: const Text('重新尝试'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在恢复云端数据…'),
            ],
          ),
        ),
      );
    }
    return shell ?? const OfflineDataMergePrompt(child: AppShell());
  }

  String? _safeRestoreDetail(SyncAccountState sync) {
    final stage = switch (sync.stage) {
      SyncAccountStage.reading => '读取云端数据',
      SyncAccountStage.validating => '校验云端数据',
      SyncAccountStage.applying => '写入本机数据',
      SyncAccountStage.bootstrap => '准备本机同步',
      SyncAccountStage.upload => '上传本机变更',
      null => null,
    };
    final table = sync.restoreTable;
    final category = switch (sync.restoreErrorCategory) {
      SyncRestoreErrorCategory.timeout => '请求超时',
      SyncRestoreErrorCategory.network => '网络连接失败',
      SyncRestoreErrorCategory.authentication => '登录状态异常',
      SyncRestoreErrorCategory.schema => '云端结构不兼容',
      SyncRestoreErrorCategory.localDatabase => '本机数据状态异常',
      SyncRestoreErrorCategory.conflict => '本机数据冲突',
      SyncRestoreErrorCategory.accountChanged => '账号已切换',
      SyncRestoreErrorCategory.unknown => '未知恢复错误',
      null => null,
    };
    final parts = <String>[
      if (stage != null) '阶段：$stage',
      if (table != null && table.isNotEmpty) '数据表：$table',
      if (category != null) '原因：$category',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
