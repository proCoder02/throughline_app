import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart' show notifyProvider;
import '../services/api_client.dart';
import '../state/notify_provider.dart';
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
  }

  @override
  void dispose() {
    notifyProvider.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notify = context.watch<NotifyProvider>();
    return Scaffold(
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
    );
  }

  Widget _badged(IconData icon, int count) {
    if (count <= 0) return Icon(icon);
    return Badge(label: Text('$count'), child: Icon(icon));
  }
}
