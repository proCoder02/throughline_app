import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';

/// Wraps /ws/notify (badges + call signaling). One connection for the app's
/// lifetime while authenticated; the server itself queues events while
/// disconnected. Reconnects with backoff on drop -- unlike the web client,
/// mobile network transitions (backgrounding, wifi/cell handoff) make this
/// necessary rather than optional.
class NotifySocket {
  WebSocketChannel? _channel;
  String? _token;
  void Function(Map<String, dynamic>)? _onEvent;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _disposed = false;

  void connect(String token, {required void Function(Map<String, dynamic>) onEvent}) {
    _token = token;
    _onEvent = onEvent;
    _disposed = false;
    _open();
  }

  void _open() {
    final uri = Uri.parse('${ApiConfig.wsBase}/ws/notify?token=$_token');
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    channel.stream.listen(
      (data) {
        _attempt = 0;
        try {
          _onEvent?.call(jsonDecode(data));
        } catch (_) {
          // ignore malformed frames
        }
      },
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: false,
    );
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    final delaySeconds = [1, 2, 5, 10, 20][_attempt.clamp(0, 4)];
    _attempt++;
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), _open);
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
  }
}
