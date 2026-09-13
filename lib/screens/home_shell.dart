import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart' show notifyProvider, callProvider, navigatorKey;
import '../models/conversation.dart';
import '../models/friend.dart';
import '../services/api_client.dart';
import '../services/conversation_service.dart';
import '../services/friend_service.dart';
import '../services/push_service.dart';
import '../state/notify_provider.dart';
import '../state/theme_provider.dart';
import '../theme.dart';
import '../widgets/call_overlay.dart';
import '../widgets/island_nav_bar.dart';
import 'chats/chat_thread_screen.dart';
import 'chats/chats_screen.dart';
import 'home/home_screen.dart';
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

  // Bottom-nav is retired in favor of the side drawer below (Chats/Tasks/
  // Profiles/Friends/Settings, opened from Home's top-left menu icon) --
  // flip this back to true to restore it instantly. IslandNavBar itself
  // (widgets/island_nav_bar.dart) is untouched/still fully wired below,
  // just not rendered while this is false -- nothing was deleted.
  static const bool _showBottomNav = false;

  // Needed to open the drawer from Home's own top bar: Home renders its own
  // nested Scaffold (for its floating ask-bar), which shadows a plain
  // Scaffold.of(context) lookup from finding this outer one.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // Only the active tab's screen is actually built/initState'd -- an eager
  // IndexedStack would fire all 5 screens' initState (and their network/cache
  // calls) simultaneously the moment this widget mounts, right in the middle
  // of app startup. Once a tab has been visited its widget is kept (matching
  // IndexedStack's usual "preserve state across tab switches" behavior);
  // never-visited tabs stay an empty placeholder.
  final _visited = <int>{0};

  // Home is index 0 (new -- see home/home_screen.dart), shifting every
  // existing tab up by one. Not `static const` like before: Home's Quick
  // Actions need to switch tabs (e.g. tapping "Tasks"), which only this
  // State's own _switchTab can do -- a plain static builder has no way to
  // close over it.
  VoidCallback get _openDrawer => () => _scaffoldKey.currentState?.openDrawer();

  // Every tab's own app bar gets the same menu button now (see each
  // screen's onOpenDrawer) -- with the bottom nav gone, that's the only way
  // back to any other section (Home included) once you've navigated away.
  List<WidgetBuilder> get _builders => [
        (_) => HomeScreen(onNavigateToTab: _switchTab, onOpenDrawer: _openDrawer),
        (_) => ChatsScreen(onOpenDrawer: _openDrawer),
        (_) => TasksScreen(onOpenDrawer: _openDrawer),
        (_) => ProfilesScreen(onOpenDrawer: _openDrawer),
        (_) => FriendsScreen(onOpenDrawer: _openDrawer),
        (_) => SettingsScreen(onOpenDrawer: _openDrawer),
      ];

  void _switchTab(int i) {
    setState(() {
      _index = i;
      _visited.add(i);
      // TasksScreen (now index 2) only ever runs its own initState() (which
      // clears this) the first time the tab is visited -- see the comment
      // on _visited below.
      if (i == 2) notifyProvider.clearTaskBadge();
    });
  }

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
          key: _scaffoldKey,
          // Needed now that IslandNavBar is genuinely translucent (real
          // BackdropFilter transparency) -- without this, tab content stops
          // short of the nav bar's reserved slot, so there'd be nothing
          // behind it to blur/show through, just the plain scaffold
          // background color. Screens with their own FloatingActionButton
          // (ChatsScreen) compensate by padding themselves clear of
          // IslandNavBar.barHeight so their FAB doesn't end up hidden
          // behind it. Left on even with the bottom nav retired -- Home's
          // own floating ask-bar relies on the exact same clearance.
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
          // Chats/Tasks/Profiles/Friends/Settings live in the side drawer
          // now (see _AppDrawer below) -- attached to this same outer
          // Scaffold, so it also opens via the standard left-edge swipe
          // from any tab, not just from Home's menu icon.
          drawer: _AppDrawer(currentIndex: _index, onSelect: _switchTab, notify: notify),
          bottomNavigationBar: _showBottomNav
              ? IslandNavBar(
                  currentIndex: _index,
                  onTap: _switchTab,
                  items: [
                    const IslandNavItem(
                        icon: Icons.home_outlined,
                        activeIcon: Icons.home,
                        label: 'Home'),
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
                )
              : null,
        ),
        const CallOverlay(),
      ],
    );
  }
}

/// Side-drawer equivalent of the retired bottom nav -- same destinations and
/// badge counts, same _switchTab wiring underneath, plus Home itself (every
/// other screen's own app bar opens this same drawer, so Home needs to be
/// reachable from here too, not just by launching the app fresh). Restyled
/// to the same warm-gradient palette every main-tab screen uses (it was
/// plain Material defaults before), with no "Throughline" title (removed
/// per request -- the nav items speak for themselves), and a real Recent
/// Conversations section below Settings, ChatGPT-sidebar style.
class _AppDrawer extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final NotifyProvider notify;

  const _AppDrawer({required this.currentIndex, required this.onSelect, required this.notify});

  @override
  State<_AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<_AppDrawer> {
  final _conversationService = ConversationService();
  List<Conversation>? _recentConversations;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final conversations = await _conversationService.list();
      if (mounted) setState(() => _recentConversations = conversations.take(12).toList());
    } catch (_) {
      // Best-effort, same fail-silent-to-nothing convention as MoodTrendCard
      // -- a slow/offline fetch just means this section doesn't show yet.
      if (mounted) setState(() => _recentConversations = []);
    }
  }

  void _select(int index) {
    Navigator.of(context).pop();
    widget.onSelect(index);
  }

  void _openConversation(Conversation conversation) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatThreadScreen(conversationId: conversation.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      (0, Icons.home_outlined, 'Home', 0),
      (1, Icons.chat_bubble_outline, 'Chats', widget.notify.unreadConversations.length),
      (2, Icons.check_circle_outline, 'Tasks', widget.notify.taskBadge),
      (3, Icons.people_outline, 'Profiles', 0),
      (4, Icons.group_outlined, 'Friends', 0),
      (5, Icons.settings_outlined, 'Settings', 0),
    ];
    return Drawer(
      backgroundColor: AppColors.dmGradient.first,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.dmGradient,
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              const SizedBox(height: 8),
              for (final (index, icon, label, badge) in items)
                ListTile(
                  leading: Icon(icon, color: index == widget.currentIndex ? AppColors.dmAccent : AppColors.dmTextSoft),
                  title: Text(label,
                      style: TextStyle(
                        color: index == widget.currentIndex ? AppColors.dmAccent : AppColors.dmText,
                        fontWeight: index == widget.currentIndex ? FontWeight.w700 : FontWeight.w500,
                      )),
                  selected: index == widget.currentIndex,
                  selectedTileColor: AppColors.dmPillFill,
                  trailing: badge > 0
                      ? Badge(label: Text('$badge'), backgroundColor: AppColors.dmAccent)
                      : null,
                  onTap: () => _select(index),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.history, size: 16, color: AppColors.dmTextSoft),
                    const SizedBox(width: 8),
                    Text('Recent Conversations',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.dmTextSoft)),
                  ],
                ),
              ),
              if (_recentConversations == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                )
              else if (_recentConversations!.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Nothing recorded yet.', style: TextStyle(fontSize: 12.5, color: AppColors.dmTextSoft)),
                )
              else
                for (final conversation in _recentConversations!)
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.chat_bubble_outline, size: 18, color: AppColors.dmTextSoft),
                    title: Text(
                      conversation.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, color: AppColors.dmText),
                    ),
                    onTap: () => _openConversation(conversation),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
