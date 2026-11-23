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
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      userId: userId,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// Reactive identity for account-scoped repositories and diagnostics. The
/// SupabaseClient itself is stable when its session changes.
final authenticatedUserIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authControllerProvider);
  return auth.status == AuthStatus.authenticated ? auth.userId : null;
});

class AuthController extends Notifier<AuthState> {
  late AuthRepository _repository;
  var _generation = 0;

  @override
  AuthState build() {
    _generation++;
    _repository = ref.watch(authRepositoryProvider);
    final subscription = _repository.userChanges.listen(
      _onUserChanged,
      onError: (Object error) => _logAuthFailure('session', error),
    );
    ref.onDispose(subscription.cancel);
    final user = _repository.currentUser;
    return AuthState(
      status: user == null ? AuthStatus.signedOut : AuthStatus.authenticated,
      userId: user?.id,
    );
  }

  Future<bool> signIn(String email, String password) async {
    return _runAuthAction(
      () => _repository.signIn(email: email, password: password),
      actionName: 'signIn',
    );
  }

  Future<bool> signUp(String email, String password) async {
    if (state.isSubmitting) return false;
    final generation = _generation;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final hasSession = await _repository.signUp(
        email: email,
        password: password,
      );
      if (!_isCurrent(generation)) return false;
      final user = _repository.currentUser;
      if (hasSession && user != null) {
        state = AuthState(status: AuthStatus.authenticated, userId: user.id);
      } else {
        state = const AuthState(
          status: AuthStatus.signedOut,
          errorMessage: '注册成功，请前往邮箱完成验证后登录。',
        );
      }
      return true;
    } on Object catch (error) {
      if (!_isCurrent(generation)) return false;
      _logAuthFailure('signUp', error);
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _readableError(error, actionName: 'signUp'),
      );
      return false;
    }
  }

  void continueOffline() {
    if (state.isSubmitting) return;
    state = const AuthState(status: AuthStatus.offline);
  }

  Future<void> signOut() async {
    if (state.isSubmitting) return;
    final generation = _generation;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await _repository.signOut();
      if (_isCurrent(generation)) {
        state = const AuthState(status: AuthStatus.signedOut);
      }
    } on Object catch (error) {
      if (!_isCurrent(generation)) return;
      _logAuthFailure('signOut', error);
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: '退出登录失败，请检查网络后重试。',
      );
    }
  }

  Future<bool> _runAuthAction(
    Future<void> Function() action, {
    required String actionName,
  }) async {
    if (state.isSubmitting) return false;
    final generation = _generation;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await action();
      if (!_isCurrent(generation)) return false;
      final user = _repository.currentUser;
      state = AuthState(
        status: user == null ? AuthStatus.signedOut : AuthStatus.authenticated,
        userId: user?.id,
      );
      return user != null;
    } on Object catch (error) {
      if (!_isCurrent(generation)) return false;
      _logAuthFailure(actionName, error);
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _readableError(error, actionName: actionName),
      );
      return false;
    }
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

  void _onUserChanged(User? user) {
    if (!ref.mounted || state.status == AuthStatus.offline) return;
    final status = user == null
        ? AuthStatus.signedOut
        : AuthStatus.authenticated;
    if (state.userId == user?.id && state.status == status) return;
    state = AuthState(
      status: status,
      userId: user?.id,
      isSubmitting: state.isSubmitting,
    );
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
        'code=${error.code}',
      );
      return;
    }
    debugPrint('[Auth][$actionName] ${error.runtimeType}');
  }
}
