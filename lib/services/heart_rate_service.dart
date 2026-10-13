import '../models/heart_rate.dart';
import 'api_client.dart';

class HeartRateService {
  final _api = ApiClient.instance;

  Future<List<HeartRateSession>> sessions() async {
    final r = await _api.dio.get('/health/heart-rate');
    return (r.data as List).map((j) => HeartRateSession.fromJson(j)).toList();
  }

  Future<List<HeartRateCorrelation>> correlate({int windowMinutes = 15}) async {
    final r = await _api.dio.get(
      '/health/heart-rate/correlate',
      queryParameters: {'window_minutes': windowMinutes},
    );
    return (r.data as List).map((j) => HeartRateCorrelation.fromJson(j)).toList();
  }
}
