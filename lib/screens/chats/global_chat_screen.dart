import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../services/conversation_service.dart';
import '../../theme.dart';
import '../../widgets/message_bubble.dart';

/// Persistent cross-session thread (§6): "what did I discuss with Rahul
/// last week?" -- scoped to the whole account, not one conversation.
class GlobalChatScreen extends StatefulWidget {
  const GlobalChatScreen({super.key});

  @override
  State<GlobalChatScreen> createState() => _GlobalChatScreenState();
}

class _GlobalChatScreenState extends State<GlobalChatScreen> {
  final _service = ConversationService();
  final _promptController = TextEditingController();
  final _scrollController = ScrollController();

  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final messages = await _service.globalChat();
    if (!mounted) return;
    setState(() {
      _messages = messages;
      _loading = false;
    });
  }

  Future<void> _send() async {
    final text = _promptController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _messages = [..._messages, ChatMessage(role: 'user', content: text, createdAt: DateTime.now())];
    });
    _promptController.clear();
    try {
      final reply = await _service.sendGlobalChat(text);
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, ChatMessage(role: 'assistant', content: reply, createdAt: DateTime.now())];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          ChatMessage(role: 'assistant', content: 'Request failed.', createdAt: DateTime.now()),
        ];
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.chatBg,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ask about your people & conversations'),
            Text('Ask across everything you\'ve recorded',
                style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              "Ask about a person or a past topic -- I'll pull in whichever conversations are relevant.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSoft),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) => MessageBubble(message: _messages[i]),
                        ),
                ),
                SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    color: AppColors.bgApp,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _promptController,
                            decoration: InputDecoration(
                              hintText: 'e.g. "What did I discuss with Rahul last week?"',
                              filled: true,
                              fillColor: AppColors.panel,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          backgroundColor: AppColors.accent,
                          child: IconButton(
                            icon: _sending
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.send, color: Colors.white, size: 20),
                            onPressed: _sending ? null : _send,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
