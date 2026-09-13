import 'package:flutter/material.dart';

import '../motion/motion_profile.dart';

/// Subtle one-shot fade+slide-up entrance, staggered by [index] -- used to
/// give list rows (chats, tasks) a bit of life on first appearance instead
/// of just popping in fully-formed. Purely visual: wraps a child without
/// changing its layout size or interaction, so it can't affect taps/swipes/
/// data underneath it.
///
/// [profile] is optional and defaults to MotionProfile.balanced, whose spec
/// (see motion_profile.dart) is deliberately identical to this widget's
/// original hardcoded constants -- a caller that doesn't pass one sees
/// exactly the behavior this widget always had, not a subtly different
/// "new default."
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  final MotionProfile profile;

  const FadeSlideIn({super.key, required this.child, this.index = 0, this.profile = MotionProfile.balanced});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    final spec = motionSpecs[widget.profile]!;
    _controller = AnimationController(vsync: this, duration: spec.entranceDuration);
    _fade = CurvedAnimation(parent: _controller, curve: spec.entranceCurve);
    _slide = Tween<Offset>(begin: Offset(0, spec.slideDistance / 100), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: spec.entranceCurve));
    // Small stagger per row, capped so a long list's last rows don't wait
    // ages -- purely cosmetic delay, nothing is blocked on it.
    final delay = Duration(milliseconds: (widget.index * spec.staggerMs).clamp(0, 220));
    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
