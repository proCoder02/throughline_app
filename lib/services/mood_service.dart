import '../models/mood_day.dart';
import 'api_client.dart';

class MoodService {
  final _api = ApiClient.instance;

  Future<MoodHistory> history({int days = 30}) async {
    final r = await _api.dio.get('/mood/history', queryParameters: {'days': days});
    return MoodHistory.fromJson(r.data);
  }
}
