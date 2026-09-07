import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/direct_message.dart';
import '../../models/friend.dart';
import '../../services/friend_service.dart';
import '../../services/message_service.dart';
import '../../services/upload_service.dart';
import '../../state/auth_provider.dart';
import '../../state/notify_provider.dart';
import '../../theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/photo_viewer.dart';
import '../../widgets/tap_bounce.dart';

/// Best-effort file-extension -> MIME type -- good enough for R2's content
/// type and for this screen's own image/video/file branching; a wrong
/// guess for an obscure document extension only affects how a browser
/// treats the download, never whether the upload/send itself works (the
/// backend's chat_file purpose accepts any content type -- see storage.py).
String _guessMimeType(String path) {
  final ext = path.split('.').last.toLowerCase();
  const map = {
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp', 'gif': 'image/gif',
    'mp4': 'video/mp4', 'mov': 'video/quicktime', 'webm': 'video/webm',
    'pdf': 'application/pdf', 'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'txt': 'text/plain', 'zip': 'application/zip',
  };
  return map[ext] ?? 'application/octet-stream';
}

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

class _DirectMessageScreenState extends State<DirectMessageScreen> with SingleTickerProviderStateMixin {
  final _service = MessageService();
  final _friendService = FriendService();
  final _uploadService = UploadService();
  final _imagePicker = ImagePicker();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  List<DirectMessage>? _messages;
  bool _loading = true;
  bool _sending = false;
  Object? _loadError;
  bool _offline = false;
  bool _hasText = false;

  // Only messages at/after this index get the entrance fade+slide (see
  // _MessageBubble below) -- set once, from whichever load path (cache or
  // network) fills _messages first, so the existing history never
  // re-plays its "arriving" animation on every rebuild, only genuinely new
  // messages appended afterward (live WS/send) do.
  int _animateFromIndex = 0;
  bool _baselineSet = false;

  void _setAnimationBaseline(int length) {
    if (_baselineSet) return;
    _baselineSet = true;
    _animateFromIndex = length;
  }

  // Object storage (Cloudflare R2) attachments -- see MEDIA_STORAGE_PLAN.md.
  // Same null-until-known/hide-if-disabled pattern as every other gated
  // feature in this app (GET /uploads/status).
  bool _uploadsEnabled = false;
  bool _uploadingAttachment = false;
  double _uploadProgress = 0;

  // -- Cognitive Sharing (Phase 2/3) --------------------------------------
  bool _cognitiveSharingAvailable = false; // both sides >= 'limited' -- gates the AppBar action
  bool _requestingSuggestion = false;
  CognitiveSuggestion? _suggestion;

  // Event-driven auto-check: counts new messages (sent or received) since
  // the last check, not wall-clock time -- an automatic re-check only ever
  // fires when there's actually new conversation to reason about, so cost
  // scales with real activity rather than a fixed polling interval. The
  // pulse threshold is deliberately lower than the auto-fire one so the
  // icon visibly "builds up" before the automatic check actually happens,
  // rather than the suggestion just appearing with no warning.
  static const _pulseAttentionThreshold = 3;
  static const _autoCheckThreshold = 6;
  int _messagesSinceLastCheck = 0;
  late final AnimationController _pulseController;

  bool get _shouldPulse =>
      _cognitiveSharingAvailable &&
      _suggestion == null &&
      !_requestingSuggestion &&
      _messagesSinceLastCheck >= _pulseAttentionThreshold;

  late final NotifyProvider _notify;
  int? _myUserId;
  DateTime? _lastTypingSentAt;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
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
      _setAnimationBaseline(cached.length);
    }
    _load();
    _markRead();
    _loadCognitiveSharingAvailability();
    _loadLatestSuggestion();
    _uploadService.status().then((s) {
      if (mounted) setState(() => _uploadsEnabled = s['enabled'] == true);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _notify.setActiveDirectMessageFriend(null);
    _notify.removeListener(_onNotify);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Bumps the event-driven counter and silently auto-fires a check once it
  /// crosses the threshold -- "silent" meaning no SnackBar if it turns out
  /// there's nothing to suggest, unlike a manual tap.
  void _bumpMessageActivity(int count) {
    if (!_cognitiveSharingAvailable || count <= 0 || _suggestion != null) return;
    setState(() => _messagesSinceLastCheck += count);
    if (_messagesSinceLastCheck >= _autoCheckThreshold && !_requestingSuggestion) {
      _findCommonGround(silent: true);
    }
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
      _bumpMessageActivity(incoming.length);
    }
    if (_notify.hasPendingCognitiveSuggestion(widget.friend.id)) {
      _notify.clearPendingCognitiveSuggestion(widget.friend.id);
      _loadLatestSuggestion();
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
        _setAnimationBaseline(items.length);
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

  Future<void> _loadCognitiveSharingAvailability() async {
    try {
      final status = await _friendService.getCognitiveSharing(widget.friend.id);
      if (mounted) setState(() => _cognitiveSharingAvailable = status.bothEnabled);
    } catch (_) {
      // Offline/unreachable -- action stays hidden rather than showing
      // something that would just 403 if tapped.
    }
  }

  /// Picks up a suggestion that already exists for this pair -- either from
  /// before this screen opened, or right after a 'cognitive_suggestion' WS
  /// event tells us one exists (see _onNotify above).
  Future<void> _loadLatestSuggestion() async {
    try {
      final suggestion = await _friendService.getLatestCognitiveSuggestion(widget.friend.id);
      if (mounted && suggestion != null && !suggestion.dismissed) {
        setState(() => _suggestion = suggestion);
      }
    } catch (_) {
      // Not friends anymore, offline, etc. -- just don't show a card.
    }
  }

  Future<void> _findCommonGround({bool silent = false}) async {
    if (_requestingSuggestion) return;
    setState(() => _requestingSuggestion = true);
    try {
      final suggestion = await _friendService.requestCognitiveSuggestion(widget.friend.id);
      if (!mounted) return;
      setState(() {
        _requestingSuggestion = false;
        _messagesSinceLastCheck = 0;
        if (suggestion != null) _suggestion = suggestion;
      });
      if (suggestion == null && !silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing to suggest right now.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _requestingSuggestion = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not check: $e')));
      }
    }
  }

  Future<void> _dismissSuggestion() async {
    final suggestion = _suggestion;
    if (suggestion == null) return;
    setState(() => _suggestion = null); // optimistic -- this is a low-stakes, easily-repeatable action
    try {
      await _friendService.dismissCognitiveSuggestion(widget.friend.id, suggestion.id);
    } catch (_) {
      // Not worth surfacing an error for a dismiss -- worst case it reappears
      // on next load, which is harmless.
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    HapticFeedback.lightImpact();
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
      _bumpMessageActivity(1);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send: $e')));
    }
  }

  /// Bottom sheet offering the three attachment kinds -- mirrors the
  /// existing vision-chat feature's picker but with a second/third option
  /// (video, file) that feature never needed.
  Future<void> _pickAttachment() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_outlined),
            title: const Text('Photo'),
            onTap: () => Navigator.of(ctx).pop('image'),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: const Text('Video'),
            onTap: () => Navigator.of(ctx).pop('video'),
          ),
          ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: const Text('Document'),
            onTap: () => Navigator.of(ctx).pop('file'),
          ),
        ]),
      ),
    );
    if (kind == null || !mounted) return;

    File file;
    String mimeType;
    if (kind == 'image') {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (picked == null) return;
      file = File(picked.path);
      mimeType = _guessMimeType(picked.path);
    } else if (kind == 'video') {
      final picked = await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;
      file = File(picked.path);
      mimeType = _guessMimeType(picked.path);
    } else {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      final path = result?.files.single.path;
      if (path == null) return;
      file = File(path);
      mimeType = _guessMimeType(path);
    }
    if (!mounted) return;

    final caption = await _showAttachmentPreviewSheet(file, kind);
    if (caption == null) return; // cancelled
    _sendAttachment(file, kind, mimeType, caption);
  }

  /// WhatsApp-style preview-before-send, same shape as the vision-chat
  /// feature's sheet -- but the caption here is optional (an attachment
  /// with no caption is a normal, complete message), not required.
  Future<String?> _showAttachmentPreviewSheet(File file, String kind) {
    final controller = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (kind == 'image')
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(file, height: 200, fit: BoxFit.cover),
                  )
                else
                  Container(
                    height: 80,
                    decoration: BoxDecoration(color: AppColors.panel, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Icon(kind == 'video' ? Icons.videocam_outlined : Icons.insert_drive_file_outlined,
                            color: AppColors.textSoft),
                        const SizedBox(width: 12),
                        Expanded(child: Text(file.path.split(Platform.pathSeparator).last, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 16),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Add a caption (optional)',
                    filled: true,
                    fillColor: AppColors.panel,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(controller.text.trim()),
                        child: const Text('Send'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Requires being online now -- unlike a plain text message, an
  /// attachment's bytes can't be queued for a later retry without keeping
  /// the whole file on-device for a background upload, which is real added
  /// complexity for a case (losing connectivity mid-pick) rare enough to
  /// just ask the user to try again.
  Future<void> _sendAttachment(File file, String kind, String mimeType, String caption) async {
    setState(() {
      _uploadingAttachment = true;
      _uploadProgress = 0;
    });
    try {
      final purpose = kind == 'image' ? 'chat_image' : (kind == 'video' ? 'chat_video' : 'chat_file');
      final objectKey = await _uploadService.uploadFile(
        file, purpose, mimeType,
        onProgress: (p) { if (mounted) setState(() => _uploadProgress = p); },
      );
      final attachmentUrl = await _uploadService.confirmUpload(objectKey, purpose);
      // Only images get a real thumbnail (see MEDIA_STORAGE_PLAN.md) --
      // video/file attachments render as a plain download card instead of
      // needing a captured frame, which would need extra packages
      // (video_thumbnail/video_player) this app doesn't have yet.
      String? thumbnailDataUrl;
      if (kind == 'image') {
        try {
          thumbnailDataUrl = await _uploadService.makeThumbnailDataUrl(file);
        } catch (_) {
          thumbnailDataUrl = null; // no thumbnail is a degraded-but-fine outcome, not a failed send
        }
      }
      final message = await _service.send(
        widget.friend.id, caption,
        attachmentUrl: attachmentUrl, attachmentType: mimeType, thumbnailDataUrl: thumbnailDataUrl,
      );
      if (!mounted) return;
      setState(() {
        _messages = [...(_messages ?? []), message];
      });
      _scrollToBottom();
      _bumpMessageActivity(1);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send attachment: $e')));
    } finally {
      if (mounted) setState(() => _uploadingAttachment = false);
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
            GestureDetector(
              onTap: widget.friend.profilePictureUrl != null
                  ? () => showPhotoViewer(context, imageUrl: widget.friend.profilePictureUrl!)
                  : null,
              child: InitialAvatar(name: widget.friend.displayName, size: 34, imageUrl: widget.friend.profilePictureUrl),
            ),
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
        actions: [
          if (_cognitiveSharingAvailable) _buildSharingAction(),
        ],
      ),
      body: Column(
        children: [
          if (_offline) const OfflineBanner(),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            transitionBuilder: (child, animation) => SizeTransition(
              sizeFactor: animation,
              alignment: const Alignment(0, -1),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: _suggestion != null
                ? _CognitiveSuggestionCard(
                    key: ValueKey(_suggestion!.id),
                    suggestion: _suggestion!,
                    onDismiss: _dismissSuggestion,
                  )
                : const SizedBox.shrink(key: ValueKey('no-suggestion')),
          ),
          Expanded(child: _buildList()),
          SafeArea(child: _buildInputBar()),
        ],
      ),
    );
  }

  /// The brain icon builds up a pulsing glow as new messages accumulate
  /// (see _pulseAttentionThreshold) -- a visible "something might be worth
  /// checking" cue that resolves itself automatically once
  /// _autoCheckThreshold is hit, rather than requiring the user to notice
  /// and remember to tap it every time.
  Widget _buildSharingAction() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = _shouldPulse ? _pulseController.value : 0.0;
        return Transform.scale(
          scale: 1 + pulse * 0.12,
          child: Container(
            decoration: pulse > 0
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.4 * pulse),
                        blurRadius: 8 + 8 * pulse,
                        spreadRadius: 1 + 2 * pulse,
                      ),
                    ],
                  )
                : null,
            child: child,
          ),
        );
      },
      child: IconButton(
        icon: _requestingSuggestion
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.psychology_outlined, color: _shouldPulse ? AppColors.accent : null),
        tooltip: 'Find common ground',
        onPressed: _requestingSuggestion ? null : _findCommonGround,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_uploadingAttachment)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: LinearProgressIndicator(value: _uploadProgress, minHeight: 3),
            ),
          Row(
            children: [
              if (_uploadsEnabled)
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  color: AppColors.textSoft,
                  tooltip: 'Attach a photo, video, or file',
                  onPressed: _uploadingAttachment ? null : _pickAttachment,
                ),
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
        ],
      ),
    );
  }
}

/// A dismissible banner for an on-demand "find common ground" result --
/// deliberately NOT a message bubble in the thread itself (matching Google
/// Messages' "visible only to you" precedent cited in
/// COGNITIVE_SHARING_INTERVENTION_PLAN.md): each side dismisses it
/// independently, and it never becomes part of either person's permanent
/// message history.
class _CognitiveSuggestionCard extends StatelessWidget {
  final CognitiveSuggestion suggestion;
  final VoidCallback onDismiss;

  const _CognitiveSuggestionCard({super.key, required this.suggestion, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.psychology_outlined, size: 18, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(suggestion.suggestionText, style: TextStyle(fontSize: 13.5, color: AppColors.text)),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
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
            if (message.attachmentUrl != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _AttachmentContent(
                  url: message.attachmentUrl!,
                  type: message.attachmentType,
                  thumbnailDataUrl: message.thumbnailDataUrl,
                  summary: message.attachmentSummary,
                ),
              ),
            if (message.content.isNotEmpty) ...[
              Text(message.content, style: TextStyle(fontSize: 15, color: AppColors.text)),
              const SizedBox(height: 3),
            ],
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

/// Renders an R2-backed attachment (see MEDIA_STORAGE_PLAN.md) by MIME
/// type. Images show `thumbnailDataUrl` immediately (decoded inline, no
/// network wait) and swap to the full network image once it loads; video
/// and generic files render as a tappable download/open card (no inline
/// video playback in this pass -- that needs video_player/video_thumbnail,
/// which aren't dependencies of this app yet). If the full-resolution
/// `url` 404s (e.g. expired off R2 via an Object Lifecycle Rule), an image
/// falls back to just the thumbnail with a small label instead of
/// Flutter's default broken-image icon.
class _AttachmentContent extends StatefulWidget {
  final String url;
  final String? type;
  final String? thumbnailDataUrl;
  // Cognitive Sharing add-on: a 20-30 word summary, present only when both
  // people in this DM pair have sharing turned on (see DirectMessage's own
  // doc comment and app.py's _generate_attachment_summary).
  final String? summary;

  const _AttachmentContent({required this.url, this.type, this.thumbnailDataUrl, this.summary});

  @override
  State<_AttachmentContent> createState() => _AttachmentContentState();
}

class _AttachmentContentState extends State<_AttachmentContent> {
  bool _broken = false;

  @override
  Widget build(BuildContext context) {
    final type = widget.type ?? '';

    if (type.startsWith('image/')) {
      if (_broken) {
        if (widget.thumbnailDataUrl == null) {
          return Text('Photo no longer available', style: TextStyle(fontSize: 12.5, color: AppColors.textSoft));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Opacity(
              opacity: 0.6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(base64Decode(widget.thumbnailDataUrl!.split(',').last), fit: BoxFit.cover),
              ),
            ),
            Text('Photo no longer available', style: TextStyle(fontSize: 11, color: AppColors.textSoft)),
          ],
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240, maxHeight: 320),
          child: Image.network(
            widget.url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              // Can't call setState during build -- defer to next frame.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _broken = true);
              });
              return widget.thumbnailDataUrl != null
                  ? Image.memory(base64Decode(widget.thumbnailDataUrl!.split(',').last), fit: BoxFit.cover)
                  : const SizedBox(width: 160, height: 120);
            },
          ),
        ),
      );
    }

    final isVideo = type.startsWith('video/');
    final segments = Uri.tryParse(widget.url)?.pathSegments ?? const <String>[];
    final filename = segments.isNotEmpty ? segments.last : 'file';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.bgApp,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isVideo ? Icons.videocam_outlined : Icons.insert_drive_file_outlined, size: 20, color: AppColors.textSoft),
                const SizedBox(width: 8),
                Flexible(child: Text(isVideo ? 'Video' : filename, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                const SizedBox(width: 6),
                Icon(Icons.open_in_new, size: 14, color: AppColors.textSoft),
              ],
            ),
          ),
        ),
        if (widget.summary != null && widget.summary!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.psychology_outlined, size: 13, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.summary!,
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textSoft, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
