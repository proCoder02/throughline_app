import '../models/speaker.dart';
import 'api_client.dart';

class SpeakerService {
  final _api = ApiClient.instance;

  Future<List<Speaker>> list() async {
    final r = await _api.dio.get('/speakers');
    return (r.data as List).map((j) => Speaker.fromJson(j)).toList();
  }
}
