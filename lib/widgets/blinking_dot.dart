import 'dart:async';

import 'package:flutter/material.dart';

/// A hard on/off blink (not a smooth fade or scale) -- the classic
/// recording-indicator dot next to a live timer, e.g. Telegram/WhatsApp's
/// voice-message recording UI. Deliberately a crisp Timer-driven toggle
/// rather than an AnimationController-eased transition, since that snap is
/// what reads as "blinking" instead of "breathing".
class BlinkingDot extends StatefulWidget {
  final Color color;
  final double radius;

  const BlinkingDot({super.key, this.color = Colors.red, this.radius = 5});

  @override
  State<BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<BlinkingDot> {
  late final Timer _timer;
  bool _on = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      setState(() => _on = !_on);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _on ? 1.0 : 0.15,
      child: CircleAvatar(radius: widget.radius, backgroundColor: widget.color),
    );
  }
}
