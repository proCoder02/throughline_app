import 'package:flutter/material.dart';

import '../services/message_draft_service.dart';
import '../theme.dart';

/// The "review before sending" card a global-chat reply carries as
/// ChatMessage.actionCard when message_friend drafts a direct message
/// (see app.py's _tool_message_friend) -- the message is already composed
/// and held as a pending row server-side; Send/Cancel here is the only
/// thing that decides whether it actually goes out. Same shape as
/// EmailDraftCard.
class MessageDraftCard extends StatefulWidget {
  final Map<String, dynamic> card;

  const MessageDraftCard({super.key, required this.card});

  @override
  State<MessageDraftCard> createState() => _MessageDraftCardState();
}

enum _DraftState { pending, busy, sent, dismissed, error }

class _MessageDraftCardState extends State<MessageDraftCard> {
  final _service = MessageDraftService();
  late _DraftState _state;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    // widget.card is the SAME Map instance held in GlobalChatBodyState's
    // _messages list, which survives ListView.builder disposing/rebuilding
    // this widget on scroll -- so a resolution recorded into it directly
    // (see _send/_cancel below) is still there when this State is
    // recreated fresh, instead of always resetting to pending.
    _state = switch (widget.card['_resolvedStatus']) {
      'sent' => _DraftState.sent,
      'dismissed' => _DraftState.dismissed,
      _ => _DraftState.pending,
    };
  }

  int get _draftId => widget.card['draft_id'] as int;

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
        _errorText = 'Could not send this message.';
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
    final friendName = widget.card['friend_name'] as String? ?? '';

    if (_state == _DraftState.sent) {
      return _card(children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.send_outlined, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text('Message sent to $friendName.', style: TextStyle(fontSize: 13.5, color: AppColors.dmTextSoft))),
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

    final content = widget.card['content'] as String? ?? '';
    final busy = _state == _DraftState.busy;

    return _card(children: [
      Row(children: [
        const Icon(Icons.drafts_outlined, size: 18, color: AppColors.dmAccent),
        const SizedBox(width: 8),
        Expanded(child: Text('To: $friendName', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
      const SizedBox(height: 6),
      Text(content, style: TextStyle(fontSize: 13, color: AppColors.dmTextSoft), maxLines: 6, overflow: TextOverflow.ellipsis),
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
