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
  bool _ready = false;
  // Client -> server sends made before the connection actually finished
  // opening -- found via a real bug: DirectMessageScreen fires its initial
  // ackRead()/ackDelivered() from initState(), which can genuinely race
  // ahead of the socket handshake completing (unlike an ack triggered by
  // an already-arrived 'direct_message' event, which by definition means
  // the socket is already open). Without this queue, that first ack was
  // silently dropped with no retry anywhere -- exactly the "ticks never
  // update" symptom this was written to fix.
  final List<Map<String, dynamic>> _outbox = [];
  static const _outboxCap = 20;

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
    _ready = false;
    channel.ready.then((_) {
      if (_channel != channel) return; // superseded by a later reconnect
      _ready = true;
      _flushOutbox();
    }).catchError((_) {
      // Connection failed outright -- onDone below handles the reconnect;
      // nothing queued here gets a chance to send until then.
    });
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

  void _flushOutbox() {
    if (_outbox.isEmpty) return;
    final pending = List<Map<String, dynamic>>.from(_outbox);
    _outbox.clear();
    for (final event in pending) {
      _sendNow(event);
    }
  }

  void _sendNow(Map<String, dynamic> event) {
    try {
      _channel?.sink.add(jsonEncode(event));
    } catch (_) {
      // Best-effort -- a failure here (vs. simply not being ready yet,
      // handled by the queue below) genuinely has nowhere better to go.
    }
  }

  /// Client -> server messages (direct-message delivery/read acks, typing
  /// signals) -- rides this same persistent connection rather than a
  /// separate REST call per ack. Queued (capped, oldest dropped first) if
  /// the connection isn't fully open yet, flushed the moment it is -- see
  /// the _outbox doc comment above for why this isn't just best-effort.
  void send(Map<String, dynamic> event) {
    if (_ready) {
      _sendNow(event);
    } else {
      _outbox.add(event);
      if (_outbox.length > _outboxCap) _outbox.removeAt(0);
    }
  }

  // Tightened from [1, 2, 5, 10, 20] after finding, via real device testing,
  // that the very first connection attempt at cold app start frequently
  // fails (network/DNS not fully ready yet right after process start) --
  // with the old schedule this meant task_created/direct_message pushes
  // routinely arrived while the socket was still down, sometimes for 1-2+
  // minutes before recovering. This schedule reaches its steady-state retry
  // interval in under 10s instead of ~38s.
  static const _reconnectDelaysSeconds = [0.5, 1, 2, 3, 5];

  void _scheduleReconnect() {
    _ready = false;
    if (_disposed) return;
    _reconnectTimer?.cancel();
    final delaySeconds = _reconnectDelaysSeconds[_attempt.clamp(0, _reconnectDelaysSeconds.length - 1)];
    _attempt++;
    _reconnectTimer = Timer(Duration(milliseconds: (delaySeconds * 1000).round()), _open);
  }

  /// Called on app resume (see HomeShell's AppLifecycleState.resumed
  /// handler) -- without this, a connection dropped while backgrounded just
  /// sits on whatever backoff delay (up to 5s) happened to be running when
  /// the user reopens the app, instead of reconnecting the instant it's
  /// visible again. A no-op if already connected.
  void forceReconnect() {
    if (_disposed || _ready) return;
    _reconnectTimer?.cancel();
    _attempt = 0;
    _open();
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
  }
}
