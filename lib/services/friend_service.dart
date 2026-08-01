import '../models/friend.dart';
import 'api_client.dart';

class FriendService {
  final _api = ApiClient.instance;

  Future<List<Friend>> list() async {
    final r = await _api.dio.get('/friends');
    return (r.data as List).map((j) => Friend.fromJson(j)).toList();
  }

  Future<void> add(String friendCode) => _api.dio.post('/friends/add', data: {'friend_code': friendCode});

  Future<List<MoodEntry>> mood(int friendId) async {
    final r = await _api.dio.get('/friends/$friendId/mood');
    return (r.data['entries'] as List).map((j) => MoodEntry.fromJson(j)).toList();
  }
}
