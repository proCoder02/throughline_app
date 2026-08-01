import '../models/profile.dart';
import 'api_client.dart';

class ProfileService {
  final _api = ApiClient.instance;

  Future<Map<String, Profile>> list() async {
    final r = await _api.dio.get('/profiles');
    return Profile.mapFromJson(Map<String, dynamic>.from(r.data));
  }
}
