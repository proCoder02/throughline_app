import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/call_provider.dart';
import '../theme.dart';

/// The "call started" card a global-chat reply carries as
/// ChatMessage.actionCard when the assistant's make_call tool fires (see
/// app.py's _tool_make_call). The call and its LiveKit room already exist
/// server-side at this point -- tapping Join just connects to them, it
/// never creates a new call the way CallProvider.startCall does.
class CallActionCard extends StatefulWidget {
  final Map<String, dynamic> card;

  const CallActionCard({super.key, required this.card});

  @override
  State<CallActionCard> createState() => _CallActionCardState();
}

class _CallActionCardState extends State<CallActionCard> {
  bool _joining = false;

  Future<void> _join() async {
    setState(() => _joining = true);
    await context.read<CallProvider>().startFromActionCard(widget.card);
    // No need to reset _joining on success -- CallOverlay takes over the
    // screen once status flips to connecting/active. On failure
    // CallProvider itself resets to idle, so just let this card unmount
    // naturally along with the rest of the chat if the user navigates away.
  }

  @override
  Widget build(BuildContext context) {
    final friendName = widget.card['friend_name'] as String?;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: isAppDarkMode ? 0.18 : 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.dmBubbleBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.call, size: 18, color: AppColors.dmAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              friendName != null ? 'Call with $friendName' : 'Call started',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
            ),
          ),
          ElevatedButton(
            onPressed: _joining ? null : _join,
            child: Text(_joining ? 'Joining…' : 'Join'),
          ),
        ],
      ),
    );
  }
}
