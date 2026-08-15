import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart' show notifyProvider, callProvider, navigatorKey;
import '../models/friend.dart';
import '../services/api_client.dart';
import '../services/friend_service.dart';
import '../services/push_service.dart';
import '../state/notify_provider.dart';
import '../state/theme_provider.dart';
import '../widgets/call_overlay.dart';
import '../widgets/island_nav_bar.dart';
import 'chats/chat_thread_screen.dart';
import 'chats/chats_screen.dart';
import 'insights/digest_screen.dart';
import 'tasks/tasks_screen.dart';
import 'profiles/profiles_screen.dart';
import 'friends/friends_screen.dart';
import 'friends/direct_message_screen.dart';
import 'settings/settings_screen.dart';

/// Bottom-nav shell for phones (Â§2): replaces the web app's 3-pane layout.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  // WhatsApp/Telegram-style instant ticks after backgrounding: without this,
  // a WS connection dropped while backgrounded (OS network suspension, or
  // just cellular/wifi handoff) sits on whatever backoff delay happened to
  // be running when the app comes back, instead of reconnecting the moment
  // it's visible again -- see NotifySocket.forceReconnect.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      notifyProvider.forceReconnect();
    }
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
    PushService.instance.onNativeRingStarted =
        notifyProvider.markNativelyRinging;
    // Fed by MainActivity.kt's capturePendingTaskAction() when the engine is
    // already running (app backgrounded, not killed) and the user taps
    // SimpleNotificationHelper's task_created notification -- see
    // consumePendingTaskAction() below for the cold-start counterpart.
    PushService.instance.onTaskActionRequested = _openConversationForTaskAction;
    // Fed by MainActivity.kt's capturePendingDigestOpen() -- same
    // already-running-engine case as onTaskActionRequested above, for a tap
    // on SimpleNotificationHelper's digest_ready notification.
    PushService.instance.onDigestReadyTapped = _openDigestFromPush;
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

    // Cold-start counterpart to onTaskActionRequested above -- the app was
    // killed, so tapping the notification launched this Activity fresh
    // rather than delivering onNewIntent to an already-running engine.
    final pendingTaskAction = await consumePendingTaskAction();
    if (pendingTaskAction != null) _openConversationForTaskAction(pendingTaskAction);

    // Cold-start counterpart to onDigestReadyTapped above.
    final pendingDigestOpen = await consumePendingDigestOpen();
    if (pendingDigestOpen) _openDigestFromPush();

    // Connect the app-wide notify socket once, for as long as the user stays
    // in the authenticated area (this widget persists across tab switches).
    final token = await ApiClient.instance.readToken();
    if (token != null) notifyProvider.start(token);

    // FCM: reaches this device even when it's backgrounded/killed, unlike
    // the WS socket above. onIncomingCallForeground reuses the exact same
    // overlay the WS 'incoming_call' case drives, so a call rings the same
    // way regardless of which channel got there first.
    PushService.instance.onIncomingCallForeground =
        notifyProvider.handleIncomingCallPush;
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
          break;
        case 'direct_message':
          // Only sender_id/message_id ride along on this payload (see
          // send_direct_message in app.py) -- no name, so the friend has to
          // be looked up before DirectMessageScreen (which needs a full
          // Friend, not just an id) can open. WhatsApp/Telegram both land
          // you straight in the conversation from a tapped notification;
          // without this it fell back to just opening HomeShell.
          _openDirectMessageFromPush(data);
          break;
        case 'digest_ready':
          // No id/content on this payload at all (see _check_weekly_digest
          // in nudge_engine.py -- deliberately just a teaser) -- DigestScreen
          // fetches the real content itself on open, same push-is-a-teaser
          // pattern task_created/direct_message already use.
          _openDigestFromPush();
        // reminder_email_sent / friend_mood_update: landing on HomeShell is
        // enough for now -- the relevant tab's badge already reflects it
        // once the WS reconnects.
      }
    };
    unawaited(PushService.instance.registerDevice());
  }

  void _openConversationFromPush(Map<String, dynamic> data) {
    final conversationId =
        int.tryParse(data['conversation_id']?.toString() ?? '');
    if (conversationId == null) return;
    notifyProvider.clearConversation(conversationId);
    // Posted after the frame so this can't race HomeShell's own first
    // build/route (e.g. a cold start where this fires before the
    // Navigator under navigatorKey has attached its first route yet).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
            builder: (_) => ChatThreadScreen(conversationId: conversationId)),
      );
    });
  }

  Future<void> _openDirectMessageFromPush(Map<String, dynamic> data) async {
    final friendId = int.tryParse(data['sender_id']?.toString() ?? '');
    if (friendId == null) return;
    notifyProvider.clearDirectMessageBadge(friendId);

    final service = FriendService();
    Friend? friend = service.listCached()?.where((f) => f.id == friendId).firstOrNull;
    if (friend == null) {
      try {
        friend = (await service.list()).where((f) => f.id == friendId).firstOrNull;
      } catch (_) {
        // No connectivity or the lookup failed -- staying on HomeShell
        // (today's fallback for this case) beats crashing the tap handler.
      }
    }
    if (friend == null || !mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => DirectMessageScreen(friend: friend!)),
      );
    });
  }

  /// From SimpleNotificationHelper's task_created notification (see
  /// MainActivity.ACTION_TASK_OPEN/ACTION_TASK_ASK) -- "ask" distinguishes
  /// its default tap (just open the conversation) from its "Ask" action
  /// (open it AND auto-submit a question about the task).
  void _openConversationForTaskAction(Map<String, dynamic> data) {
    final conversationId = int.tryParse(data['conversation_id']?.toString() ?? '');
    if (conversationId == null) return;
    final ask = data['ask']?.toString() == 'true';
    final description = data['task_description'] as String?;
    notifyProvider.clearConversation(conversationId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(
            conversationId: conversationId,
            initialQuestion: (ask && description != null) ? 'What was said about: $description?' : null,
          ),
        ),
      );
    });
  }

  void _openDigestFromPush() {
    notifyProvider.clearDigestBadge();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const DigestScreen()),
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
    WidgetsBinding.instance.removeObserver(this);
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
                    onPressed: () => _openConversationFromPush(
                        {'conversation_id': notice.conversationId}),
                  )
                : null,
          ),
        );
      });
    }

    return Stack(
      children: [
        Scaffold(
          // Needed now that IslandNavBar is genuinely translucent (real
          // BackdropFilter transparency) -- without this, tab content stops
          // short of the nav bar's reserved slot, so there'd be nothing
          // behind it to blur/show through, just the plain scaffold
          // background color. Screens with their own FloatingActionButton
          // (ChatsScreen) compensate by padding themselves clear of
          // IslandNavBar.barHeight so their FAB doesn't end up hidden
          // behind it.
          extendBody: true,
          body: IndexedStack(
            index: _index,
            children: [
              for (var i = 0; i < _builders.length; i++)
                _visited.contains(i)
                    ? _builders[i](context)
                    : const SizedBox.shrink(),
            ],
          ),
          bottomNavigationBar: IslandNavBar(
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
              IslandNavItem(
                icon: Icons.chat_bubble_outline,
                activeIcon: Icons.chat_bubble,
                label: 'Chats',
                badgeCount: notify.unreadConversations.length,
              ),
              IslandNavItem(
                icon: Icons.check_circle_outline,
                activeIcon: Icons.check_circle,
                label: 'Tasks',
                badgeCount: notify.taskBadge,
              ),
              const IslandNavItem(
                  icon: Icons.people_outline,
                  activeIcon: Icons.people,
                  label: 'Profiles'),
              const IslandNavItem(
                  icon: Icons.group_outlined,
                  activeIcon: Icons.group,
                  label: 'Friends'),
              const IslandNavItem(
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings,
                  label: 'Settings'),
            ],
          ),
        ),
        const CallOverlay(),
      ],
    );
  }
}
