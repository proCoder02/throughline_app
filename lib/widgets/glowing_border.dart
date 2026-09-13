import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme.dart';

/// A short comet of light that continuously travels around [child]'s
/// rounded border -- a signifier meant to draw the eye toward Home's Ask
/// bar without demanding attention the way a popup or badge would, the
/// same idea as a voice-assistant's ambient "I'm listening" glow.
///
/// Deliberately subtle: one short bright arc with a long dark tail, not a
/// full glowing ring -- a border that's lit up all the way around just
/// reads as a static highlight, not as something alive worth tapping.
class GlowingBorder extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final double strokeWidth;
  final Duration duration;

  /// When false, the comet stops traveling and fades out -- used so it
  /// switches off the moment a user actually engages with a real composer
  /// (focuses or starts typing in it), rather than distracting behind the
  /// text they're entering.
  final bool active;

  const GlowingBorder({
    super.key,
    required this.child,
    required this.borderRadius,
    this.strokeWidth = 1.6,
    this.duration = const Duration(seconds: 3),
    this.active = true,
  });

  @override
  State<GlowingBorder> createState() => _GlowingBorderState();
}

class _GlowingBorderState extends State<GlowingBorder> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant GlowingBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      if (widget.active) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => TweenAnimationBuilder<double>(
        tween: Tween(end: widget.active ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 250),
        builder: (context, opacity, child) => CustomPaint(
          foregroundPainter: opacity == 0
              ? null
              : _CometBorderPainter(
                  angle: _controller.value * 2 * math.pi,
                  radius: widget.borderRadius,
                  strokeWidth: widget.strokeWidth,
                  opacity: opacity,
                ),
          child: child,
        ),
        child: child,
      ),
    );
  }
}

class _CometBorderPainter extends CustomPainter {
  final double angle;
  final double radius;
  final double strokeWidth;
  final double opacity;

  _CometBorderPainter({required this.angle, required this.radius, required this.strokeWidth, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(strokeWidth / 2), Radius.circular(radius));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = SweepGradient(
        colors: [
          AppColors.dmAccent.withValues(alpha: 0.95 * opacity),
          AppColors.dmAccent.withValues(alpha: 0.0),
          AppColors.dmAccent.withValues(alpha: 0.0),
          AppColors.dmAccent.withValues(alpha: 0.95 * opacity),
        ],
        stops: const [0.0, 0.16, 0.86, 1.0],
        transform: GradientRotation(angle),
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _CometBorderPainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.opacity != opacity;
}
