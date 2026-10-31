import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/avatar.dart';
import 'meet_models.dart';

/// Motion for Meet. Every effect maps to something real, so it doubles as
/// feedback: glow brightness = signal strength, the ring = how long to keep
/// holding, the merge = the match itself. With the system "remove
/// animations" setting on, each one falls back to a still frame or a fade.

bool _reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// 0..1 from a signal reading: 0 at the edge of range, 1 at the touch threshold.
double signalLevel(int? rssi, int threshold) {
  if (rssi == null) return 0;
  const floor = -95;
  return ((rssi - floor) / (threshold - floor)).clamp(0.0, 1.0);
}

/// A soft glow along the top edge of the screen that brightens as the other
/// phone gets closer -- the "they're right here" cue, visible at a glance.
class EdgeGlow extends StatelessWidget {
  final double level;

  const EdgeGlow({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: level),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        builder: (_, v, __) => Container(
          height: 180,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.accent.withValues(alpha: 0.55 * v),
                AppColors.accent.withValues(alpha: 0.18 * v),
                AppColors.accent.withValues(alpha: 0),
              ],
              stops: const [0, 0.35, 1],
            ),
          ),
        ),
      ),
    );
  }
}

/// The centre of the searching screen: breathing rings that speed up and
/// warm up with the signal, and a ring that fills while the user holds
/// still. Full ring = touch registered.
class ProximityOrb extends StatefulWidget {
  final double level; // 0..1, from signalLevel()
  final double hold; // 0..1, hold-still progress

  const ProximityOrb({super.key, required this.level, required this.hold});

  @override
  State<ProximityOrb> createState() => _ProximityOrbState();
}

class _ProximityOrbState extends State<ProximityOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      _breath.stop();
    } else if (!_breath.isAnimating) {
      _breath.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant ProximityOrb old) {
    super.didUpdateWidget(old);
    // Faster breathing as the other phone gets closer: 2.4 s -> 0.9 s.
    final ms = (2400 - 1500 * widget.level).round();
    if (((_breath.duration?.inMilliseconds ?? 0) - ms).abs() > 150 && !_reduceMotion(context)) {
      _breath.duration = Duration(milliseconds: ms);
      _breath.repeat();
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = _reduceMotion(context);
    return SizedBox(
      height: 200,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: widget.level),
        duration: const Duration(milliseconds: 260),
        builder: (_, level, __) => TweenAnimationBuilder<double>(
          tween: Tween(end: widget.hold),
          duration: const Duration(milliseconds: 160),
          builder: (_, hold, __) => AnimatedBuilder(
            animation: _breath,
            builder: (_, __) => Stack(
              alignment: Alignment.center,
              children: [
                // halo -- grows and brightens with the signal
                Container(
                  width: 110 + 70 * level,
                  height: 110 + 70 * level,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.15 + 0.45 * level),
                        blurRadius: 30 + 40 * level,
                        spreadRadius: 4 + 14 * level,
                      ),
                    ],
                  ),
                ),
                if (!reduce)
                  for (final offset in const [0.0, 0.33, 0.66])
                    Builder(builder: (_) {
                      final t = (_breath.value + offset) % 1.0;
                      return Container(
                        width: 72 + 110 * t,
                        height: 72 + 110 * t,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.accent.withValues(alpha: (1 - t) * (0.35 + 0.4 * level)),
                            width: 2,
                          ),
                        ),
                      );
                    }),
                // hold-still ring
                SizedBox(
                  width: 92,
                  height: 92,
                  child: CustomPaint(painter: _RingPainter(progress: hold, color: AppColors.accent, track: AppColors.border)),
                ),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(AppColors.accentDark, AppColors.accent, level),
                  ),
                  child: const Icon(Icons.contactless_outlined, color: Colors.white, size: 34),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;

  _RingPainter({required this.progress, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    if (progress > 0) {
      canvas.drawArc(rect.deflate(2), 0, 2 * math.pi, false, stroke..color = track.withValues(alpha: 0.6));
      canvas.drawArc(rect.deflate(2), -math.pi / 2, 2 * math.pi * progress, false, stroke..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}

/// The match moment: my avatar and theirs slide in from the sides and
/// overlap, with a glow burst behind them as they meet.
class MergeAvatars extends StatelessWidget {
  final MeetPerson me;
  final MeetPerson them;

  const MergeAvatars({super.key, required this.me, required this.them});

  @override
  Widget build(BuildContext context) {
    final reduce = _reduceMotion(context);
    return SizedBox(
      height: 150,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduce ? 1 : 0, end: 1),
        duration: const Duration(milliseconds: 750),
        curve: Curves.easeOutCubic,
        builder: (_, t, __) {
          final gap = 110 * (1 - t); // apart -> overlapping
          final burst = math.sin(t * math.pi); // peaks as they meet, then settles
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 120 + 80 * burst,
                height: 120 + 80 * burst,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.25 + 0.35 * burst),
                      blurRadius: 40 + 30 * burst,
                      spreadRadius: 6 + 18 * burst,
                    ),
                  ],
                ),
              ),
              Transform.translate(offset: Offset(-34 - gap, 0), child: _ring(me)),
              Transform.translate(offset: Offset(34 + gap, 0), child: _ring(them)),
            ],
          );
        },
      ),
    );
  }

  Widget _ring(MeetPerson p) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.bgApp, border: Border.all(color: AppColors.accent, width: 2)),
        child: InitialAvatar(name: p.name, imageUrl: p.photo, size: 88),
      );
}

/// The other person's card rising in with a brief warm glow -- the payoff.
class CardReveal extends StatelessWidget {
  final Widget child;

  const CardReveal({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final reduce = _reduceMotion(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 28 * (1 - t)),
          child: Transform.scale(
            scale: 0.96 + 0.04 * t,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.35 * math.sin(t * math.pi)),
                    blurRadius: 36,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ),
      child: child,
    );
  }
}
