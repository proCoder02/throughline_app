import 'api_client.dart';

/// Confirm/dismiss for MessageDraftCard -- thin wrapper over the
/// /message-drafts/<id>/confirm and /dismiss routes in app.py, same shape
/// as EmailDraftService.
class MessageDraftService {
  final _api = ApiClient.instance;

  Future<void> confirm(int draftId) {
    return _api.dio.post('/message-drafts/$draftId/confirm');
  }

  Future<void> dismiss(int draftId) {
    return _api.dio.post('/message-drafts/$draftId/dismiss');
  }
}
