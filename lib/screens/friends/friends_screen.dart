import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/friend.dart';
import '../../services/friend_service.dart';
import '../../state/call_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme.dart';
import '../../utils/call_format.dart';
import '../../widgets/avatar.dart';
import 'call_history_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _service = FriendService();
  final _codeController = TextEditingController();
  late Future<List<Friend>> _future;
  bool _adding = false;
  String? _error;
  bool _pickingCall = false;
  final Set<int> _callSelection = {};

  @override
  void initState() {
    super.initState();
    _future = _service.list();
  }

  void _reload() {
    final future = _service.list();
    setState(() {
      _future = future;
    });
  }

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
    // Rename/remove happen inside CallHistoryScreen's app bar -- reload on
    // return so a changed nickname or a removal shows up immediately.
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallHistoryScreen(friend: f)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
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
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _reload(),
              child: FutureBuilder<List<Friend>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(child: Text('Failed to load friends: ${snap.error}'));
                  }
                  final friends = snap.data ?? [];
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
                        onTap: () => _openFriend(f),
                        onCall: () => _startCall([f.id]),
                      );
                    },
                  );
                },
              ),
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
}

/// A single friend row: avatar, name, last-call summary, and a single
/// prominent call action. Mood/rename/remove intentionally live one level
/// down (CallHistoryScreen's app bar) rather than crowding this row with
/// more icons than a glance needs.
class _FriendRow extends StatelessWidget {
  final Friend friend;
  final VoidCallback onTap;
  final VoidCallback onCall;

  const _FriendRow({required this.friend, required this.onTap, required this.onCall});

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
              _CallButton(onPressed: onCall),
            ],
          ),
        ),
      ),
    );
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
