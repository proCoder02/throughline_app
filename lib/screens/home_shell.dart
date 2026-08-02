import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart' show notifyProvider;
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

  final _screens = const [
    ChatsScreen(),
    TasksScreen(),
    ProfilesScreen(),
    FriendsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Connect the app-wide notify socket once, for as long as the user stays
    // in the authenticated area (this widget persists across tab switches).
    ApiClient.instance.readToken().then((token) {
      if (token != null) notifyProvider.start(token);
    });

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
    PushService.instance.registerDevice();

    // Cover the case the notification/tap callbacks above can't: the app
    // was killed, the incoming_call background handler's full-screen-intent
    // notification cold-started us, and this is the first normal main()
    // run since -- consumePendingIncomingCall() picks up what the
    // background isolate stashed before we existed to receive it.
    consumePendingIncomingCall().then((data) {
      if (data != null) notifyProvider.handleIncomingCallPush(data);
    });
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
          body: IndexedStack(index: _index, children: _screens),
          bottomNavigationBar: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: _index,
            onTap: (i) => setState(() => _index = i),
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
