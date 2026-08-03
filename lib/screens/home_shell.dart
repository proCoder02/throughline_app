import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart' show notifyProvider, callProvider;
import '../services/api_client.dart';
import '../services/push_service.dart';
import '../state/notify_provider.dart';
import '../widgets/call_overlay.dart';
import 'chats/chats_screen.dart';
import 'tasks/tasks_screen.dart';
import 'profiles/profiles_screen.dart';
import 'friends/friends_screen.dart';
import 'settings/settings_screen.dart';

/// Bottom-nav shell for phones (Â§2): replaces the web app's 3-pane layout.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // Only the active tab's screen is actually built/initState'd -- an eager
  // IndexedStack would fire all 5 screens' initState (and their network/cache
  // calls) simultaneously the moment this widget mounts, right in the middle
  // of app startup. Once a tab has been visited its widget is kept (matching
  // IndexedStack's usual "preserve state across tab switches" behavior);
  // never-visited tabs stay an empty placeholder.
  final _visited = <int>{0};

  static const _builders = <WidgetBuilder>[
    _buildChats,
    _buildTasks,
    _buildProfiles,
    _buildFriends,
    _buildSettings,
  ];

  static Widget _buildChats(BuildContext _) => const ChatsScreen();
  static Widget _buildTasks(BuildContext _) => const TasksScreen();
  static Widget _buildProfiles(BuildContext _) => const ProfilesScreen();
  static Widget _buildFriends(BuildContext _) => const FriendsScreen();
  static Widget _buildSettings(BuildContext _) => const SettingsScreen();

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    // Attached before anything below -- covers the case where this engine
    // was already running (app backgrounded, not killed) when the user
    // answered a call on the native ringing screen. That arrives via
    // MainActivity.onNewIntent(), not a fresh configureFlutterEngine, so
    // HomeShell.initState() never runs again to pull it -- native pushes it
    // here instead (see MainActivity.kt's capturePendingCallAnswer()).
    PushService.instance.onCallAnsweredNatively = _joinNativelyAnsweredCall;
    // Fed the instant the native ConnectionService starts ringing a call
    // (see MyFirebaseMessagingReceiver.kt) -- suppresses this device's own
    // independent WS/FCM-driven ringing screen for that call_id entirely
    // (see notify_provider.dart's guards), rather than showing it and racing
    // to clear it once the user answers natively.
    PushService.instance.onNativeRingStarted = notifyProvider.markNativelyRinging;
    PushService.instance.listenForNativeCallAnswers();

    // Checked -- and, if it fires, acted on -- before the WS socket below is
    // even started: covers the true cold-start case (app was killed) where
    // the native answer arrived as this Activity's launching Intent.
    // CallProvider.status must flip away from idle before the WS connects,
    // not after -- otherwise a reconnect can replay the still-pending
    // incoming_call event for this exact call (see _filter_stale_call_events
    // in app.py) while status is still idle, and NotifyProvider.incomingCall's
    // own already-mid-call guard (see notify_provider.dart) hasn't kicked in
    // yet, briefly resurfacing a real, tappable accept/decline screen for a
    // call already answered.
    final pendingAnswer = await consumePendingCallAnswer();
    if (pendingAnswer != null) _joinNativelyAnsweredCall(pendingAnswer);

    // Connect the app-wide notify socket once, for as long as the user stays
    // in the authenticated area (this widget persists across tab switches).
    final token = await ApiClient.instance.readToken();
    if (token != null) notifyProvider.start(token);

    // FCM: reaches this device even when it's backgrounded/killed, unlike
    // the WS socket above. onIncomingCallForeground reuses the exact same
    // overlay the WS 'incoming_call' case drives, so a call rings the same
    // way regardless of which channel got there first.
    PushService.instance.onIncomingCallForeground = notifyProvider.handleIncomingCallPush;
    PushService.instance.onMessageTapped = (data) {
      if (data['type'] == 'incoming_call') notifyProvider.handleIncomingCallPush(data);
      // task_created / reminder_email_sent / friend_mood_update: landing on
      // HomeShell is enough for now -- the relevant tab's badge already
      // reflects it once the WS reconnects. Deep-linking a tap straight to
      // the task/conversation/friend is a reasonable follow-up, not done here.
    };
    unawaited(PushService.instance.registerDevice());
  }

  void _joinNativelyAnsweredCall(Map<String, dynamic> data) {
    final callId = int.tryParse(data['call_id']?.toString() ?? '');
    final callerId = int.tryParse(data['caller_id']?.toString() ?? '');
    // Clears out any stale ringing state a WS/FCM incoming_call event might
    // already have set for this same call -- otherwise it can resurface as a
    // phantom ringing screen once this call ends and CallProvider.status
    // returns to idle.
    notifyProvider.clearIncomingCall();
    if (callId != null) {
      notifyProvider.clearNativelyRinging(callId);
      unawaited(callProvider.joinCall(callId, callerId: callerId ?? 0));
    }
  }

  @override
  void dispose() {
    notifyProvider.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notify = context.watch<NotifyProvider>();
    return Stack(
      children: [
        Scaffold(
          body: IndexedStack(
            index: _index,
            children: [
              for (var i = 0; i < _builders.length; i++)
                _visited.contains(i) ? _builders[i](context) : const SizedBox.shrink(),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: _index,
            onTap: (i) => setState(() {
              _index = i;
              _visited.add(i);
            }),
            items: [
              BottomNavigationBarItem(
                icon: _badged(Icons.chat_bubble_outline, notify.unreadConversations.length),
                label: 'Chats',
              ),
              BottomNavigationBarItem(
                icon: _badged(Icons.check_circle_outline, notify.taskBadge),
                label: 'Tasks',
              ),
              const BottomNavigationBarItem(icon: Icon(Icons.people_outline), label: 'Profiles'),
              const BottomNavigationBarItem(icon: Icon(Icons.group_outlined), label: 'Friends'),
              const BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
            ],
          ),
        ),
        const CallOverlay(),
      ],
    );
  }

  Widget _badged(IconData icon, int count) {
    if (count <= 0) return Icon(icon);
    return Badge(label: Text('$count'), child: Icon(icon));
  }
}
