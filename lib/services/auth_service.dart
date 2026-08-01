import 'api_client.dart';

class AuthService {
  final _api = ApiClient.instance;

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    String personalization = 'personal',
  }) async {
    final r = await _api.dio.post('/register', data: {
      'username': username,
      'email': email,
      'password': password,
      'personalization': personalization,
    });
    await _api.saveToken(r.data['token']);
    return r.data;
  }

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final r = await _api.dio.post('/login', data: {
      'username': username,
      'password': password,
    });
    await _api.saveToken(r.data['token']);
    return r.data;
  }

  Future<void> logout() async {
    try {
      await _api.dio.post('/logout');
    } catch (_) {
      // safe to ignore; discarding the local token is equivalent
    }
    await _api.clearToken();
  }

  /// Validates the stored token. Returns null if missing/invalid.
  Future<Map<String, dynamic>?> fetchMe() async {
    try {
      final r = await _api.dio.get('/me');
      return r.data;
    } catch (_) {
      return null;
    }
  }
}
