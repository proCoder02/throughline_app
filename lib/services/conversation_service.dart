import 'dart:io';

import 'package:dio/dio.dart';

import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/search_result.dart';
import 'api_client.dart';
import 'local_cache.dart';

class ConversationService {
  final _api = ApiClient.instance;
  final _cache = LocalCache.instance;

  /// Cache-only, synchronous reads -- screens call these first so they can
  /// render instantly from disk, before kicking off the network fetch below.
  List<Conversation>? listCached() => _cache.getConversations();
  Conversation? getCached(int id) => _cache.getConversation(id);
  List<ChatMessage>? chatCached(int id) => _cache.getMessages(id);
  List<ChatMessage>? globalChatCached() => _cache.getGlobalChat();

  Future<List<Conversation>> list() async {
    final r = await _api.dio.get('/conversations');
    final items = (r.data as List).map((j) => Conversation.fromJson(j)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _cache.setConversations(items);
    return items;
  }

  Future<Conversation> get(int id) async {
    final r = await _api.dio.get('/conversations/$id');
    final conversation = Conversation.fromJson(r.data);
    await _cache.setConversation(conversation);
    return conversation;
  }

  Future<List<ChatMessage>> chat(int id) async {
    final r = await _api.dio.get('/conversations/$id/chat');
    final messages = (r.data as List).map((j) => ChatMessage.fromJson(j)).toList();
    await _cache.setMessages(id, messages);
    return messages;
  }

  Future<String> sendChat({required String prompt, required int conversationId, String? transcript}) async {
    final r = await _api.dio.post('/chat', data: {
      'prompt': prompt,
      'conversation_id': conversationId,
      // Only set while a live session for this conversation is in
      // progress -- lets the LLM see lines not yet persisted to
      // raw_transcript (spec §6).
      if (transcript != null) 'transcript': transcript,
    });
    final reply = r.data['reply'] as String;
    final now = DateTime.now();
    await _cache.appendMessages(conversationId, [
      ChatMessage(role: 'user', content: prompt, createdAt: now),
      ChatMessage(role: 'assistant', content: reply, createdAt: now),
    ]);
    return reply;
  }

  Future<void> delete(int id) async {
    await _api.dio.delete('/conversations/$id');
    await _cache.removeConversation(id);
  }

  /// Path B (§8) upload flow: one-shot diarized transcript from a recorded file.
  Future<String> transcribe(File audioFile) async {
    final form = FormData.fromMap({
      'audio': await MultipartFile.fromFile(audioFile.path),
    });
    final r = await _api.dio.post('/transcribe', data: form);
    return r.data['transcript'];
  }

  Future<int> save({required String transcript, String? title}) async {
    final r = await _api.dio.post('/save', data: {
      'transcript': transcript,
      if (title != null) 'title': title,
    });
    return r.data['conversation_id'];
  }

  Future<void> analyze({required int conversationId}) {
    return _api.dio.post('/analyze', data: {'conversation_id': conversationId});
  }

  /// Persistent cross-session thread (§6) -- not scoped to any one conversation.
  Future<List<ChatMessage>> globalChat() async {
    final r = await _api.dio.get('/chat/global');
    final messages = (r.data as List).map((j) => ChatMessage.fromJson(j)).toList();
    await _cache.setGlobalChat(messages);
    return messages;
  }

  /// lat/lon are optional -- only attached when the global chat screen
  /// already has a fresh device location on hand (see its own
  /// _maybeGetLocation, which never blocks sending on a permission prompt
  /// or a slow GPS fix). The backend decides for itself whether the
  /// message actually needed location at all.
  ///
  /// Returns both the reply text and an optional Cognitive Commerce
  /// (Swiggy MCP) action_card -- present only when the backend actually
  /// found real, orderable results for this message.
  Future<(String reply, Map<String, dynamic>? actionCard)> sendGlobalChat(
    String prompt, {
    double? lat,
    double? lon,
  }) async {
    final r = await _api.dio.post('/chat/global', data: {
      'prompt': prompt,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
    });
    final reply = (r.data['reply'] as String?) ?? 'No response.';
    final actionCard = r.data['action_card'] as Map<String, dynamic>?;
    final now = DateTime.now();
    await _cache.appendGlobalMessages([
      ChatMessage(role: 'user', content: prompt, createdAt: now),
      ChatMessage(role: 'assistant', content: reply, createdAt: now, actionCard: actionCard),
    ]);
    return (reply, actionCard);
  }

  /// Companion to sendGlobalChat -- sends an image (e.g. a bill photo) with
  /// a required description into the global chat. The backend extracts the
  /// image's content via a vision model and stores it as a normal
  /// conversation, so it's retrievable in a later plain-text globalChat()
  /// question with no special handling needed on this side. The description
  /// is cached the same way the text-chat prompt is above (localImage is
  /// deliberately NOT persisted -- see ChatMessage's own doc comment).
  Future<String> sendGlobalImage(File imageFile, String description) async {
    final form = FormData.fromMap({
      'description': description,
      'image': await MultipartFile.fromFile(imageFile.path),
    });
    final r = await _api.dio.post('/chat/global/image', data: form);
    final reply = (r.data['reply'] as String?) ?? 'No response.';
    final now = DateTime.now();
    await _cache.appendGlobalMessages([
      ChatMessage(role: 'user', content: description, createdAt: now),
      ChatMessage(role: 'assistant', content: reply, createdAt: now),
    ]);
    return reply;
  }

  /// Full-text search over titles/transcripts/chat content (GET /search) --
  /// not cached locally, unlike everything above: results are query-specific
  /// and change as chats grow, so there's nothing durable worth persisting
  /// on-device the way a conversation's own messages are.
  Future<List<SearchResult>> search(String query) async {
    final r = await _api.dio.get('/search', queryParameters: {'q': query});
    return (r.data as List).map((j) => SearchResult.fromJson(j)).toList();
  }
}
