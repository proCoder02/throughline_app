import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/conversation.dart';
import '../../models/friend.dart';
import '../../models/task.dart';
import '../../models/weekly_digest.dart';
import '../../services/conversation_service.dart';
import '../../services/digest_service.dart';
import '../../services/friend_service.dart';
import '../../services/local_cache.dart';
import '../../services/task_service.dart';
import '../../state/auth_provider.dart';
import '../../theme.dart';
import '../../widgets/animated_task_checkbox.dart';
import '../../widgets/glowing_border.dart';
import '../../widgets/pulsing_halo.dart';
import '../../widgets/tap_bounce.dart';
import '../chats/global_chat_body.dart';
import '../settings/your_world_preview_screen.dart';

/// Home tab -- a single-glance dashboard (greeting, one AI insight, quick
/// actions, upcoming reminders, recent activity, and a persona-derived
/// "Your World" strip), matching the approved reference layout component-
/// for-component. Uses the same warm-gradient palette (AppColors.dmGradient/
/// dmText/dmTextSoft/dmBubbleIn/dmBubbleBorder/dmAccent) as every other
/// main-tab screen (Chats/Tasks/Profiles/Friends/Settings) -- this was
/// deliberately neutral/colorless at first while the layout was still being
/// worked out, now matched to the real app palette.
///
/// Every section loads its own real data (persona, weekly digest, tasks,
/// recent conversations) and fails silently to an empty/placeholder state
/// rather than blocking the rest of the screen -- same self-contained,
/// best-effort convention MoodTrendCard already uses elsewhere. The one
/// exception is the weather chip: there is no weather integration anywhere
/// in this app, so it renders as a plainly-labeled placeholder, not real data.
class HomeScreen extends StatefulWidget {
  /// Quick Actions need to switch tabs (Tasks/People), which only
  /// HomeShell's own state owns -- passed down rather than duplicating tab
  /// index state here.
  final ValueChanged<int> onNavigateToTab;

  /// Opens HomeShell's side drawer (Chats/Tasks/Profiles/Friends/Settings --
  /// the bottom nav's replacement) via the top-left menu icon. A plain
  /// Scaffold.of(context).openDrawer() from in here would find this screen's
  /// own nested Scaffold instead of HomeShell's outer one, so HomeShell hands
  /// down a direct trigger instead.
  final VoidCallback onOpenDrawer;

  const HomeScreen(
      {super.key, required this.onNavigateToTab, required this.onOpenDrawer});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _digestService = DigestService();
  final _taskService = TaskService();
  final _conversationService = ConversationService();
  final _friendService = FriendService();

  WeeklyDigest? _digest;
  List<Task> _openTasks = [];
  List<Conversation> _recentConversations = [];
  List<Friend> _friends = [];
  bool _loaded = false;

  /// This week's relationship-category digest cards -- the real, already
  /// server-generated signal behind the "Your World" teaser's dynamism (see
  /// _WorldTeaserCard's doc comment). Never fabricated: empty just means
  /// nothing relationship-related was actually detected this week.
  List<DigestCard> get _relationshipCards =>
      _digest?.cards.where((c) => c.category == 'relationship').toList() ??
      const [];

  /// True only when there's a relationship card from a digest genuinely
  /// newer than the last one the user actually opened the teaser for --
  /// never perpetual, never shown just because content exists.
  bool get _hasNewWorldSignal {
    final digest = _digest;
    if (digest == null || _relationshipCards.isEmpty) return false;
    final lastSeen = LocalCache.instance.getLastSeenWorldDigestAt();
    return lastSeen == null || digest.generatedAt.isAfter(lastSeen);
  }

  void _openWorldTeaser() {
    final digest = _digest;
    if (digest != null) {
      LocalCache.instance.setLastSeenWorldDigestAt(digest.generatedAt);
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const YourWorldPreviewScreen()));
  }

  // The chat used to live on its own pushed route (Navigator.push), which is
  // exactly what read as "glitchy" -- a full-screen route transition for
  // what should feel like the same surface expanding in place. Toggling
  // this instead swaps AnimatedSwitcher's child within the same screen/
  // route -- no page transition exists to be glitchy. This is deliberately
  // a plain crossfade (AnimatedSwitcher's own FadeTransition), not a custom
  // effect -- that's genuinely how ChatGPT's own home-to-chat transition
  // works too, not a particle/dissolve effect.
  bool _chatOpen = false;
  bool _chatAutoPickImage = false;
  String? _chatInitialPrompt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _digestService.fetch().catchError((_) => null),
      _taskService.list(status: 'open').catchError((_) => <Task>[]),
      _conversationService.list().catchError((_) => <Conversation>[]),
      _friendService.list().catchError((_) => <Friend>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _digest = results[0] as WeeklyDigest?;
      _openTasks = results[1] as List<Task>;
      _recentConversations = results[2] as List<Conversation>;
      _friends = results[3] as List<Friend>;
      _loaded = true;
    });
  }

  void _openChat({bool autoPickImage = false, String? initialPrompt}) {
    setState(() {
      _chatOpen = true;
      _chatAutoPickImage = autoPickImage;
      _chatInitialPrompt = initialPrompt;
    });
  }

  /// "View Summary" on the Insight card -- opens the embedded chat and
  /// immediately asks about that specific digest card, so the reply is
  /// actually grounded in it rather than landing on an empty thread.
  void _openChatWithSummary(DigestCard card) {
    final prompt = StringBuffer('Tell me more about this: ${card.headline}');
    if (card.body.trim().isNotEmpty) prompt.write('\n\n${card.body}');
    _openChat(initialPrompt: prompt.toString());
  }

  void _closeChat() => setState(() => _chatOpen = false);

  /// The row itself already played the checkmark animation and waited for
  /// it before calling this -- this just does the real completion (best-
  /// effort; the task simply reappears next reload if the request fails)
  /// and drops it from the visible list.
  Future<void> _completeReminderTask(Task task) async {
    try {
      await _taskService.complete(task.id);
    } catch (_) {
      // Best-effort -- see doc comment above.
    }
    if (mounted) {
      setState(() => _openTasks = _openTasks.where((t) => t.id != task.id).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Good Morning'
        : (hour < 17 ? 'Good Afternoon' : 'Good Evening');
    final firstCard =
        _digest?.cards.isNotEmpty == true ? _digest!.cards.first : null;

    return Container(
      // Same warm-gradient wallpaper as every other main-tab screen -- see
      // AppColors.dmGradient's doc comment in theme.dart.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.dmGradient,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          // Wraps the WHOLE screen (top bar included), not just the middle
          // content -- tapping any chat-opening control fades every
          // dashboard element away together, leaving the chat as the only
          // thing on screen, rather than just swapping the content below a
          // top bar that stays put. GlobalChatBody supplies its own
          // back+title header once it's the only thing showing. Plain
          // crossfade on purpose -- this is genuinely how ChatGPT's own
          // home-to-chat transition works.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: _chatOpen
                ? GlobalChatBody(
                    key: const ValueKey('chat'),
                    onBack: _closeChat,
                    autoPickImage: _chatAutoPickImage,
                    initialPrompt: _chatInitialPrompt,
                  )
                : Column(
                    key: const ValueKey('dashboard'),
                    children: [
                      _TopBar(
                        onMenuTap: widget.onOpenDrawer,
                        onAvatarTap: () => widget.onNavigateToTab(5),
                        avatarUrl: auth.profilePictureUrl,
                        username: auth.username,
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                          children: [
                            _GreetingHeader(
                                    greeting: greeting,
                                    username: auth.username,
                                    now: now)
                                .animate()
                                .fadeIn(duration: 320.ms, curve: Curves.easeOut)
                                .slideY(
                                    begin: 0.08,
                                    end: 0,
                                    duration: 320.ms,
                                    curve: Curves.easeOut),
                            const SizedBox(height: 16),
                            _InsightCard(
                              headline: firstCard?.headline ??
                                  'Keep talking -- your first insight appears once there\'s enough to look at.',
                              body: firstCard?.body,
                              onViewSummary: firstCard != null
                                  ? () => _openChatWithSummary(firstCard)
                                  : null,
                            )
                                .animate()
                                .fadeIn(
                                    delay: 60.ms,
                                    duration: 320.ms,
                                    curve: Curves.easeOut)
                                .slideY(
                                    begin: 0.08,
                                    end: 0,
                                    delay: 60.ms,
                                    duration: 320.ms,
                                    curve: Curves.easeOut),
                            const SizedBox(height: 20),
                            // Right after the hero insight, before Quick
                            // Actions -- deliberately high for visibility
                            // (see the design discussion this came from):
                            // it's a new feature that needs discovery, so it
                            // gets primacy even though that pushes an
                            // already-learned control down slightly.
                            _WorldTeaserCard(
                              friends: _friends,
                              relationshipCards: _relationshipCards,
                              hasNew: _hasNewWorldSignal,
                              onTap: _openWorldTeaser,
                            )
                                .animate()
                                .fadeIn(
                                    delay: 100.ms,
                                    duration: 320.ms,
                                    curve: Curves.easeOut)
                                .slideY(
                                    begin: 0.08,
                                    end: 0,
                                    delay: 100.ms,
                                    duration: 320.ms,
                                    curve: Curves.easeOut),
                            const SizedBox(height: 20),
                            const _SectionHeader(title: 'Quick Actions'),
                            const SizedBox(height: 10),
                            _QuickActionsRow(
                              onChat: () => _openChat(),
                              onListen: () => widget.onNavigateToTab(1),
                              onTasks: () => widget.onNavigateToTab(2),
                              onPeople: () => widget.onNavigateToTab(4),
                              onAttach: () => _openChat(autoPickImage: true),
                            )
                                .animate()
                                .fadeIn(
                                    delay: 140.ms,
                                    duration: 320.ms,
                                    curve: Curves.easeOut)
                                .slideY(
                                    begin: 0.08,
                                    end: 0,
                                    delay: 140.ms,
                                    duration: 320.ms,
                                    curve: Curves.easeOut),
                            const SizedBox(height: 20),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _RemindersCard(
                                    loaded: _loaded,
                                    tasks: _openTasks,
                                    onSeeAll: () => widget.onNavigateToTab(2),
                                    onComplete: _completeReminderTask,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _RecentActivityCard(
                                    loaded: _loaded,
                                    conversations: _recentConversations,
                                  ),
                                ),
                              ],
                            )
                                .animate()
                                .fadeIn(
                                    delay: 200.ms,
                                    duration: 320.ms,
                                    curve: Curves.easeOut)
                                .slideY(
                                    begin: 0.08,
                                    end: 0,
                                    delay: 200.ms,
                                    duration: 320.ms,
                                    curve: Curves.easeOut),
                            const SizedBox(height: 20),
                            _WeeklyInsightCard(
                              insights: (_digest?.cards ?? [])
                                  .map((c) => c.body.trim().isNotEmpty
                                      ? c.body.trim()
                                      : c.headline.trim())
                                  .where((s) => s.isNotEmpty)
                                  .toList(),
                            )
                                .animate()
                                .fadeIn(
                                    delay: 260.ms,
                                    duration: 320.ms,
                                    curve: Curves.easeOut)
                                .slideY(
                                    begin: 0.08,
                                    end: 0,
                                    delay: 260.ms,
                                    duration: 320.ms,
                                    curve: Curves.easeOut),
                          ],
                        ),
                      ),
                      // Bottom-stacked (a normal flex child docked at the
                      // foot of the Column), not a floating overlay -- the
                      // previous FloatingActionButton approach reserved
                      // clearance sized for the (now-retired) bottom nav
                      // bar, which left a dead gap once that bar was hidden,
                      // and could overlap the last card if the ListView's
                      // own padding didn't happen to match. Being a real
                      // sibling of the ListView instead means it always
                      // sits flush against the screen edge (just past
                      // SafeArea) with zero manual clearance math, and can
                      // never overlap scrolled content since the ListView
                      // only ever occupies the space actually left over.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                        child: GlowingBorder(
                          borderRadius: 28,
                          child: _AskBar(onTap: () => _openChat()),
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

class _TopBar extends StatelessWidget {
  final VoidCallback onMenuTap;
  final VoidCallback onAvatarTap;
  final String? avatarUrl;
  final String? username;

  const _TopBar({
    required this.onMenuTap,
    required this.onAvatarTap,
    required this.avatarUrl,
    required this.username,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
              icon: const Icon(Icons.menu),
              color: AppColors.dmText,
              tooltip: 'Open menu',
              onPressed: onMenuTap),
          const SizedBox(width: 4),
          // Just a lightweight "you're in Throughline" anchor now that
          // there's no bottom nav bar -- the full name-plus-tagline block
          // this used to be was pure marketing copy repeated on every visit,
          // redundant with the personalized greeting right below it, and
          // most real apps (Gmail, WhatsApp, Instagram) show at most a small
          // icon/wordmark on their home screen, never a name+tagline.
          Icon(Icons.all_inclusive, color: AppColors.dmTextSoft, size: 22),
          const Spacer(),
          GestureDetector(
            onTap: onAvatarTap,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.dmBubbleBorder,
              backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
                  ? NetworkImage(avatarUrl!)
                  : null,
              child: (avatarUrl == null || avatarUrl!.isEmpty)
                  ? Text(
                      (username?.isNotEmpty == true ? username![0] : '?')
                          .toUpperCase(),
                      style: TextStyle(
                          color: AppColors.dmText, fontWeight: FontWeight.w700))
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  final String greeting;
  final String? username;
  final DateTime now;

  const _GreetingHeader(
      {required this.greeting, required this.username, required this.now});

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${_weekdays[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]} ${now.year}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.wb_sunny_outlined, color: AppColors.dmTextSoft, size: 26),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$greeting${username != null ? ', $username' : ''}',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.dmText)),
              const SizedBox(height: 2),
              Text("Here's what's happening with your world today.",
                  style:
                      TextStyle(fontSize: 12.5, color: AppColors.dmTextSoft)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(dateStr,
                style: TextStyle(fontSize: 11.5, color: AppColors.dmTextSoft)),
            const SizedBox(height: 4),
            // No weather integration exists anywhere in this app today --
            // shown as a plain placeholder chip, not real data, until one
            // is wired up.
            Row(
              children: [
                Icon(Icons.cloud_outlined,
                    size: 14, color: AppColors.dmTextSoft),
                const SizedBox(width: 3),
                Text('--Â°  Â·  --',
                    style:
                        TextStyle(fontSize: 11.5, color: AppColors.dmTextSoft)),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  final String headline;
  final String? body;
  final VoidCallback? onViewSummary;

  const _InsightCard({required this.headline, this.body, this.onViewSummary});

  @override
  Widget build(BuildContext context) {
    // A Border with a different color/width per side (the accent left
    // edge vs. the plain border on the other three) can't be painted as a
    // rounded rectangle -- Flutter falls back to square corners for a
    // non-uniform border regardless of borderRadius, which is exactly why
    // this card alone looked square next to every other rounded card on
    // the screen. Fixed by keeping the outer border uniform (rounded
    // corners work again) and drawing the accent stripe as a separate
    // overlay clipped to the same rounded shape instead.
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.dmBubbleIn,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dmBubbleBorder),
      ),
      child: Stack(
        children: [
          Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: Container(color: AppColors.dmAccent)),
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A small accent badge instead of a plain gray label -- signals
                // "personalized for you" at a glance, matching how Discover-style
                // surfaces (Spotify, Google) flag tailored content.
                Container(
                  padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
                  decoration: BoxDecoration(
                    color: AppColors.dmAccent.withValues(alpha: 0.14),
                    border: Border.all(
                        color: AppColors.dmAccent.withValues(alpha: 0.35)),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt, size: 12, color: AppColors.dmAccent),
                      SizedBox(width: 5),
                      Text('FOR YOU TODAY',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: AppColors.dmAccent)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // The one place asked for a rainbow effect -- everything else on
                // this card (label, body, button) stays the plain app palette.
                // Bigger than before (15 -> 19) -- this is the single most
                // important line on the screen, and it used to read barely
                // larger than a section header.
                _RainbowText(headline,
                    style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        height: 1.25)),
                if (body != null && body!.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  // Capped at 2 lines -- "View Summary" is the deep-dive
                  // affordance, so the card itself should stay scannable rather
                  // than risk turning into a wall of text on first glance.
                  Text(
                    body!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.dmTextSoft,
                        height: 1.4),
                  ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  // Deliberately plain -- no color animation on this button.
                  child: OutlinedButton.icon(
                    onPressed: onViewSummary,
                    icon: const Icon(Icons.arrow_forward, size: 14),
                    label: const Text('View Summary'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.dmText,
                      side: BorderSide(color: AppColors.dmBubbleBorder),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A fixed rainbow gradient painted through the text's own glyph shapes
/// (ShaderMask + BlendMode.srcIn) -- the text's own color is irrelevant
/// since the shader replaces it wherever a glyph is opaque; it just needs
/// to BE opaque there, hence plain white.
///
/// Static on purpose -- this used to continuously sweep (a 4s looping
/// AnimationController), but Home already runs the Ask bar's comet glow,
/// the Weekly Insight crossfade, and the world-teaser's "new" dot; a 4th
/// perpetual animation on the very first thing a user reads competed for
/// attention rather than helping it (see this session's cognitive-load
/// discussion). The color itself still reads as distinctly "insight",
/// it just doesn't move anymore.
class _RainbowText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _RainbowText(this.text, {required this.style});

  static const _rainbow = [
    Color(0xFFFF3B30),
    Color(0xFFFF9500),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF32ADE6),
    Color(0xFF5E5CE6),
    Color(0xFFAF52DE),
    Color(0xFFFF3B30),
  ];

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) =>
          const LinearGradient(colors: _rainbow).createShader(bounds),
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  final IconData? icon;

  const _SectionHeader({required this.title, this.onSeeAll, this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: AppColors.dmTextSoft),
          const SizedBox(width: 6)
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.dmText),
          ),
        ),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('See all',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.dmTextSoft)),
                const SizedBox(width: 2),
                Icon(Icons.arrow_forward,
                    size: 12, color: AppColors.dmTextSoft),
              ],
            ),
          ),
      ],
    );
  }
}

/// Compact teaser for the full "Your World" relationship thread (see
/// screens/settings/your_world_preview_screen.dart) -- deliberately the
/// same footprint as _QuickActionsRow rather than a full card, since this
/// screen already fights for the same vertical space Quick Actions needs.
///
/// Its dynamism is tied to real signals only, never fabricated: the
/// subtitle prefers an actual relationship-category digest card generated
/// this week (real LLM-detected observation) and only falls back to a
/// factual "last call" line when there isn't one -- and the small accent
/// dot only appears when that digest card is genuinely newer than the last
/// one the user opened this for (see _hasNewWorldSignal). See this
/// session's own design discussion: the goal is a real check-in habit for
/// relationship awareness, which only works if "something's new" is never
/// a lie the user eventually catches.
class _WorldTeaserCard extends StatelessWidget {
  final List<Friend> friends;
  final List<DigestCard> relationshipCards;
  final bool hasNew;
  final VoidCallback onTap;

  const _WorldTeaserCard({
    required this.friends,
    required this.relationshipCards,
    required this.hasNew,
    required this.onTap,
  });

  String _subtitle() {
    if (relationshipCards.isNotEmpty) {
      final card = relationshipCards.first;
      return card.body.trim().isNotEmpty
          ? card.body.trim()
          : card.headline.trim();
    }
    if (friends.isEmpty) return 'Add a friend to start your world';
    Friend? mostRecent;
    for (final f in friends) {
      if (f.lastCallAt == null) continue;
      if (mostRecent == null || f.lastCallAt!.isAfter(mostRecent.lastCallAt!)) {
        mostRecent = f;
      }
    }
    return mostRecent != null
        ? 'Last thread with ${mostRecent.displayName} • ${DateFormat.MMMd().format(mostRecent.lastCallAt!)}'
        : 'Tap to see your relationship thread';
  }

  @override
  Widget build(BuildContext context) {
    final shown = friends.take(4).toList();
    final extra = friends.length - shown.length;
    final stackWidth = shown.isEmpty
        ? 0.0
        : 16.0 * (shown.length - 1) + 32 + (extra > 0 ? 16 : 0);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.dmBubbleIn,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.dmBubbleBorder),
        ),
        child: Row(
          children: [
            if (shown.isNotEmpty) ...[
              SizedBox(
                width: stackWidth,
                height: 32,
                child: Stack(
                  children: [
                    for (final (i, _) in shown.indexed)
                      Positioned(
                        left: i * 16,
                        // An icon instead of a photo/initials avatar, with a
                        // one-time entrance settle (not an infinite pulse --
                        // Home already has the Ask bar's comet, the weekly
                        // insight crossfade, and the "new"-signal dot all
                        // running; a 4th perpetual loop here was gratuitous
                        // motion competing for attention with no real signal
                        // behind it, unlike that dot's genuinely-unread cue).
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.dmPillFill,
                          child: const Icon(Icons.person_rounded,
                              size: 17, color: AppColors.dmAccent),
                        )
                            .animate()
                            .scale(
                              begin: const Offset(0.4, 0.4),
                              end: const Offset(1, 1),
                              delay: (i * 90).ms,
                              duration: 260.ms,
                              curve: Curves.easeOutBack,
                            )
                            .fadeIn(delay: (i * 90).ms, duration: 180.ms),
                      ),
                    if (extra > 0)
                      Positioned(
                        left: shown.length * 16,
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.dmPillFill,
                          child: Text('+$extra',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.dmTextSoft,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Your World',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.dmText)),
                      if (hasNew) ...[
                        const SizedBox(width: 6),
                        PulsingHalo(
                          active: true,
                          color: AppColors.dmAccent,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.dmAccent),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(_subtitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.dmTextSoft)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.dmTextSoft),
          ],
        ),
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  final VoidCallback onChat;
  final VoidCallback onListen;
  final VoidCallback onTasks;
  final VoidCallback onPeople;
  final VoidCallback onAttach;

  const _QuickActionsRow({
    required this.onChat,
    required this.onListen,
    required this.onTasks,
    required this.onPeople,
    required this.onAttach,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.chat_bubble_outline, 'Chat', 'Talk to your AI', onChat),
      (Icons.mic_none, 'Listen', 'Voice notes & calls', onListen),
      (Icons.check_box_outlined, 'Tasks', 'Manage your tasks', onTasks),
      (Icons.people_outline, 'People', 'Your network', onPeople),
      (Icons.attach_file, 'Add', 'Bills, docs, images', onAttach),
    ];
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final (icon, label, sub, onTap) = items[i];
          return _QuickActionTile(
                  icon: icon, label: label, subtitle: sub, onTap: onTap)
              .animate()
              .fadeIn(
                  delay: (120 + i * 50).ms,
                  duration: 280.ms,
                  curve: Curves.easeOut)
              .slideX(
                  begin: 0.15,
                  end: 0,
                  delay: (120 + i * 50).ms,
                  duration: 280.ms,
                  curve: Curves.easeOut);
        },
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionTile(
      {required this.icon,
      required this.label,
      required this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TapBounce(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 92,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.dmBubbleIn,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.dmBubbleBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: AppColors.dmPillFill,
                    borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 17, color: AppColors.dmText),
              ),
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dmText)),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9.5, color: AppColors.dmTextSoft)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemindersCard extends StatelessWidget {
  final bool loaded;
  final List<Task> tasks;
  final VoidCallback onSeeAll;
  final ValueChanged<Task> onComplete;

  const _RemindersCard(
      {required this.loaded,
      required this.tasks,
      required this.onSeeAll,
      required this.onComplete});

  @override
  Widget build(BuildContext context) {
    final shown = tasks.take(4).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dmBubbleIn,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dmBubbleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              title: 'Reminders',
              icon: Icons.notifications_none,
              onSeeAll: onSeeAll),
          const SizedBox(height: 10),
          if (!loaded)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.dmTextSoft))),
            )
          else if (shown.isEmpty)
            Text('No open tasks.',
                style: TextStyle(fontSize: 12, color: AppColors.dmTextSoft))
          else
            // Keyed so completing one row doesn't get its still-in-flight
            // checkmark animation reassigned to whatever task slides into
            // its old list position once _openTasks updates underneath it.
            for (final t in shown)
              _ReminderRow(
                  key: ValueKey(t.id), task: t, onComplete: onComplete),
        ],
      ),
    );
  }
}

/// Tapping the checkbox actually completes the task now (it used to be a
/// static, non-interactive icon) -- plays the same draw-in checkmark
/// animation TasksScreen's own row uses, then hands off to onComplete once
/// that's had time to actually show rather than yanking the row out from
/// under it the instant the tap lands.
class _ReminderRow extends StatefulWidget {
  final Task task;
  final ValueChanged<Task> onComplete;

  const _ReminderRow({super.key, required this.task, required this.onComplete});

  @override
  State<_ReminderRow> createState() => _ReminderRowState();
}

class _ReminderRowState extends State<_ReminderRow> {
  bool _checked = false;

  Future<void> _handleTap() async {
    if (_checked) return;
    setState(() => _checked = true);
    await Future.delayed(const Duration(milliseconds: 420));
    if (mounted) widget.onComplete(widget.task);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: AnimatedTaskCheckbox(checked: _checked, size: 17),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.task.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color:
                            _checked ? AppColors.dmTextSoft : AppColors.dmText,
                        decoration:
                            _checked ? TextDecoration.lineThrough : null,
                      )),
                  if (widget.task.dueDate != null)
                    Text(widget.task.dueDate!,
                        style: TextStyle(
                            fontSize: 10.5, color: AppColors.dmTextSoft)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  final bool loaded;
  final List<Conversation> conversations;

  const _RecentActivityCard(
      {required this.loaded, required this.conversations});

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 2) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day} ${_months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final shown = conversations.take(4).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dmBubbleIn,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dmBubbleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'Recent Activity', icon: Icons.history),
          const SizedBox(height: 10),
          if (!loaded)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.dmTextSoft))),
            )
          else if (shown.isEmpty)
            Text('Nothing recorded yet.',
                style: TextStyle(fontSize: 12, color: AppColors.dmTextSoft))
          else
            for (final c in shown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.chat_bubble_outline,
                        size: 14, color: AppColors.dmTextSoft),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.dmText)),
                          Text('${_relative(c.createdAt)} Â· ${c.category}',
                              style: TextStyle(
                                  fontSize: 10, color: AppColors.dmTextSoft)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 16, color: AppColors.dmTextSoft),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// Cycles through this week's digest cards -- the top _InsightCard already
/// surfaces the single most notable one, so this is deliberately
/// understated (small, muted) rather than competing with it for attention.
/// Replaced the old "Your World" persona-tags card entirely -- those tags
/// had no real content behind them and were dead weight on the screen.
class _WeeklyInsightCard extends StatelessWidget {
  final List<String> insights;
  const _WeeklyInsightCard({this.insights = const []});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dmBubbleIn,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dmBubbleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: AppColors.dmTextSoft),
              const SizedBox(width: 6),
              Text('WEEKLY INSIGHT',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: AppColors.dmTextSoft)),
            ],
          ),
          const SizedBox(height: 8),
          if (insights.isEmpty)
            Text(
                'Keep talking -- weekly insights show up here once there\'s enough to look at.',
                style: TextStyle(fontSize: 12, color: AppColors.dmTextSoft))
          else
            _RotatingInsightText(insights: insights),
        ],
      ),
    );
  }
}

class _RotatingInsightText extends StatefulWidget {
  final List<String> insights;
  const _RotatingInsightText({required this.insights});

  @override
  State<_RotatingInsightText> createState() => _RotatingInsightTextState();
}

class _RotatingInsightTextState extends State<_RotatingInsightText> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer = Timer(const Duration(seconds: 5), () {
      if (!mounted || widget.insights.length < 2) return;
      setState(() => _index = (_index + 1) % widget.insights.length);
      _scheduleNext();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      // Slow and simple on purpose -- a short duration on plain color-on-
      // color text (no motion/size change to help sell it) read as an
      // instant cut rather than a fade.
      duration: const Duration(milliseconds: 900),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: Text(
        widget.insights[_index],
        key: ValueKey(_index),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style:
            TextStyle(fontSize: 12, color: AppColors.dmTextSoft, height: 1.35),
      ),
    );
  }
}

class _AskBar extends StatelessWidget {
  final VoidCallback onTap;
  const _AskBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Frosted glass, matching the real composer pill GlobalChatBody/the 1:1
    // chat screen already use (dmPillFill's own translucency + a blur) --
    // "transparent" here means genuinely see-through to the gradient behind
    // it, not just a differently-colored opaque bar.
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.dmPillFill,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.dmBubbleBorder),
          ),
          child: Row(
            children: [
              IconButton(
                  icon: Icon(Icons.add, color: AppColors.dmTextSoft),
                  onPressed: onTap),
              Expanded(
                child: GestureDetector(
                  onTap: onTap,
                  child: Text('Ask about your people, plans, or anything...',
                      style:
                          TextStyle(fontSize: 13, color: AppColors.dmTextSoft)),
                ),
              ),
              Material(
                color: AppColors.dmAccent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                  child: const Padding(
                    padding: EdgeInsets.all(9),
                    child:
                        Icon(Icons.arrow_upward, size: 18, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
