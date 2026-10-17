import 'api_client.dart';

/// Confirm/dismiss for EmailDraftCard -- thin wrapper over the
/// /email-drafts/<id>/confirm and /dismiss routes in app.py, same shape as
/// CommerceService's confirm/dismiss for the Swiggy action card.
class EmailDraftService {
  final _api = ApiClient.instance;

  Future<void> confirm(int draftId) {
    return _api.dio.post('/email-drafts/$draftId/confirm');
  }

  Future<void> dismiss(int draftId) {
    return _api.dio.post('/email-drafts/$draftId/dismiss');
  }
}
