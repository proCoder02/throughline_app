import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/direct_message.dart';
import '../../models/friend.dart';
import '../../services/message_service.dart';
import '../../state/auth_provider.dart';
import '../../state/notify_provider.dart';
import '../../theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/tap_bounce.dart';

/// Real-time 1:1 text chat with a friend -- distinct from ChatThreadScreen
/// (which is a solo Listen conversation's LLM Q&A). Cache-first load (same
/// pattern as every other list screen in this app) for an instant first
/// paint, live updates via NotifyProvider's WS-fed pending-message queue
/// while this screen is open, and a foreground-notification suppression
/// flag so you don't get notified about the thread you're already looking at.
class DirectMessageScreen extends StatefulWidget {
  final Friend friend;

  const DirectMessageScreen({super.key, required this.friend});

  @override
  State<DirectMessageScreen> createState() => _DirectMessageScreenState();
}

class _DirectMessageScreenState extends State<DirectMessageScreen> {
  final _service = MessageService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  List<DirectMessage>? _messages;
  bool _loading = true;
  bool _sending = false;
  Object? _loadError;
  bool _offline = false;
  bool _hasText = false;

  late final NotifyProvider _notify;
  int? _myUserId;
  DateTime? _lastTypingSentAt;

  @override
  void initState() {
    super.initState();
    _notify = context.read<NotifyProvider>();
    _notify.setActiveDirectMessageFriend(widget.friend.id);
    _notify.addListener(_onNotify);
    _myUserId = context.read<AuthProvider>().userId;
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
      if (hasText) _maybeSendTyping();
    });

    final cached = _service.historyCached(widget.friend.id);
    if (cached != null) {
      _messages = cached;
      _loading = false;
    }
    _load();
    _markRead();
  }

  @override
  void dispose() {
    _notify.setActiveDirectMessageFriend(null);
    _notify.removeListener(_onNotify);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onNotify() {
    final incoming = _notify.drainPendingDirectMessages(widget.friend.id);
    final readIds = _notify.drainReadReceipts(widget.friend.id);
    final deliveredIds = _notify.drainDeliveryReceipts(widget.friend.id);
    // Always rebuild, not just when this friend's messages/receipts changed
    // -- NotifyProvider.notifyListeners() also fires for the "typing" timer
    // expiring and for a fresh 'friend_typing' event, neither of which has
    // anything to drain here, but both need this screen's AppBar to
    // re-render (it reads _notify.isFriendTyping directly in build()).
    setState(() {
      var updated = _messages ?? [];
      if (readIds.isNotEmpty) {
        final readSet = readIds.toSet();
        updated = updated.map((m) => readSet.contains(m.id) ? m.copyWith(readAt: DateTime.now()) : m).toList();
      }
      if (deliveredIds.isNotEmpty) {
        final deliveredSet = deliveredIds.toSet();
        updated = updated.map((m) => deliveredSet.contains(m.id) ? m.copyWith(deliveredAt: DateTime.now()) : m).toList();
      }
      _messages = [...updated, ...incoming];
    });
    if (incoming.isNotEmpty) {
      _markRead(); // arrived while the thread was already open -- read immediately
      _scrollToBottom();
    }
  }

  /// Debounced client-side: only actually sends a 'typing' signal once every
  /// _typingSendInterval while the user keeps typing, not on every keystroke
  /// -- the recipient's own indicator already stays up for 3s per signal
  /// (see NotifyProvider._typingTimeout), so re-sending more often than that
  /// would just be wasted traffic.
  static const _typingSendInterval = Duration(seconds: 2);

  void _maybeSendTyping() {
    final now = DateTime.now();
    if (_lastTypingSentAt != null && now.difference(_lastTypingSentAt!) < _typingSendInterval) return;
    _lastTypingSentAt = now;
    _notify.sendTyping(widget.friend.id);
  }

  Future<void> _load() async {
    try {
      final items = await _service.history(widget.friend.id);
      if (!mounted) return;
      setState(() {
        _messages = items;
        _loading = false;
        _loadError = null;
        _offline = false;
      });
      // Safety-net backfill: NotifyProvider's ackDelivered already fires for
      // every live/reconnect-replayed 'direct_message' event (see its own
      // case in _handle), which covers the normal case -- this only matters
      // if the pending-event queue itself capped out (very long offline
      // stretch, more than its 50-event limit) and some older messages from
      // this friend never got a chance to trigger that. ackDelivered is
      // idempotent server-side (only touches still-NULL rows), so calling
      // it again here even when everything's already acked is a no-op.
      if (items.any((m) => !m.sentByMe(_myUserId ?? -1) && m.deliveredAt == null)) {
        _notify.ackDelivered(widget.friend.id);
      }
      _scrollToBottom(jump: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _offline = true;
        if (_messages == null) _loadError = e;
      });
    }
  }

  Future<void> _markRead() async {
    _notify.ackRead(widget.friend.id);
    _notify.clearDirectMessageBadge(widget.friend.id);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    _controller.clear();
    setState(() => _sending = true);
    try {
      final message = await _service.send(widget.friend.id, text);
      if (!mounted) return;
      setState(() {
        _messages = [...(_messages ?? []), message];
        _sending = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send: $e')));
    }
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(
        title: Row(
          children: [
            InitialAvatar(name: widget.friend.displayName, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.friend.displayName, overflow: TextOverflow.ellipsis),
                  if (_notify.isFriendTyping(widget.friend.id))
                    const Text(
                      'typing...',
                      style: TextStyle(fontSize: 12.5, color: AppColors.accent, fontWeight: FontWeight.w500),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_offline) const OfflineBanner(),
          Expanded(child: _buildList()),
          SafeArea(child: _buildInputBar()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_messages == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return Center(child: Text('Failed to load messages: $_loadError'));
    }
    if (_messages!.isEmpty) {
      return Center(
        child: Text('Say hello to ${widget.friend.displayName}', style: TextStyle(color: AppColors.textSoft)),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      itemCount: _messages!.length,
      itemBuilder: (context, i) => _MessageBubble(message: _messages![i], mine: _messages![i].sentByMe(_myUserId ?? -1)),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Message', isDense: true),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          TapBounce(
            child: Material(
              color: _hasText ? AppColors.accent : AppColors.border,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _hasText && !_sending ? _send : null,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: _sending
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(Icons.send_rounded, color: _hasText ? Colors.white : AppColors.textSoft, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single tick (sent) -> double grey (delivered, reached their device) ->
/// double blue (read, they opened it) -- WhatsApp/Telegram's exact model.
class _Tick extends StatelessWidget {
  final TickState state;
  const _Tick({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state == TickState.sent) {
      return Icon(Icons.done, size: 14, color: AppColors.textSoft);
    }
    return Icon(
      Icons.done_all,
      size: 14,
      color: state == TickState.read ? AppColors.accent : AppColors.textSoft,
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final DirectMessage message;
  final bool mine;

  const _MessageBubble({required this.message, required this.mine});

  String _time(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${dt.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 6),
        decoration: BoxDecoration(
          color: mine ? AppColors.bubbleOut : AppColors.bubbleIn,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(mine ? 12 : 2),
            bottomRight: Radius.circular(mine ? 2 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message.content, style: TextStyle(fontSize: 15, color: AppColors.text)),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_time(message.createdAt), style: TextStyle(fontSize: 11, color: AppColors.textSoft)),
                if (mine) ...[
                  const SizedBox(width: 3),
                  _Tick(state: message.tickState),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
