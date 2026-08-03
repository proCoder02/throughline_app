import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/local_cache.dart';
import '../services/push_service.dart';

class AuthProvider extends ChangeNotifier {
  final _authService = AuthService();

  bool isLoading = true;
  bool isAuthenticated = false;
  String? username;
  int? userId;

  /// Optimistic: a stored token is trusted immediately (no blocking network
  /// call), so the app's first frame never waits on a round-trip -- if it
  /// turns out to actually be invalid, the very next real API call's 401
  /// routes back to the auth screen via ApiClient.onUnauthorized/forceLogout
  /// anyway, same as any mid-session expiry. This also fixes a real bug the
  /// old blocking version had: fetchMe() returning null (which happens both
  /// for an invalid token AND for "device is offline right now") used to
  /// force a logout in both cases -- being offline at launch should never
  /// sign you out.
  Future<void> bootstrap() async {
    final token = await ApiClient.instance.readToken();
    if (token == null) {
      isLoading = false;
      notifyListeners();
      return;
    }
    isAuthenticated = true;
    isLoading = false;
    notifyListeners();

    // Refresh username/userId in the background -- best-effort, since the
    // gate decision above has already been made.
    final me = await _authService.fetchMe();
    if (me != null) {
      username = me['username'];
      userId = me['id'];
      notifyListeners();
    }
  }

  Future<String?> login(String user, String password) async {
    try {
      final r = await _authService.login(username: user, password: password);
      isAuthenticated = true;
      username = r['username'];
      userId = r['id'];
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return _errorMessage(e);
    }
  }

  Future<String?> register({
    required String user,
    required String email,
    required String password,
    required String personalization,
  }) async {
    try {
      final r = await _authService.register(
        username: user,
        email: email,
        password: password,
        personalization: personalization,
      );
      isAuthenticated = true;
      username = r['username'];
      userId = r['id'];
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return _errorMessage(e);
    }
  }

  Future<void> logout() async {
    await PushService.instance.unregisterDevice();
    await _authService.logout();
    isAuthenticated = false;
    username = null;
    userId = null;
    await LocalCache.instance.clear();
    notifyListeners();
  }

  /// Called when ApiClient sees a 401 from any request.
  void forceLogout() {
    isAuthenticated = false;
    username = null;
    userId = null;
    LocalCache.instance.clear();
    notifyListeners();
  }

  String _errorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    return e.message ?? 'Something went wrong';
  }
}
