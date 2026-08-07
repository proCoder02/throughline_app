import 'package:flutter/material.dart';

/// Purely visual press feedback -- scales [child] down slightly while a
/// finger is down on it. Uses a raw pointer Listener rather than a
/// GestureDetector so it never enters the same gesture arena as the
/// wrapped widget's own tap handler (e.g. FloatingActionButton.onPressed);
/// it only observes, it doesn't compete for or consume the tap.
class TapBounce extends StatefulWidget {
  final Widget child;

  const TapBounce({super.key, required this.child});

  @override
  State<TapBounce> createState() => _TapBounceState();
}

class _TapBounceState extends State<TapBounce> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
