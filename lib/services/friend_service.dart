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

  Future<CognitiveSharingStatus> getCognitiveSharing(int friendId) async {
    final r = await _api.dio.get('/friends/$friendId/cognitive-sharing');
    return CognitiveSharingStatus.fromJson(r.data as Map<String, dynamic>);
  }

  /// [level] must be 'off' | 'limited' | 'collaborative'.
  Future<CognitiveSharingStatus> setCognitiveSharing(int friendId, String level) async {
    await _api.dio.post('/friends/$friendId/cognitive-sharing', data: {'level': level});
    // Re-fetch rather than trust the POST response alone -- bothEnabled
    // depends on the OTHER side's row too, which that response can't know.
    return getCognitiveSharing(friendId);
  }

  /// On-demand "find common ground" request -- null means either the
  /// bilateral gate isn't satisfied (caller should check
  /// getCognitiveSharing().bothEnabled first to avoid this) or the model
  /// genuinely found nothing worth suggesting, which is the common case.
  Future<CognitiveSuggestion?> requestCognitiveSuggestion(int friendId) async {
    final r = await _api.dio.post('/friends/$friendId/cognitive-suggestion');
    final data = r.data['suggestion'];
    return data == null ? null : CognitiveSuggestion.fromJson(data as Map<String, dynamic>);
  }

  /// Latest not-yet-dismissed-by-me suggestion for this pair, if any --
  /// used on screen load and after a push notification tells the OTHER
  /// side a suggestion exists (the push payload only carries an id).
  Future<CognitiveSuggestion?> getLatestCognitiveSuggestion(int friendId) async {
    final r = await _api.dio.get('/friends/$friendId/cognitive-suggestion');
    final data = r.data['suggestion'];
    return data == null ? null : CognitiveSuggestion.fromJson(data as Map<String, dynamic>);
  }

  Future<void> dismissCognitiveSuggestion(int friendId, int suggestionId) =>
      _api.dio.post('/friends/$friendId/cognitive-suggestion/$suggestionId/dismiss');
}
