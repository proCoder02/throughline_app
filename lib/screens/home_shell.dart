import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart' show notifyProvider, callProvider, navigatorKey;
import '../services/api_client.dart';
import '../services/push_service.dart';
import '../state/notify_provider.dart';
import '../state/theme_provider.dart';
import '../widgets/call_overlay.dart';
import 'chats/chat_thread_screen.dart';
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
      switch (data['type']) {
        case 'incoming_call':
          notifyProvider.handleIncomingCallPush(data);
          break;
        case 'task_created':
        case 'call_conversation_ready':
        case 'conversation_created':
          // All three carry conversation_id -- there's no dedicated task
          // detail screen (see task_service.dart/tasks_screen.dart), so a
          // tapped task notification opens its source conversation, same as
          // the existing "view source conversation" icon already does on
          // the Tasks tab.
          _openConversationFromPush(data);
        // reminder_email_sent / friend_mood_update: landing on HomeShell is
        // enough for now -- the relevant tab's badge already reflects it
        // once the WS reconnects.
      }
    };
    unawaited(PushService.instance.registerDevice());
  }

  void _openConversationFromPush(Map<String, dynamic> data) {
    final conversationId = int.tryParse(data['conversation_id']?.toString() ?? '');
    if (conversationId == null) return;
    notifyProvider.clearConversation(conversationId);
    // Posted after the frame so this can't race HomeShell's own first
    // build/route (e.g. a cold start where this fires before the
    // Navigator under navigatorKey has attached its first route yet).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => ChatThreadScreen(conversationId: conversationId)),
      );
    });
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
    // Establishes a real Provider dependency so this (and everything it
    // builds fresh below, including every IndexedStack tab) reliably
    // rebuilds the instant dark/light mode changes -- a plain global flag
    // read with no listener attached doesn't reliably propagate through
    // Flutter's Navigator/Overlay machinery on its own (a known gotcha:
    // already-pushed routes especially don't reliably repaint just because
    // an ancestor happened to rebuild), which is what made toggling the
    // setting feel glitchy/inconsistent before this.
    context.watch<ThemeProvider>();

    // A new task/conversation while the app is open previously only ever
    // showed up as a silent badge increment -- easy to miss entirely if
    // you're not already looking at that tab. This is the visible
    // heads-up, sourced from the live WS channel (already the reliable one
    // while foregrounded) rather than duplicating it via the FCM foreground
    // listener too. Scheduled after this frame, not shown directly here,
    // since triggering a SnackBar mid-build isn't safe.
    final notice = notify.foregroundNotice;
    if (notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyProvider.clearForegroundNotice();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(notice.message),
            action: notice.conversationId != null
                ? SnackBarAction(
                    label: 'View',
                    onPressed: () => _openConversationFromPush({'conversation_id': notice.conversationId}),
                  )
                : null,
          ),
        );
      });
    }

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
              // TasksScreen only ever runs its own initState() (which
              // clears this) the first time the tab is visited -- the
              // IndexedStack above deliberately keeps it alive afterward
              // (see the comment on _visited), so a badge from a task
              // created after that first visit never cleared on later
              // visits without this.
              if (i == 1) notifyProvider.clearTaskBadge();
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
