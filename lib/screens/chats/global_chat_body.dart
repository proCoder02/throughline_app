import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../models/chat_message.dart';
import '../../services/conversation_service.dart';
import '../../services/home_signals_service.dart';
import '../../theme.dart';
import '../../widgets/chat_list_skeleton.dart';
import '../../widgets/dissolving_typing_indicator.dart';
import '../../widgets/glowing_border.dart';
import '../../widgets/live_timer_text.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/policy_confirm_sheet.dart';
import '../../widgets/pulsing_halo.dart';
import '../../widgets/transaction_confirm_sheet.dart';

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

  /// A file shared into the app from another app's share sheet (e.g. a UPI
  /// receipt screenshot from GPay/PhonePe/Paytm, see main.dart's
  /// receive_sharing_intent listener) -- when set, skips the gallery
  /// picker _pickImage normally opens and goes straight to the same
  /// describe-then-send flow as a manually attached image.
  final File? sharedImageFile;

  const GlobalChatBody({
    super.key,
    this.onBack,
    this.autoPickImage = false,
    this.initialPrompt,
    this.sharedImageFile,
  });

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
  final _voiceRecorder = AudioRecorder();

  // Voice input (§ mic button in the composer) -- records to a temp file,
  // same record()/transcribe() shape as the watch app's CaptureScreen, then
  // fills the composer for review rather than auto-sending: a misheard
  // amount/name in a voice-driven action is exactly the kind of mistake
  // that should be caught before it's sent, not after (see this session's
  // own "confirm before anything consequential" discussion). Explicit
  // Send afterward reuses _send() completely unchanged.
  bool _isRecording = false;
  bool _transcribing = false;
  DateTime? _recordingStartedAt;

  // Drives the composer's GlowingBorder -- on while idle (a subtle "tap me"
  // signifier), off the moment the user actually engages with the field
  // (focuses it or has typed something), so it never distracts behind text
  // being entered.
  bool get _composerActive =>
      _promptFocusNode.hasFocus || _promptController.text.isNotEmpty || _isRecording || _transcribing;

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
      if (widget.sharedImageFile != null) {
        _describeAndSendImage(widget.sharedImageFile!);
      } else if (widget.autoPickImage) {
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
    if (_isRecording) unawaited(_voiceRecorder.stop());
    _voiceRecorder.dispose();
    _promptController.dispose();
    _promptFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_isRecording || _transcribing) return;
    try {
      if (!await _voiceRecorder.hasPermission()) {
        _showMessage('Microphone permission is needed for voice input.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_input_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _voiceRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _recordingStartedAt = DateTime.now();
      });
    } catch (e) {
      _showMessage('Could not start recording: $e');
    }
  }

  Future<void> _stopRecordingAndTranscribe() async {
    if (!_isRecording) return;
    String? path;
    try {
      path = await _voiceRecorder.stop();
    } catch (_) {
      // Fall through to the null-path branch below, same as a failed start.
    }
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _transcribing = path != null;
    });
    if (path == null) {
      _showMessage('Recording did not produce any audio. Try again.');
      return;
    }

    final file = File(path);
    try {
      final transcript = _stripSpeakerLabels(await _service.transcribe(file));
      if (!mounted) return;
      if (transcript.trim().isEmpty) {
        _showMessage('Could not make out any speech in that recording.');
        return;
      }
      // Sends immediately, same as typing + hitting send (Gemini/ChatGPT
      // voice-mode style) -- any consequential action the message triggers
      // gets its own confirm card (ExpenseConfirmCard/MessageDraftCard)
      // before it actually does anything, so there's no need to hold the
      // transcript back in the composer for a manual review first. Still
      // combines with anything already typed, same as the old append
      // behavior, so a voice note can extend a message in progress.
      final existing = _promptController.text.trim();
      final combined = existing.isEmpty ? transcript : '$existing $transcript';
      _promptController.clear();
      await _sendInitialPrompt(combined);
    } catch (e) {
      if (mounted) _showMessage('Could not transcribe that: $e');
    } finally {
      if (mounted) setState(() => _transcribing = false);
      if (await file.exists()) await file.delete();
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static final _speakerLinePrefix = RegExp(r'^\s*Speaker\s+\d+:\s*', caseSensitive: false);

  /// /transcribe always returns the "Speaker N: text" convention (see
  /// transcribe_audio_bytes in app.py) -- built for multi-person call/Listen
  /// transcripts, where it's genuinely needed. Global chat's voice input is
  /// always one person dictating a single message, so the label is pure
  /// noise here, not information. Joins multiple lines (Deepgram splits on
  /// pauses) back into one block of plain text rather than leaving
  /// "Speaker 0: ..." stacked on separate lines in the composer.
  String _stripSpeakerLabels(String transcript) {
    return transcript
        .split('\n')
        .map((line) => line.replaceFirst(_speakerLinePrefix, '').trim())
        .where((line) => line.isNotEmpty)
        .join(' ');
  }

  /// Replaces the TextField in place while recording -- a pulsing red dot
  /// (PulsingHalo, same widget the old Listen FAB used for this exact
  /// "recording" signifier) + a live "0:07"-style counter (LiveTimerText,
  /// same widget call_overlay.dart uses for call duration), not a second
  /// bespoke recording UI.
  Widget _buildRecordingIndicator() {
    return Row(
      children: [
        PulsingHalo(
          active: true,
          color: AppColors.danger,
          child: Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 10),
        Text('Listening…', style: TextStyle(color: AppColors.dmText, fontSize: 13)),
        const Spacer(),
        LiveTimerText(
          startedAt: _recordingStartedAt!,
          style: TextStyle(color: AppColors.dmTextSoft, fontSize: 12.5),
        ),
      ],
    );
  }

  /// One circle, same size/shape/padding throughout (Home's Ask bar's own
  /// convention) -- only the icon/color/action inside it changes with
  /// state, rather than swapping between visually different widgets, so
  /// nothing jumps around as recording starts/stops/transcribes.
  Widget _buildTrailingAction() {
    if (_transcribing) {
      return const Padding(
        padding: EdgeInsets.all(9),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.dmAccent),
        ),
      );
    }
    if (_isRecording) {
      return Material(
        color: AppColors.danger,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _stopRecordingAndTranscribe,
          child: const Padding(
            padding: EdgeInsets.all(9),
            child: Icon(Icons.stop_rounded, color: Colors.white, size: 18),
          ),
        ),
      );
    }
    final hasText = _promptController.text.trim().isNotEmpty;
    return Material(
      color: AppColors.dmAccent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _sending
            ? null
            : hasText
                ? _send
                : _startRecording,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(hasText ? Icons.arrow_upward : Icons.mic_none_rounded, color: Colors.white, size: 18),
        ),
      ),
    );
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
      final (reply, actionCards) = await _service.sendGlobalChat(
        backendText,
        lat: position?.latitude,
        lon: position?.longitude,
      );
      if (!mounted) return;
      _hadExchange = true;
      final assistantMessage =
          ChatMessage(role: 'assistant', content: reply, createdAt: DateTime.now(), actionCards: actionCards);
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

  /// "+" button entry point -- a photo (receipt, policy card, note) goes
  /// through the existing vision pipeline; a PDF is offered separately
  /// since it needs a different extraction path (text, not vision) with
  /// no caption step -- but like a photo, a PDF can turn out to be a
  /// receipt, a vehicle insurance policy, or neither; the backend decides
  /// from its actual content, same as it does for a photo.
  ///
  /// Large icon tiles (WhatsApp/Telegram's attach-menu style) rather than
  /// a plain text list -- the two options read at a glance instead of
  /// needing to be read, and the tap target is the whole tile, not just
  /// a thin row.
  Future<void> _showAttachMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.dmBubbleIn,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.dmBubbleBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AttachTile(
                icon: Icons.photo_outlined,
                label: 'Photo',
                color: AppColors.dmAccent,
                onTap: () => Navigator.of(sheetContext).pop('photo'),
              ),
              _AttachTile(
                icon: Icons.picture_as_pdf_outlined,
                label: 'PDF document',
                color: Colors.redAccent,
                onTap: () => Navigator.of(sheetContext).pop('pdf'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'photo') {
      await _pickImage();
    } else if (choice == 'pdf') {
      await _pickPdf();
    }
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null || !mounted) return;
    await _describeAndSendImage(File(picked.path));
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    await _sendPdf(File(path));
  }

  /// Same chat-bubble + dissolve-in + confirm-sheet flow as _sendImage --
  /// a PDF upload reads back a real overview in chat, and surfaces a
  /// transaction or policy confirm sheet exactly like a photo would,
  /// since the backend's extraction is the same for both upload forms.
  Future<void> _sendPdf(File file) async {
    setState(() {
      _sending = true;
      _messages = [
        ..._messages,
        ChatMessage(role: 'user', content: '[PDF document uploaded]', createdAt: DateTime.now()),
      ];
    });
    _scrollToEnd();
    try {
      final (reply, conversationId, transaction, policy) = await _service.sendGlobalPdf(file);
      if (!mounted) return;
      final assistantMessage = ChatMessage(role: 'assistant', content: reply, createdAt: DateTime.now());
      setState(() {
        _sending = false;
        _typingDissolving = true;
        _pendingReply = assistantMessage;
      });
      // A policy document can legitimately ALSO be a receipt for the
      // premium paid (confirmed live: a real policy PDF's own "Gross
      // Premium Paid" section extracted as a genuine transaction) -- both
      // sheets are shown, one after another, rather than an if/else-if
      // that would silently drop whichever one didn't go first. Same
      // "don't let one surfaced outcome hide another" principle as the
      // action_cards list fix for chat replies.
      if (transaction != null) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        final confirmed = await showTransactionConfirmSheet(context, transaction);
        if (confirmed != null) {
          try {
            final wasDuplicate = await _service.saveTransaction(conversationId, confirmed);
            if (mounted && wasDuplicate) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Already saved -- looks like the same payment was shared again.')),
              );
            }
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not save that transaction. Try again from the chat.')),
              );
            }
          }
        }
      }
      if (policy != null) {
        await Future.delayed(Duration(milliseconds: transaction != null ? 150 : 300));
        if (!mounted) return;
        final confirmed = await showPolicyConfirmSheet(context, policy);
        if (confirmed != null) {
          try {
            final replaced = await _service.saveVehiclePolicy(confirmed);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(replaced ? 'Policy updated.' : 'Policy saved.')),
              );
            }
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not save that policy. Try again from the chat.')),
              );
            }
          }
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          ChatMessage(role: 'assistant', content: 'Could not read that PDF.', createdAt: DateTime.now()),
        ];
        _sending = false;
      });
      _scrollToEnd();
    }
  }

  /// Shared by _pickImage (gallery) and a file shared in from another app's
  /// share sheet (widget.sharedImageFile) -- same describe-then-send flow
  /// either way, the file just comes from a different source.
  Future<void> _describeAndSendImage(File file) async {
    final description = await _showDescribeImageSheet(file);
    if (description == null || !mounted) return;
    _sendImage(file, description);
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
      final (reply, conversationId, transaction, policy) = await _service.sendGlobalImage(file, description);
      if (!mounted) return;
      final assistantMessage = ChatMessage(role: 'assistant', content: reply, createdAt: DateTime.now());
      setState(() {
        _sending = false;
        _typingDissolving = true;
        _pendingReply = assistantMessage;
      });
      // A policy document can legitimately ALSO be a receipt for the
      // premium paid (confirmed live: a real policy PDF's own "Gross
      // Premium Paid" section extracted as a genuine transaction) -- both
      // sheets are shown, one after another, rather than an if/else-if
      // that would silently drop whichever one didn't go first. Same
      // "don't let one surfaced outcome hide another" principle as the
      // action_cards list fix for chat replies.
      if (transaction != null) {
        // Fires after the reply's own dissolve-in has had a moment to
        // start, rather than stacking a modal sheet on top of a message
        // that hasn't appeared yet.
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        final confirmed = await showTransactionConfirmSheet(context, transaction);
        if (confirmed != null) {
          try {
            final wasDuplicate = await _service.saveTransaction(conversationId, confirmed);
            if (mounted && wasDuplicate) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Already saved -- looks like the same payment was shared again.')),
              );
            }
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not save that transaction. Try again from the chat.')),
              );
            }
          }
        }
      }
      if (policy != null) {
        await Future.delayed(Duration(milliseconds: transaction != null ? 150 : 300));
        if (!mounted) return;
        final confirmed = await showPolicyConfirmSheet(context, policy);
        if (confirmed != null) {
          try {
            final replaced = await _service.saveVehiclePolicy(confirmed);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(replaced ? 'Policy updated.' : 'Policy saved.')),
              );
            }
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not save that policy. Try again from the chat.')),
              );
            }
          }
        }
      }
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
                              tooltip: 'Attach',
                              onPressed: (_sending || _isRecording || _transcribing) ? null : _showAttachMenu,
                            ),
                            Expanded(
                              child: _isRecording ? _buildRecordingIndicator() : TextField(
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
                            _buildTrailingAction(),
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

/// A single large icon tile in _showAttachMenu's bottom sheet -- the whole
/// tile (icon + label) is the tap target, not just the text.
class _AttachTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachTile({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontSize: 12.5, color: AppColors.dmText)),
          ],
        ),
      ),
    );
  }
}
