import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../main.dart' show notifyProvider;
import '../../models/conversation.dart';
import '../../models/search_result.dart';
import '../../services/conversation_service.dart';
import '../../state/listen_provider.dart';
import '../../state/notify_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/category_chip_bar.dart';
import '../../widgets/chat_list_skeleton.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/mood_trend_card.dart';
import '../../widgets/offline_banner.dart';
import 'chat_thread_screen.dart';
import 'global_chat_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

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

  /// Backend full-text search results for the *current* [_search] query --
  /// additive on top of the always-on local title filter below: null until
  /// the debounced /search call for this exact query resolves.
  List<SearchResult>? _searchResults;
  Timer? _searchDebounce;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

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
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (mounted) setState(() => _offline = !hasConnection);
    });
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
      _searchResults = null; // stale results from a previous query no longer apply
    });
    _searchDebounce?.cancel();
    if (query.isEmpty) return;
    _searchDebounce = Timer(const Duration(milliseconds: 400), () => _runBackendSearch(query));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete conversation')));
      }
    }
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
    // See home_shell.dart's identical line for why this is needed --
    // without it this screen doesn't reliably repaint on a theme change.
    context.watch<ThemeProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              CategoryChipBar(selected: _category, onChanged: (v) => setState(() => _category = v)),
              const SizedBox(height: 8),
            ],
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
      body: Column(
        children: [
          if (_offline) const OfflineBanner(),
          if (_search.isEmpty) const MoodTrendCard(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: _buildBody(notify),
            ),
          ),
        ],
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
        return const EmptyState(icon: Icons.search_off, title: 'No matches found');
      }
      return ListView.separated(
        itemCount: results.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border, indent: 78),
        itemBuilder: (context, i) {
          final r = results[i];
          return _SearchResultRow(
            result: r,
            onTap: () {
              notifyProvider.clearConversation(r.id);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadScreen(conversationId: r.id)));
            },
          );
        },
      );
    }

    var items = _conversations!;
    if (_category != null) items = items.where((c) => c.category == _category).toList();
    if (_search.isNotEmpty) {
      items = items.where((c) => c.displayTitle.toLowerCase().contains(_search)).toList();
    }
    if (items.isEmpty) {
      return _search.isNotEmpty
          ? const EmptyState(icon: Icons.search_off, title: 'No matches found')
          : const EmptyState(
              icon: Icons.chat_bubble_outline,
              title: 'No conversations yet',
              subtitle: 'Start a live listen session or make a call to get started.',
            );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border, indent: 78),
      itemBuilder: (context, i) {
        final c = items[i];
        final unread = notify.unreadConversations.contains(c.id);
        return FadeSlideIn(
          key: ValueKey('fade_${c.id}'),
          index: i,
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
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadScreen(conversationId: c.id)));
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
                            style: TextStyle(fontSize: 13.5, color: AppColors.textSoft),
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

/// Same row shape as _ChatRow, but for a /search hit -- shows a highlighted
/// snippet of the matched text instead of the category label.
class _SearchResultRow extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;

  const _SearchResultRow({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.panel,
      child: InkWell(
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
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('MMM d, HH:mm').format(result.createdAt),
                          style: TextStyle(fontSize: 12, color: AppColors.textSoft),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        style: TextStyle(fontSize: 13.5, color: AppColors.textSoft),
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
    if (match.start > last) spans.add(TextSpan(text: snippet.substring(last, match.start)));
    spans.add(TextSpan(text: match.group(1), style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text)));
    last = match.end;
  }
  if (last < snippet.length) spans.add(TextSpan(text: snippet.substring(last)));
  return spans;
}
