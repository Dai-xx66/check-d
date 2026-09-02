import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  const AuthRepository(this._client);

  final SupabaseClient? _client;

  bool get isCloudConfigured => _client != null;

  User? get currentUser => _client?.auth.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    final client = _requireClient();
    await client.auth.signInWithPassword(email: email, password: password);
  }

  Future<bool> signUp({required String email, required String password}) async {
    final client = _requireClient();
    final response = await client.auth.signUp(email: email, password: password);
    return response.session != null;
  }

  Future<void> signOut() async {
    await _client?.auth.signOut();
  }

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw const AuthConfigurationException();
    }
    return client;
  }
}

class AuthConfigurationException implements Exception {
  const AuthConfigurationException();

  @override
  String toString() => '尚未配置云端服务，请先使用离线体验模式。';
}
