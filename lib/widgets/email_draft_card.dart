import 'package:flutter/material.dart';

import '../services/email_draft_service.dart';
import '../theme.dart';

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
  late _DraftState _state;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _state = _DraftState.pending;
  }

  int get _draftId => widget.card['draft_id'] as int;

  Future<void> _send() async {
    setState(() => _state = _DraftState.busy);
    try {
      await _service.confirm(_draftId);
      if (!mounted) return;
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
    final busy = _state == _DraftState.busy;

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
      const SizedBox(height: 10),
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
