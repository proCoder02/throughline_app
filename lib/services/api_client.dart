import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';

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

  Future<void> saveToken(String token) => _storage.write(key: 'token', value: token);
  Future<String?> readToken() => _storage.read(key: 'token');
  Future<void> clearToken() => _storage.delete(key: 'token');
}
