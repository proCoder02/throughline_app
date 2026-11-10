import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../../services/push_service.dart' show showLocalNotification;
import 'work_api.dart';

/// Where a tapped notification (or anything else) wants Work to open.
class WorkTarget {
  final int? orgId;
  final int? threadId;
  final String? threadTitle;
  final bool team;
  final int? commitmentId;

  const WorkTarget({this.orgId, this.threadId, this.threadTitle, this.team = true, this.commitmentId});

  static int? _int(dynamic v) => v == null ? null : int.tryParse('$v');

  /// From a push payload (all values arrive as strings). Null for non-work pushes.
  static WorkTarget? fromPush(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == null || !type.startsWith('corp_')) return null;
    return WorkTarget(
      orgId: _int(data['org_id']),
      threadId: type == 'corp_message' ? _int(data['thread_id']) : null,
      threadTitle: data['title'] as String?,
      team: data['team'] != '0',
      commitmentId: _int(data['commitment_id']),
    );
  }
}

/// App-wide Work state, alive while signed in (kept here, not in
/// NotifyProvider, so everything about Work stays in features/work/):
///  - live work messages from the app's existing /ws/notify connection
///  - the unread count shown on the Personal/Work switch
///  - whether this person is in an organisation at all (no switch if not)
///  - the remembered mode, so a work-first person reopens in Work
///  - sending the offline outbox when the connection comes back
class WorkLive {
  WorkLive._();
  static final WorkLive instance = WorkLive._();

  final _api = WorkApi.instance;
  final _messages = StreamController<Map<String, dynamic>>.broadcast();

  /// Every live work message (thread screens listen for their own).
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  final unread = ValueNotifier<int>(0);
  final hasWork = ValueNotifier<bool>(false);

  /// The conversation on screen right now (no heads-up or badge for it).
  int? activeThreadId;

  /// Set while WorkScreen is mounted, so a notification tap opens the item
  /// in the open Work section instead of stacking a second one.
  void Function(WorkTarget target)? openInPlace;

  StreamSubscription? _net;

  /// Called once after sign-in / startup. Uses the saved copy first.
  Future<void> start() async {
    final cached = await _api.cached('me');
    if (cached is Map) hasWork.value = _orgCount(cached) > 0;
    _net ??= Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) _api.flush();
    });
    await refresh();
  }

  int _orgCount(Map me) => List<Map>.from(me['orgs'] ?? []).where((o) => o['status'] != 'left').length;

  Future<void> refresh() async {
    try {
      final me = await _api.me();
      hasWork.value = _orgCount(me) > 0;
      if (hasWork.value) {
        final u = await _api.unread();
        unread.value = (u['total'] as num?)?.toInt() ?? 0;
      }
      unawaited(_api.flush());
    } catch (_) {/* offline: keep the saved values */}
  }

  /// From NotifyProvider when /ws/notify delivers {"type": "corp_message"}.
  void onLiveMessage(Map<String, dynamic> event) {
    _messages.add(event);
    final tid = event['thread_id'];
    if (tid == activeThreadId) return;
    unread.value = unread.value + 1;
    // A message replayed on reconnect already showed as a push while the
    // app was closed; only fresh ones get a heads-up here.
    final at = (event['at'] as num?)?.toInt();
    final fresh = at == null || DateTime.now().millisecondsSinceEpoch ~/ 1000 - at < 60;
    if (fresh) {
      final team = event['team'] == true;
      final title = event['title'] as String? ?? 'Work message';
      final body = team ? '${event['sender'] ?? ''}: ${event['preview'] ?? ''}' : '${event['preview'] ?? ''}';
      unawaited(showLocalNotification(title, body));
    }
  }

  // ---- mode: Personal or Work ----
  Future<bool> lastModeWasWork() async => (await _api.cached('mode')) == 'work';
  Future<void> rememberMode(String mode) => _api.remember('mode', mode);

  void stop() {
    _net?.cancel();
    _net = null;
    unread.value = 0;
    hasWork.value = false;
    activeThreadId = null;
  }
}
