import 'api_client.dart';
import 'local_cache.dart';

class SettingsService {
  final _api = ApiClient.instance;
  final _cache = LocalCache.instance;

  Map<String, dynamic>? getCached() => _cache.getSettings();

  Future<Map<String, dynamic>> get() async {
    final r = await _api.dio.get('/settings');
    final settings = Map<String, dynamic>.from(r.data);
    await _cache.setSettings(settings);
    return settings;
  }

  Future<void> update(String personalization) {
    return _api.dio.post('/settings', data: {'personalization': personalization});
  }
}
