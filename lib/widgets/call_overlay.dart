import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/call.dart';
import '../services/ringtone.dart';
import '../state/call_provider.dart';
import '../state/notify_provider.dart';
import '../theme.dart';

/// Global overlay: full-screen incoming/active call UI, WhatsApp-style.
/// Mounted once in home_shell.dart so it survives tab switches.
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
      return _CallScreen(incoming: showIncoming);
    }
    if (call.status != CallStatus.idle) {
      return const _CallScreen();
    }
    return const SizedBox.shrink();
  }
}

/// Single full-screen shell for both incoming and active states -- mirrors
/// how WhatsApp/Telegram keep the same layout (avatar, name, status, big
/// circular actions) and just swap the button row and status text.
class _CallScreen extends StatelessWidget {
  final IncomingCall? incoming;
  const _CallScreen({this.incoming});

  @override
  Widget build(BuildContext context) {
    final notify = context.read<NotifyProvider>();
    final call = context.watch<CallProvider>();
    final isIncoming = incoming != null;

    final name = isIncoming
        ? incoming!.callerName
        : (call.participantNames.isNotEmpty ? call.participantNames.first : 'Call');
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    String status;
    if (isIncoming) {
      status = 'Incoming voice call...';
    } else if (call.status == CallStatus.connecting) {
      status = 'Calling...';
    } else if (call.participantNames.isEmpty) {
      status = 'Waiting for others to join...';
    } else {
      final others = call.participantNames.length + 1;
      status = call.participantNames.length == 1
          ? 'On call with ${call.participantNames.first}'
          : '$others on this call';
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.accentDark, Color(0xFF0B141A)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 140,
                height: 140,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white24),
                alignment: Alignment.center,
                child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 24),
              Text(name,
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(status, style: const TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
              for (final notice in call.dropNotices)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(notice, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(20)),
                child: const Text('This call is being recorded',
                    style: TextStyle(color: Color(0xFFFF8A80), fontSize: 12)),
              ),
              const Spacer(flex: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: isIncoming
                    ? _incomingActions(notify, call)
                    : _activeActions(call),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _incomingActions(NotifyProvider notify, CallProvider call) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CallButton(
          icon: Icons.call_end,
          label: 'Decline',
          color: AppColors.danger,
          onPressed: () {
            notify.clearIncomingCall();
            call.declineCall(incoming!.callId);
          },
        ),
        _CallButton(
          icon: Icons.call,
          label: 'Accept',
          color: const Color(0xFF25D366),
          onPressed: () {
            notify.clearIncomingCall();
            call.joinCall(incoming!.callId, callerId: incoming!.callerId);
          },
        ),
      ],
    );
  }

  Widget _activeActions(CallProvider call) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CallButton(
          icon: call.muted ? Icons.mic_off : Icons.mic,
          label: call.muted ? 'Unmute' : 'Mute',
          color: Colors.white24,
          onPressed: call.toggleMute,
        ),
        _CallButton(
          icon: Icons.call_end,
          label: 'Leave',
          color: AppColors.danger,
          onPressed: call.leaveCall,
        ),
      ],
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _CallButton({required this.icon, required this.label, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          elevation: 4,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(width: 72, height: 72, child: Icon(icon, color: Colors.white, size: 32)),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ],
    );
  }
}
