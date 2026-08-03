import 'package:flutter/foundation.dart';

import '../main.dart' show callProvider;
import '../models/call.dart';
import '../services/notify_socket.dart';

/// Badge state + call signaling fed by /ws/notify. Connect once app-wide
/// while authenticated.
class NotifyProvider extends ChangeNotifier {
  final NotifySocket _socket = NotifySocket();
  final Set<int> unreadConversations = {};
  int taskBadge = 0;
  IncomingCall? incomingCall;

  void start(String token) {
    _socket.connect(token, onEvent: _handle);
  }

  void _handle(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'task_created':
        taskBadge++;
        notifyListeners();
        break;
      case 'chat_message':
      case 'call_conversation_ready':
        final id = event['conversation_id'];
        if (id != null) {
          unreadConversations.add(id);
          notifyListeners();
        }
        break;
      case 'incoming_call':
        incomingCall = IncomingCall(
          callId: event['call_id'],
          roomName: event['room_name'],
          callerId: event['caller_id'],
          callerName: event['caller_name'],
        );
        notifyListeners();
        break;
      case 'call_declined':
        final id = event['call_id'];
        if (id != null) callProvider.handleRemoteDecline(id);
        break;
      case 'call_ended':
        // Sent when a call ends before this device ever joined it -- either
        // the caller hung up first, or nobody answered before the ring
        // timeout. Covers both roles on this device: if we're the callee
        // still ringing, dismiss that (the incoming-call notification is
        // `ongoing: true` and never expires on its own, and there's no live
        // LiveKit connection yet to notice any other way); if we're the
        // caller still waiting, end our own "Calling..." screen the exact
        // same way an explicit decline already does.
        final id = event['call_id'];
        if (id != null) {
          if (incomingCall?.callId == id) {
            incomingCall = null;
            notifyListeners();
          }
          callProvider.handleRemoteDecline(id);
        }
        break;
    }
  }

  /// Fed by PushService when an `incoming_call` FCM message arrives --
  /// mirrors the WS 'incoming_call' case in _handle, but tolerates FCM data
  /// payloads where every value arrives as a String rather than JSON's
  /// native int/string types.
  void handleIncomingCallPush(Map<String, dynamic> data) {
    final callId = int.tryParse(data['call_id']?.toString() ?? '');
    final callerId = int.tryParse(data['caller_id']?.toString() ?? '');
    if (callId == null || callerId == null) return;
    incomingCall = IncomingCall(
      callId: callId,
      roomName: data['room_name']?.toString() ?? '',
      callerId: callerId,
      callerName: data['caller_name']?.toString() ?? '',
    );
    notifyListeners();
  }

  void clearConversation(int id) {
    if (unreadConversations.remove(id)) notifyListeners();
  }

  void clearTaskBadge() {
    if (taskBadge != 0) {
      taskBadge = 0;
      notifyListeners();
    }
  }

  void clearIncomingCall() {
    if (incomingCall != null) {
      incomingCall = null;
      notifyListeners();
    }
  }

  void stop() {
    _socket.dispose();
    unreadConversations.clear();
    taskBadge = 0;
    incomingCall = null;
  }
}
