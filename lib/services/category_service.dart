import 'package:dio/dio.dart';

import '../models/category.dart';
import 'api_client.dart';
import 'local_cache.dart';

class CategoryService {
  final _api = ApiClient.instance;
  final _cache = LocalCache.instance;

  Categories? listCached() => _cache.getCategories();

  Future<Categories> list() async {
    final r = await _api.dio.get('/categories');
    final categories = Categories.fromJson(r.data);
    await _cache.setCategories(categories);
    return categories;
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
