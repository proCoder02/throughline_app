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

  // Two distinct things extracted per background-analysis batch: short
  // topic keywords (always extracted) and tappable follow-up questions
  // (only when one's actually raised/implied) -- previously conflated into
  // one "tags" field where questions crowded out topics almost entirely,
  // since the backend prompt preferred a question whenever one was
  // available. See build_analysis_prompt in app.py.
  final List<String> topics = [];
  final List<String> questions = [];
  final Map<String, Timer> _topicTimers = {};
  final Map<String, Timer> _questionTimers = {};
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
    topics.clear();
    questions.clear();
    for (final timer in _topicTimers.values) {
      timer.cancel();
    }
    _topicTimers.clear();
    for (final timer in _questionTimers.values) {
      timer.cancel();
    }
    _questionTimers.clear();
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
        final newTopics = (msg['topics'] as List?)?.cast<String>() ?? const [];
        final newQuestions = (msg['questions'] as List?)?.cast<String>() ?? const [];
        if (newTopics.isNotEmpty) _addChips(topics, _topicTimers, newTopics);
        if (newQuestions.isNotEmpty) _addChips(questions, _questionTimers, newQuestions);
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

  /// Caps the accumulated (deduped) set at 5 and schedules each new chip to
  /// auto-expire 20s after it appears, even if never tapped/dismissed.
  /// Shared by both topics and questions -- same accumulate/cap/expire
  /// behavior, just against whichever list+timer-map is passed in.
  void _addChips(List<String> list, Map<String, Timer> timers, List<String> newItems) {
    final existing = list.map((t) => t.toLowerCase()).toSet();
    for (final t in newItems) {
      if (existing.contains(t.toLowerCase())) continue;
      existing.add(t.toLowerCase());
      list.add(t);
      timers[t] = Timer(const Duration(seconds: 20), () => _removeChip(list, timers, t));
    }
    if (list.length > 5) {
      final evicted = list.sublist(0, list.length - 5);
      list.removeRange(0, list.length - 5);
      for (final t in evicted) {
        timers.remove(t)?.cancel();
      }
    }
  }

  void _removeChip(List<String> list, Map<String, Timer> timers, String item) {
    if (list.remove(item)) {
      timers.remove(item)?.cancel();
      notifyListeners();
    }
  }

  void removeTopic(String t) => _removeChip(topics, _topicTimers, t);
  void removeQuestion(String q) => _removeChip(questions, _questionTimers, q);

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
    for (final timer in _topicTimers.values) {
      timer.cancel();
    }
    _topicTimers.clear();
    for (final timer in _questionTimers.values) {
      timer.cancel();
    }
    _questionTimers.clear();
    isListening = false;
    _stopping = false;
    status = 'Stopped. Saved automatically.';
    pendingSpeakerIndex = null;
    _onSessionStarted = null;
    notifyListeners();
  }
}
