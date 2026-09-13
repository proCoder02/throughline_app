import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/friend.dart';
import '../../services/friend_service.dart';
import '../../theme.dart';
import '../../widgets/pulsing_halo.dart';

/// Concept sandbox for a possible "Your World" screen -- a vertical
/// relationship thread ("You" at the top, real friends branching alternately
/// left/right off it) with a bottom detail card for whichever friend is
/// tapped. Reachable only from Settings, no production screen references
/// this.
///
/// Friends only for now, real data from `GET /friends` (+ a lazy per-friend
/// `GET /friends/<id>/mood` on tap) -- an earlier version also tried to
/// join against `GET /profiles` (people detected in Listen recordings) by
/// matching names, but that's a genuinely separate identity space in this
/// schema (a friend you've never mentioned by name in a recording has no
/// profile row at all, regardless of how real the friendship is), so it
/// produced misleading empty states for real friends. Dropped until/unless
/// there's an actual link between the two (see the doc comment this screen
/// had before: a `friend_user_id` column on speaker_profiles, or a mapping
/// table, would be the real backend fix for that).
class YourWorldPreviewScreen extends StatefulWidget {
  const YourWorldPreviewScreen({super.key});

  @override
  State<YourWorldPreviewScreen> createState() => _YourWorldPreviewScreenState();
}

class _YourWorldPreviewScreenState extends State<YourWorldPreviewScreen> {
  final _friendService = FriendService();

  List<Friend>? _friends;
  Object? _error;
  int? _activeFriendId;

  // Fetched lazily per friend (only once, on first becoming active) rather
  // than all at once for every friend up front -- moods aren't returned by
  // GET /friends itself, and fetching every friend's mood just to render a
  // thread map nobody's looked at yet would be a lot of unnecessary calls.
  final Map<int, CompiledMood?> _moods = {};
  final Set<int> _moodLoading = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final friends = await _friendService.list();
      if (!mounted) return;
      setState(() {
        _friends = friends;
        _activeFriendId ??= friends.isNotEmpty ? friends.first.id : null;
      });
      if (_activeFriendId != null) _ensureMood(_activeFriendId!);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _ensureMood(int friendId) async {
    if (_moods.containsKey(friendId) || _moodLoading.contains(friendId)) return;
    _moodLoading.add(friendId);
    try {
      final mood = await _friendService.mood(friendId);
      if (mounted) setState(() => _moods[friendId] = mood);
    } catch (_) {
      if (mounted) setState(() => _moods[friendId] = null);
    } finally {
      _moodLoading.remove(friendId);
    }
  }

  void _setActive(int friendId) {
    setState(() => _activeFriendId = friendId);
    _ensureMood(friendId);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppColors.dmGradient,
      )),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: AppColors.dmText),
          titleTextStyle: appHeadlineFont(color: AppColors.dmText, fontSize: 18),
          title: const Text('Your World Concept'),
        ),
        body: SafeArea(child: _body()),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, color: AppColors.dmTextSoft, size: 32),
              const SizedBox(height: 10),
              Text('Could not load friends/profiles.', style: TextStyle(color: AppColors.dmTextSoft)),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final friends = _friends;
    if (friends == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (friends.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Add a friend to see your relationship thread here.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.dmTextSoft)),
        ),
      );
    }

    final activeFriend = friends.firstWhere((f) => f.id == _activeFriendId, orElse: () => friends.first);
    return Column(
      children: [
        Text('Your World', style: appHeadlineFont(color: AppColors.dmText, fontSize: 26)),
        const SizedBox(height: 2),
        const Text(
          'RELATIONAL COGNITIVE THREAD',
          style: TextStyle(fontSize: 10.5, letterSpacing: 3, color: AppColors.dmAccent),
        ),
        Expanded(
          child: _ThreadMap(
            friends: friends,
            activeFriendId: _activeFriendId,
            onTapFriend: _setActive,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _DetailCard(
            friend: activeFriend,
            mood: _moods[activeFriend.id],
            moodFetched: _moods.containsKey(activeFriend.id),
            moodLoading: _moodLoading.contains(activeFriend.id),
          ),
        ),
      ],
    );
  }
}

class _ThreadMap extends StatelessWidget {
  final List<Friend> friends;
  final int? activeFriendId;
  final ValueChanged<int> onTapFriend;

  const _ThreadMap({required this.friends, required this.activeFriendId, required this.onTapFriend});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        const Positioned.fill(child: _LivingThreadLine()),
        Positioned(
          top: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.dmPillFill,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.dmBubbleBorder),
            ),
            child: Text('You', style: appHeadlineFont(color: AppColors.dmAccent, fontSize: 14)),
          ),
        ),
        Positioned(
          top: 48,
          left: 0,
          right: 0,
          bottom: 8,
          // Scrollable, not evenly-spaced -- the actual friend count is
          // real and unbounded (0 to however many you have), unlike the
          // original mockup's fixed 4 nodes.
          child: ListView.builder(
            itemCount: friends.length,
            itemBuilder: (context, i) {
              final friend = friends[i];
              return _FriendRow(
                friend: friend,
                labelOnRight: i.isEven,
                active: friend.id == activeFriendId,
                onTap: () => onTapFriend(friend.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The thread itself -- "keeps track of all your aspects of life,
/// relationships etc." -- so it's rendered as visibly alive rather than a
/// static rule: a soft pulse of light continuously travels its length,
/// looping, on top of a faint static base line.
class _LivingThreadLine extends StatefulWidget {
  const _LivingThreadLine();

  @override
  State<_LivingThreadLine> createState() => _LivingThreadLineState();
}

class _LivingThreadLineState extends State<_LivingThreadLine> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: SizedBox(
          width: 24,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(painter: _ThreadPainter(progress: _controller.value)),
          ),
        ),
      ),
    );
  }
}

class _ThreadPainter extends CustomPainter {
  final double progress;
  _ThreadPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final base = Paint()
      ..strokeWidth = 2
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.dmAccent.withValues(alpha: 0.08),
          AppColors.dmAccent.withValues(alpha: 0.35),
          AppColors.dmAccent.withValues(alpha: 0.08),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), base);

    final pulseCenter = progress * size.height;
    final pulse = Paint()
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, AppColors.dmAccent, Colors.transparent],
      ).createShader(Rect.fromLTWH(0, pulseCenter - 36, size.width, 72));
    canvas.drawLine(Offset(x, pulseCenter - 36), Offset(x, pulseCenter + 36), pulse);
  }

  @override
  bool shouldRepaint(covariant _ThreadPainter oldDelegate) => oldDelegate.progress != progress;
}

class _FriendRow extends StatelessWidget {
  final Friend friend;
  final bool labelOnRight;
  final bool active;
  final VoidCallback onTap;

  const _FriendRow({required this.friend, required this.labelOnRight, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dot = PulsingHalo(
      active: active,
      color: AppColors.dmAccent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: active ? 16 : 12,
        height: active ? 16 : 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? AppColors.dmAccent : AppColors.dmAccent.withValues(alpha: 0.4),
          border: Border.all(color: active ? AppColors.dmText : AppColors.dmAccent, width: active ? 2 : 1),
        ),
      ),
    );

    final label = active
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.dmAccent.withValues(alpha: 0.12),
              border: Border.all(color: AppColors.dmAccent.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(friend.displayName,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.dmAccent)),
          )
        : Text(friend.displayName,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.dmTextSoft));

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: labelOnRight ? const SizedBox.shrink() : label),
            ),
            const SizedBox(width: 14),
            dot,
            const SizedBox(width: 14),
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: labelOnRight ? label : const SizedBox.shrink()),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final Friend friend;
  final CompiledMood? mood;
  final bool moodFetched;
  final bool moodLoading;

  const _DetailCard({
    required this.friend,
    required this.mood,
    required this.moodFetched,
    required this.moodLoading,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: Container(
        key: ValueKey(friend.id),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.dmBubbleIn,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.dmBubbleBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(friend.displayName, style: appHeadlineFont(color: AppColors.dmText, fontSize: 16)),
                ),
                const Text('NODE EXPANDED',
                    style: TextStyle(fontSize: 9.5, letterSpacing: 1, color: AppColors.dmAccent, fontWeight: FontWeight.w600)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: AppColors.dmBubbleBorder, height: 1),
            ),
            _row('Calls', friend.callCount == 0 ? 'No calls yet' : '${friend.callCount} total'),
            const SizedBox(height: 6),
            _row('Last call', _lastCallText()),
            const SizedBox(height: 6),
            _row('Mood', _moodText()),
          ],
        ),
      ),
    );
  }

  String _lastCallText() {
    final at = friend.lastCallAt;
    if (at == null) return 'Never';
    final direction = friend.lastCallOutgoing == true ? 'Outgoing' : 'Incoming';
    return '$direction • ${DateFormat.MMMd().add_jm().format(at)}';
  }

  String _moodText() {
    if (moodLoading || !moodFetched) return 'Loading...';
    final m = mood;
    if (m == null || m.moodLabel == null) return 'Not enough recent data';
    return '${m.emoji ?? ''} ${m.moodLabel}'.trim();
  }

  Widget _row(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.dmPillFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.dmBubbleBorder),
        ),
        child: Row(
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(
                    fontSize: 9.5, color: AppColors.dmAccent, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            const Spacer(),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right, style: TextStyle(fontSize: 12.5, color: AppColors.dmText)),
            ),
          ],
        ),
      );
}
