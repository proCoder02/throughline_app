import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/chat_message.dart';
import '../../services/conversation_service.dart';
import '../../services/home_signals_service.dart';
import '../../theme.dart';
import '../../widgets/chat_list_skeleton.dart';
import '../../widgets/dissolving_typing_indicator.dart';
import '../../widgets/glowing_border.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/offline_banner.dart';

/// The actual persistent cross-session chat (§6) -- extracted out of
/// GlobalChatScreen so the exact same real logic (load/send/image-attach/
/// location-aware prompts/reply-quoting) can be embedded directly in
/// HomeScreen instead of only reachable by pushing a whole new route. All
/// state/behavior here is unchanged from the original GlobalChatScreen;
/// only the surrounding Scaffold/AppBar/gradient were peeled off, since an
/// embedded instance lives inside whatever screen hosts it instead of
/// owning the page.
class GlobalChatBody extends StatefulWidget {
  /// When set, a compact header row (back arrow + title) is shown above the
  /// thread and this fires instead of a Navigator pop -- lets an embedding
  /// screen (HomeScreen) swap this back out for its own content in place,
  /// with no page route involved at all. Null when GlobalChatScreen hosts
  /// this as a real pushed route (its own AppBar already provides back).
  final VoidCallback? onBack;

  /// Opens the image picker the instant this mounts -- wired from Home's
  /// "Add Attachment" quick action, which should land the user straight in
  /// the picker rather than an extra tap once the thread appears.
  final bool autoPickImage;

  /// Sent to /chat/global automatically once history has loaded -- wired
  /// from Home's "View Summary" button, so tapping it lands straight on an
  /// LLM reply grounded in that digest card instead of an empty thread the
  /// user has to manually re-type the summary into.
  final String? initialPrompt;

  const GlobalChatBody({super.key, this.onBack, this.autoPickImage = false, this.initialPrompt});

  @override
  State<GlobalChatBody> createState() => GlobalChatBodyState();
}

class GlobalChatBodyState extends State<GlobalChatBody> {
  final _service = ConversationService();
  final _signalsService = HomeSignalsService();
  final _promptController = TextEditingController();
  final _promptFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();

  // Drives the composer's GlowingBorder -- on while idle (a subtle "tap me"
  // signifier), off the moment the user actually engages with the field
  // (focuses it or has typed something), so it never distracts behind text
  // being entered.
  bool get _composerActive => _promptFocusNode.hasFocus || _promptController.text.isNotEmpty;

  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _offline = false;
  ChatMessage? _replyingTo;
  bool _hadExchange = false;

  // Drives the typing indicator's particle dissolve (see
  // DissolvingTypingIndicator) -- true only for the brief window between a
  // reply landing and its dissolve animation finishing, decoupled from
  // _sending so the compose bar unlocks immediately instead of waiting on it.
  bool _typingDissolving = false;

  // Holds a reply that has arrived but isn't inserted into _messages yet --
  // it waits for the typing indicator to actually finish dissolving first
  // (see onDissolved below). Appending it immediately, in the same setState
  // as flipping `disappear`, grows the list length in the same frame the
  // dissolve is supposed to start; that shifts the typing row's index by
  // one, which reads to ListView.builder as a brand-new element rather
  // than the same one transitioning, so the dissolve never actually plays
  // on it -- it shows up as a stray fade-out appearing *after* the reply.
  ChatMessage? _pendingReply;

  // Identity, not equality -- the exact ChatMessage instance just appended
  // this session, so only that bubble streams its text in; anything loaded
  // from cache/history is never streamed. See MessageBubble.streamIn.
  ChatMessage? _streamingMessage;

  @override
  void initState() {
    super.initState();
    _promptController.addListener(_onComposerActivityChanged);
    _promptFocusNode.addListener(_onComposerActivityChanged);
    // Both auto-behaviors wait for _load() to finish first -- otherwise the
    // real fetched history (which _load applies via setState once it
    // resolves) would land on top of and wipe out the message(s) either one
    // adds while that fetch is still in flight.
    _load().then((_) {
      if (!mounted) return;
      if (widget.autoPickImage) {
        _pickImage();
      } else if (widget.initialPrompt != null && widget.initialPrompt!.trim().isNotEmpty) {
        _sendInitialPrompt(widget.initialPrompt!.trim());
      }
    });
  }

  void _onComposerActivityChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_hadExchange) {
      unawaited(_signalsService.wrapUpGlobalChat().catchError((_) {}));
    }
    _promptController.dispose();
    _promptFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startReply(ChatMessage message) {
    setState(() => _replyingTo = message);
  }

  String _quoteSnippet(ChatMessage message) {
    final oneLine = message.content.replaceAll('\n', ' ').trim();
    return oneLine.length > 80 ? '${oneLine.substring(0, 80)}...' : oneLine;
  }

  static final _locationKeywordRe = RegExp(
    r'\bnear(?:by)?\b|\baround\s+(?:here|me)\b|\bclose\s+to\s+me\b|\bnearest\b|\btrek\b|\bhik(?:e|ing)\b|'
    r'\btrail\b|\bshop(?:ping)?\b|\brestaurant\b|\bcafe\b|\bcoffee\b|\bpark\b',
    caseSensitive: false,
  );

  bool _looksLocationAware(String text) => _locationKeywordRe.hasMatch(text);

  Future<Position?> _maybeGetLocation(String text) async {
    if (!_looksLocationAware(text)) return null;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 4)),
      );
    } catch (_) {
      return null;
    }
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
    final textForBackend = replyingTo == null ? text : 'Replying to: "${_quoteSnippet(replyingTo)}"\n\n$text';
    setState(() => _replyingTo = null);
    _promptController.clear();
    await _sendToBackend(text, textForBackend, replyToPreview: replyingTo == null ? null : _quoteSnippet(replyingTo));
  }

  /// Same real send path as a user-typed message, just without a quoted
  /// reply -- used for "View Summary" on Home's Insight card, which drops
  /// the digest card's own text straight in as the prompt.
  Future<void> _sendInitialPrompt(String prompt) async {
    if (_sending) return;
    await _sendToBackend(prompt, prompt);
  }

  Future<void> _sendToBackend(String displayText, String backendText, {String? replyToPreview}) async {
    setState(() {
      _sending = true;
      _messages = [
        ..._messages,
        ChatMessage(role: 'user', content: displayText, createdAt: DateTime.now(), replyToPreview: replyToPreview),
      ];
    });
    _scrollToEnd();
    try {
      final position = await _maybeGetLocation(backendText);
      final (reply, actionCard) = await _service.sendGlobalChat(
        backendText,
        lat: position?.latitude,
        lon: position?.longitude,
      );
      if (!mounted) return;
      _hadExchange = true;
      final assistantMessage =
          ChatMessage(role: 'assistant', content: reply, createdAt: DateTime.now(), actionCard: actionCard);
      // Not appended to _messages yet -- see _pendingReply's doc comment.
      // The typing row's index must not move in this same setState, or the
      // dissolve never actually plays on it.
      setState(() {
        _sending = false;
        _typingDissolving = true;
        _pendingReply = assistantMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          ChatMessage(role: 'assistant', content: 'Request failed.', createdAt: DateTime.now()),
        ];
        _sending = false;
      });
      _scrollToEnd();
    }
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null || !mounted) return;
    final description = await _showDescribeImageSheet(File(picked.path));
    if (description == null || !mounted) return;
    _sendImage(File(picked.path), description);
  }

  Future<String?> _showDescribeImageSheet(File file) {
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(file, height: 200, fit: BoxFit.cover),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Add a description...',
                    filled: true,
                    fillColor: AppColors.dmBubbleIn,
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
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (_, value, __) => ElevatedButton(
                          onPressed: value.text.trim().isEmpty
                              ? null
                              : () => Navigator.of(sheetContext).pop(value.text.trim()),
                          child: const Text('Send'),
                        ),
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

  Future<void> _sendImage(File file, String description) async {
    setState(() {
      _sending = true;
      _messages = [
        ..._messages,
        ChatMessage(role: 'user', content: description, createdAt: DateTime.now(), localImage: file),
      ];
    });
    _scrollToEnd();
    try {
      final reply = await _service.sendGlobalImage(file, description);
      if (!mounted) return;
      final assistantMessage = ChatMessage(role: 'assistant', content: reply, createdAt: DateTime.now());
      setState(() {
        _sending = false;
        _typingDissolving = true;
        _pendingReply = assistantMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          ChatMessage(role: 'assistant', content: 'Request failed.', createdAt: DateTime.now()),
        ];
        _sending = false;
      });
      _scrollToEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.onBack != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Ask about your people & conversations',
                          style: TextStyle(color: AppColors.dmText, fontSize: 15, fontWeight: FontWeight.w700)),
                      Text("Ask across everything you've recorded",
                          style: TextStyle(fontSize: 11.5, color: AppColors.dmTextSoft)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (_offline) const OfflineBanner(),
        Expanded(
          child: _loading
              ? const MessageListSkeleton()
              : _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome, size: 36, color: AppColors.dmAccent),
                            const SizedBox(height: 16),
                            Text(
                              "Ask about a person or a past topic -- I'll pull in whichever conversations are relevant.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.dmTextSoft),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _messages.length + ((_sending || _typingDissolving) ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == _messages.length) {
                          return DissolvingTypingIndicator(
                            disappear: _typingDissolving,
                            onDissolved: () {
                              if (!mounted) return;
                              final reply = _pendingReply;
                              setState(() {
                                _typingDissolving = false;
                                if (reply != null) {
                                  _messages = [..._messages, reply];
                                  _streamingMessage = reply;
                                  _pendingReply = null;
                                }
                              });
                              if (reply != null) _scrollToEnd();
                            },
                          );
                        }
                        final message = _messages[i];
                        return MessageBubble(
                          message: message,
                          onReply: () => _startReply(message),
                          streamIn: identical(message, _streamingMessage),
                          onStreamTick: () => _scrollToEnd(animate: false),
                          onStreamDone: () {
                            if (identical(message, _streamingMessage) && mounted) {
                              setState(() => _streamingMessage = null);
                            }
                          },
                        );
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            // Same outer margin as Home's Ask bar (see _AskBar's own
            // Padding in home_screen.dart) -- these two composers need to
            // sit the same distance from the screen edges for the "same
            // surface continuing" feel to actually hold up.
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_replyingTo != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.dmBubbleIn,
                      borderRadius: BorderRadius.circular(8),
                      border: const Border(left: BorderSide(color: AppColors.dmAccent, width: 3)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _quoteSnippet(_replyingTo!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.dmTextSoft, fontSize: 12.5),
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
                // One single pill -- add icon, field, send circle all
                // inside the same Container -- exactly matching Home's Ask
                // bar's structure (padding, border, child order) instead of
                // a pill plus a separate floating circle outside it, so the
                // two look and measure identically and landing here from
                // the Ask bar feels like the same surface continuing.
                GlowingBorder(
                  borderRadius: 28,
                  active: !_composerActive,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.dmBubbleIn,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: AppColors.dmBubbleBorder),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              // Same "+" glyph as Home's Ask bar -- this
                              // button does the same job there (attach/add
                              // content), so it should look identical, not
                              // like a different affordance (a paperclip)
                              // once you're actually inside the chat.
                              icon: Icon(Icons.add, color: AppColors.dmTextSoft),
                              tooltip: 'Attach an image',
                              onPressed: _sending ? null : _pickImage,
                            ),
                            Expanded(
                              child: TextField(
                                controller: _promptController,
                                focusNode: _promptFocusNode,
                                // A bare TextField defaults to maxLines: 1,
                                // which clips/ellipsizes the hint on one
                                // line instead of letting it wrap the way
                                // Home's Ask bar's plain Text does (it has
                                // no line cap at all). Allowing a few lines
                                // here matches that wrapping behavior for
                                // both the hint and anything actually typed.
                                minLines: 1,
                                maxLines: 4,
                                // Multi-line fields default their keyboard's
                                // return key to inserting a newline instead
                                // of submitting -- explicit here so hitting
                                // enter still sends, matching the old
                                // single-line field's behavior.
                                textInputAction: TextInputAction.send,
                                // Same fontSize as Home's Ask bar's Text
                                // (see _AskBar) -- without this it falls
                                // back to the theme's default body size,
                                // which reads noticeably larger/heavier
                                // than the Ask bar right next to it.
                                style: TextStyle(color: AppColors.dmText, fontSize: 13),
                                cursorColor: AppColors.dmAccent,
                                decoration: InputDecoration(
                                  // Same wording as Home's Ask bar hint --
                                  // the field should read the same whether
                                  // you're looking at it before or after
                                  // tapping in.
                                  hintText: 'Ask about your people, plans, or anything...',
                                  hintStyle: TextStyle(color: AppColors.dmTextSoft, fontSize: 13),
                                  hintMaxLines: 2,
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                            // Same circle -- icon, size, padding -- as
                            // Home's Ask bar.
                            Material(
                              color: AppColors.dmAccent,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _sending ? null : _send,
                                child: const Padding(
                                  padding: EdgeInsets.all(9),
                                  child: Icon(Icons.arrow_upward, color: Colors.white, size: 18),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
