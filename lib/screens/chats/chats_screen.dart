import 'dart:async';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../main.dart' show notifyProvider;
import '../../models/conversation.dart';
import '../../models/search_result.dart';
import '../../motion/motion_profile.dart';
import '../../services/conversation_service.dart';
import '../../services/home_signals_service.dart';
import '../../state/listen_provider.dart';
import '../../state/notify_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/blinking_dot.dart';
import '../../widgets/category_chip_bar.dart';
import '../../widgets/chat_list_skeleton.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/insight_preview_card.dart';
import '../../widgets/island_nav_bar.dart';
import '../../widgets/live_timer_text.dart';
import '../../widgets/mood_trend_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/pulsing_halo.dart';
import '../../widgets/tap_bounce.dart';
import 'chat_thread_screen.dart';
import 'global_chat_screen.dart';

class ChatsScreen extends StatefulWidget {
  /// Opens HomeShell's side drawer (the retired bottom nav's replacement).
  final VoidCallback? onOpenDrawer;

  const ChatsScreen({super.key, this.onOpenDrawer});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final _service = ConversationService();
  List<Conversation>? _conversations;
  bool _loading = true;
  Object? _error;
  bool _offline = false;
  String? _category;
  String _search = '';

  // True from the moment Listen is tapped (to start a new session) until
  // either the live thread screen actually opens or starting it fails.
  // ListenProvider.isListening flips true synchronously as soon as the mic
  // starts, well before the backend confirms the session and this screen
  // navigates away -- without this flag, this screen's own FAB would
  // re-render into its red "recording" look for that whole gap, which is
  // exactly the flash of a red icon that shows right before leaving this
  // screen and serves no purpose here.
  bool _startingListen = false;

  /// Backend full-text search results for the *current* [_search] query --
  /// additive on top of the always-on local title filter below: null until
  /// the debounced /search call for this exact query resolves.
  List<SearchResult>? _searchResults;
  Timer? _searchDebounce;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // Adaptive home-screen motion (see ADAPTIVE_HOME_ANIMATION_PLAN.md) --
  // starts at the always-safe default and only ever improves once the
  // signal fetch resolves; a slow/failed fetch just means this list's
  // entrance keeps looking exactly like it always has.
  final _signalsService = HomeSignalsService();
  MotionProfile _motionProfile = MotionProfile.balanced;

  @override
  void initState() {
    super.initState();
    // Show the on-device copy instantly if there is one, then always
    // refresh from the network in the background -- mirrors the backend's
    // own cache-aside pattern, just one tier further down the stack.
    final cached = _service.listCached();
    if (cached != null) {
      _conversations = cached;
      _loading = false;
    }
    _reload();
    _loadMotionProfile();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (mounted) setState(() => _offline = !hasConnection);
    });
  }

  Future<void> _loadMotionProfile() async {
    try {
      final signals = await _signalsService.fetch();
      if (!mounted) return;
      setState(() {
        _motionProfile = profileFor(time: currentTimeBucket(), mood: signals.mood, chatTone: signals.chatTone);
      });
    } catch (_) {
      // Signals are optional and additive -- this screen's motion just
      // stays at the default MotionProfile.balanced on any failure.
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final items = await _service.list();
      if (!mounted) return;
      setState(() {
        _conversations = items;
        _loading = false;
        _error = null;
        _offline = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _offline = true;
        if (_conversations == null) _error = e;
      });
    }
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    setState(() {
      _search = query.toLowerCase();
      _searchResults =
          null; // stale results from a previous query no longer apply
    });
    _searchDebounce?.cancel();
    if (query.isEmpty) return;
    _searchDebounce = Timer(
        const Duration(milliseconds: 400), () => _runBackendSearch(query));
  }

  Future<void> _runBackendSearch(String query) async {
    try {
      final results = await _service.search(query);
      if (!mounted) return;
      // Guard against a stale response for a query the user has since
      // changed or cleared -- only apply results for the query still active.
      if (_search != query.toLowerCase()) return;
      setState(() => _searchResults = results);
    } catch (_) {
      // Offline/unreachable -- the always-on local title filter below still
      // works, full-text search is purely additive.
    }
  }

  Future<void> _confirmDelete(Conversation c) async {
    // Slidable's own auto-close animation was still running (it closes the
    // swiped-open row the instant an action is tapped) right as the dialog's
    // open animation started -- two animations competing for frames on the
    // same tap read as laggy. Closing it instantly here removes the overlap.
    Slidable.of(context)?.close(duration: Duration.zero);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
            'This deletes the conversation and its chat history. Tasks and profiles from it are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child:
                const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    HapticFeedback.mediumImpact();
    try {
      await _service.delete(c.id);
      if (!mounted) return;
      setState(() {
        _conversations = _conversations?.where((x) => x.id != c.id).toList();
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete conversation')));
      }
    }
  }

  Future<void> _toggleListen(ListenProvider listen) async {
    if (listen.isListening) {
      await listen.stop();
      _reload();
      return;
    }
    setState(() => _startingListen = true);
    try {
      await listen.start(
        onSessionStarted: (id) {
          _reload();
          // Resetting the flag here (before the push) still leaves it
          // false for at least one frame that this screen itself paints
          // before the new route visually covers it -- confirmed via
          // logging: this screen rebuilt with the red "recording" layout
          // twice right at this instant. Instead, reset it only once we're
          // actually back on this screen (the pushed route popped) -- while
          // ChatThreadScreen is on top, this screen's own look doesn't
          // matter, and by the time it's visible again, isListening
          // correctly reflects whatever the real state is by then.
          //
          // Same plain MaterialPageRoute every other "open this
          // conversation" tap on this screen uses (see _ChatRow/
          // _SearchResultRow onTap below) -- one consistent transition
          // for every way of landing on a thread, not a special one just
          // for this entry point.
          Navigator.of(context)
              .push(MaterialPageRoute(
            builder: (_) => ChatThreadScreen(
                conversationId: id, isNewLiveConversation: true),
          ))
              .then((_) {
            if (mounted) setState(() => _startingListen = false);
          });
        },
      );
      // start() can return without ever calling onSessionStarted (denied
      // mic permission, missing auth token) -- if we're still not actually
      // listening at this point, nothing else is coming to clear the flag.
      if (mounted && !listen.isListening) {
        setState(() => _startingListen = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _startingListen = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not access microphone: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final notify = context.watch<NotifyProvider>();
    final listen = context.watch<ListenProvider>();
    // See home_shell.dart's identical line for why this is needed --
    // without it this screen doesn't reliably repaint on a theme change.
    context.watch<ThemeProvider>();
    return Container(
      // Same warm-gradient wallpaper as the 1:1 chat screen -- see
      // AppColors.dmGradient's doc comment.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.dmGradient,
        ),
      ),
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppColors.dmText),
        titleTextStyle: appHeadlineFont(color: AppColors.dmText, fontSize: 19),
        leading: widget.onOpenDrawer != null
            ? IconButton(icon: const Icon(Icons.menu), onPressed: widget.onOpenDrawer)
            : null,
        title: const Text('Chats'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: TextField(
                      style: TextStyle(color: AppColors.dmText),
                      decoration: InputDecoration(
                        hintText: 'Search',
                        hintStyle: TextStyle(color: AppColors.dmTextSoft),
                        prefixIcon: Icon(Icons.search, color: AppColors.dmTextSoft),
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.dmPillFill,
                        border: OutlineInputBorder(
                            borderRadius: const BorderRadius.all(Radius.circular(20)),
                            borderSide: BorderSide(color: AppColors.dmBubbleBorder)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: const BorderRadius.all(Radius.circular(20)),
                            borderSide: BorderSide(color: AppColors.dmBubbleBorder)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: const BorderRadius.all(Radius.circular(20)),
                            borderSide: const BorderSide(color: AppColors.dmAccent, width: 2)),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                ),
              ),
              CategoryChipBar(
                  selected: _category,
                  onChanged: (v) => setState(() => _category = v)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      floatingActionButton: Padding(
        // HomeShell's Scaffold now extends its body under the translucent
        // IslandNavBar (needed for the bar's blur to have real content
        // behind it) -- without this, this screen's own nested Scaffold
        // would think it owns the full screen height and place the FAB
        // right at the bottom, hidden behind the nav bar.
        padding: const EdgeInsets.only(
            bottom: IslandNavBar.barHeight + IslandNavBar.bottomMargin),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TapBounce(
              child: FloatingActionButton.extended(
                heroTag: 'chat',
                // Slightly translucent fill (icon/label stay fully opaque) so
                // a conversation row scrolled underneath is still visible
                // through/around the button instead of fully hidden behind it.
                backgroundColor: AppColors.dmAccent.withValues(alpha: 0.85),
                tooltip: 'Ask about your people & conversations',
                // Refetch signals on return: ChatsScreen's State persists
                // underneath this push (Navigator doesn't rebuild it), so
                // without this a chat_tone set by GlobalChatScreen.dispose()
                // just now would otherwise only ever show up after a full
                // app restart.
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const GlobalChatScreen()),
                  );
                  _loadMotionProfile();
                },
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Chat'),
              ),
            ),
            const SizedBox(height: 12),
            if (listen.isListening &&
                !_startingListen &&
                listen.startedAt != null)
              // Recording layout, Telegram/WhatsApp voice-message style: a
              // pill with a hard-blinking dot + live duration counter sits
              // beside the button, which itself has morphed from the idle
              // pill into a plain filled red circle with continuous outward
              // sound-wave rings. Gated on !_startingListen so this screen's
              // own button stays looking idle for the whole gap between
              // tapping Listen and actually navigating to the live thread --
              // otherwise it flashes into this look right before leaving,
              // which serves no purpose here.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.dmPillFill,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.dmBubbleBorder),
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            // Same conversation, same transition as tapping it
                            // from the list -- the timer is just another way
                            // to jump straight into the live thread it's
                            // counting for.
                            onTap: listen.conversationId == null
                                ? null
                                : () {
                                    notifyProvider
                                        .clearConversation(listen.conversationId!);
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) => ChatThreadScreen(
                                              conversationId:
                                                  listen.conversationId!)),
                                    );
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const BlinkingDot(color: AppColors.danger),
                                  const SizedBox(width: 8),
                                  LiveTimerText(
                                    startedAt: listen.startedAt!,
                                    style: const TextStyle(
                                        color: AppColors.danger,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TapBounce(
                    child: PulsingHalo(
                      active: true,
                      color: AppColors.danger,
                      child: FloatingActionButton(
                        heroTag: 'listen',
                        backgroundColor:
                            AppColors.danger.withValues(alpha: 0.85),
                        shape: const CircleBorder(),
                        onPressed: () => _toggleListen(listen),
                        child: const Icon(Icons.stop, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              )
            else
              TapBounce(
                child: FloatingActionButton.extended(
                  heroTag: 'listen',
                  backgroundColor: AppColors.dmAccent.withValues(alpha: 0.85),
                  onPressed: () => _toggleListen(listen),
                  icon: const Icon(Icons.mic),
                  label: const Text('Listen'),
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_offline) const OfflineBanner(),
          if (_search.isEmpty) const MoodTrendCard(),
          if (_search.isEmpty) const InsightPreviewCard(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: _buildBody(notify),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildBody(NotifyProvider notify) {
    if (_conversations == null) {
      if (_loading) return const ChatListSkeleton();
      return Center(child: Text('Failed to load chats: $_error'));
    }

    // Full-text search results (title/transcript/message content) take over
    // the list once they've resolved for the active query -- until then the
    // always-on local title filter below keeps results appearing instantly.
    if (_search.isNotEmpty && _searchResults != null) {
      final results = _searchResults!;
      if (results.isEmpty) {
        return const EmptyState(
            icon: Icons.search_off, title: 'No matches found');
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: results.length,
        itemBuilder: (context, i) {
          final r = results[i];
          return _SearchResultRow(
            result: r,
            onTap: () {
              notifyProvider.clearConversation(r.id);
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChatThreadScreen(conversationId: r.id)));
            },
          );
        },
      );
    }

    var items = _conversations!;
    if (_category != null)
      items = items.where((c) => c.category == _category).toList();
    if (_search.isNotEmpty) {
      items = items
          .where((c) => c.displayTitle.toLowerCase().contains(_search))
          .toList();
    }
    if (items.isEmpty) {
      return _search.isNotEmpty
          ? const EmptyState(icon: Icons.search_off, title: 'No matches found')
          : const EmptyState(
              icon: Icons.chat_bubble_outline,
              title: 'No conversations yet',
              subtitle:
                  'Start a live listen session or make a call to get started.',
            );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final c = items[i];
        final unread = notify.unreadConversations.contains(c.id);
        return FadeSlideIn(
          key: ValueKey('fade_${c.id}'),
          index: i,
          profile: _motionProfile,
          child: Slidable(
            key: ValueKey(c.id),
            endActionPane: ActionPane(
              motion: const DrawerMotion(),
              extentRatio: 0.25,
              children: [
                SlidableAction(
                  onPressed: (_) => _confirmDelete(c),
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  icon: Icons.delete_outline,
                  label: 'Delete',
                ),
              ],
            ),
            child: _ChatRow(
              conversation: c,
              unread: unread,
              onTap: () {
                notifyProvider.clearConversation(c.id);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChatThreadScreen(conversationId: c.id)));
              },
            ),
          ),
        );
      },
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

  const _ChatRow(
      {required this.conversation, required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final category = conversation.category;
    final categoryLabel = category.isEmpty
        ? ''
        : category[0].toUpperCase() + category.substring(1);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.dmBubbleIn,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dmBubbleBorder),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
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
                                fontWeight:
                                    unread ? FontWeight.w700 : FontWeight.w600,
                                color: AppColors.dmText,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('MMM d, HH:mm')
                                .format(conversation.createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: unread ? AppColors.dmAccent : AppColors.dmTextSoft,
                              fontWeight:
                                  unread ? FontWeight.w600 : FontWeight.normal,
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
                              style: TextStyle(fontSize: 13.5, color: AppColors.dmTextSoft),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (unread)
                            Container(
                              width: 9,
                              height: 9,
                              margin: const EdgeInsets.only(left: 8),
                              decoration: const BoxDecoration(
                                  color: AppColors.unreadBadge,
                                  shape: BoxShape.circle),
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
      ),
    );
  }
}

/// Same row shape as _ChatRow, but for a /search hit -- shows a highlighted
/// snippet of the matched text instead of the category label.
class _SearchResultRow extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;

  const _SearchResultRow({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.dmBubbleIn,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dmBubbleBorder),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InitialAvatar(name: result.displayTitle),
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
                              result.displayTitle,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.dmText),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('MMM d, HH:mm').format(result.createdAt),
                            style: TextStyle(
                                fontSize: 12, color: AppColors.dmTextSoft),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text.rich(
                        TextSpan(
                          style: TextStyle(
                              fontSize: 13.5, color: AppColors.dmTextSoft),
                          children: _parseSnippetSpans(result.snippet),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Backend wraps matched terms in <b>...</b> (Postgres ts_headline) -- turn
/// that into bold TextSpans instead of pulling in an HTML-rendering package
/// for what's always exactly one tag type.
final _snippetBoldTag = RegExp(r'<b>(.*?)</b>');

List<TextSpan> _parseSnippetSpans(String snippet) {
  final spans = <TextSpan>[];
  var last = 0;
  for (final match in _snippetBoldTag.allMatches(snippet)) {
    if (match.start > last)
      spans.add(TextSpan(text: snippet.substring(last, match.start)));
    spans.add(TextSpan(
        text: match.group(1),
        style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.dmText)));
    last = match.end;
  }
  if (last < snippet.length) spans.add(TextSpan(text: snippet.substring(last)));
  return spans;
}
