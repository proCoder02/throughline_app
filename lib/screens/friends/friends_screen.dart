import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/friend.dart';
import '../../services/friend_service.dart';
import '../../state/call_provider.dart';
import '../../theme.dart';
import '../../widgets/avatar.dart';
import 'friend_mood_screen.dart';

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

  @override
  Widget build(BuildContext context) {
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
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeController,
                          decoration: const InputDecoration(
                            hintText: 'Friend code',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(onPressed: _adding ? null : _addFriend, child: const Text('Add')),
                    ],
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
                    ),
                ],
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
                    return const Center(child: Text('No friends yet', style: TextStyle(color: AppColors.textSoft)));
                  }
                  return ListView.separated(
                    itemCount: friends.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, i) {
                      final f = friends[i];
                      if (_pickingCall) {
                        final selected = _callSelection.contains(f.id);
                        return CheckboxListTile(
                          value: selected,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _callSelection.add(f.id);
                            } else {
                              _callSelection.remove(f.id);
                            }
                          }),
                          secondary: InitialAvatar(name: f.username),
                          title: Text(f.username),
                        );
                      }
                      return ListTile(
                        tileColor: AppColors.panel,
                        leading: InitialAvatar(name: f.username),
                        title: Text(f.username),
                        subtitle: const Text('Tap to view mood timeline'),
                        trailing: IconButton(
                          icon: const Icon(Icons.call, color: AppColors.accent),
                          onPressed: () => _startCall([f.id]),
                        ),
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => FriendMoodScreen(friend: f))),
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
                padding: const EdgeInsets.all(12),
                child: ElevatedButton(
                  onPressed: _callSelection.isEmpty ? null : _confirmGroupCall,
                  child: Text('Call ${_callSelection.length}'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
