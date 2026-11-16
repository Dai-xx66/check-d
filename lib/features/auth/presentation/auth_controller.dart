import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/app_providers.dart';
import '../data/auth_repository.dart';

enum AuthStatus { initializing, signedOut, authenticated, offline }

class AuthState {
  const AuthState({
    required this.status,
    this.userId,
    this.isSubmitting = false,
    this.errorMessage,
  });

  final AuthStatus status;
  final String? userId;
  final bool isSubmitting;
  final String? errorMessage;

  AuthState copyWith({
    AuthStatus? status,
    String? userId,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

/// Supabase is the source of truth for session creation, refresh, sign-out and
/// account switching. Keeping this stream injectable also lets provider tests
/// exercise the account-bound repository lifecycle without network auth.
final authStateChangesProvider = Provider<Stream<AuthState>>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const Stream<AuthState>.empty();
  return client.auth.onAuthStateChange.map((change) {
    final session = change.session;
    if (session == null) return const AuthState(status: AuthStatus.signedOut);
    return AuthState(status: AuthStatus.authenticated, userId: session.user.id);
  });
});

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  late final AuthRepository _repository;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  AuthState build() {
    _repository = ref.watch(authRepositoryProvider);
    final user = _repository.currentUser;
    final initial = AuthState(
      status: user == null ? AuthStatus.signedOut : AuthStatus.authenticated,
      userId: user?.id,
    );
    _authSubscription = ref
        .watch(authStateChangesProvider)
        .listen((next) => state = next);
    ref.onDispose(() => _authSubscription?.cancel());
    return initial;
  }

  Future<bool> signIn(String email, String password) async {
    return _runAuthAction(
      () => _repository.signIn(email: email, password: password),
      actionName: 'signIn',
    );
  }

  Future<bool> signUp(String email, String password) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final hasSession = await _repository.signUp(
        email: email,
        password: password,
      );
      if (hasSession) {
        state = AuthState(
          status: AuthStatus.authenticated,
          userId: _repository.currentUser?.id,
        );
      } else {
        state = const AuthState(
          status: AuthStatus.signedOut,
          errorMessage: '注册成功，请前往邮箱完成验证后登录。',
        );
      }
      return true;
    } on Object catch (error) {
      _logAuthFailure('signUp', error);
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _readableError(error, actionName: 'signUp'),
      );
      return false;
    }
  }

  void continueOffline() {
    state = const AuthState(status: AuthStatus.offline);
  }

  Future<void> signOut() async {
    await _repository.signOut();
    state = const AuthState(status: AuthStatus.signedOut);
  }

  Future<bool> _runAuthAction(
    Future<void> Function() action, {
    required String actionName,
  }) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await action();
      state = AuthState(
        status: AuthStatus.authenticated,
        userId: _repository.currentUser?.id,
      );
      return true;
    } on Object catch (error) {
      _logAuthFailure(actionName, error);
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _readableError(error, actionName: actionName),
      );
      return false;
    }
  }

  String _readableError(Object error, {required String actionName}) {
    if (error is AuthConfigurationException) {
      return error.toString();
    }
    if (error is AuthException) {
      return actionName == 'signUp'
          ? '注册失败：${error.message}'
          : '登录失败：${error.message}';
    }
    return actionName == 'signUp'
        ? '注册失败，请检查邮箱、密码和网络后重试。'
        : '登录失败，请检查账号、密码和网络后重试。';
  }

  void _logAuthFailure(String actionName, Object error) {
    if (error is AuthException) {
      debugPrint(
        '[Auth][$actionName] Supabase AuthException '
        'type=${error.runtimeType}, statusCode=${error.statusCode}, '
        'code=${error.code}, message=${error.message}',
      );
      return;
    }
    debugPrint('[Auth][$actionName] ${error.runtimeType}: $error');
  }
}
