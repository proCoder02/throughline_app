import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../../services/conversation_service.dart';
import '../../theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/message_bubble.dart';

class ChatThreadScreen extends StatefulWidget {
  final int conversationId;

  const ChatThreadScreen({super.key, required this.conversationId});

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _service = ConversationService();
  final _promptController = TextEditingController();
  final _scrollController = ScrollController();

  Conversation? _conversation;
  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final conversation = await _service.get(widget.conversationId);
    final chat = await _service.chat(widget.conversationId);
    if (!mounted) return;
    setState(() {
      _conversation = conversation;
      _messages = chat;
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
      final reply = await _service.sendChat(prompt: text, conversationId: widget.conversationId);
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, ChatMessage(role: 'assistant', content: reply, createdAt: DateTime.now())];
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to send message')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showTranscript() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Raw transcript', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Text(_conversation?.rawTranscript ?? '(no transcript)'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text('This deletes the conversation and its chat history. Tasks and profiles from it are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _service.delete(widget.conversationId);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final title = _conversation?.displayTitle ?? 'Untitled conversation';
    return Scaffold(
      backgroundColor: AppColors.chatBg,
      appBar: AppBar(
        title: Row(
          children: [
            InitialAvatar(name: title, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, overflow: TextOverflow.ellipsis),
                  const Text('Ask about this conversation',
                      style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.info_outline), onPressed: _showTranscript),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Text('Ask a question about this conversation', style: TextStyle(color: AppColors.textSoft)))
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
                        hintText: 'Ask a question...',
                        filled: true,
                        fillColor: AppColors.panel,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
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
                              height: 16, width: 16,
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
