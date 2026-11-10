import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../services/api_client.dart';

/// Everything the phone's Work section asks the server for. Employee-level
/// only, by design: setting up the organisation, teams, people, invitations
/// and projects happens on the website, so none of those calls exist here.
/// The server still enforces who may see and change what (role access), so
/// the app shows exactly what the website shows the same person.
///
/// Responses are plain JSON maps (same field names as the web app uses) and
/// read-heavy ones are mirrored to an on-device box, so every screen paints
/// its last-known data instantly and refreshes over the network after.
class WorkApi {
  WorkApi._();
  static final WorkApi instance = WorkApi._();

  final Dio _dio = ApiClient.instance.dio;
  Box<String>? _box;

  Future<Box<String>> _cache() async => _box ??= await Hive.openBox<String>('work_cache');

  /// Last saved copy of a GET, or null. Cheap: the box is opened once.
  Future<dynamic> cached(String key) async {
    final raw = (await _cache()).get(key);
    return raw == null ? null : jsonDecode(raw);
  }

  Future<dynamic> _get(String path, {Map<String, dynamic>? query, String? cacheKey}) async {
    final r = await _dio.get(path, queryParameters: query);
    if (cacheKey != null) await (await _cache()).put(cacheKey, jsonEncode(r.data));
    return r.data;
  }

  Future<dynamic> _post(String path, [Map<String, dynamic>? data]) async => (await _dio.post(path, data: data ?? {})).data;

  String _o(int org) => '/corp/orgs/$org';

  // ---- outbox: changes made with no connection ----
  // A change made offline (confirm, done, an update, a message…) is kept on
  // the phone in order and sent when the connection is back. A change the
  // server refuses (e.g. someone else already closed it) is dropped and
  // reported, never retried forever.

  /// How many changes are waiting to be sent.
  final pending = ValueNotifier<int>(0);

  /// "<what> wasn't saved: <server reason>" for changes the server refused.
  final refused = StreamController<String>.broadcast();

  bool _flushing = false;

  Future<List> _outbox() async {
    final raw = (await _cache()).get('outbox');
    return raw == null ? [] : jsonDecode(raw) as List;
  }

  Future<void> _saveOutbox(List items) async {
    await (await _cache()).put('outbox', jsonEncode(items));
    pending.value = items.length;
  }

  /// Sends now if possible. With no connection, keeps it and returns false.
  /// A server refusal is thrown as usual (nothing is kept).
  Future<bool> sendOrKeep(String path, Map<String, dynamic> data, String label) async {
    try {
      await _dio.post(path, data: data);
      return true;
    } on DioException catch (e) {
      if (e.response != null) rethrow;
      final items = await _outbox();
      items.add({'path': path, 'data': data, 'label': label, 'at': DateTime.now().toIso8601String()});
      await _saveOutbox(items);
      return false;
    }
  }

  /// Waiting messages for one conversation, to show as "sending".
  Future<List<Map>> keptFor(String path) async => (await _outbox()).cast<Map>().where((i) => i['path'] == path).toList();

  /// Sends whatever is waiting, oldest first; stops at the first connection
  /// failure. Returns how many were sent.
  Future<int> flush() async {
    if (_flushing) return 0;
    _flushing = true;
    var sent = 0;
    try {
      final items = await _outbox();
      pending.value = items.length;
      while (items.isNotEmpty) {
        final item = items.first as Map;
        try {
          await _dio.post(item['path'] as String, data: item['data']);
          sent++;
        } on DioException catch (e) {
          if (e.response == null) break; // still offline: keep the rest
          refused.add("${item['label']} wasn't saved: ${workError(e)}");
        }
        items.removeAt(0);
        await _saveOutbox(items);
      }
    } catch (_) {
      // leave what's left for next time
    } finally {
      _flushing = false;
    }
    return sent;
  }

  /// Small local settings (e.g. which organisation was last open).
  Future<void> remember(String key, Object value) async => (await _cache()).put(key, jsonEncode(value));

  /// Clears this person's cached work data (sign out / switching accounts).
  Future<void> clear() async {
    await (await _cache()).clear();
    pending.value = 0;
  }

  // Changes that can be made offline (kept and sent later).
  String messagesPath(int org, int thread) => '${_o(org)}/threads/$thread/messages';
  Future<bool> sendMessage(int org, int thread, String body) => sendOrKeep(messagesPath(org, thread), {'body': body}, 'Message');
  Future<bool> act(int org, int id, String action, [Map<String, dynamic>? data]) => sendOrKeep(
        '${_o(org)}/commitments/$id/$action',
        data ?? {},
        switch (action) {
          'confirm' => 'Confirming',
          'done' => 'Marking done',
          'reopen' => 'Reopening',
          'drop' => 'Dropping',
          _ => 'A change'
        },
      );
  Future<bool> update(int org, int id, String kind, String text) =>
      sendOrKeep('${_o(org)}/commitments/$id/updates', {'kind': kind, 'text': text}, kind == 'blocker' ? 'A blocker' : 'An update');

  // ---- organisations I belong to, and invitations waiting for me ----
  Future<Map> me() async => await _get('/corp/me', cacheKey: 'me') as Map;
  Future<Map> org(int org) async => await _get(_o(org), cacheKey: 'org:$org') as Map;
  Future<Map> myInvites() async => await _get('/corp/invites/mine') as Map;
  Future<Map> acceptInvite(int id) async => await _post('/corp/invites/mine/$id/accept') as Map;
  Future<Map> unread() async => await _get('/corp/unread') as Map;

  // ---- home ----
  Future<Map> brief(int org) async => await _get('${_o(org)}/brief', cacheKey: 'brief:$org') as Map;
  Future<Map> catchUp(int org, {int days = 7}) async => await _post('${_o(org)}/catch-up', {'days': days}) as Map;
  Future<Map> incomingRequests(int org) async => await _get('${_o(org)}/requests/incoming', cacheKey: 'requests:$org') as Map;
  Future<void> acceptRequest(int org, int id, {String? dueDate}) =>
      _post('${_o(org)}/requests/$id/accept', {if (dueDate != null) 'due_date': dueDate});
  Future<void> declineRequest(int org, int id, String reason) => _post('${_o(org)}/requests/$id/decline', {'reason': reason});

  // ---- messages ----
  Future<Map> threads(int org) async => await _get('${_o(org)}/threads', cacheKey: 'threads:$org') as Map;
  Future<Map> messages(int org, int thread, {int after = 0}) async => await _get(
        '${_o(org)}/threads/$thread/messages',
        query: {'after': after},
        cacheKey: after == 0 ? 'messages:$org:$thread' : null,
      ) as Map;
  Future<void> send(int org, int thread, String body) => _post('${_o(org)}/threads/$thread/messages', {'body': body});
  Future<void> markRead(int org, int thread, int upto) => _post('${_o(org)}/threads/$thread/read', {'upto': upto});
  Future<Map> members(int org) async => await _get('${_o(org)}/members', cacheKey: 'members:$org') as Map;
  Future<int> directThread(int org, int userId) async =>
      ((await _post('${_o(org)}/threads/direct', {'user_id': userId})) as Map)['thread_id'] as int;

  // ---- commitments ----
  Future<Map> commitments(int org, String scope) async =>
      await _get('${_o(org)}/commitments', query: {'scope': scope}, cacheKey: 'commitments:$org:$scope') as Map;
  Future<Map> commitment(int org, int id) async => await _get('${_o(org)}/commitments/$id') as Map;
  Future<Map> commitmentAction(int org, int id, String action, [Map<String, dynamic>? data]) async =>
      await _post('${_o(org)}/commitments/$id/$action', data) as Map;
  Future<Map> activity(int org, int id) async => await _get('${_o(org)}/commitments/$id/updates') as Map;
  Future<void> postUpdate(int org, int id, String kind, String text) =>
      _post('${_o(org)}/commitments/$id/updates', {'kind': kind, 'text': text});

  // ---- meetings and decisions (read-only on the phone) ----
  Future<Map> meetings(int org) async => await _get('${_o(org)}/meetings', cacheKey: 'meetings:$org') as Map;
  Future<Map> meeting(int org, int id) async => await _get('${_o(org)}/meetings/$id', cacheKey: 'meeting:$org:$id') as Map;
  Future<Map> decisions(int org) async => await _get('${_o(org)}/decisions', cacheKey: 'decisions:$org') as Map;
  Future<Map> decision(int org, int id) async => await _get('${_o(org)}/decisions/$id') as Map;

  // ---- ask ----
  Future<Map> ask(int org, String question, {int? unitId}) async =>
      await _post('${_o(org)}/ask', {'question': question, 'unit_id': unitId}) as Map;
}

/// The server's own error text ("Only the people involved…") when there is
/// one, else a plain network message.
String workError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['error'] is String) return data['error'] as String;
    if (e.response == null) return "Can't reach Throughline. Check your connection.";
  }
  return 'Something went wrong. Please try again.';
}
