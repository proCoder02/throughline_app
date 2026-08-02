import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/chat_message.dart';
import '../models/conversation.dart';

/// On-device mirror of the chat data the backend serves -- lets the chat
/// screens render instantly from disk before the network round-trip
/// completes, the same "local cache first" step the Redis-backed backend
/// cache plays server-side. Values are stored as plain JSON strings (not
/// typed Hive objects) so no generated TypeAdapter/build_runner step is
/// needed.
class LocalCache {
  LocalCache._();
  static final LocalCache instance = LocalCache._();

  static const _boxName = 'chat_cache';
  late Box<String> _box;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  List<Conversation>? getConversations() {
    final raw = _box.get('conversations');
    if (raw == null) return null;
    return (jsonDecode(raw) as List).map((j) => Conversation.fromJson(j)).toList();
  }

  Future<void> setConversations(List<Conversation> items) {
    return _box.put('conversations', jsonEncode(items.map((c) => c.toJson()).toList()));
  }

  Conversation? getConversation(int id) {
    final raw = _box.get('conversation:$id');
    if (raw == null) return null;
    return Conversation.fromJson(jsonDecode(raw));
  }

  Future<void> setConversation(Conversation c) {
    return _box.put('conversation:${c.id}', jsonEncode(c.toJson()));
  }

  List<ChatMessage>? getMessages(int conversationId) {
    final raw = _box.get('messages:$conversationId');
    if (raw == null) return null;
    return (jsonDecode(raw) as List).map((j) => ChatMessage.fromJson(j)).toList();
  }

  Future<void> setMessages(int conversationId, List<ChatMessage> messages) {
    return _box.put('messages:$conversationId', jsonEncode(messages.map((m) => m.toJson()).toList()));
  }

  /// Only appends if this conversation's messages are already cached --
  /// otherwise there's nothing established to append to, and the next full
  /// fetch will populate it from scratch anyway.
  Future<void> appendMessages(int conversationId, List<ChatMessage> newMessages) async {
    final existing = getMessages(conversationId);
    if (existing == null) return;
    await setMessages(conversationId, [...existing, ...newMessages]);
  }

  List<ChatMessage>? getGlobalChat() {
    final raw = _box.get('global_chat');
    if (raw == null) return null;
    return (jsonDecode(raw) as List).map((j) => ChatMessage.fromJson(j)).toList();
  }

  Future<void> setGlobalChat(List<ChatMessage> messages) {
    return _box.put('global_chat', jsonEncode(messages.map((m) => m.toJson()).toList()));
  }

  Future<void> appendGlobalMessages(List<ChatMessage> newMessages) async {
    final existing = getGlobalChat();
    if (existing == null) return;
    await setGlobalChat([...existing, ...newMessages]);
  }

  Future<void> removeConversation(int id) async {
    await _box.delete('conversation:$id');
    await _box.delete('messages:$id');
    final list = getConversations();
    if (list != null) {
      await setConversations(list.where((c) => c.id != id).toList());
    }
  }

  /// Wipes every cached chat/conversation -- called on logout so a second
  /// account signing in on the same device never sees the previous
  /// account's cached chats.
  Future<void> clear() => _box.clear();
}
