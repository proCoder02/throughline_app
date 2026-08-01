import 'dart:io';

import 'package:dio/dio.dart';

import '../models/chat_message.dart';
import '../models/conversation.dart';
import 'api_client.dart';

class ConversationService {
  final _api = ApiClient.instance;

  Future<List<Conversation>> list() async {
    final r = await _api.dio.get('/conversations');
    return (r.data as List).map((j) => Conversation.fromJson(j)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<Conversation> get(int id) async {
    final r = await _api.dio.get('/conversations/$id');
    return Conversation.fromJson(r.data);
  }

  Future<List<ChatMessage>> chat(int id) async {
    final r = await _api.dio.get('/conversations/$id/chat');
    return (r.data as List).map((j) => ChatMessage.fromJson(j)).toList();
  }

  Future<String> sendChat({required String prompt, required int conversationId}) async {
    final r = await _api.dio.post('/chat', data: {
      'prompt': prompt,
      'conversation_id': conversationId,
    });
    return r.data['reply'];
  }

  Future<void> delete(int id) => _api.dio.delete('/conversations/$id');

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
}
