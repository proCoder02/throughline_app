import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/email_draft_service.dart';
import '../services/upload_service.dart';
import '../theme.dart';
import '../utils/mime_type.dart';

/// The "review before sending" card a global-chat reply carries as
/// ChatMessage.actionCard when send_email's recipient isn't a known friend
/// (see app.py's _tool_send_email) -- the email is already composed and
/// held as a pending row server-side.
///
/// Every state this card shows comes from the server: it loads the email's
/// real status when it appears (it may have been sent from the chat, the
/// website, or before the app restarted), and Send / Cancel / Attach only
/// change the card when the server says the action happened. A failure keeps
/// the draft pending with the server's reason, so the user can retry.
class EmailDraftCard extends StatefulWidget {
  final Map<String, dynamic> card;

  const EmailDraftCard({super.key, required this.card});

  @override
  State<EmailDraftCard> createState() => _EmailDraftCardState();
}

enum _DraftState { pending, busy, sending, sent, dismissed }

class _EmailDraftCardState extends State<EmailDraftCard> {
  final _service = EmailDraftService();
  final _uploadService = UploadService();
  late _DraftState _state;
  String? _errorText;
  bool _attaching = false;

  @override
  void initState() {
    super.initState();
    // widget.card is the SAME Map instance held in GlobalChatBodyState's
    // _messages list, which survives ListView.builder disposing/rebuilding
    // this widget on scroll -- so a resolution recorded into it directly
    // is still there when this State is recreated fresh.
    _state = _stateFor(widget.card['_resolvedStatus'] as String? ?? widget.card['status'] as String?);
    _refresh();
  }

  static _DraftState _stateFor(String? status) => switch (status) {
        'sent' => _DraftState.sent,
        'sending' => _DraftState.sending,
        'dismissed' => _DraftState.dismissed,
        _ => _DraftState.pending,
      };

  int get _draftId => widget.card['draft_id'] as int;

  Map<String, dynamic> get _record => (widget.card['_record'] as Map<String, dynamic>?) ?? widget.card;

  List<Map<String, dynamic>> get _attachments =>
      ((widget.card['_attachments'] as List?) ?? const []).cast<Map<String, dynamic>>();

  /// Records the server's answer into the shared card map and the UI.
  void _apply(Map<String, dynamic> data) {
    final status = data['status'] as String?;
    if (status == null) return;
    widget.card['_resolvedStatus'] = status;
    widget.card['_record'] = data;
    if (data['attachments'] is List) {
      widget.card['_attachments'] = List<Map<String, dynamic>>.from(data['attachments'] as List);
    }
    _state = _stateFor(status);
  }

  Future<void> _refresh() async {
    final result = await _service.status(_draftId);
    if (!mounted || !result.ok) return; // keep what the chat reply said; the next action re-checks anyway
    setState(() => _apply(result.data));
  }

  /// A failed action: if the server reports the email already moved on
  /// (sent or cancelled elsewhere), show that; otherwise stay pending with
  /// the reason so the user can retry.
  void _handleFailure(EmailDraftResult result) {
    setState(() {
      final status = result.status;
      if (status != null && status != 'pending') {
        _apply(result.data);
        _errorText = null;
      } else {
        _state = _DraftState.pending;
        _errorText = result.error;
      }
    });
  }

  Future<void> _attach() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    setState(() {
      _attaching = true;
      _errorText = null;
    });
    final filename = path.split(Platform.pathSeparator).last;
    EmailDraftResult result;
    try {
      final file = File(path);
      final contentType = guessMimeType(path);
      final objectKey = await _uploadService.uploadFile(file, 'chat_file', contentType);
      await _uploadService.confirmUpload(objectKey, 'chat_file');
      result = await _service.attachFile(_draftId, objectKey, filename, contentType);
    } catch (_) {
      result = EmailDraftResult(const {}, error: 'Could not upload $filename. Try again.');
    }
    if (!mounted) return;
    setState(() {
      _attaching = false;
      if (result.ok) {
        widget.card['_attachments'] = List<Map<String, dynamic>>.from(result.data['attachments'] as List);
      } else {
        final status = result.status;
        if (status != null && status != 'pending') _apply(result.data);
        _errorText = result.error;
      }
    });
  }

  Future<void> _removeAttachment(int attachmentId) async {
    setState(() {
      _attaching = true;
      _errorText = null;
    });
    final result = await _service.removeAttachment(_draftId, attachmentId);
    if (!mounted) return;
    setState(() {
      _attaching = false;
      if (result.ok) {
        widget.card['_attachments'] = List<Map<String, dynamic>>.from(result.data['attachments'] as List);
      } else {
        _errorText = result.error;
      }
    });
  }

  Future<void> _send() async {
    setState(() {
      _state = _DraftState.busy;
      _errorText = null;
    });
    final result = await _service.confirm(_draftId);
    if (!mounted) return;
    if (result.ok) {
      setState(() => _apply(result.data));
    } else {
      _handleFailure(result);
    }
  }

  Future<void> _cancel() async {
    setState(() {
      _state = _DraftState.busy;
      _errorText = null;
    });
    final result = await _service.dismiss(_draftId);
    if (!mounted) return;
    if (result.ok) {
      setState(() => _apply(result.data));
    } else {
      _handleFailure(result);
    }
  }

  Widget _card({required List<Widget> children}) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: isAppDarkMode ? 0.18 : 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.dmBubbleBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
      );

  String _sentDetail() {
    final verified = _record['sent_box_verified'];
    final copyTo = _record['copy_to'] as String?;
    final base = verified == true
        ? 'Confirmed in Throughline’s Sent folder.'
        : verified == false
            ? 'The mail server accepted it, but it could not be confirmed in Throughline’s Sent folder.'
            : 'Sent before Sent-folder tracking, so it cannot be checked there.';
    return copyTo != null && copyTo.isNotEmpty ? '$base A copy went to your inbox ($copyTo).' : base;
  }

  @override
  Widget build(BuildContext context) {
    final soft = TextStyle(fontSize: 13.5, color: AppColors.dmTextSoft);
    if (_state == _DraftState.sent) {
      return _card(children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.mark_email_read_outlined, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text('Email sent to ${widget.card['to_email']}.', style: soft)),
        ]),
        const SizedBox(height: 4),
        Text(_sentDetail(), style: TextStyle(fontSize: 12.5, color: AppColors.dmTextSoft)),
      ]);
    }
    if (_state == _DraftState.sending) {
      return _card(children: [Text('Sending to ${widget.card['to_email']}…', style: soft)]);
    }
    if (_state == _DraftState.dismissed) {
      return _card(children: [Text('Draft cancelled. Nothing was sent.', style: soft)]);
    }

    final toEmail = widget.card['to_email'] as String? ?? '';
    final subject = widget.card['subject'] as String? ?? '';
    final body = widget.card['body'] as String? ?? '';
    final busy = _state == _DraftState.busy || _attaching;
    final attachments = _attachments;

    return _card(children: [
      Row(children: [
        const Icon(Icons.drafts_outlined, size: 18, color: AppColors.dmAccent),
        const SizedBox(width: 8),
        Expanded(child: Text('To: $toEmail', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
      const SizedBox(height: 6),
      Text(subject, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
      const SizedBox(height: 4),
      Text(body, style: TextStyle(fontSize: 13, color: AppColors.dmTextSoft), maxLines: 6, overflow: TextOverflow.ellipsis),
      if (attachments.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: attachments.map((a) {
            return Chip(
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              avatar: const Icon(Icons.attach_file, size: 14),
              label: Text(a['filename'] as String? ?? 'file', style: const TextStyle(fontSize: 11.5)),
              onDeleted: busy ? null : () => _removeAttachment(a['id'] as int),
              deleteIcon: const Icon(Icons.close, size: 14),
            );
          }).toList(),
        ),
      ],
      if (_errorText != null) ...[
        const SizedBox(height: 8),
        Text(_errorText!, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.error)),
      ],
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: busy ? null : _attach,
          icon: _attaching
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.attach_file, size: 15),
          label: Text(_attaching ? 'Attaching...' : 'Attach file'),
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), visualDensity: VisualDensity.compact),
        ),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: busy ? null : _send,
              icon: _state == _DraftState.busy
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send, size: 15),
              label: const Text('Send'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: busy ? null : _cancel,
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    ]);
  }
}
