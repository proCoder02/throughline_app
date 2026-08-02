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
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border, indent: 78),
              itemBuilder: (context, i) {
                final c = items[i];
                final unread = notify.unreadConversations.contains(c.id);
                return _ChatRow(
                  conversation: c,
                  unread: unread,
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

/// WhatsApp-style row: title + time share the top line, category sits below.
/// Unread state bolds the title and shows a small accent dot next to the
/// time, instead of the previous plain ListTile (which also had no
/// explicit subtitle color and read as barely-visible gray-on-white).
class _ChatRow extends StatelessWidget {
  final Conversation conversation;
  final bool unread;
  final VoidCallback onTap;

  const _ChatRow({required this.conversation, required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final category = conversation.category;
    final categoryLabel = category.isEmpty ? '' : category[0].toUpperCase() + category.substring(1);
    return Material(
      color: AppColors.panel,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialAvatar(name: conversation.displayTitle),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.displayTitle,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                              color: AppColors.text,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('MMM d, HH:mm').format(conversation.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: unread ? AppColors.accent : AppColors.textSoft,
                            fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            categoryLabel,
                            style: const TextStyle(fontSize: 13.5, color: AppColors.textSoft),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 9,
                            height: 9,
                            margin: const EdgeInsets.only(left: 8),
                            decoration: const BoxDecoration(color: AppColors.unreadBadge, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
