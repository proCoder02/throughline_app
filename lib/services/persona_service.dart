import 'api_client.dart';

class PersonaService {
  final _api = ApiClient.instance;

  Future<Map<String, dynamic>> get() async {
    final r = await _api.dio.get('/persona');
    return r.data;
  }

  Future<void> submit(Map<String, dynamic> persona) {
    return _api.dio.post('/persona', data: persona);
  }
}
