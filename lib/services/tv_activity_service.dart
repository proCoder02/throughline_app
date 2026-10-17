import '../models/tv_activity.dart';
import 'api_client.dart';

class TvActivityService {
  final _api = ApiClient.instance;

  Future<List<TvActivitySession>> sessions() async {
    final r = await _api.dio.get('/tv/activity');
    return (r.data as List).map((j) => TvActivitySession.fromJson(j)).toList();
  }

  Future<List<TvActivityCorrelation>> correlate({int windowMinutes = 15}) async {
    final r = await _api.dio.get(
      '/tv/activity/correlate',
      queryParameters: {'window_minutes': windowMinutes},
    );
    return (r.data as List).map((j) => TvActivityCorrelation.fromJson(j)).toList();
  }
}
