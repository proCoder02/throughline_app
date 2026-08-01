import 'package:flutter/foundation.dart';

import '../services/notify_socket.dart';

/// Badge state fed by /ws/notify. Connect once app-wide while authenticated.
class NotifyProvider extends ChangeNotifier {
  final NotifySocket _socket = NotifySocket();
  final Set<int> unreadConversations = {};
  int taskBadge = 0;

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
        final id = event['conversation_id'];
        if (id != null) {
          unreadConversations.add(id);
          notifyListeners();
        }
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

  void stop() {
    _socket.dispose();
    unreadConversations.clear();
    taskBadge = 0;
  }
}
