import '../models/weekly_digest.dart';
import 'api_client.dart';

class DigestService {
  final _api = ApiClient.instance;

  /// Null if no digest exists yet (brand-new account, or no EI data yet) --
  /// not an error, same shape the backend itself returns. No cache-first
  /// path here (unlike TaskService/FriendService) -- this is inherently
  /// fresh, one-shot content the user reads once per week, not a list
  /// that's repeatedly browsed offline.
  Future<WeeklyDigest?> fetch() async {
    final r = await _api.dio.get('/insights/digest');
    final digest = r.data['digest'];
    return digest == null ? null : WeeklyDigest.fromJson(digest as Map<String, dynamic>);
  }
}
