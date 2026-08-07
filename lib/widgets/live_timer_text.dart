import 'dart:async';

import 'package:flutter/material.dart';

/// A "0:07"-style elapsed-time counter that ticks on its own once a second,
/// like the recording-duration readout next to Telegram/WhatsApp's
/// voice-message record button. Takes the real start instant rather than
/// counting frames itself, so it's correct even if this widget mounts a
/// moment after recording actually began.
class LiveTimerText extends StatefulWidget {
  final DateTime startedAt;
  final TextStyle? style;

  const LiveTimerText({super.key, required this.startedAt, this.style});

  @override
  State<LiveTimerText> createState() => _LiveTimerTextState();
}

class _LiveTimerTextState extends State<LiveTimerText> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.startedAt);
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    return Text(
      '$minutes:${seconds.toString().padLeft(2, '0')}',
      style: widget.style,
    );
  }
}
