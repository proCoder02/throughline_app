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
/// held as a pending row server-side; Send/Cancel here is the only thing
/// that decides whether it actually goes out. Same recommend-then-act
/// shape as the Swiggy ActionCard, just without its item-selection/
/// payment-polling complexity.
class EmailDraftCard extends StatefulWidget {
  final Map<String, dynamic> card;

  const EmailDraftCard({super.key, required this.card});

  @override
  State<EmailDraftCard> createState() => _EmailDraftCardState();
}

enum _DraftState { pending, busy, sent, dismissed, error }

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
    // (see _send/_cancel/_attach/_removeAttachment below) is still there
    // when this State is recreated fresh, instead of always resetting.
    _state = switch (widget.card['_resolvedStatus']) {
      'sent' => _DraftState.sent,
      'dismissed' => _DraftState.dismissed,
      _ => _DraftState.pending,
    };
  }

  int get _draftId => widget.card['draft_id'] as int;

  List<Map<String, dynamic>> get _attachments =>
      ((widget.card['_attachments'] as List?) ?? const []).cast<Map<String, dynamic>>();

  Future<void> _attach() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    setState(() => _attaching = true);
    try {
      final file = File(path);
      final contentType = guessMimeType(path);
      final objectKey = await _uploadService.uploadFile(file, 'chat_file', contentType);
      await _uploadService.confirmUpload(objectKey, 'chat_file');
      final filename = path.split(Platform.pathSeparator).last;
      final attachments = await _service.attachFile(_draftId, objectKey, filename, contentType);
      if (!mounted) return;
      widget.card['_attachments'] = attachments;
      setState(() => _attaching = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _attaching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not attach that file. Try again.')),
      );
    }
  }

  Future<void> _removeAttachment(int attachmentId) async {
    setState(() => _attaching = true);
    try {
      final attachments = await _service.removeAttachment(_draftId, attachmentId);
      if (!mounted) return;
      widget.card['_attachments'] = attachments;
    } catch (_) {
      // Leaving the chip in place on failure is fine -- the user can
      // just try removing it again, same as every other best-effort
      // action in this card.
    }
    if (!mounted) return;
    setState(() => _attaching = false);
  }

  Future<void> _send() async {
    setState(() => _state = _DraftState.busy);
    try {
      await _service.confirm(_draftId);
      if (!mounted) return;
      widget.card['_resolvedStatus'] = 'sent';
      setState(() => _state = _DraftState.sent);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _DraftState.error;
        _errorText = 'Could not send this email.';
      });
    }
  }

  Future<void> _cancel() async {
    setState(() => _state = _DraftState.busy);
    try {
      await _service.dismiss(_draftId);
    } catch (_) {
      // Dismiss failing silently is fine -- worst case the card stays
      // pending server-side; it can never accidentally send either way.
    }
    if (!mounted) return;
    widget.card['_resolvedStatus'] = 'dismissed';
    setState(() => _state = _DraftState.dismissed);
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

  @override
  Widget build(BuildContext context) {
    if (_state == _DraftState.sent) {
      return _card(children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.mail_outline, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text('Email sent to ${widget.card['to_email']}.', style: TextStyle(fontSize: 13.5, color: AppColors.dmTextSoft))),
        ]),
      ]);
    }
    if (_state == _DraftState.dismissed) {
      return _card(children: [
        Text('Draft cancelled.', style: TextStyle(fontSize: 13.5, color: AppColors.dmTextSoft)),
      ]);
    }
    if (_state == _DraftState.error) {
      return _card(children: [
        Text(_errorText ?? 'Something went wrong.', style: TextStyle(fontSize: 13.5, color: AppColors.dmTextSoft)),
      ]);
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
              icon: const Icon(Icons.send, size: 15),
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
