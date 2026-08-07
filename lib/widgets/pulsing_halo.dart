import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Wraps [child] with two continuously outward-expanding, fading ring
/// outlines (phase-offset from each other so one is always mid-ripple --
/// reads as a continuous sound wave rather than a single ring resetting
/// abruptly), plus a subtle synchronized "breathe" scale on [child] itself.
/// The whole thing only runs while [active] is true -- used for the Listen
/// button while ListenProvider.isListening. Idle (active: false) renders
/// [child] alone with no controller running, so it costs nothing while not
/// listening.
class PulsingHalo extends StatefulWidget {
  final bool active;
  final Color color;
  final Widget child;

  /// Ring shape: true for a circular button (the Listen FAB once it morphs
  /// into a plain circle while recording), false for a stadium/pill shape.
  final bool circular;

  const PulsingHalo({
    super.key,
    required this.active,
    required this.color,
    required this.child,
    this.circular = true,
  });

  @override
  State<PulsingHalo> createState() => _PulsingHaloState();
}

class _PulsingHaloState extends State<PulsingHalo> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant PulsingHalo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.repeat();
    } else if (!widget.active && oldWidget.active) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _ring(double raw) {
    final t = Curves.easeOut.transform(raw);
    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: (1 - t) * 0.55,
          child: Transform.scale(
            scale: 1 + t * 0.7,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: widget.circular
                    ? CircleBorder(side: BorderSide(color: widget.color, width: 2))
                    : StadiumBorder(side: BorderSide(color: widget.color, width: 2)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final raw = _controller.value;
        final raw2 = (raw + 0.5) % 1.0;
        // Button itself breathes in sync with the primary ring's expand/fade
        // cycle -- reads as one cohesive "recording" heartbeat, closer to
        // how Telegram/WhatsApp's voice-record button visibly swells rather
        // than sitting static while only rings move around it.
        final breathe = 1 + math.sin(raw * math.pi) * 0.06;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            _ring(raw),
            _ring(raw2),
            Transform.scale(scale: breathe, child: child),
          ],
        );
      },
      child: widget.child,
    );
  }
}
