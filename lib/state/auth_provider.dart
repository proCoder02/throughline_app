import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final _authService = AuthService();

  bool isLoading = true;
  bool isAuthenticated = false;
  String? username;
  int? userId;

  /// Validates any stored token on app launch.
  Future<void> bootstrap() async {
    final token = await ApiClient.instance.readToken();
    if (token == null) {
      isLoading = false;
      notifyListeners();
      return;
    }
    final me = await _authService.fetchMe();
    if (me != null) {
      isAuthenticated = true;
      username = me['username'];
      userId = me['id'];
    } else {
      await ApiClient.instance.clearToken();
    }
    isLoading = false;
    notifyListeners();
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
    await _authService.logout();
    isAuthenticated = false;
    username = null;
    userId = null;
    notifyListeners();
  }

  /// Called when ApiClient sees a 401 from any request.
  void forceLogout() {
    isAuthenticated = false;
    username = null;
    userId = null;
    notifyListeners();
  }

  String _errorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    return e.message ?? 'Something went wrong';
  }
}
