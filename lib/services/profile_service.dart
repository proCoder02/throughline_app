import '../models/profile.dart';
import 'api_client.dart';
import 'local_cache.dart';

class ProfileService {
  final _api = ApiClient.instance;
  final _cache = LocalCache.instance;

  Map<String, Profile>? listCached() => _cache.getProfiles();

  Future<Map<String, Profile>> list() async {
    final r = await _api.dio.get('/profiles');
    final profiles = Profile.mapFromJson(Map<String, dynamic>.from(r.data));
    await _cache.setProfiles(profiles);
    return profiles;
  }

  Future<void> rename(int profileId, String name) =>
      _api.dio.post('/profiles/$profileId/rename', data: {'name': name});

  Future<void> delete(int profileId) => _api.dio.delete('/profiles/$profileId');
}
