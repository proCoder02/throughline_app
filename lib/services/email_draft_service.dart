import 'package:dio/dio.dart';

import 'api_client.dart';

/// What the server said happened to one email. [status] is the server's
/// real state ('pending' | 'sending' | 'sent' | 'dismissed'); [error] is set
/// when the requested action did NOT happen, with the server's reason.
class EmailDraftResult {
  final Map<String, dynamic> data;
  final String? error;

  const EmailDraftResult(this.data, {this.error});

  String? get status => data['status'] as String?;
  bool get ok => error == null;
}

/// Send/cancel/status/attachments for EmailDraftCard -- thin wrapper over the
/// /email-drafts/<id> routes in app.py. Never throws for a server answer:
/// every outcome comes back as an [EmailDraftResult], so the card can show
/// exactly what the server did (including "already sent elsewhere").
class EmailDraftService {
  final _api = ApiClient.instance;

  EmailDraftResult _fromError(Object e, String fallback) {
    if (e is DioException && e.response?.data is Map) {
      final data = Map<String, dynamic>.from(e.response!.data as Map);
      return EmailDraftResult(data, error: (data['error'] as String?) ?? fallback);
    }
    return EmailDraftResult(const {}, error: fallback);
  }

  Future<EmailDraftResult> status(int draftId) async {
    try {
      final r = await _api.dio.get('/email-drafts/$draftId');
      return EmailDraftResult(Map<String, dynamic>.from(r.data as Map));
    } catch (e) {
      return _fromError(e, 'Could not load this email’s status.');
    }
  }

  Future<EmailDraftResult> confirm(int draftId) async {
    try {
      final r = await _api.dio.post('/email-drafts/$draftId/confirm');
      final data = Map<String, dynamic>.from(r.data as Map);
      if (data['ok'] != true || data['status'] != 'sent') {
        return EmailDraftResult(data, error: (data['error'] as String?) ?? 'The email was not sent.');
      }
      return EmailDraftResult(data);
    } catch (e) {
      return _fromError(e, 'The email was not sent. Check your connection and try again.');
    }
  }

  Future<EmailDraftResult> dismiss(int draftId) async {
    try {
      final r = await _api.dio.post('/email-drafts/$draftId/dismiss');
      final data = Map<String, dynamic>.from(r.data as Map);
      if (data['ok'] != true || data['status'] != 'dismissed') {
        return EmailDraftResult(data, error: (data['error'] as String?) ?? 'The draft was not cancelled.');
      }
      return EmailDraftResult(data);
    } catch (e) {
      return _fromError(e, 'Could not cancel the draft. Check your connection and try again.');
    }
  }

  /// Records an already-uploaded R2 object (see UploadService -- the
  /// presign+PUT+confirm already happened before this is called) against
  /// a still-pending draft. Returns the draft's full attachment list so
  /// the card can update itself from this response alone.
  Future<EmailDraftResult> attachFile(
    int draftId,
    String objectKey,
    String filename,
    String contentType,
  ) async {
    try {
      final r = await _api.dio.post('/email-drafts/$draftId/attachments', data: {
        'object_key': objectKey,
        'filename': filename,
        'content_type': contentType,
      });
      return EmailDraftResult(Map<String, dynamic>.from(r.data as Map));
    } catch (e) {
      return _fromError(e, 'Could not attach $filename. Try again.');
    }
  }

  Future<EmailDraftResult> removeAttachment(int draftId, int attachmentId) async {
    try {
      final r = await _api.dio.delete('/email-drafts/$draftId/attachments/$attachmentId');
      return EmailDraftResult(Map<String, dynamic>.from(r.data as Map));
    } catch (e) {
      return _fromError(e, 'Could not remove that file. Try again.');
    }
  }
}
