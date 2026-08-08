import 'dart:async';

import 'package:flutter/foundation.dart';

import '../main.dart' show callProvider;
import '../models/call.dart';
import '../services/notify_socket.dart';
import '../services/push_service.dart'
    show dismissNativeRinging, markCallFinishedNative, showLocalNotification;
import 'call_provider.dart' show CallStatus;

/// A visible, dismissable heads-up for something that just happened while
/// the app was open -- a new task/conversation appearing only as a silent
/// badge increment is easy to miss entirely if you're not looking at that
/// specific tab right now. Distinct from the badge counts themselves (which
/// stay, so the tab still shows it's unread even after this notice is gone).
class ForegroundNotice {
  final String message;
  final int? conversationId;
  ForegroundNotice(this.message, {this.conversationId});
}

/// Badge state + call signaling fed by /ws/notify. Connect once app-wide
/// while authenticated.
class NotifyProvider extends ChangeNotifier {
  final NotifySocket _socket = NotifySocket();
  final Set<int> unreadConversations = {};
  int taskBadge = 0;
  IncomingCall? incomingCall;
  ForegroundNotice? foregroundNotice;

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
        // A real system notification, not the in-app SnackBar (see
        // ForegroundNotice) -- FCM's own foreground-invisible behavior meant
        // a new task while the app was open was too easy to miss entirely.
        // conversation_id/description ride along on this same WS event
        // (unlike the other cases below, which only carry conversation_id),
        // so the notification can deep-link straight to it and offer an
        // "Ask" action that auto-submits a question about the task there.
        final description = event['description'] as String?;
        unawaited(showLocalNotification(
          'New task',
          description ?? 'untitled',
          conversationId: event['conversation_id'] as int?,
          description: description,
        ));
        notifyListeners();
        break;
      case 'chat_message':
        final id = event['conversation_id'];
        if (id != null) {
          unreadConversations.add(id);
          notifyListeners();
        }
        break;
      case 'call_conversation_ready':
      case 'conversation_created':
        final id = event['conversation_id'];
        if (id != null) {
          unreadConversations.add(id);
          foregroundNotice = ForegroundNotice('New conversation ready', conversationId: id);
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
          // Covers this device having been foregrounded (native ring
          // suppressed) when the call arrived -- native has no record of
          // this call_id being over otherwise, and a later FCM redelivery
          // of the original incoming_call push would ring it again.
          unawaited(markCallFinishedNative(id));
          // Covers the reverse: the native Telecom ringing screen is what's
          // actually showing right now (call arrived while backgrounded) --
          // clearing Dart's own incomingCall below does nothing for that
          // screen, which otherwise keeps ringing/showing until manually
          // declined even though the caller already hung up.
          unawaited(dismissNativeRinging(id));
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

  void clearForegroundNotice() {
    if (foregroundNotice != null) {
      foregroundNotice = null;
      notifyListeners();
    }
  }

  void stop() {
    _socket.dispose();
    unreadConversations.clear();
    taskBadge = 0;
    incomingCall = null;
    foregroundNotice = null;
  }
}
