import '../models/friend.dart';
import 'api_client.dart';

class FriendService {
  final _api = ApiClient.instance;

  Future<List<Friend>> list() async {
    final r = await _api.dio.get('/friends');
    return (r.data as List).map((j) => Friend.fromJson(j)).toList();
  }

  Future<void> add(String friendCode) => _api.dio.post('/friends/add', data: {'friend_code': friendCode});

  Future<CompiledMood> mood(int friendId) async {
    final r = await _api.dio.get('/friends/$friendId/mood');
    return CompiledMood.fromJson(r.data as Map<String, dynamic>);
  }
}
