import 'package:flutter/material.dart';

/// Wraps a list row so flipping [fading] to true makes it visibly fade out
/// AND collapse its height smoothly, instead of an instant disappearance --
/// used for row deletion (Tasks/Chats, see this session's own request).
/// [onFadedOut] fires once the fade+collapse finishes; the caller does the
/// actual removal from its data list there, not before, so the row
/// survives long enough to actually play the animation (same "animate
/// first, mutate the real list after" pattern already used elsewhere in
/// this app -- e.g. the typing indicator's dissolve before a reply is
/// inserted).
class FadeCollapse extends StatelessWidget {
  final bool fading;
  final Widget child;
  final VoidCallback? onFadedOut;
  final Duration duration;

  const FadeCollapse({
    super.key,
    required this.fading,
    required this.child,
    this.onFadedOut,
    this.duration = const Duration(milliseconds: 280),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.0, end: fading ? 0.0 : 1.0),
      duration: duration,
      curve: Curves.easeOut,
      onEnd: () {
        if (fading) onFadedOut?.call();
      },
      builder: (context, t, child) {
        final clamped = t.clamp(0.0, 1.0);
        return ClipRect(
          child: Align(
            heightFactor: clamped,
            child: Opacity(opacity: clamped, child: child),
          ),
        );
      },
      child: child,
    );
  }
}
