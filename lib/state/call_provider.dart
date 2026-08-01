import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../main.dart' show authProvider;
import '../models/call.dart';
import '../services/call_service.dart';

enum CallStatus { idle, connecting, active }

/// Mirrors the web client's useCall.js state machine: idle -> connecting ->
/// active, with roster tracking, mute, auto-hangup-when-alone, and transient
/// drop notices. Call recording here is "record my own mic locally, upload
/// independently" (see call_service.dart) rather than the web's
/// browser-only mixed-stream capture.
class CallProvider extends ChangeNotifier {
  final _service = CallService();
  final _recorder = AudioRecorder();

  CallStatus status = CallStatus.idle;
  int? callId;
  bool muted = false;
  List<String> participantNames = [];
  final List<String> dropNotices = [];

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  String? _recordingPath;

  // Which participant is the initiator matters for group-call hangup rules
  // (see the ParticipantDisconnectedEvent handler below): identity strings
  // on LiveKit are the backend's str(user_id) (generate_livekit_token in
  // app.py), so this is comparable directly against a disconnecting
  // participant's identity.
  String? _initiatorIdentity;

  Future<void> startCall(List<int> friendIds) async {
    _initiatorIdentity = authProvider.userId?.toString();
    final info = await _service.start(friendIds);
    await _connect(info);
  }

  Future<void> joinCall(int callId, {required int callerId}) async {
    _initiatorIdentity = callerId.toString();
    final info = await _service.join(callId);
    await _connect(info);
  }

  Future<void> declineCall(int callId) => _service.decline(callId);

  /// Fired by NotifyProvider on a `call_declined` push -- the backend only
  /// sends this when nobody is left who could still join, so it's always
  /// safe to hang up outright rather than just dropping a roster entry.
  void handleRemoteDecline(int declinedCallId) {
    if (callId == declinedCallId && status != CallStatus.idle) {
      leaveCall();
    }
  }

  Future<void> _connect(CallJoinInfo info) async {
    status = CallStatus.connecting;
    callId = info.callId;
    notifyListeners();

    final room = lk.Room();
    final listener = room.createListener();
    listener
      ..on<lk.ParticipantConnectedEvent>((_) => _refreshRoster())
      ..on<lk.ParticipantDisconnectedEvent>((e) {
        _addDropNotice(e.participant.name.isNotEmpty ? e.participant.name : e.participant.identity);
        _refreshRoster();

        // 1:1 calls: the only other participant leaving always ends the
        // call (remoteParticipants goes to zero). Group calls: only the
        // initiator leaving ends it for everyone else -- anyone else
        // dropping just leaves them out, the rest of the call continues,
        // matching how normal group calling apps behave.
        final everyoneGone = _room != null && _room!.remoteParticipants.isEmpty;
        final initiatorLeft = _initiatorIdentity != null && e.participant.identity == _initiatorIdentity;
        if (everyoneGone || initiatorLeft) {
          // Deferred, matching the web's setTimeout(...,0): avoid tearing
          // the room down from inside its own event dispatch.
          Future.microtask(leaveCall);
        }
      });

    await room.connect(info.livekitUrl, info.token);
    await room.localParticipant?.setMicrophoneEnabled(true);

    _room = room;
    _listener = listener;
    status = CallStatus.active;
    _refreshRoster();
    notifyListeners();

    unawaited(_startLocalRecording());
  }

  void _refreshRoster() {
    participantNames =
        _room?.remoteParticipants.values.map((p) => p.name.isNotEmpty ? p.name : p.identity).toList() ?? [];
    notifyListeners();
  }

  void _addDropNotice(String name) {
    final notice = '$name dropped from the call';
    dropNotices.add(notice);
    notifyListeners();
    Timer(const Duration(seconds: 4), () {
      dropNotices.remove(notice);
      notifyListeners();
    });
  }

  Future<void> _startLocalRecording() async {
    try {
      if (!await _recorder.hasPermission()) return;
      final dir = await getTemporaryDirectory();
      _recordingPath = '${dir.path}/call_${callId}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: _recordingPath!);
    } catch (_) {
      // Best-effort -- the call itself works fine without a local recording.
    }
  }

  void toggleMute() {
    muted = !muted;
    _room?.localParticipant?.setMicrophoneEnabled(!muted);
    notifyListeners();
  }

  Future<void> leaveCall() async {
    if (status == CallStatus.idle) return;
    final id = callId;
    final room = _room;
    final listener = _listener;

    status = CallStatus.idle;
    _room = null;
    _listener = null;
    notifyListeners();

    await listener?.dispose();

    try {
      final path = await _recorder.stop();
      if (id != null && path != null) {
        await _service.uploadRecording(id, File(path));
      }
    } catch (_) {
      // Best-effort, matches the web client swallowing upload errors.
    }

    await room?.disconnect();
    if (id != null) {
      try {
        await _service.leave(id);
      } catch (_) {}
    }

    callId = null;
    muted = false;
    participantNames = [];
    dropNotices.clear();
    _initiatorIdentity = null;
    notifyListeners();
  }
}
