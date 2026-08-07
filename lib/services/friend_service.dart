import '../models/friend.dart';
import 'api_client.dart';
import 'local_cache.dart';

class FriendService {
  final _api = ApiClient.instance;
  final _cache = LocalCache.instance;

  List<Friend>? listCached() => _cache.getFriends();

  Future<List<Friend>> list() async {
    final r = await _api.dio.get('/friends');
    final items = (r.data as List).map((j) => Friend.fromJson(j)).toList();
    await _cache.setFriends(items);
    return items;
  }

  Future<void> add(String friendCode) => _api.dio.post('/friends/add', data: {'friend_code': friendCode});

  Future<CompiledMood> mood(int friendId) async {
    final r = await _api.dio.get('/friends/$friendId/mood');
    return CompiledMood.fromJson(r.data as Map<String, dynamic>);
  }

  Future<List<CallHistoryEntry>> callHistory(int friendId) async {
    final r = await _api.dio.get('/friends/$friendId/calls');
    return (r.data as List).map((j) => CallHistoryEntry.fromJson(j)).toList();
  }

  /// Empty string clears the nickname back to just showing their username.
  Future<String?> setNickname(int friendId, String nickname) async {
    final r = await _api.dio.post('/friends/$friendId/nickname', data: {'nickname': nickname});
    return r.data['nickname'] as String?;
  }

  Future<void> remove(int friendId) => _api.dio.delete('/friends/$friendId');
}
