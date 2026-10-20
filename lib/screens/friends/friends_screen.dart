import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/friend.dart';
import '../../services/friend_service.dart';
import '../../services/message_service.dart';
import '../../state/call_provider.dart';
import '../../state/notify_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme.dart';
import '../../utils/call_format.dart';
import '../../widgets/avatar.dart';
import '../../widgets/chat_list_skeleton.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/extended_profile_sheet.dart';
import '../../widgets/offline_banner.dart';
import 'direct_message_screen.dart';
import 'friend_profile_screen.dart';

class FriendsScreen extends StatefulWidget {
  /// Opens HomeShell's side drawer (the retired bottom nav's replacement).
  final VoidCallback? onOpenDrawer;

  const FriendsScreen({super.key, this.onOpenDrawer});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _service = FriendService();
  final _messageService = MessageService();
  final _codeController = TextEditingController();
  final _searchController = TextEditingController();
  List<Friend>? _friends;
  bool _loading = true;
  Object? _loadError;
  bool _offline = false;
  bool _adding = false;
  String? _error;
  bool _pickingCall = false;
  final Set<int> _callSelection = {};

  // Direct-friend matches are a plain client-side filter (the full list is
  // already loaded) -- only the friends-of-friends half needs a network
  // call, debounced so fast typing doesn't fire one request per keystroke.
  String _search = '';
  Timer? _searchDebounce;
  List<ExtendedFriend> _extendedResults = [];
  bool _searchingExtended = false;

  @override
  void initState() {
    super.initState();
    // Show the on-device copy instantly if there is one, then always refresh
    // from the network in the background -- same cache-first pattern as
    // ChatsScreen, so this tab still shows its last-known list offline.
    final cached = _service.listCached();
    if (cached != null) {
      _friends = cached;
      _loading = false;
    }
    _load();
    _loadUnreadMessageCounts();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _codeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _search = value.trim().toLowerCase());
    _searchDebounce?.cancel();
    if (_search.isEmpty) {
      setState(() => _extendedResults = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () => _searchExtendedNetwork(_search));
  }

  Future<void> _searchExtendedNetwork(String query) async {
    setState(() => _searchingExtended = true);
    try {
      final results = await _service.searchExtendedNetwork(query);
      // The query may have changed again while this was in flight (fast
      // typing outrunning the debounce's own network round trip) -- drop a
      // stale response rather than overwrite newer, still-loading results.
      if (!mounted || _search != query) return;
      setState(() {
        _extendedResults = results;
        _searchingExtended = false;
      });
    } catch (_) {
      if (!mounted || _search != query) return;
      setState(() => _searchingExtended = false);
    }
  }

  Future<void> _loadUnreadMessageCounts() async {
    try {
      final counts = await _messageService.unreadCounts();
      if (mounted) context.read<NotifyProvider>().setDirectMessageBadges(counts);
    } catch (_) {
      // Offline/unreachable -- badges just stay at whatever NotifyProvider
      // already has from this session's WS deltas (or none yet).
    }
  }

  Future<void> _openChat(Friend f) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DirectMessageScreen(friend: f)));
  }

  Future<void> _load() async {
    try {
      final items = await _service.list();
      if (!mounted) return;
      setState(() {
        _friends = items;
        _loading = false;
        _loadError = null;
        _offline = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _offline = true;
        if (_friends == null) _loadError = e;
      });
    }
  }

  Future<void> _reload() => _load();

  Future<void> _addFriend() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      await _service.add(code);
      _codeController.clear();
      _reload();
    } catch (_) {
      setState(() => _error = 'Could not add friend. Check the code.');
    } finally {
      setState(() => _adding = false);
    }
  }

  Future<void> _startCall(List<int> friendIds) async {
    try {
      await context.read<CallProvider>().startCall(friendIds);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start call: $e')));
      }
    }
  }

  void _togglePicking() {
    setState(() {
      _pickingCall = !_pickingCall;
      _callSelection.clear();
    });
  }

  Future<void> _confirmGroupCall() async {
    final ids = _callSelection.toList();
    setState(() {
      _pickingCall = false;
      _callSelection.clear();
    });
    if (ids.isNotEmpty) await _startCall(ids);
  }

  Future<void> _openFriend(Friend f) async {
    // Rename/remove/cognitive-sharing all live in FriendProfileScreen --
    // reload on return so a changed nickname or a removal shows up
    // immediately.
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => FriendProfileScreen(friend: f)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final directMessageBadges = context.watch<NotifyProvider>().directMessageBadges;
    return Container(
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
            ? IconButton(icon: const Icon(Icons.menu), tooltip: 'Open menu', onPressed: widget.onOpenDrawer)
            : null,
        title: const Text('Friends'),
        actions: [
          IconButton(
            icon: Icon(_pickingCall ? Icons.close : Icons.phone_outlined),
            tooltip: _pickingCall ? 'Cancel' : 'Start group call',
            onPressed: _togglePicking,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_pickingCall)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: TextField(
                              controller: _codeController,
                              textCapitalization: TextCapitalization.characters,
                              style: TextStyle(color: AppColors.dmText),
                              cursorColor: AppColors.dmAccent,
                              decoration: InputDecoration(
                                hintText: "Friend's code",
                                hintStyle: TextStyle(color: AppColors.dmTextSoft),
                                isDense: true,
                                filled: true,
                                fillColor: AppColors.dmPillFill,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide(color: AppColors.dmBubbleBorder)),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide(color: AppColors.dmBubbleBorder)),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: const BorderSide(color: AppColors.dmAccent, width: 2)),
                              ),
                              onSubmitted: (_) => _addFriend(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.dmAccent, foregroundColor: Colors.white),
                        onPressed: _adding ? null : _addFriend,
                        child: _adding
                            ? const SizedBox(
                                height: 16, width: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Add'),
                      ),
                    ],
                  ),
                  if (_error != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                      ),
                    ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(color: AppColors.dmText),
                        cursorColor: AppColors.dmAccent,
                        decoration: InputDecoration(
                          hintText: 'Search your friends and their friends',
                          hintStyle: TextStyle(color: AppColors.dmTextSoft),
                          prefixIcon: Icon(Icons.search, color: AppColors.dmTextSoft),
                          suffixIcon: _search.isEmpty
                              ? null
                              : IconButton(
                                  icon: Icon(Icons.close, color: AppColors.dmTextSoft),
                                  onPressed: () {
                                    _searchController.clear();
                                    _onSearchChanged('');
                                  },
                                ),
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.dmPillFill,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(color: AppColors.dmBubbleBorder)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(color: AppColors.dmBubbleBorder)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: const BorderSide(color: AppColors.dmAccent, width: 2)),
                        ),
                        onChanged: _onSearchChanged,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Pick who to call, then confirm below.', style: TextStyle(color: AppColors.dmTextSoft)),
              ),
            ),
          if (_offline) const OfflineBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: _buildList(directMessageBadges),
            ),
          ),
          if (_pickingCall)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: _callSelection.isEmpty ? null : _confirmGroupCall,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.dmAccent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: Text(_callSelection.isEmpty ? 'Call' : 'Call (${_callSelection.length})'),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildList(Map<int, int> directMessageBadges) {
    if (_friends == null) {
      // Same shimmer skeleton as Chats/Tasks/Profiles' cold-start load (see
      // this session's UX audit) instead of a bare spinner.
      if (_loading) return const ChatListSkeleton();
      return Center(child: Text('Failed to load friends: $_loadError'));
    }
    final friends = _friends!;
    if (friends.isEmpty) {
      // Shared EmptyState component instead of a bare gray sentence.
      return const EmptyState(
        icon: Icons.people_outline,
        title: 'No friends added yet',
        subtitle: 'Add a friend using their friend code from Settings.',
      );
    }
    if (_search.isNotEmpty && !_pickingCall) {
      return _buildSearchResults(friends, directMessageBadges);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: friends.length,
      itemBuilder: (context, i) {
        final f = friends[i];
        if (_pickingCall) {
          final selected = _callSelection.contains(f.id);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.dmBubbleIn,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.dmBubbleBorder),
            ),
            // Material ancestor required -- CheckboxListTile paints its own
            // background/shape/ink via Ink, which is otherwise invisible
            // (and throws a debug warning) sitting directly inside a plain
            // Container with no Material above it.
            child: Material(
              type: MaterialType.transparency,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: CheckboxListTile(
                value: selected,
                activeColor: AppColors.dmAccent,
                checkColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _callSelection.add(f.id);
                  } else {
                    _callSelection.remove(f.id);
                  }
                }),
                secondary: InitialAvatar(name: f.displayName, imageUrl: f.profilePictureUrl),
                title: Text(f.displayName, style: TextStyle(color: AppColors.dmText, fontWeight: FontWeight.w600)),
              ),
            ),
          );
        }
        return _FriendRow(
          friend: f,
          unreadMessages: directMessageBadges[f.id] ?? 0,
          onTap: () => _openFriend(f),
          onChat: () => _openChat(f),
          onCall: () => _startCall([f.id]),
        );
      },
    );
  }

  /// Two sections while searching: direct-friend matches (a plain client-
  /// side filter over the already-loaded list, same _FriendRow as the
  /// normal list), then -- below a header, only if any exist -- people in
  /// the extended network (friends of friends) matching the same query,
  /// fetched via _searchExtendedNetwork's debounced call. A small ListView
  /// (not .builder) is fine here: search results are a short, filtered
  /// subset, not the full 100+-friend list the normal path optimizes for.
  Widget _buildSearchResults(List<Friend> friends, Map<int, int> directMessageBadges) {
    final matches = friends
        .where((f) => f.displayName.toLowerCase().contains(_search) || f.username.toLowerCase().contains(_search))
        .toList();

    if (matches.isEmpty && _extendedResults.isEmpty && !_searchingExtended) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'No one found',
        subtitle: 'No friends or friends-of-friends match "$_search".',
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        for (final f in matches)
          _FriendRow(
            friend: f,
            unreadMessages: directMessageBadges[f.id] ?? 0,
            onTap: () => _openFriend(f),
            onChat: () => _openChat(f),
            onCall: () => _startCall([f.id]),
          ),
        if (_searchingExtended)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_extendedResults.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(
              'IN YOUR NETWORK',
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.dmTextSoft),
            ),
          ),
          for (final ef in _extendedResults)
            _ExtendedFriendRow(friend: ef, onTap: () => showExtendedProfileSheet(context, ef)),
        ],
      ],
    );
  }
}

/// A single friend row: avatar, name, last-call summary, and two actions --
/// chat (left) and call (right). Mood/rename/remove/cognitive-sharing
/// intentionally live one level down (FriendProfileScreen) rather than
/// crowding this row with more icons than a glance needs.
class _FriendRow extends StatelessWidget {
  final Friend friend;
  final int unreadMessages;
  final VoidCallback onTap;
  final VoidCallback onChat;
  final VoidCallback onCall;

  const _FriendRow({
    required this.friend,
    required this.unreadMessages,
    required this.onTap,
    required this.onChat,
    required this.onCall,
  });

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
              children: [
                InitialAvatar(name: friend.displayName, imageUrl: friend.profilePictureUrl),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        friend.displayName,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.dmText),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (friend.lastCallAt != null) ...[
                            Icon(
                              friend.lastCallOutgoing == true ? Icons.call_made : Icons.call_received,
                              size: 14,
                              color: AppColors.dmTextSoft,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              formatLastCallSubtitle(
                                lastCallAt: friend.lastCallAt,
                                lastCallOutgoing: friend.lastCallOutgoing,
                                callCount: friend.callCount,
                              ),
                              style: TextStyle(fontSize: 13.5, color: AppColors.dmTextSoft),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _ChatButton(onPressed: onChat, unreadCount: unreadMessages),
                const SizedBox(width: 8),
                _CallButton(onPressed: onCall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A friends-of-friends search result -- same card shape as _FriendRow for
/// visual consistency, but no chat/call actions (not a direct friend) and
/// a "via {mutual friend}" subtitle instead of a call-history one. Tapping
/// opens the read-only extended-profile sheet, never a chat/call screen.
class _ExtendedFriendRow extends StatelessWidget {
  final ExtendedFriend friend;
  final VoidCallback onTap;

  const _ExtendedFriendRow({required this.friend, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.dmBubbleIn,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dmBubbleBorder.withValues(alpha: 0.6), style: BorderStyle.solid),
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
              children: [
                InitialAvatar(name: friend.username, imageUrl: friend.profilePictureUrl),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        friend.username,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.dmText),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        friend.mutualVia.isEmpty ? 'In your network' : 'via ${friend.mutualVia.join(', ')}',
                        style: TextStyle(fontSize: 13.5, color: AppColors.dmTextSoft),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.dmTextSoft),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatButton extends StatelessWidget {
  final VoidCallback onPressed;
  final int unreadCount;
  const _ChatButton({required this.onPressed, this.unreadCount = 0});

  @override
  Widget build(BuildContext context) {
    // Was 10px padding around a 20px icon (40x40 total) with no tooltip --
    // below the 48px minimum tap target, and sitting directly adjacent to
    // _CallButton below made a mis-tap between the two more likely. Bumped
    // to reach 48px and labeled for screen readers.
    final button = Tooltip(
      message: 'Message',
      child: Material(
        color: AppColors.dmPillFill,
        shape: CircleBorder(side: BorderSide(color: AppColors.dmBubbleBorder)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Icon(Icons.chat_bubble_outline, color: AppColors.dmAccent, size: 20),
          ),
        ),
      ),
    );
    return unreadCount > 0 ? Badge(label: Text('$unreadCount'), child: button) : button;
  }
}

class _CallButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _CallButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    // Same fix as _ChatButton above -- 48px tap target + tooltip instead of
    // a 40px unlabeled one immediately next to it.
    return Tooltip(
      message: 'Call',
      child: Material(
        color: AppColors.dmBubbleOut,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Icon(Icons.call, color: AppColors.dmAccent, size: 20),
          ),
        ),
      ),
    );
  }
}
