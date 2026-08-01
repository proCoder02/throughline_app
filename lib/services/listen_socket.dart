import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';

/// Wraps /ws/listen for a single live-listening session: streams raw audio
/// out, receives transcript/speaker/tag events back in. Unlike NotifySocket
/// this is intentionally session-scoped, not persistent -- a drop just ends
/// the session (matches the web client's onclose behavior).
class ListenSocket {
  WebSocketChannel? _channel;

  void connect({
    required String token,
    int? conversationId,
    required void Function(Map<String, dynamic>) onMessage,
    required void Function() onDone,
  }) {
    final params = {
      'token': token,
      // Raw linear16 PCM -- see the matching additive change in
      // app.py's ws_listen (`encoding`/`sample_rate` query params).
      'encoding': 'linear16',
      'sample_rate': '16000',
      if (conversationId != null) 'conversation_id': '$conversationId',
    };
    final uri = Uri.parse('${ApiConfig.wsBase}/ws/listen').replace(queryParameters: params);
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    channel.stream.listen(
      (data) {
        if (data is String) {
          try {
            onMessage(jsonDecode(data));
          } catch (_) {
            // ignore malformed frames
          }
        }
      },
      onDone: onDone,
      onError: (_) => onDone(),
      cancelOnError: false,
    );
  }

  void sendAudio(Uint8List chunk) {
    _channel?.sink.add(chunk);
  }

  void renameSpeaker(int speakerIndex, String name) {
    _channel?.sink.add(jsonEncode({'type': 'rename_speaker', 'speaker_index': speakerIndex, 'name': name}));
  }

  void close() {
    _channel?.sink.close();
    _channel = null;
  }
}
