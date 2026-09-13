import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../models/conversation.dart';
import '../../models/task.dart';
import '../../models/weekly_digest.dart';
import '../../services/conversation_service.dart';
import '../../services/digest_service.dart';
import '../../services/task_service.dart';
import '../../state/auth_provider.dart';
import '../../theme.dart';
import '../../widgets/animated_task_checkbox.dart';
import '../../widgets/glowing_border.dart';
import '../../widgets/tap_bounce.dart';
import '../chats/global_chat_body.dart';

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

  const HomeScreen({super.key, required this.onNavigateToTab, required this.onOpenDrawer});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _digestService = DigestService();
  final _taskService = TaskService();
  final _conversationService = ConversationService();

  WeeklyDigest? _digest;
  List<Task> _openTasks = [];
  List<Conversation> _recentConversations = [];
  bool _loaded = false;

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
    ]);
    if (!mounted) return;
    setState(() {
      _digest = results[0] as WeeklyDigest?;
      _openTasks = results[1] as List<Task>;
      _recentConversations = results[2] as List<Conversation>;
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
    if (mounted) setState(() => _openTasks = _openTasks.where((t) => t.id != task.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12 ? 'Good Morning' : (hour < 17 ? 'Good Afternoon' : 'Good Evening');
    final firstCard = _digest?.cards.isNotEmpty == true ? _digest!.cards.first : null;

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
            transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
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
                            _GreetingHeader(greeting: greeting, username: auth.username, now: now)
                                .animate()
                                .fadeIn(duration: 320.ms, curve: Curves.easeOut)
                                .slideY(begin: 0.08, end: 0, duration: 320.ms, curve: Curves.easeOut),
                            const SizedBox(height: 16),
                            _InsightCard(
                              headline: firstCard?.headline ??
                                  'Keep talking -- your first insight appears once there\'s enough to look at.',
                              body: firstCard?.body,
                              onViewSummary: firstCard != null ? () => _openChatWithSummary(firstCard) : null,
                            )
                                .animate()
                                .fadeIn(delay: 60.ms, duration: 320.ms, curve: Curves.easeOut)
                                .slideY(begin: 0.08, end: 0, delay: 60.ms, duration: 320.ms, curve: Curves.easeOut),
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
                                .fadeIn(delay: 120.ms, duration: 320.ms, curve: Curves.easeOut)
                                .slideY(begin: 0.08, end: 0, delay: 120.ms, duration: 320.ms, curve: Curves.easeOut),
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
                                .fadeIn(delay: 180.ms, duration: 320.ms, curve: Curves.easeOut)
                                .slideY(begin: 0.08, end: 0, delay: 180.ms, duration: 320.ms, curve: Curves.easeOut),
                            const SizedBox(height: 20),
                            _WeeklyInsightCard(
                              insights: (_digest?.cards ?? [])
                                  .map((c) => c.body.trim().isNotEmpty ? c.body.trim() : c.headline.trim())
                                  .where((s) => s.isNotEmpty)
                                  .toList(),
                            )
                                .animate()
                                .fadeIn(delay: 240.ms, duration: 320.ms, curve: Curves.easeOut)
                                .slideY(begin: 0.08, end: 0, delay: 240.ms, duration: 320.ms, curve: Curves.easeOut),
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
          IconButton(icon: const Icon(Icons.menu), color: AppColors.dmText, onPressed: onMenuTap),
          const SizedBox(width: 4),
          Icon(Icons.all_inclusive, color: AppColors.dmTextSoft, size: 22),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Throughline',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.dmText)),
              Text('Your conversations. Your people. Your life.',
                  style: TextStyle(fontStyle: FontStyle.italic, fontSize: 10.5, color: AppColors.dmTextSoft)),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: onAvatarTap,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.dmBubbleBorder,
              backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty) ? NetworkImage(avatarUrl!) : null,
              child: (avatarUrl == null || avatarUrl!.isEmpty)
                  ? Text((username?.isNotEmpty == true ? username![0] : '?').toUpperCase(),
                      style: TextStyle(color: AppColors.dmText, fontWeight: FontWeight.w700))
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

  const _GreetingHeader({required this.greeting, required this.username, required this.now});

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  Widget build(BuildContext context) {
    final dateStr = '${_weekdays[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]} ${now.year}';
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
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.dmText)),
              const SizedBox(height: 2),
              Text("Here's what's happening with your world today.",
                  style: TextStyle(fontSize: 12.5, color: AppColors.dmTextSoft)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(dateStr, style: TextStyle(fontSize: 11.5, color: AppColors.dmTextSoft)),
            const SizedBox(height: 4),
            // No weather integration exists anywhere in this app today --
            // shown as a plain placeholder chip, not real data, until one
            // is wired up.
            Row(
              children: [
                Icon(Icons.cloud_outlined, size: 14, color: AppColors.dmTextSoft),
                const SizedBox(width: 3),
                Text('--Â°  Â·  --', style: TextStyle(fontSize: 11.5, color: AppColors.dmTextSoft)),
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
    return Container(
      padding: const EdgeInsets.all(16),
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
              Icon(Icons.bolt, size: 16, color: AppColors.dmTextSoft),
              const SizedBox(width: 6),
              Text('Throughline Insight',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.dmTextSoft)),
            ],
          ),
          const SizedBox(height: 8),
          // The one place asked for a rainbow effect -- everything else on
          // this card (label, body, button) stays the plain app palette.
          _RainbowText(headline, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          if (body != null && body!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(body!, style: TextStyle(fontSize: 12.5, color: AppColors.dmTextSoft)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A slowly-sweeping rainbow gradient painted through the text's own glyph
/// shapes (ShaderMask + BlendMode.srcIn) -- the text's own color is
/// irrelevant since the shader replaces it wherever a glyph is opaque; it
/// just needs to BE opaque there, hence plain white.
class _RainbowText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _RainbowText(this.text, {required this.style});

  @override
  State<_RainbowText> createState() => _RainbowTextState();
}

class _RainbowTextState extends State<_RainbowText> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: 4000.ms)..repeat();

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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Slides the gradient's start/end across the text over time (mirror
        // tiling so it loops seamlessly) -- a continuous sweep rather than a
        // static rainbow fill.
        final shift = _controller.value * 2;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            colors: _rainbow,
            begin: Alignment(-1 - shift, 0),
            end: Alignment(1 - shift, 0),
            tileMode: TileMode.mirror,
          ).createShader(bounds),
          child: Text(widget.text, style: widget.style.copyWith(color: Colors.white)),
        );
      },
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
        if (icon != null) ...[Icon(icon, size: 16, color: AppColors.dmTextSoft), const SizedBox(width: 6)],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.dmText),
          ),
        ),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('See all', style: TextStyle(fontSize: 12, color: AppColors.dmTextSoft)),
                const SizedBox(width: 2),
                Icon(Icons.arrow_forward, size: 12, color: AppColors.dmTextSoft),
              ],
            ),
          ),
      ],
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
          return _QuickActionTile(icon: icon, label: label, subtitle: sub, onTap: onTap)
              .animate()
              .fadeIn(delay: (120 + i * 50).ms, duration: 280.ms, curve: Curves.easeOut)
              .slideX(begin: 0.15, end: 0, delay: (120 + i * 50).ms, duration: 280.ms, curve: Curves.easeOut);
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

  const _QuickActionTile({required this.icon, required this.label, required this.subtitle, required this.onTap});

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
              decoration: BoxDecoration(color: AppColors.dmPillFill, borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 17, color: AppColors.dmText),
            ),
            const SizedBox(height: 6),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.dmText)),
            Text(subtitle,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.5, color: AppColors.dmTextSoft)),
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

  const _RemindersCard({required this.loaded, required this.tasks, required this.onSeeAll, required this.onComplete});

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
          _SectionHeader(title: 'Reminders', icon: Icons.notifications_none, onSeeAll: onSeeAll),
          const SizedBox(height: 10),
          if (!loaded)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.dmTextSoft))),
            )
          else if (shown.isEmpty)
            Text('No open tasks.', style: TextStyle(fontSize: 12, color: AppColors.dmTextSoft))
          else
            // Keyed so completing one row doesn't get its still-in-flight
            // checkmark animation reassigned to whatever task slides into
            // its old list position once _openTasks updates underneath it.
            for (final t in shown) _ReminderRow(key: ValueKey(t.id), task: t, onComplete: onComplete),
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
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _checked ? AppColors.dmTextSoft : AppColors.dmText,
                        decoration: _checked ? TextDecoration.lineThrough : null,
                      )),
                  if (widget.task.dueDate != null)
                    Text(widget.task.dueDate!, style: TextStyle(fontSize: 10.5, color: AppColors.dmTextSoft)),
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

  const _RecentActivityCard({required this.loaded, required this.conversations});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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
              child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.dmTextSoft))),
            )
          else if (shown.isEmpty)
            Text('Nothing recorded yet.', style: TextStyle(fontSize: 12, color: AppColors.dmTextSoft))
          else
            for (final c in shown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 14, color: AppColors.dmTextSoft),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.displayTitle,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.dmText)),
                          Text('${_relative(c.createdAt)} Â· ${c.category}',
                              style: TextStyle(fontSize: 10, color: AppColors.dmTextSoft)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: AppColors.dmTextSoft),
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
                      fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: AppColors.dmTextSoft)),
            ],
          ),
          const SizedBox(height: 8),
          if (insights.isEmpty)
            Text('Keep talking -- weekly insights show up here once there\'s enough to look at.',
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
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
      child: Text(
        widget.insights[_index],
        key: ValueKey(_index),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: AppColors.dmTextSoft, height: 1.35),
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
              IconButton(icon: Icon(Icons.add, color: AppColors.dmTextSoft), onPressed: onTap),
              Expanded(
                child: GestureDetector(
                  onTap: onTap,
                  child: Text('Ask about your people, plans, or anything...',
                      style: TextStyle(fontSize: 13, color: AppColors.dmTextSoft)),
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
                    child: Icon(Icons.arrow_upward, size: 18, color: Colors.white),
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
