import 'dart:async';

import 'package:check_d/app/app.dart';
import 'package:check_d/app/app_providers.dart';
import 'package:check_d/core/config/app_config.dart';
import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_providers.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/auth/data/auth_repository.dart';
import 'package:check_d/features/auth/presentation/auth_controller.dart';
import 'package:check_d/features/tasks/application/task_providers.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

void main() {
  late _AuthRepository repository;
  late AppDatabase database;
  late ProviderContainer container;

  setUpAll(() => initializeDateFormatting('zh_CN'));

  setUp(() {
    repository = _AuthRepository();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        appDatabaseProvider.overrideWithValue(database),
        supabaseClientProvider.overrideWithValue(null),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await repository.changes.close();
    await database.close();
  });

  test('restored session selects the authenticated account immediately', () {
    repository.user = _user('account-a');
    expect(container.read(currentDataOwnerProvider), 'account-a');
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.authenticated,
    );
  });

  test(
    'account switch rebuilds repositories and hides the old account',
    () async {
      final day = DateTime(2026, 11, 23);
      final seed = TaskRepository(
        database: database,
        syncQueue: SyncQueueService(database),
        userId: 'account-a',
      );
      final taskId = await seed.saveOneTimeReminder(
        OneTimeReminderDraft(
          name: 'Private account A task',
          colorValue: 1,
          scheduledAt: day.add(const Duration(hours: 9)),
        ),
      );
      repository.user = _user('account-a');
      final first = container.read(taskRepositoryProvider);
      expect(await first.getTask(taskId), isNotNull);

      repository.emit(null);
      expect(container.read(currentDataOwnerProvider), 'offline-user');
      repository.emit(_user('account-b'));
      final second = container.read(taskRepositoryProvider);
      expect(container.read(currentDataOwnerProvider), 'account-b');
      expect(identical(first, second), isFalse);
      expect(await second.getTask(taskId), isNull);
      expect(await second.watchTasksForDate(day).first, isEmpty);
    },
  );

  test(
    'sync health switches accounts and clears after session expiry',
    () async {
      final queue = container.read(syncQueueServiceProvider);
      for (final owner in ['account-a', 'account-b', 'account-b']) {
        await queue.enqueue(
          entityType: 'tasks',
          entityId: 'task-$owner',
          operation: SyncOperationType.upsert,
          payload: const {},
          userId: owner,
        );
      }
      repository.user = _user('account-a');
      final subscription = container.listen(
        syncOperationHealthProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      expect(
        (await container.read(syncOperationHealthProvider.future)).pending,
        1,
      );

      repository.emit(_user('account-b'));
      expect(
        (await container.read(syncOperationHealthProvider.future)).pending,
        2,
      );
      repository.emit(null);
      expect(
        (await container.read(syncOperationHealthProvider.future)).pending,
        0,
      );
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.signedOut,
      );
    },
  );

  test('external auth events do not leave explicit offline mode', () {
    final controller = container.read(authControllerProvider.notifier);
    controller.continueOffline();
    repository.emit(_user('account-a'));
    expect(container.read(currentDataOwnerProvider), 'offline-user');
    expect(container.read(authControllerProvider).status, AuthStatus.offline);
  });

  test(
    'pending login rejects duplicate requests and offline navigation',
    () async {
      final completion = Completer<void>();
      repository.onSignIn = () async {
        await completion.future;
        repository.emit(_user('account-a'));
      };
      final controller = container.read(authControllerProvider.notifier);
      final pending = controller.signIn('a@example.test', 'test-password');
      expect(
        await controller.signIn('b@example.test', 'test-password'),
        isFalse,
      );
      controller.continueOffline();
      expect(container.read(authControllerProvider).isSubmitting, isTrue);
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.signedOut,
      );
      expect(repository.signInCalls, 1);

      completion.complete();
      expect(await pending, isTrue);
      expect(container.read(currentDataOwnerProvider), 'account-a');
    },
  );

  test(
    'expired session cannot be resurrected by a late login completion',
    () async {
      final completion = Completer<void>();
      repository.onSignIn = () => completion.future;
      final controller = container.read(authControllerProvider.notifier);
      final pending = controller.signIn('a@example.test', 'test-password');
      repository.emit(_user('account-a'));
      repository.emit(null);
      completion.complete();
      expect(await pending, isFalse);
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.signedOut,
      );
      expect(container.read(currentDataOwnerProvider), 'offline-user');
    },
  );

  test('sign-up without a session requests email confirmation', () async {
    final controller = container.read(authControllerProvider.notifier);
    expect(await controller.signUp('a@example.test', 'test-password'), isTrue);
    final state = container.read(authControllerProvider);
    expect(state.status, AuthStatus.signedOut);
    expect(state.userId, isNull);
    expect(state.isSubmitting, isFalse);
    expect(state.errorMessage, contains('邮箱完成验证'));
  });

  test(
    'failed sign-out remains on the account and reports a safe error',
    () async {
      repository.user = _user('account-a');
      repository.onSignOut = () async =>
          throw StateError('private backend detail');
      final controller = container.read(authControllerProvider.notifier);
      await controller.signOut();
      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.authenticated);
      expect(state.userId, 'account-a');
      expect(state.isSubmitting, isFalse);
      expect(state.errorMessage, '退出登录失败，请检查网络后重试。');
    },
  );

  test(
    'disposed controller ignores completion of an in-flight login',
    () async {
      final completion = Completer<void>();
      repository.onSignIn = () => completion.future;
      final controller = container.read(authControllerProvider.notifier);
      final pending = controller.signIn('a@example.test', 'test-password');
      container.invalidate(authControllerProvider);
      repository.user = _user('account-b');
      expect(container.read(currentDataOwnerProvider), 'account-b');
      completion.complete();
      expect(await pending, isFalse);
      expect(container.read(currentDataOwnerProvider), 'account-b');
    },
  );
  for (final nextAccount in [null, 'account-b']) {
    testWidgets('identity change to $nextAccount clears pushed account pages', (
      tester,
    ) async {
      repository.user = _user('account-a');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ProviderScope(
            overrides: [
              appConfigProvider.overrideWithValue(
                const AppConfig(supabaseUrl: '', supabaseAnonKey: ''),
              ),
            ],
            child: const CheckDApp(),
          ),
        ),
      );
      await tester.pump();
      final context = tester.element(find.text('正在恢复云端数据…'));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Text('account-a-private-detail')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('account-a-private-detail'), findsOneWidget);

      repository.emit(nextAccount == null ? null : _user(nextAccount));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('account-a-private-detail'), findsNothing);
      expect(
        find.text(nextAccount == null ? '欢迎回来' : '正在恢复云端数据…'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}

User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-11-23T00:00:00Z',
);

class _AuthRepository extends AuthRepository {
  _AuthRepository() : super(null);

  final changes = StreamController<User?>.broadcast(sync: true);
  User? user;
  int signInCalls = 0;
  Future<void> Function()? onSignIn;
  Future<void> Function()? onSignOut;

  @override
  User? get currentUser => user;

  @override
  Stream<User?> get userChanges => changes.stream;

  void emit(User? next) {
    user = next;
    changes.add(next);
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    await onSignIn?.call();
  }

  @override
  Future<bool> signUp({
    required String email,
    required String password,
  }) async => false;

  @override
  Future<void> signOut() async {
    await onSignOut?.call();
    emit(null);
  }
}
