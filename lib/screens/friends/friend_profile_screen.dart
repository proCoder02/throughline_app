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
import '../../widgets/photo_viewer.dart';
import '../../widgets/settings_style_card.dart';
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
        profilePictureUrl: _friend.profilePictureUrl,
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
        title: Text(_friend.displayName),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // ── Header: big avatar + name, contact-card style ──
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _friend.profilePictureUrl != null
                      ? () => showPhotoViewer(context, imageUrl: _friend.profilePictureUrl!)
                      : null,
                  child: InitialAvatar(name: _friend.displayName, size: 92, imageUrl: _friend.profilePictureUrl),
                ),
                const SizedBox(height: 14),
                Text(
                  _friend.displayName,
                  style: appHeadlineFont(color: AppColors.dmText, fontSize: 21),
                ),
                if (_friend.nickname != null && _friend.nickname!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(_friend.username, style: TextStyle(fontSize: 13.5, color: AppColors.dmTextSoft)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // ── Action row: glass circular chips, contact-card style ──
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.dmBubbleIn,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.dmBubbleBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ProfileAction(icon: Icons.chat_bubble_outline, label: 'Message', onTap: _openChat),
                _ProfileAction(icon: Icons.call_outlined, label: 'Call', onTap: _startCall),
                _ProfileAction(icon: Icons.edit_outlined, label: 'Nickname', onTap: _rename),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Quick stats: real data only (call count / last call / mood) ──
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.dmBubbleIn,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.dmBubbleBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _StatTile(
                    value: '${_friend.callCount}',
                    label: _friend.callCount == 1 ? 'Call' : 'Calls',
                  ),
                ),
                Container(width: 1, height: 30, color: AppColors.dmBubbleBorder),
                Expanded(
                  child: _StatTile(
                    value: _friend.lastCallAt != null ? formatCallTimestamp(_friend.lastCallAt!) : '—',
                    label: 'Last call',
                  ),
                ),
                Container(width: 1, height: 30, color: AppColors.dmBubbleBorder),
                Expanded(
                  child: _StatTile(
                    value: _mood?.emoji ?? '—',
                    label: 'Mood',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Everything below is always visible -- no tab-switching ──
          SettingsStyleCard(
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
                          style: TextStyle(fontSize: 13, color: AppColors.dmTextSoft),
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
                    style: TextStyle(fontSize: 13, color: AppColors.dmTextSoft),
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

          SettingsStyleCard(
            title: 'Mood',
            children: [
              if (_mood == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_mood!.emoji == null)
                Text('No mood data logged yet today.', style: TextStyle(color: AppColors.dmTextSoft, fontSize: 13))
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
                            style: TextStyle(fontSize: 12, color: AppColors.dmTextSoft),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),

          SettingsStyleCard(
            title: 'Calls',
            children: [
              if (_callHistory == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_callHistory!.isEmpty)
                Text('No calls yet.', style: TextStyle(color: AppColors.dmTextSoft, fontSize: 13))
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
                          color: c.missed ? AppColors.danger : AppColors.dmAccent,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          c.missed ? 'Missed call' : (c.outgoing ? 'Outgoing' : 'Incoming'),
                          style: TextStyle(fontSize: 14, color: c.missed ? AppColors.danger : AppColors.dmText),
                        ),
                        const Spacer(),
                        Text(
                          !c.missed && duration != null && duration.inSeconds > 0
                              ? '${formatCallTimestamp(c.createdAt)} · ${_formatDuration(duration)}'
                              : formatCallTimestamp(c.createdAt),
                          style: TextStyle(fontSize: 12.5, color: AppColors.dmTextSoft),
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
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;

  const _StatTile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.dmText)),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.dmTextSoft)),
      ],
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
    // Was 4px padding on each side -- the tightest tap cushion of any
    // icon-affordance in the app per this session's audit. Bumped to 8px;
    // kept modest (not the full 14px used by Friends' icon-only circles)
    // since this Row has 3 items under spaceEvenly and a visible text
    // label already, so it doesn't need as much invisible padding to read
    // as tappable.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.dmAccent, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.dmTextSoft)),
          ],
        ),
      ),
    );
  }
}

