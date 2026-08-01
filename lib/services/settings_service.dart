import 'api_client.dart';

class SettingsService {
  final _api = ApiClient.instance;

  Future<Map<String, dynamic>> get() async {
    final r = await _api.dio.get('/settings');
    return r.data;
  }

  Future<void> update(String personalization) {
    return _api.dio.post('/settings', data: {'personalization': personalization});
  }
}
