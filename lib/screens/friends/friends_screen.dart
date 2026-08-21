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
import '../../widgets/offline_banner.dart';
import 'direct_message_screen.dart';
import 'friend_profile_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _service = FriendService();
  final _messageService = MessageService();
  final _codeController = TextEditingController();
  List<Friend>? _friends;
  bool _loading = true;
  Object? _loadError;
  bool _offline = false;
  bool _adding = false;
  String? _error;
  bool _pickingCall = false;
  final Set<int> _callSelection = {};

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
    return Scaffold(
      appBar: AppBar(
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
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(hintText: "Friend's code", isDense: true),
                          onSubmitted: (_) => _addFriend(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
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
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Pick who to call, then confirm below.', style: TextStyle(color: AppColors.textSoft)),
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
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: Text(_callSelection.isEmpty ? 'Call' : 'Call (${_callSelection.length})'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildList(Map<int, int> directMessageBadges) {
    if (_friends == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return Center(child: Text('Failed to load friends: $_loadError'));
    }
    final friends = _friends!;
    if (friends.isEmpty) {
      return Center(
        child: Text('No friends added yet', style: TextStyle(color: AppColors.textSoft)),
      );
    }
    return ListView.separated(
      itemCount: friends.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
      itemBuilder: (context, i) {
        final f = friends[i];
        if (_pickingCall) {
          final selected = _callSelection.contains(f.id);
          return CheckboxListTile(
            value: selected,
            activeColor: AppColors.accent,
            onChanged: (v) => setState(() {
              if (v == true) {
                _callSelection.add(f.id);
              } else {
                _callSelection.remove(f.id);
              }
            }),
            secondary: InitialAvatar(name: f.displayName),
            title: Text(f.displayName),
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
    return Material(
      color: AppColors.panel,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              InitialAvatar(name: friend.displayName),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      friend.displayName,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (friend.lastCallAt != null) ...[
                          Icon(
                            friend.lastCallOutgoing == true ? Icons.call_made : Icons.call_received,
                            size: 14,
                            color: AppColors.textSoft,
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
                            style: TextStyle(fontSize: 13.5, color: AppColors.textSoft),
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
    );
  }
}

class _ChatButton extends StatelessWidget {
  final VoidCallback onPressed;
  final int unreadCount;
  const _ChatButton({required this.onPressed, this.unreadCount = 0});

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: AppColors.panel,
      shape: CircleBorder(side: BorderSide(color: AppColors.border)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.chat_bubble_outline, color: AppColors.accentDark, size: 20),
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
    return Material(
      color: AppColors.bubbleOut,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.call, color: AppColors.accentDark, size: 20),
        ),
      ),
    );
  }
}
