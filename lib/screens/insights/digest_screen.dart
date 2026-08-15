import 'package:flutter/material.dart';

import '../../models/weekly_digest.dart';
import '../../services/digest_service.dart';
import '../../theme.dart';

const _categoryColors = {
  'preference': AppColors.accent,
  'fact': Color(0xFFE8A33D),
  'mood': Color(0xFF6C8EF5),
  'personality': Color(0xFFB072E8),
  'relationship': Color(0xFFEA6A9C),
};

Color _colorForCategory(String category) => _categoryColors[category] ?? AppColors.accent;

/// Push-triggered full-screen route (from a digest_ready notification tap,
/// or InsightPreviewCard on the Chats/home tab) -- see home_shell.dart's
/// onMessageTapped and lib/widgets/insight_preview_card.dart. Swipeable
/// card stack, one card per insight, matching the drag-to-swipe physics
/// prototyped in this session's Artifact mockups: left advances, right
/// goes back, real drag rotation/follow rather than a carousel.
class DigestScreen extends StatefulWidget {
  const DigestScreen({super.key});

  @override
  State<DigestScreen> createState() => _DigestScreenState();
}

class _DigestScreenState extends State<DigestScreen> {
  final _service = DigestService();
  WeeklyDigest? _digest;
  bool _loading = true;
  Object? _error;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final digest = await _service.fetch();
      if (!mounted) return;
      setState(() {
        _digest = digest;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  void _advance(int direction) {
    final total = _digest?.cards.length ?? 0;
    setState(() => _index = (_index + direction).clamp(0, total));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly Insight')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Text("Couldn't load your insight -- pull to try again from the Chats tab.",
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
      );
    }
    final digest = _digest;
    if (digest == null || digest.cards.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "No insight yet -- check back once I've noticed something worth sharing.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSoft, fontSize: 15),
          ),
        ),
      );
    }

    return Column(
      children: [
        _ProgressRow(total: digest.cards.length, current: _index),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: _index >= digest.cards.length
                ? _DoneState(onReplay: () => setState(() => _index = 0))
                : _CardStack(cards: digest.cards, index: _index, onSwipe: _advance),
          ),
        ),
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final int total;
  final int current;
  const _ProgressRow({required this.total, required this.current});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: List.generate(total, (i) {
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i == total - 1 ? 0 : 5),
              height: 3,
              decoration: BoxDecoration(
                color: i < current ? AppColors.accent : AppColors.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _CardStack extends StatefulWidget {
  final List<DigestCard> cards;
  final int index;
  final void Function(int direction) onSwipe;

  const _CardStack({required this.cards, required this.index, required this.onSwipe});

  @override
  State<_CardStack> createState() => _CardStackState();
}

class _CardStackState extends State<_CardStack> {
  // 0..1 fraction of the swipe threshold the top card has been dragged --
  // drives the cards underneath rising into the top slot live as you drag,
  // instead of popping into their new position only once the swipe
  // completes (the "transition isn't user friendly" gap vs. Tinder).
  double _progress = 0;

  @override
  void didUpdateWidget(covariant _CardStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) _progress = 0;
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.cards.skip(widget.index).take(3).toList();
    return Stack(
      children: [
        for (var depth = visible.length - 1; depth >= 0; depth--)
          if (depth == 0)
            _DraggableCard(
              key: ValueKey(widget.index), // fresh widget per top card so drag state never carries over
              card: visible[0],
              canGoBack: widget.index > 0,
              onSwipe: widget.onSwipe,
              onProgressChanged: (p) => setState(() => _progress = p),
            )
          else
            _PeekCard(card: visible[depth], depth: depth, progress: _progress),
      ],
    );
  }
}

/// One of the cards stacked behind the draggable top card. Its resting pose
/// is set by [depth], but as the top card is dragged away, [progress] (0..1)
/// eases it toward the next depth up's pose in real time, so the whole stack
/// visibly rises together instead of the next card just popping into place
/// once the swipe finishes.
class _PeekCard extends StatelessWidget {
  final DigestCard card;
  final int depth;
  final double progress;
  const _PeekCard({required this.card, required this.depth, required this.progress});

  static double _scaleAt(int d) => 1 - d * 0.03;
  static double _offsetYAt(int d) => d * 7.0;
  static double _opacityAt(int d) => (1 - d * 0.22).clamp(0.0, 1.0);
  static double _angleAt(int d) => d == 0 ? 0 : (d.isEven ? -1 : 1) * 0.035;
  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0);
    return Transform.translate(
      offset: Offset(0, _lerp(_offsetYAt(depth), _offsetYAt(depth - 1), t)),
      child: Transform.rotate(
        angle: _lerp(_angleAt(depth), _angleAt(depth - 1), t),
        child: Transform.scale(
          scale: _lerp(_scaleAt(depth), _scaleAt(depth - 1), t),
          child: Opacity(
            opacity: _lerp(_opacityAt(depth), _opacityAt(depth - 1), t),
            child: RepaintBoundary(child: _InsightCard(card: card)),
          ),
        ),
      ),
    );
  }
}

class _DraggableCard extends StatefulWidget {
  final DigestCard card;
  final bool canGoBack;
  final void Function(int direction) onSwipe;
  final ValueChanged<double>? onProgressChanged;
  const _DraggableCard({
    super.key,
    required this.card,
    required this.canGoBack,
    required this.onSwipe,
    this.onProgressChanged,
  });

  @override
  State<_DraggableCard> createState() => _DraggableCardState();
}

class _DraggableCardState extends State<_DraggableCard> with SingleTickerProviderStateMixin {
  static const _threshold = 100.0;
  // A flick this fast commits the swipe even if it hasn't crossed
  // _threshold yet -- Tinder-style flick-to-dismiss, not just distance-gated.
  static const _flingVelocity = 600.0;

  late final AnimationController _controller;
  Animation<Offset>? _animation;
  Offset _dragOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() {
        if (_animation != null) {
          setState(() => _dragOffset = _animation!.value);
          _reportProgress();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reportProgress() {
    widget.onProgressChanged?.call((_dragOffset.dx.abs() / _threshold).clamp(0.0, 1.0));
  }

  void _onPanStart(DragStartDetails details) {
    _controller.stop();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() => _dragOffset += details.delta);
    _reportProgress();
  }

  void _onPanEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    final pastThreshold = _dragOffset.dx.abs() >= _threshold;
    final flung = velocity.abs() >= _flingVelocity;
    if (pastThreshold || flung) {
      // screenDirection is which way the card physically exits: -1 left, 1
      // right -- always matches the drag, independent of index semantics.
      final screenDirection = flung ? (velocity < 0 ? -1 : 1) : (_dragOffset.dx <= 0 ? -1 : 1);
      // Left exit advances to the next card; right exit goes back to the
      // previous one. Swiping right past the very first card has nowhere to
      // go back to -- spring back instead of flying a card off to a slot
      // that will never change the index (which left it visually stranded
      // off-screen, the actual cause of the "stuck" card).
      if (screenDirection == 1 && !widget.canGoBack) {
        _springBack();
        return;
      }
      _flyOut(screenDirection, velocity);
    } else {
      _springBack();
    }
  }

  void _flyOut(int screenDirection, double velocity) {
    final screenWidth = MediaQuery.of(context).size.width;
    final end = Offset(screenDirection * (screenWidth + 80), _dragOffset.dy);
    // Duration scales with how fast the finger was already moving, so a
    // hard flick keeps carrying its own momentum instead of restarting from
    // a standstill -- that restart-from-zero read as "stuck" on release.
    // easeOut (fast start) replaces the old easeIn (slow start), which was
    // the main cause of the release-hesitation.
    final remaining = (end.dx - _dragOffset.dx).abs();
    final speed = velocity.abs().clamp(400.0, 3000.0);
    final ms = (remaining / speed * 1000).clamp(120.0, 260.0).round();
    _animation = Tween<Offset>(begin: _dragOffset, end: end)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.duration = Duration(milliseconds: ms);
    // Index delta is the inverse of screen direction: exiting left (-1)
    // means "advance" (+1 index), exiting right (1) means "go back" (-1
    // index). Previously these were conflated (index delta == screen
    // direction), so a left swipe from the first card decreased the index,
    // which the outer clamp(0, total) silently absorbed -- the index never
    // changed, _CardStack's ValueKey(index) never changed, so the card that
    // had just flown off-screen was reused as-is instead of being replaced,
    // leaving it permanently stuck outside the viewport.
    _controller.forward(from: 0).whenComplete(() {
      if (mounted) widget.onSwipe(-screenDirection);
    });
  }

  void _springBack() {
    _animation = Tween<Offset>(begin: _dragOffset, end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.duration = const Duration(milliseconds: 220);
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final rotation = _dragOffset.dx / 280; // radians -- gentle tilt, matches the mockup's feel
    final nextOpacity = (-_dragOffset.dx / _threshold).clamp(0.0, 1.0);
    final backOpacity = (_dragOffset.dx / _threshold).clamp(0.0, 1.0);

    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Transform.translate(
        offset: _dragOffset,
        child: Transform.rotate(
          angle: rotation,
          // Isolates the card's own paint (including its blurred shadow,
          // the single most expensive part of this tree to re-rasterize)
          // from the Transform above -- without this, every onPanUpdate
          // tick during a drag repaints the whole card from scratch on
          // top of just moving it, which is what made the drag feel janky/
          // stuck on a real device instead of smoothly following the
          // finger. With it, the card paints once and the transform just
          // repositions the cached layer each frame.
          child: RepaintBoundary(
            child: Stack(
              children: [
                _InsightCard(card: widget.card),
                if (nextOpacity > 0)
                  Positioned(top: 14, right: 14, child: _SwipeStamp(label: 'NEXT', color: AppColors.accent, opacity: nextOpacity)),
                if (backOpacity > 0)
                  Positioned(top: 14, left: 14, child: _SwipeStamp(label: 'BACK', color: AppColors.textSoft, opacity: backOpacity)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeStamp extends StatelessWidget {
  final String label;
  final Color color;
  final double opacity;
  const _SwipeStamp({required this.label, required this.color, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.panel,
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1)),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final DigestCard card;
  const _InsightCard({required this.card});

  @override
  Widget build(BuildContext context) {
    final color = _colorForCategory(card.category);
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 17),
          ),
          const SizedBox(height: 10),
          Text(card.label.toUpperCase(),
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 10.5, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Text(card.headline,
              style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 17, height: 1.25)),
          const SizedBox(height: 6),
          Text(card.body, style: TextStyle(color: AppColors.textSoft, fontSize: 13, height: 1.45)),
        ],
      ),
    );
  }
}

class _DoneState extends StatelessWidget {
  final VoidCallback onReplay;
  const _DoneState({required this.onReplay});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border, style: BorderStyle.solid),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('✓', style: TextStyle(fontSize: 34)),
              const SizedBox(height: 8),
              Text("That's everything this week.",
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Text('Check back next week for more.', style: TextStyle(color: AppColors.textSoft, fontSize: 13)),
              const SizedBox(height: 12),
              TextButton(onPressed: onReplay, child: const Text('Replay')),
            ],
          ),
        ),
      ),
    );
  }
}
