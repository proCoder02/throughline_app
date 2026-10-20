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

  /// Records an already-uploaded R2 object (see UploadService -- the
  /// presign+PUT+confirm already happened before this is called) against
  /// a still-pending draft. Returns the draft's full attachment list so
  /// the card can update itself from this response alone.
  Future<List<Map<String, dynamic>>> attachFile(
    int draftId,
    String objectKey,
    String filename,
    String contentType,
  ) async {
    final r = await _api.dio.post('/email-drafts/$draftId/attachments', data: {
      'object_key': objectKey,
      'filename': filename,
      'content_type': contentType,
    });
    return List<Map<String, dynamic>>.from(r.data['attachments'] as List);
  }

  Future<List<Map<String, dynamic>>> removeAttachment(int draftId, int attachmentId) async {
    final r = await _api.dio.delete('/email-drafts/$draftId/attachments/$attachmentId');
    return List<Map<String, dynamic>>.from(r.data['attachments'] as List);
  }
}
