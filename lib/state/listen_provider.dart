import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../models/speaker.dart';
import '../services/api_client.dart';
import '../services/listen_socket.dart';
import '../services/speaker_service.dart';

class TranscriptLine {
  final int speakerIndex;
  final String text;
  TranscriptLine(this.speakerIndex, this.text);
}

/// Live listening (spec §9), ported from the web client's useLiveSession.js.
/// Deliberately app-wide (not screen-local) so it survives navigating
/// between the Chats list and a conversation's thread -- exactly like the
/// React hook keeps running while its owning component just re-renders
/// around it. No separate "listening" screen: whichever chat thread is
/// open for the live conversation just shows a "Listening..." header badge.
class ListenProvider extends ChangeNotifier {
  final _recorder = AudioRecorder();
  final _socket = ListenSocket();
  final _speakerService = SpeakerService();

  StreamSubscription<Uint8List>? _audioSub;

  bool isListening = false;
  bool _stopping = false;
  bool _done = false;
  String status = '';
  int? conversationId;

  final Map<int, String> speakerNames = {};
  final List<int> seenIndices = [];
  int? pendingSpeakerIndex;
  List<Speaker> knownSpeakers = [];
  final List<String> tags = [];
  final Map<String, Timer> _tagTimers = {};
  final List<TranscriptLine> lines = [];

  void Function(int conversationId)? _onSessionStarted;

  String get transcriptText => lines
      .map((l) => '${speakerNames[l.speakerIndex] ?? 'Speaker ${l.speakerIndex}'}: ${l.text}')
      .join('\n');

  Future<void> start({int? resumeConversationId, void Function(int conversationId)? onSessionStarted}) async {
    if (isListening) return;
    if (!await _recorder.hasPermission()) {
      status = 'Error: microphone permission denied';
      notifyListeners();
      return;
    }
    final token = await ApiClient.instance.readToken();
    if (token == null) return;

    _onSessionStarted = onSessionStarted;
    _done = false;
    _stopping = false;
    conversationId = resumeConversationId;
    lines.clear();
    speakerNames.clear();
    seenIndices.clear();
    tags.clear();
    for (final timer in _tagTimers.values) {
      timer.cancel();
    }
    _tagTimers.clear();
    pendingSpeakerIndex = null;

    _socket.connect(
      token: token,
      conversationId: resumeConversationId,
      onMessage: _handleMessage,
      onDone: _handleDone,
    );

    final stream = await _recorder.startStream(
      const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
    );
    _audioSub = stream.listen(_socket.sendAudio);

    isListening = true;
    status = 'Listening...';
    notifyListeners();
  }

  void _handleMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'session_started':
        conversationId = msg['conversation_id'];
        _onSessionStarted?.call(conversationId!);
        openPrompt(0);
        break;
      case 'transcript':
        final line = (msg['line'] as String? ?? '');
        final text = line.contains(': ') ? line.split(': ').skip(1).join(': ') : line;
        lines.add(TranscriptLine(msg['speaker_index'] ?? 0, text));
        notifyListeners();
        break;
      case 'new_speaker':
        final idx = msg['speaker_index'] as int;
        if (!seenIndices.contains(idx)) seenIndices.add(idx);
        if (pendingSpeakerIndex != idx) openPrompt(idx);
        notifyListeners();
        break;
      case 'speaker_renamed':
        speakerNames[msg['speaker_index']] = msg['name'];
        notifyListeners();
        break;
      case 'background_update':
        final tasksFound = msg['tasks_found'] ?? 0;
        final speakersFound = msg['speakers_found'] ?? 0;
        status = 'Auto-extracted $tasksFound task(s), notes on $speakersFound speaker(s).';
        final newTags = (msg['tags'] as List?)?.cast<String>() ?? const [];
        if (newTags.isNotEmpty) _addTags(newTags);
        notifyListeners();
        break;
      case 'error':
        status = 'Error: ${msg['message']}';
        notifyListeners();
        break;
    }
  }

  Future<void> openPrompt(int idx) async {
    pendingSpeakerIndex = idx;
    notifyListeners();
    try {
      knownSpeakers = await _speakerService.list();
      notifyListeners();
    } catch (_) {
      // keep previous list
    }
  }

  void nameSpeaker(int idx, String name) {
    if (name.trim().isEmpty) return;
    speakerNames[idx] = name.trim();
    if (!seenIndices.contains(idx)) seenIndices.add(idx);
    pendingSpeakerIndex = null;
    notifyListeners();
    _socket.renameSpeaker(idx, name.trim());
  }

  void dismissPrompt() {
    pendingSpeakerIndex = null;
    notifyListeners();
  }

  /// Caps the accumulated (deduped) set at 5 and schedules each new tag to
  /// auto-expire 20s after it appears, even if never tapped/dismissed.
  void _addTags(List<String> newTags) {
    final existing = tags.map((t) => t.toLowerCase()).toSet();
    for (final t in newTags) {
      if (existing.contains(t.toLowerCase())) continue;
      existing.add(t.toLowerCase());
      tags.add(t);
      _tagTimers[t] = Timer(const Duration(seconds: 20), () => removeTag(t));
    }
    if (tags.length > 5) {
      final evicted = tags.sublist(0, tags.length - 5);
      tags.removeRange(0, tags.length - 5);
      for (final t in evicted) {
        _tagTimers.remove(t)?.cancel();
      }
    }
  }

  void removeTag(String tag) {
    if (tags.remove(tag)) {
      _tagTimers.remove(tag)?.cancel();
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (!isListening || _stopping) return;
    _stopping = true;
    await _audioSub?.cancel();
    await _recorder.stop();
    _socket.close();
    _handleDone();
  }

  void _handleDone() {
    // stop() calls this directly, and closing our own socket also fires
    // the channel's onDone asynchronously right after -- guard so cleanup
    // below only ever runs once.
    if (_done) return;
    _done = true;
    for (final timer in _tagTimers.values) {
      timer.cancel();
    }
    _tagTimers.clear();
    isListening = false;
    _stopping = false;
    status = 'Stopped. Saved automatically.';
    pendingSpeakerIndex = null;
    _onSessionStarted = null;
    notifyListeners();
  }
}
