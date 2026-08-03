import 'package:flutter/foundation.dart';

import '../main.dart' show callProvider;
import '../models/call.dart';
import '../services/notify_socket.dart';
import 'call_provider.dart' show CallStatus;

/// Badge state + call signaling fed by /ws/notify. Connect once app-wide
/// while authenticated.
class NotifyProvider extends ChangeNotifier {
  final NotifySocket _socket = NotifySocket();
  final Set<int> unreadConversations = {};
  int taskBadge = 0;
  IncomingCall? incomingCall;

  // Call ids the native ConnectionService is already ringing for (see
  // PushService.onNativeRingStarted / MyFirebaseMessagingReceiver.kt) --
  // this device's own live WS socket (or a still-in-flight foreground FCM
  // delivery) can independently receive the very same incoming_call while
  // that native ring is up, and without this it would show its own
  // accept/decline screen for a call already ringing (and about to be
  // answered) natively. Cleared once the call is answered/ends so the set
  // doesn't grow without bound over a long session.
  final Set<int> _nativelyRingingCallIds = {};

  void start(String token) {
    _socket.connect(token, onEvent: _handle);
  }

  void markNativelyRinging(int callId) => _nativelyRingingCallIds.add(callId);

  void clearNativelyRinging(int callId) => _nativelyRingingCallIds.remove(callId);

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
        // Every call push arrives twice (WS + FCM, see send_fcm_to_user/
        // push_notification in app.py's create_call), and a WS reconnect can
        // replay a still-pending one (see _filter_stale_call_events in
        // app.py) -- ignore it entirely once this device is already
        // joining/on a call, otherwise a redelivery of the very call just
        // answered can re-populate incomingCall and pop the accept/decline
        // screen right back up on top of the call in progress.
        if (callProvider.status != CallStatus.idle || _nativelyRingingCallIds.contains(event['call_id'])) {
          debugPrint('[notify] WS incoming_call ${event['call_id']} suppressed, '
              'callProvider.status=${callProvider.status}, '
              'nativelyRinging=${_nativelyRingingCallIds.contains(event['call_id'])}');
          break;
        }
        debugPrint('[notify] WS incoming_call ${event['call_id']} -> showing ringing screen');
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
          _nativelyRingingCallIds.remove(id);
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
    if (callProvider.status != CallStatus.idle || _nativelyRingingCallIds.contains(callId)) {
      debugPrint('[notify] FCM incoming_call $callId suppressed, '
          'callProvider.status=${callProvider.status}, '
          'nativelyRinging=${_nativelyRingingCallIds.contains(callId)}');
      return;
    }
    debugPrint('[notify] FCM incoming_call $callId -> showing ringing screen');
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
