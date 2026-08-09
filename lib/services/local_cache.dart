import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/category.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/friend.dart';
import '../models/profile.dart';
import '../models/task.dart';

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

  /// Whether persona onboarding has been completed -- lets PersonaGate skip
  /// its own network round-trip on every single app open and go straight to
  /// the home screen, re-verifying in the background instead of blocking on
  /// it. Cleared on logout along with everything else in this box, so a
  /// second account on the same device always gets a fresh check.
  bool? getPersonaCompleted() {
    final raw = _box.get('persona_completed');
    return raw == null ? null : raw == 'true';
  }

  Future<void> setPersonaCompleted(bool completed) {
    return _box.put('persona_completed', completed.toString());
  }

  /// Device-local light/dark/system preference (ThemeMode.name, e.g.
  /// "system"/"light"/"dark") -- a display setting, not account data, so it
  /// lives here rather than on the server. Reset to the default (system) on
  /// logout along with everything else in this box -- an acceptable,
  /// unsurprising fallback rather than something worth preserving specially.
  String? getThemeMode() => _box.get('theme_mode');

  Future<void> setThemeMode(String mode) => _box.put('theme_mode', mode);

  /// Keyed by status ("open"/"done"/"all") -- TasksScreen's filter switches
  /// between them, and each is its own independent last-known snapshot.
  List<Task>? getTasks(String status) {
    final raw = _box.get('tasks:$status');
    if (raw == null) return null;
    return (jsonDecode(raw) as List).map((j) => Task.fromJson(j)).toList();
  }

  Future<void> setTasks(String status, List<Task> tasks) {
    return _box.put('tasks:$status', jsonEncode(tasks.map((t) => t.toJson()).toList()));
  }

  Map<String, Profile>? getProfiles() {
    final raw = _box.get('profiles');
    if (raw == null) return null;
    return Profile.mapFromJson(jsonDecode(raw));
  }

  Future<void> setProfiles(Map<String, Profile> profiles) {
    return _box.put('profiles', jsonEncode(Profile.mapToJson(profiles)));
  }

  List<Friend>? getFriends() {
    final raw = _box.get('friends');
    if (raw == null) return null;
    return (jsonDecode(raw) as List).map((j) => Friend.fromJson(j)).toList();
  }

  Future<void> setFriends(List<Friend> friends) {
    return _box.put('friends', jsonEncode(friends.map((f) => f.toJson()).toList()));
  }

  Map<String, dynamic>? getSettings() {
    final raw = _box.get('settings');
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw));
  }

  Future<void> setSettings(Map<String, dynamic> settings) {
    return _box.put('settings', jsonEncode(settings));
  }

  Map<String, dynamic>? getNudgeSettings() {
    final raw = _box.get('nudge_settings');
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw));
  }

  Future<void> setNudgeSettings(Map<String, dynamic> settings) {
    return _box.put('nudge_settings', jsonEncode(settings));
  }

  Categories? getCategories() {
    final raw = _box.get('categories');
    if (raw == null) return null;
    return Categories.fromJson(jsonDecode(raw));
  }

  Future<void> setCategories(Categories categories) {
    return _box.put('categories', jsonEncode(categories.toJson()));
  }

  /// Wipes every cached chat/conversation -- called on logout so a second
  /// account signing in on the same device never sees the previous
  /// account's cached chats.
  Future<void> clear() => _box.clear();
}
