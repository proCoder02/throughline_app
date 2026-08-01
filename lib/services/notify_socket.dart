import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';

/// Wraps /ws/notify (badge counts). One connection for the app's lifetime
/// while authenticated; the server itself queues events while disconnected.
class NotifySocket {
  WebSocketChannel? _channel;

  void connect(String token, {required void Function(Map<String, dynamic>) onEvent}) {
    final uri = Uri.parse('${ApiConfig.wsBase}/ws/notify?token=$token');
    _channel = WebSocketChannel.connect(uri);
    _channel!.stream.listen(
      (data) {
        try {
          onEvent(jsonDecode(data));
        } catch (_) {
          // ignore malformed frames
        }
      },
      onError: (_) {},
      onDone: () {},
      cancelOnError: false,
    );
  }

  void dispose() {
    _channel?.sink.close();
    _channel = null;
  }
}
