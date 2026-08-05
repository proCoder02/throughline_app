import 'package:flutter/material.dart';

/// Subtle one-shot fade+slide-up entrance, staggered by [index] -- used to
/// give list rows (chats, tasks) a bit of life on first appearance instead
/// of just popping in fully-formed. Purely visual: wraps a child without
/// changing its layout size or interaction, so it can't affect taps/swipes/
/// data underneath it.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;

  const FadeSlideIn({super.key, required this.child, this.index = 0});

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
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    // Small stagger per row, capped so a long list's last rows don't wait
    // ages -- purely cosmetic delay, nothing is blocked on it.
    final delay = Duration(milliseconds: (widget.index * 18).clamp(0, 220));
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
