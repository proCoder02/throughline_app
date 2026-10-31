import 'package:dio/dio.dart';

import '../../services/api_client.dart';
import 'meet_models.dart';

/// Thrown when the server doesn't have Meet switched on (MEET_ENABLED unset):
/// /meet/* then falls through to the web app's page and isn't JSON.
class MeetUnavailable implements Exception {}

class MeetSuggestionError implements Exception {
  final String message;
  const MeetSuggestionError(this.message);
}

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
      traitOptions: (j['trait_options'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      canSuggest: (j['can_suggest'] as bool?) ?? false,
    );
  }

  /// Throws [MeetSuggestionError] with a message the editor can show as-is.
  Future<MeetSuggestion> suggest() async {
    try {
      final j = _json(await _api.dio.post('/meet/card/suggest'));
      return MeetSuggestion(
        traits: (j['traits'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        style: (j['style'] as String?) ?? '',
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      throw MeetSuggestionError(data is Map && data['error'] is String
          ? data['error'] as String
          : "Couldn't make a suggestion right now. Try again in a moment.");
    }
  }

  Future<MeetCard> saveCard(MeetCard card) async {
    final j = _json(await _api.dio.put('/meet/card', data: card.toJson()));
    return MeetCard.fromJson((j['card'] as Map).cast<String, dynamic>());
  }

  Future<MeetSession> startSession() async => MeetSession.fromJson(_json(await _api.dio.post('/meet/session')));

  Future<MeetSighting> reportTouch({required String myCode, required MeetTouch touch}) =>
      _sighting(() => _api.dio.post('/meet/encounter', data: {'code': myCode, 'seen_code': touch.code, 'rssi': touch.rssi}));

  Future<MeetSighting> _sighting(Future<Response> Function() send) async {
    try {
      final j = _json(await send());
      final enc = j['encounter'] is Map ? MeetEncounter.fromJson((j['encounter'] as Map).cast<String, dynamic>()) : null;
      return MeetSighting(j['status'] as String, encounter: enc, error: j['error'] as String?);
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['status'] is String) {
        return MeetSighting(data['status'] as String, error: data['error'] as String?);
      }
      rethrow;
    }
  }

  // ---- QR fallback ----

  Future<MeetQr> startQr() async => MeetQr.fromJson(_json(await _api.dio.post('/meet/qr')));

  /// For the phone showing the code: the encounter once someone scans it.
  Future<MeetSighting> qrStatus(String token) => _sighting(() => _api.dio.get('/meet/qr/$token'));

  Future<MeetSighting> scanQr(String payload) => _sighting(() => _api.dio.post('/meet/qr/scan', data: {'payload': payload}));

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
