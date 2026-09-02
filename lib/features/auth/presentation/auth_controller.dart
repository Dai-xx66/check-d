import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../data/auth_repository.dart';

enum AuthStatus { initializing, signedOut, authenticated, offline }

class AuthState {
  const AuthState({
    required this.status,
    this.isSubmitting = false,
    this.errorMessage,
  });

  final AuthStatus status;
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

class AuthController extends Notifier<AuthState> {
  late final AuthRepository _repository;

  @override
  AuthState build() {
    _repository = ref.watch(authRepositoryProvider);
    final user = _repository.currentUser;
    return AuthState(
      status: user == null ? AuthStatus.signedOut : AuthStatus.authenticated,
    );
  }

  Future<bool> signIn(String email, String password) async {
    return _runAuthAction(
      () => _repository.signIn(email: email, password: password),
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
        state = const AuthState(status: AuthStatus.authenticated);
      } else {
        state = const AuthState(
          status: AuthStatus.signedOut,
          errorMessage: '注册成功，请前往邮箱完成验证后登录。',
        );
      }
      return true;
    } on Object catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _readableError(error),
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

  Future<bool> _runAuthAction(Future<void> Function() action) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await action();
      state = const AuthState(status: AuthStatus.authenticated);
      return true;
    } on Object catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _readableError(error),
      );
      return false;
    }
  }

  String _readableError(Object error) {
    if (error is AuthConfigurationException) {
      return error.toString();
    }
    return '登录失败，请检查账号、密码和网络后重试。';
  }
}
