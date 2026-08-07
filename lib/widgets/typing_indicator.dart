import 'package:flutter/material.dart';

import '../theme.dart';

/// "Assistant is typing" bubble -- shown as the next incoming message while
/// waiting for an LLM reply, so the wait is legible in the conversation
/// itself (the reply appearing IS the "read receipt") rather than only a
/// spinner on the send button that disappears into nothing.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Three dots bouncing in a staggered wave (each offset by a third of the
  // cycle), rather than one flat pulse -- reads as more alive/dynamic.
  Widget _dot(double phaseOffset) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = (_controller.value + phaseOffset) % 1.0;
        final wave = (0.5 - (t - 0.5).abs()) * 2; // 0 -> 1 -> 0 across the cycle
        final scale = 0.6 + 0.4 * wave;
        return Transform.scale(scale: scale, child: child);
      },
      child: CircleAvatar(radius: 4, backgroundColor: AppColors.textSoft),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bubbleIn,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 1, offset: Offset(0, 1))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(0.0),
            const SizedBox(width: 4),
            _dot(0.15),
            const SizedBox(width: 4),
            _dot(0.3),
          ],
        ),
      ),
    );
  }
}
