import 'dart:io';

import 'package:dio/dio.dart';

import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/search_result.dart';
import '../models/transaction.dart';
import '../models/vehicle_policy.dart';
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
  /// Returns both the reply text and the list of action cards the backend
  /// staged for this message -- zero, one, or several (e.g. a Cognitive
  /// Commerce (Swiggy MCP) card, and/or one per triggered tool action like
  /// log_expense/message_friend/send_email), present only when the
  /// backend actually has something for the user to review/confirm.
  Future<(String reply, List<Map<String, dynamic>> actionCards)> sendGlobalChat(
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
    final actionCards = ((r.data['action_cards'] as List?) ?? const [])
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final now = DateTime.now();
    await _cache.appendGlobalMessages([
      ChatMessage(role: 'user', content: prompt, createdAt: now),
      ChatMessage(role: 'assistant', content: reply, createdAt: now, actionCards: actionCards),
    ]);
    return (reply, actionCards);
  }

  /// Companion to sendGlobalChat -- sends an image (e.g. a bill photo) with
  /// a required description into the global chat. The backend extracts the
  /// image's content via a vision model and stores it as a normal
  /// conversation, so it's retrievable in a later plain-text globalChat()
  /// question with no special handling needed on this side. The description
  /// is cached the same way the text-chat prompt is above (localImage is
  /// deliberately NOT persisted -- see ChatMessage's own doc comment).
  ///
  /// Also returns a Transaction when the backend recognized the image as a
  /// UPI payment receipt, or a VehiclePolicy when it recognized a vehicle
  /// insurance policy document (at most one of the two is ever non-null)
  /// -- the caller shows a confirm card/sheet for it rather than saving it
  /// automatically, since a vision-model misread should never silently
  /// become real spending data or a real policy on file.
  Future<(String reply, int? conversationId, Transaction? transaction, VehiclePolicy? policy)> sendGlobalImage(
    File imageFile,
    String description,
  ) async {
    final form = FormData.fromMap({
      'description': description,
      'image': await MultipartFile.fromFile(imageFile.path),
    });
    final r = await _api.dio.post('/chat/global/image', data: form);
    final reply = (r.data['reply'] as String?) ?? 'No response.';
    final conversationId = r.data['conversation_id'] as int?;
    final transactionJson = r.data['transaction'] as Map<String, dynamic>?;
    final transaction = transactionJson != null ? Transaction.fromExtraction(transactionJson) : null;
    final policyJson = r.data['policy'] as Map<String, dynamic>?;
    final policy = policyJson != null ? VehiclePolicy.fromExtraction(policyJson) : null;
    final now = DateTime.now();
    await _cache.appendGlobalMessages([
      ChatMessage(role: 'user', content: description, createdAt: now),
      ChatMessage(role: 'assistant', content: reply, createdAt: now),
    ]);
    return (reply, conversationId, transaction, policy);
  }

  /// Confirm-card save step -- persists the (possibly user-edited)
  /// transaction fields a receipt share produced. See POST /transactions.
  /// Returns true when the backend recognized this as a duplicate of a
  /// transaction saved in the last 10 minutes (same amount + payee) and
  /// returned the existing row instead of inserting a new one -- lets the
  /// caller show a quick "already saved" instead of implying a second,
  /// separate transaction was recorded.
  Future<bool> saveTransaction(int? conversationId, Transaction transaction) async {
    final r = await _api.dio.post('/transactions', data: {
      if (conversationId != null) 'conversation_id': conversationId,
      'amount': transaction.amount,
      if (transaction.payee != null) 'payee': transaction.payee,
      if (transaction.category != null) 'category': transaction.category,
      if (transaction.paymentMethod != null) 'payment_method': transaction.paymentMethod,
      if (transaction.item != null) 'item': transaction.item,
    });
    return r.data['duplicate'] == true;
  }

  /// Confirm-sheet save step -- persists the (possibly user-edited) policy
  /// fields a policy-document share produced, including the claims email
  /// the sheet always asks for. See POST /vehicle-policies. Returns true
  /// when the backend recognized this as a renewal of a policy already on
  /// file (same vehicle registration or policy number) and replaced it in
  /// place, rather than adding a second row for the same vehicle.
  Future<bool> saveVehiclePolicy(VehiclePolicy policy) async {
    final r = await _api.dio.post('/vehicle-policies', data: {
      if (policy.label != null) 'label': policy.label,
      'insurer_name': policy.insurerName,
      'policy_number': policy.policyNumber,
      if (policy.vehicleRegistration != null) 'vehicle_registration': policy.vehicleRegistration,
      if (policy.insuredName != null) 'insured_name': policy.insuredName,
      if (policy.issueDate != null) 'issue_date': policy.issueDate,
      if (policy.expiryDate != null) 'expiry_date': policy.expiryDate,
      if (policy.sumInsured != null) 'sum_insured': policy.sumInsured,
      'claims_email': policy.claimsEmail,
      'coverage_type': policy.coverageType,
    });
    return r.data['replaced'] == true;
  }

  /// PDF counterpart to sendGlobalImage, same response shape -- extracts
  /// a receipt's transaction fields OR a vehicle insurance policy's
  /// fields (never both), plus a real natural-language overview, from a
  /// PDF's text (see POST /vehicle-policies/extract-pdf) rather than a
  /// photo, for documents that come as text-based PDFs rather than
  /// images. The backend decides which (if either) applies from the
  /// extracted text itself -- nothing here assumes a PDF is always a
  /// policy, same as sendGlobalImage never assumes a photo is always a
  /// receipt.
  Future<(String reply, int? conversationId, Transaction? transaction, VehiclePolicy? policy)> sendGlobalPdf(File pdfFile) async {
    final form = FormData.fromMap({
      'document': await MultipartFile.fromFile(pdfFile.path),
    });
    final r = await _api.dio.post('/vehicle-policies/extract-pdf', data: form);
    final reply = (r.data['reply'] as String?) ?? 'No response.';
    final conversationId = r.data['conversation_id'] as int?;
    final transactionJson = r.data['transaction'] as Map<String, dynamic>?;
    final transaction = transactionJson != null ? Transaction.fromExtraction(transactionJson) : null;
    final policyJson = r.data['policy'] as Map<String, dynamic>?;
    final policy = policyJson != null ? VehiclePolicy.fromExtraction(policyJson) : null;
    final now = DateTime.now();
    await _cache.appendGlobalMessages([
      ChatMessage(role: 'user', content: '[PDF document uploaded]', createdAt: now),
      ChatMessage(role: 'assistant', content: reply, createdAt: now),
    ]);
    return (reply, conversationId, transaction, policy);
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
