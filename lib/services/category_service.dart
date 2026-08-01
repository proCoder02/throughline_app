import 'package:dio/dio.dart';

import '../models/category.dart';
import 'api_client.dart';

class CategoryService {
  final _api = ApiClient.instance;

  Future<Categories> list() async {
    final r = await _api.dio.get('/categories');
    return Categories.fromJson(r.data);
  }

  Future<void> add(String name) {
    return _api.dio.post('/categories', data: {'name': name});
  }

  Future<void> remove(String name) {
    return _api.dio.delete('/categories/${Uri.encodeComponent(name)}');
  }

  static String errorMessage(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) return data['error'].toString();
    }
    return 'Something went wrong';
  }
}
