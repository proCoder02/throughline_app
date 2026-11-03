import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import 'push_service.dart';

/// Thin Dio wrapper: attaches the bearer token to every request and clears it
/// (routing back to the auth screen) on any 401.
class ApiClient {
  ApiClient._() {
    _dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await readToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            await clearToken();
            onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  static final ApiClient instance = ApiClient._();

  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  /// Set by main.dart to force the app back to the auth screen.
  VoidCallback? onUnauthorized;

  Dio get dio => _dio;

  Future<void> saveToken(String token) async {
    await _storage.write(key: 'token', value: token);
    await cacheTokenForNative(token, ApiConfig.baseUrl);
  }

  /// A stored token Android can no longer decrypt (BadPaddingException after
  /// a backup restore or keystore reset -- seen on a Realme GT, Android 16)
  /// is treated as logged out: wipe it so the user just signs in again,
  /// instead of startup throwing and the app never leaving the splash.
  Future<String?> readToken() async {
    try {
      return await _storage.read(key: 'token');
    } catch (e) {
      debugPrint('readToken: stored token unreadable, resetting ($e)');
      try {
        await _storage.deleteAll();
      } catch (_) {}
      return null;
    }
  }

  Future<void> clearToken() async {
    await _storage.delete(key: 'token');
    await clearTokenForNative();
  }
}
