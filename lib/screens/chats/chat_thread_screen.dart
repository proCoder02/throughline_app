import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../../services/conversation_service.dart';
import '../../state/listen_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/chat_list_skeleton.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/tag_chip.dart';
import '../../widgets/typing_indicator.dart';

class ChatThreadScreen extends StatefulWidget {
  final int conversationId;

  const ChatThreadScreen({super.key, required this.conversationId});

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _service = ConversationService();
  final _promptController = TextEditingController();
  final _renameController = TextEditingController();
  final _scrollController = ScrollController();

  Conversation? _conversation;
  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _offline = false;
  bool _hasText = false;
  ChatMessage? _replyingTo;

  @override
  void initState() {
    super.initState();
    _load();
    _promptController.addListener(_onPromptChanged);
  }

  void _onPromptChanged() {
    final hasText = _promptController.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  @override
  void dispose() {
    _promptController.removeListener(_onPromptChanged);
    _renameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cachedConversation = _service.getCached(widget.conversationId);
    final cachedMessages = _service.chatCached(widget.conversationId);
    if (cachedConversation != null && cachedMessages != null) {
      setState(() {
        _conversation = cachedConversation;
        _messages = cachedMessages;
        _loading = false;
      });
      _scrollToEnd(animate: false);
    }
    try {
      final conversation = await _service.get(widget.conversationId);
      final chat = await _service.chat(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _conversation = conversation;
        _messages = chat;
        _loading = false;
        _offline = false;
      });
      _scrollToEnd(animate: false);
    } catch (_) {
      // Offline/unreachable -- keep showing whatever was loaded from cache
      // above (or the loading skeleton, if there was none) rather than
      // crashing the screen.
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

  bool _isLive(ListenProvider listen) => listen.isListening && listen.conversationId == widget.conversationId;

  void _startReply(ChatMessage message) {
    setState(() => _replyingTo = message);
  }

  String _quoteSnippet(ChatMessage message) {
    final oneLine = message.content.replaceAll('\n', ' ').trim();
    return oneLine.length > 80 ? '${oneLine.substring(0, 80)}...' : oneLine;
  }

  Future<void> _send(ListenProvider listen, [String? text]) async {
    final prompt = (text ?? _promptController.text).trim();
    if (prompt.isEmpty || _sending) return;
    final replyingTo = _replyingTo;
    // No message-threading in /chat itself -- fold the quoted context into
    // the actual prompt sent to the backend so the LLM knows what "this"
    // refers to, while the user's own bubble shows just their plain text
    // plus the quote strip (see MessageBubble/_ReplyQuote).
    final promptForBackend = replyingTo == null
        ? prompt
        : 'Replying to: "${_quoteSnippet(replyingTo)}"\n\n$prompt';
    setState(() {
      _sending = true;
      _replyingTo = null;
      _messages = [
        ..._messages,
        ChatMessage(
          role: 'user',
          content: prompt,
          createdAt: DateTime.now(),
          replyToPreview: replyingTo == null ? null : _quoteSnippet(replyingTo),
        ),
      ];
    });
    _scrollToEnd();
    _promptController.clear();
    try {
      final live = _isLive(listen);
      final transcript = live
          ? [
              if ((_conversation?.rawTranscript ?? '').isNotEmpty) _conversation!.rawTranscript,
              listen.transcriptText,
            ].where((s) => s != null && s.isNotEmpty).join('\n')
          : null;
      final reply = await _service.sendChat(
        prompt: promptForBackend,
        conversationId: widget.conversationId,
        transcript: live && transcript!.isNotEmpty ? transcript : null,
      );
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, ChatMessage(role: 'assistant', content: reply, createdAt: DateTime.now())];
      });
      _scrollToEnd();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to send message')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleListen(ListenProvider listen) async {
    if (_isLive(listen)) {
      await listen.stop();
      _load();
      return;
    }
    try {
      await listen.start(resumeConversationId: widget.conversationId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not access microphone: $e')));
      }
    }
  }

  void _tapTopic(ListenProvider listen, String topic) {
    listen.removeTopic(topic);
    _send(listen, topic);
  }

  void _tapQuestion(ListenProvider listen, String question) {
    listen.removeQuestion(question);
    _send(listen, question);
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
    final listen = context.watch<ListenProvider>();
    // A pushed route -- doesn't reliably repaint on a theme change without
    // this explicit dependency (see home_shell.dart's identical comment).
    context.watch<ThemeProvider>();
    final isLive = _isLive(listen);

    if (_loading) {
      return const Scaffold(body: MessageListSkeleton());
    }
    final title = _conversation?.displayTitle ?? (isLive ? 'New conversation' : 'Untitled conversation');
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
                  isLive
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _PulsingDot(),
                            const SizedBox(width: 6),
                            Text(listen.status.isEmpty ? 'Listening' : listen.status,
                                style: const TextStyle(fontSize: 12, color: AppColors.danger),
                                overflow: TextOverflow.ellipsis),
                          ],
                        )
                      : Text('Ask about this conversation',
                          style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Column(
        children: [
          if (_offline) const OfflineBanner(),
          if (isLive && listen.seenIndices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: listen.seenIndices
                    .map((idx) => Chip(
                          label: Text(listen.speakerNames[idx] ?? 'Speaker $idx'),
                          deleteIcon: const Icon(Icons.edit, size: 16),
                          onDeleted: () => listen.openPrompt(idx),
                        ))
                    .toList(),
              ),
            ),
          if (isLive && listen.pendingSpeakerIndex != null) _renamePanel(listen, listen.pendingSpeakerIndex!),
          Expanded(
            child: _messages.isEmpty
                ? Center(child: Text('Ask a question about this conversation', style: TextStyle(color: AppColors.textSoft)))
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
          if (isLive && listen.topics.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: listen.topics
                    .map((t) => TagChip(
                          label: t,
                          onTap: () => _tapTopic(listen, t),
                          onDismiss: () => listen.removeTopic(t),
                          backgroundColor: AppColors.accent.withValues(alpha: 0.08),
                          borderColor: AppColors.accent.withValues(alpha: 0.35),
                        ))
                    .toList(),
              ),
            ),
          if (isLive && listen.questions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: listen.questions
                    .map((q) => TagChip(
                          label: q,
                          onTap: () => _tapQuestion(listen, q),
                          onDismiss: () => listen.removeQuestion(q),
                        ))
                    .toList(),
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
                            hintText: 'Ask a question...',
                            filled: true,
                            fillColor: AppColors.panel,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          ),
                          onSubmitted: (_) => _send(listen),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Mic and send occupy the same slot, WhatsApp-style: the
                      // listen button is there by default, and morphs into
                      // send the moment there's text to send, morphing back
                      // once it's sent (the text clears, _hasText goes false).
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(scale: animation, child: FadeTransition(opacity: animation, child: child)),
                        child: _hasText
                            ? CircleAvatar(
                                key: const ValueKey('send'),
                                backgroundColor: AppColors.accent,
                                child: IconButton(
                                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                                  onPressed: _sending ? null : () => _send(listen),
                                ),
                              )
                            : CircleAvatar(
                                key: const ValueKey('mic'),
                                backgroundColor: isLive ? AppColors.danger : AppColors.panel,
                                child: IconButton(
                                  icon: Icon(Icons.mic, color: isLive ? Colors.white : AppColors.accent, size: 20),
                                  tooltip: isLive ? 'Stop listening' : 'Resume listening on this conversation',
                                  onPressed: () => _toggleListen(listen),
                                ),
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

  Widget _renamePanel(ListenProvider listen, int idx) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Speaker $idx — who is this?', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (listen.knownSpeakers.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: listen.knownSpeakers
                  .map((s) => ActionChip(label: Text(s.name), onPressed: () => listen.nameSpeaker(idx, s.name)))
                  .toList(),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _renameController,
                  decoration: const InputDecoration(hintText: 'Or type a new name', isDense: true),
                  onSubmitted: (v) {
                    listen.nameSpeaker(idx, v);
                    _renameController.clear();
                  },
                ),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: listen.dismissPrompt, child: const Text('Skip')),
              ElevatedButton(
                onPressed: () {
                  listen.nameSpeaker(idx, _renameController.text);
                  _renameController.clear();
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.3).animate(_controller),
      child: const CircleAvatar(radius: 4, backgroundColor: AppColors.danger),
    );
  }
}
