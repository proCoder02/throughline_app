import 'package:dio/dio.dart';

import '../../services/api_client.dart';
import 'meet_models.dart';

/// Thrown when the server doesn't have Meet switched on (MEET_ENABLED unset):
/// /meet/* then falls through to the web app's page and isn't JSON.
class MeetUnavailable implements Exception {}

class MeetApi {
  final _api = ApiClient.instance;

  Map<String, dynamic> _json(Response r) {
    if (r.data is Map) return (r.data as Map).cast<String, dynamic>();
    throw MeetUnavailable();
  }

  Future<MyMeetCard> myCard() async {
    final j = _json(await _api.dio.get('/meet/card'));
    return MyMeetCard(
      saved: (j['saved'] as bool?) ?? false,
      card: MeetCard.fromJson((j['card'] as Map).cast<String, dynamic>()),
      me: MeetPerson.fromJson((j['me'] as Map).cast<String, dynamic>()),
    );
  }

  Future<MeetCard> saveCard(MeetCard card) async {
    final j = _json(await _api.dio.put('/meet/card', data: card.toJson()));
    return MeetCard.fromJson((j['card'] as Map).cast<String, dynamic>());
  }

  Future<MeetSession> startSession() async => MeetSession.fromJson(_json(await _api.dio.post('/meet/session')));

  Future<MeetSighting> reportTouch({required String myCode, required String seenCode}) async {
    try {
      final j = _json(await _api.dio.post('/meet/encounter', data: {'code': myCode, 'seen_code': seenCode}));
      final enc = j['encounter'] is Map ? MeetEncounter.fromJson((j['encounter'] as Map).cast<String, dynamic>()) : null;
      return MeetSighting(j['status'] as String, encounter: enc);
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['status'] is String) {
        return MeetSighting(data['status'] as String, error: data['error'] as String?);
      }
      rethrow;
    }
  }

  Future<MeetEncounter> encounter(int id) async => MeetEncounter.fromJson(_json(await _api.dio.get('/meet/encounter/$id')));

  Future<MeetEncounter> confirm(int id, {required bool accept}) async =>
      MeetEncounter.fromJson(_json(await _api.dio.post('/meet/encounter/$id/confirm', data: {'accept': accept})));

  Future<void> addFriend(int id) => _api.dio.post('/meet/encounter/$id/add-friend');

  Future<void> remove(int id) => _api.dio.delete('/meet/encounter/$id');

  Future<List<MeetEncounter>> history() async {
    final r = await _api.dio.get('/meet/encounters');
    if (r.data is! List) throw MeetUnavailable();
    return (r.data as List).map((j) => MeetEncounter.fromJson((j as Map).cast<String, dynamic>())).toList();
  }
}
