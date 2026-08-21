import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/friend.dart';
import '../../services/friend_service.dart';
import '../../state/call_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme.dart';
import '../../utils/call_format.dart';
import '../../widgets/avatar.dart';
import '../../widgets/toggle_group.dart';
import 'direct_message_screen.dart';

/// WhatsApp-contact-screen style: big avatar + name up top, Message/Call
/// actions, then every section of "detail that can be edited" visible at
/// once in one scroll -- mood, cognitive sharing, call history, nickname,
/// remove -- rather than the previous CallHistoryScreen/FriendMoodScreen
/// split across two separate screens reached via app-bar icons.
class FriendProfileScreen extends StatefulWidget {
  final Friend friend;

  const FriendProfileScreen({super.key, required this.friend});

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  final _service = FriendService();
  late Friend _friend;

  CompiledMood? _mood;
  List<CallHistoryEntry>? _callHistory;
  CognitiveSharingStatus? _sharing;
  bool _sharingLoadFailed = false;
  bool _savingSharing = false;

  @override
  void initState() {
    super.initState();
    _friend = widget.friend;
    _loadAll();
  }

  void _loadAll() {
    _service.mood(_friend.id).then((v) {
      if (mounted) setState(() => _mood = v);
    }).catchError((_) {});
    _service.callHistory(_friend.id).then((v) {
      if (mounted) setState(() => _callHistory = v);
    }).catchError((_) {
      if (mounted) setState(() => _callHistory = []);
    });
    _loadSharing();
  }

  void _loadSharing() {
    setState(() => _sharingLoadFailed = false);
    _service.getCognitiveSharing(_friend.id).then((v) {
      if (mounted) setState(() => _sharing = v);
    }).catchError((_) {
      if (mounted) setState(() => _sharingLoadFailed = true);
    });
  }

  Future<void> _setSharingLevel(String level) async {
    if (_savingSharing) return;
    setState(() => _savingSharing = true);
    try {
      final fresh = await _service.setCognitiveSharing(_friend.id, level);
      if (mounted) setState(() => _sharing = fresh);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingSharing = false);
    }
  }

  Future<void> _openChat() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DirectMessageScreen(friend: _friend)));
  }

  Future<void> _startCall() async {
    try {
      await context.read<CallProvider>().startCall([_friend.id]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start call: $e')));
      }
    }
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _friend.nickname ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set nickname'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: _friend.username),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (result == null) return;
    final nickname = await _service.setNickname(_friend.id, result.trim());
    if (!mounted) return;
    setState(() {
      _friend = Friend(
        id: _friend.id,
        username: _friend.username,
        nickname: nickname,
        lastCallAt: _friend.lastCallAt,
        lastCallOutgoing: _friend.lastCallOutgoing,
        callCount: _friend.callCount,
      );
    });
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove friend'),
        content: Text('Remove ${_friend.displayName} from your friends? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.remove(_friend.id);
    if (mounted) Navigator.of(context).pop();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(title: Text(_friend.displayName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          // ── Header: big avatar + name, WhatsApp-contact-screen style ──
          Center(
            child: Column(
              children: [
                InitialAvatar(name: _friend.displayName, size: 88),
                const SizedBox(height: 12),
                Text(
                  _friend.displayName,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text),
                ),
                if (_friend.nickname != null && _friend.nickname!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(_friend.username, style: TextStyle(fontSize: 13.5, color: AppColors.textSoft)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Action row ──
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ProfileAction(icon: Icons.chat_bubble_outline, label: 'Message', onTap: _openChat),
              const SizedBox(width: 36),
              _ProfileAction(icon: Icons.call_outlined, label: 'Call', onTap: _startCall),
              const SizedBox(width: 36),
              _ProfileAction(icon: Icons.edit_outlined, label: 'Nickname', onTap: _rename),
            ],
          ),
          const SizedBox(height: 8),

          // ── Everything below is always visible -- no tab-switching ──
          _ProfileCard(
            title: 'Cognitive Sharing',
            children: [
              if (_sharing == null && _sharingLoadFailed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Couldn't load sharing settings.",
                          style: TextStyle(fontSize: 13, color: AppColors.textSoft),
                        ),
                      ),
                      TextButton(onPressed: _loadSharing, child: const Text('Retry')),
                    ],
                  ),
                )
              else if (_sharing == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    _sharing!.bothEnabled
                        ? 'You and ${_friend.displayName} can both see mutually-helpful suggestions.'
                        : 'Both of you need to turn this on before suggestions can appear.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSoft),
                  ),
                ),
                // Same toggle-switch look as Settings' "Smart features" card
                // -- deliberately, per the ask to match that page's style.
                // The 3-level backend enum (off/limited/collaborative) maps
                // onto two switches: the parent is off<->limited, the child
                // (only enabled once the parent is on) is limited<->collaborative.
                Opacity(
                  opacity: _savingSharing ? 0.6 : 1,
                  child: AbsorbPointer(
                    absorbing: _savingSharing,
                    child: Column(
                      children: [
                        ToggleParentTile(
                          icon: Icons.psychology_outlined,
                          title: 'Cognitive Sharing',
                          subtitle: _sharing!.myLevel == 'off'
                              ? 'Your private cognitive information stays private.'
                              : 'AI may use selected context to find mutually useful outcomes.',
                          value: _sharing!.myLevel != 'off',
                          onChanged: (v) => _setSharingLevel(v ? 'limited' : 'off'),
                        ),
                        ToggleGroup(
                          children: [
                            ToggleChildTile(
                              title: 'Collaborative mode',
                              subtitle: 'AI can use approved context to actively help both of you coordinate.',
                              value: _sharing!.myLevel == 'collaborative',
                              enabled: _sharing!.myLevel != 'off',
                              onChanged: (v) => _setSharingLevel(v ? 'collaborative' : 'limited'),
                              isLast: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),

          _ProfileCard(
            title: 'Mood',
            children: [
              if (_mood == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_mood!.emoji == null)
                Text('No mood data logged yet today.', style: TextStyle(color: AppColors.textSoft, fontSize: 13))
              else
                Row(
                  children: [
                    Text(_mood!.emoji!, style: const TextStyle(fontSize: 40)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _mood!.moodLabel![0].toUpperCase() + _mood!.moodLabel!.substring(1),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'As of ${DateFormat.Hm().format(_mood!.windowStart)}–${DateFormat.Hm().format(_mood!.windowEnd)}',
                            style: TextStyle(fontSize: 12, color: AppColors.textSoft),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),

          _ProfileCard(
            title: 'Calls',
            children: [
              if (_callHistory == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_callHistory!.isEmpty)
                Text('No calls yet.', style: TextStyle(color: AppColors.textSoft, fontSize: 13))
              else
                ..._callHistory!.map((c) {
                  final duration = c.endedAt?.difference(c.createdAt);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          c.missed
                              ? Icons.call_missed
                              : (c.outgoing ? Icons.call_made : Icons.call_received),
                          size: 18,
                          color: c.missed ? AppColors.danger : AppColors.accent,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          c.missed ? 'Missed call' : (c.outgoing ? 'Outgoing' : 'Incoming'),
                          style: TextStyle(fontSize: 14, color: c.missed ? AppColors.danger : AppColors.text),
                        ),
                        const Spacer(),
                        Text(
                          !c.missed && duration != null && duration.inSeconds > 0
                              ? '${formatCallTimestamp(c.createdAt)} · ${_formatDuration(duration)}'
                              : formatCallTimestamp(c.createdAt),
                          style: TextStyle(fontSize: 12.5, color: AppColors.textSoft),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),

          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.person_remove_outlined),
              label: const Text('Remove friend'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _remove,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ProfileAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.accent, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
          ],
        ),
      ),
    );
  }
}

/// Same bordered-card look as Settings' _SettingsCard -- deliberately, so
/// this profile screen's sections read as visually consistent with the
/// settings page per the ask.
class _ProfileCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _ProfileCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  title,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text),
                ),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
