import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/chat_message.dart';
import '../../services/conversation_service.dart';
import '../../state/theme_provider.dart';
import '../../theme.dart';
import '../../widgets/chat_list_skeleton.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/typing_indicator.dart';

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
  bool _offline = false;
  ChatMessage? _replyingTo;

  void _startReply(ChatMessage message) {
    setState(() => _replyingTo = message);
  }

  String _quoteSnippet(ChatMessage message) {
    final oneLine = message.content.replaceAll('\n', ' ').trim();
    return oneLine.length > 80 ? '${oneLine.substring(0, 80)}...' : oneLine;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = _service.globalChatCached();
    if (cached != null) {
      setState(() {
        _messages = cached;
        _loading = false;
      });
      _scrollToEnd(animate: false);
    }
    try {
      final messages = await _service.globalChat();
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
        _offline = false;
      });
      _scrollToEnd(animate: false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _offline = true;
        });
      }
    }
  }

  void _scrollToEnd({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _send() async {
    final text = _promptController.text.trim();
    if (text.isEmpty || _sending) return;
    final replyingTo = _replyingTo;
    // No message-threading in /chat/global itself -- fold the quoted
    // context into the actual prompt sent to the backend so the LLM knows
    // what "this" refers to, while the user's own bubble shows just their
    // plain text plus the quote strip (see MessageBubble/_ReplyQuote).
    final textForBackend = replyingTo == null ? text : 'Replying to: "${_quoteSnippet(replyingTo)}"\n\n$text';
    setState(() {
      _sending = true;
      _replyingTo = null;
      _messages = [
        ..._messages,
        ChatMessage(
          role: 'user',
          content: text,
          createdAt: DateTime.now(),
          replyToPreview: replyingTo == null ? null : _quoteSnippet(replyingTo),
        ),
      ];
    });
    _scrollToEnd();
    _promptController.clear();
    try {
      final reply = await _service.sendGlobalChat(textForBackend);
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, ChatMessage(role: 'assistant', content: reply, createdAt: DateTime.now())];
      });
      _scrollToEnd();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          ChatMessage(role: 'assistant', content: 'Request failed.', createdAt: DateTime.now()),
        ];
      });
      _scrollToEnd();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    return Scaffold(
      backgroundColor: AppColors.chatBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ask about your people & conversations'),
            Text('Ask across everything you\'ve recorded',
                style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
          ],
        ),
      ),
      body: _loading
          ? const MessageListSkeleton()
          : Column(
              children: [
                if (_offline) const OfflineBanner(),
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
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
                          itemCount: _messages.length + (_sending ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i == _messages.length) return const TypingIndicator();
                            final message = _messages[i];
                            return MessageBubble(message: message, onReply: () => _startReply(message));
                          },
                        ),
                ),
                SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    color: AppColors.bgApp,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_replyingTo != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.panel,
                              borderRadius: BorderRadius.circular(8),
                              border: const Border(left: BorderSide(color: AppColors.accent, width: 3)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _quoteSnippet(_replyingTo!),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: AppColors.textSoft, fontSize: 12.5),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => setState(() => _replyingTo = null),
                                ),
                              ],
                            ),
                          ),
                        Row(
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
                                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                                onPressed: _sending ? null : _send,
                              ),
                            ),
                          ],
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
