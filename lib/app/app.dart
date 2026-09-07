import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../core/notifications/reminder_scheduler_providers.dart';
import '../core/platform/desktop_mini_window.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/shell/presentation/app_shell.dart';
import 'app_providers.dart';

class CheckDApp extends ConsumerWidget {
  const CheckDApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const _AppGate()),
      ],
    );

    return DesktopMainWindowSyncHost(
      onRefresh: () => ref.read(miniWindowDataRevisionProvider.notifier).bump(),
      child: ReminderSchedulerHost(
        child: MaterialApp.router(
          title: 'Check D',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          routerConfig: router,
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
      AuthStatus.authenticated || AuthStatus.offline => const AppShell(),
    };
  }
}
