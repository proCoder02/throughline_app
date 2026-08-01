import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/call.dart';
import '../services/ringtone.dart';
import '../state/call_provider.dart';
import '../state/notify_provider.dart';
import '../theme.dart';

/// Global overlay (mirrors CallOverlay.jsx): incoming-call card or
/// active-call card, mutually exclusive, shown above whichever tab is
/// active. Mounted once in home_shell.dart so it survives tab switches.
class CallOverlay extends StatelessWidget {
  const CallOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final notify = context.watch<NotifyProvider>();
    final call = context.watch<CallProvider>();

    final showIncoming = call.status == CallStatus.idle ? notify.incomingCall : null;
    if (showIncoming != null) {
      Ringtone.start();
    } else {
      Ringtone.stop();
    }

    if (showIncoming != null) {
      return _IncomingCard(incoming: showIncoming);
    }
    if (call.status != CallStatus.idle) {
      return const _ActiveCard();
    }
    return const SizedBox.shrink();
  }
}

class _IncomingCard extends StatelessWidget {
  final IncomingCall incoming;
  const _IncomingCard({required this.incoming});

  @override
  Widget build(BuildContext context) {
    final notify = context.read<NotifyProvider>();
    final call = context.read<CallProvider>();
    return _Scrim(
      child: _Card(children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: AppColors.accent,
          child: Text(
            incoming.callerName.isNotEmpty ? incoming.callerName[0].toUpperCase() : '?',
            style: const TextStyle(color: Colors.white, fontSize: 24),
          ),
        ),
        const SizedBox(height: 12),
        Text(incoming.callerName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Incoming call...', style: TextStyle(color: AppColors.textSoft)),
        const SizedBox(height: 8),
        const Text('This call is being recorded', style: TextStyle(color: AppColors.danger, fontSize: 12)),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, shape: const CircleBorder(), padding: const EdgeInsets.all(16)),
              onPressed: () {
                notify.clearIncomingCall();
                call.declineCall(incoming.callId);
              },
              child: const Icon(Icons.call_end, color: Colors.white),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, shape: const CircleBorder(), padding: const EdgeInsets.all(16)),
              onPressed: () {
                notify.clearIncomingCall();
                call.joinCall(incoming.callId, callerId: incoming.callerId);
              },
              child: const Icon(Icons.mic, color: Colors.white),
            ),
          ],
        ),
      ]),
    );
  }
}

class _ActiveCard extends StatelessWidget {
  const _ActiveCard();

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallProvider>();
    final connecting = call.status == CallStatus.connecting;
    return _Scrim(
      child: _Card(children: [
        const CircleAvatar(
          radius: 32,
          backgroundColor: AppColors.accent,
          child: Icon(Icons.call, color: Colors.white),
        ),
        const SizedBox(height: 12),
        Text(connecting ? 'Connecting...' : 'Call in progress',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (!connecting) ...[
          const SizedBox(height: 4),
          Text(
            '${call.participantNames.length + 1} participants${call.participantNames.isEmpty ? '' : ' -- ${call.participantNames.join(', ')}'}',
            style: const TextStyle(color: AppColors.textSoft),
            textAlign: TextAlign.center,
          ),
        ],
        for (final notice in call.dropNotices)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(notice, style: const TextStyle(color: AppColors.textSoft, fontSize: 12)),
          ),
        const SizedBox(height: 8),
        const Text('This call is being recorded', style: TextStyle(color: AppColors.danger, fontSize: 12)),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: call.toggleMute,
              icon: Icon(call.muted ? Icons.mic_off : Icons.mic),
              label: Text(call.muted ? 'Unmute' : 'Mute'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: call.leaveCall,
              icon: const Icon(Icons.call_end),
              label: const Text('Leave'),
            ),
          ],
        ),
      ]),
    );
  }
}

class _Scrim extends StatelessWidget {
  final Widget child;
  const _Scrim({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0x8C000000), // rgba(0,0,0,0.55)
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 30, offset: Offset(0, 8))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
