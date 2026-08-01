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
    }
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
