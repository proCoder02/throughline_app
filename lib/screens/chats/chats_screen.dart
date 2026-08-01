import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../main.dart' show notifyProvider;
import '../../models/conversation.dart';
import '../../services/conversation_service.dart';
import '../../state/listen_provider.dart';
import '../../state/notify_provider.dart';
import '../../theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/category_menu.dart';
import 'chat_thread_screen.dart';
import 'global_chat_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final _service = ConversationService();
  late Future<List<Conversation>> _future;
  String? _category;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _future = _service.list();
  }

  void _reload() {
    final future = _service.list();
    setState(() {
      _future = future;
    });
  }

  Future<void> _toggleListen(ListenProvider listen) async {
    if (listen.isListening) {
      await listen.stop();
      _reload();
      return;
    }
    try {
      await listen.start(
        onSessionStarted: (id) {
          _reload();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ChatThreadScreen(conversationId: id)),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not access microphone: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final notify = context.watch<NotifyProvider>();
    final listen = context.watch<ListenProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [CategoryMenu(selected: _category, onChanged: (v) => setState(() => _category = v))],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'chat',
            tooltip: 'Ask about your people & conversations',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GlobalChatScreen()),
            ),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Chat'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'listen',
            backgroundColor: listen.isListening ? AppColors.danger : null,
            onPressed: () => _toggleListen(listen),
            icon: Icon(listen.isListening ? Icons.stop : Icons.mic),
            label: Text(listen.isListening ? 'Stop Listening' : 'Listen'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<Conversation>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Failed to load chats: ${snap.error}'));
            }
            var items = snap.data ?? [];
            if (_category != null) items = items.where((c) => c.category == _category).toList();
            if (_search.isNotEmpty) {
              items = items.where((c) => c.displayTitle.toLowerCase().contains(_search)).toList();
            }
            if (items.isEmpty) {
              return const Center(child: Text('No conversations yet', style: TextStyle(color: AppColors.textSoft)));
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, i) {
                final c = items[i];
                final unread = notify.unreadConversations.contains(c.id);
                return ListTile(
                  tileColor: AppColors.panel,
                  leading: InitialAvatar(name: c.displayTitle),
                  title: Text(c.displayTitle),
                  subtitle: Text(DateFormat('MMM d, HH:mm').format(c.createdAt)),
                  trailing: unread
                      ? const CircleAvatar(radius: 5, backgroundColor: AppColors.unreadBadge)
                      : null,
                  onTap: () {
                    notifyProvider.clearConversation(c.id);
                    Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => ChatThreadScreen(conversationId: c.id)));
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
