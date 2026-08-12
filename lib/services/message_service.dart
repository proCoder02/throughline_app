import '../models/direct_message.dart';
import 'api_client.dart';
import 'local_cache.dart';

class MessageService {
  final _api = ApiClient.instance;
  final _cache = LocalCache.instance;

  List<DirectMessage>? historyCached(int friendId) => _cache.getDirectMessages(friendId);

  /// No beforeId -- most recent page (what a freshly opened thread wants).
  /// Passing beforeId loads older messages for scroll-up pagination; those
  /// are NOT written into the cache, which only ever holds the most recent
  /// page (same "cache is a fast-first-paint layer, not full history"
  /// scope as every other LocalCache list in this app).
  Future<List<DirectMessage>> history(int friendId, {int? beforeId}) async {
    final r = await _api.dio.get('/friends/$friendId/messages', queryParameters: {
      if (beforeId != null) 'before_id': beforeId,
    });
    final items = (r.data as List).map((j) => DirectMessage.fromJson(j)).toList();
    if (beforeId == null) await _cache.setDirectMessages(friendId, items);
    return items;
  }

  Future<DirectMessage> send(int friendId, String content) async {
    final r = await _api.dio.post('/friends/$friendId/messages', data: {'content': content});
    final message = DirectMessage.fromJson(r.data as Map<String, dynamic>);
    await _cache.appendDirectMessages(friendId, [message]);
    return message;
  }

  // Delivery/read acks are NOT REST calls -- see NotifyProvider.ackDelivered/
  // ackRead, which send them over the same persistent /ws/notify connection
  // (WhatsApp-style: no per-tick HTTP round trip).

  /// friendId -> unread count, for the Friends-list badge.
  Future<Map<int, int>> unreadCounts() async {
    final r = await _api.dio.get('/friends/unread_message_counts');
    return (r.data as Map<String, dynamic>).map((k, v) => MapEntry(int.parse(k), v as int));
  }
}
