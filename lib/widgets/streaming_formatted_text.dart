import 'dart:async';
import 'package:flutter/material.dart';

import 'formatted_text.dart';

/// Reveals [text] progressively, like ChatGPT/Gemini's own reply streaming
/// -- meant only for a freshly-arrived assistant reply (see MessageBubble's
/// `streamIn`), never for history loaded from cache/network, so re-opening
/// a thread doesn't retype every old answer.
///
/// Reveals at a fixed, legible pace (~18ms/char, ~55 chars/sec -- a real
/// "being typed" speed, not a blur) regardless of length, so a one-line
/// reply and a five-sentence one both read the same way. Only very long
/// replies get sped up, and only enough to stay under a hard cap, so
/// nothing drags on forever.
class StreamingFormattedText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  /// Fires on every tick while text is still revealing -- lets the host
  /// screen keep the list scrolled to the bottom as the bubble grows.
  final VoidCallback? onTick;

  /// Fires once the full text is visible.
  final VoidCallback? onDone;

  const StreamingFormattedText(this.text, {super.key, this.style, this.onTick, this.onDone});

  @override
  State<StreamingFormattedText> createState() => _StreamingFormattedTextState();
}

class _StreamingFormattedTextState extends State<StreamingFormattedText> {
  // 24ms (~42 ticks/sec) was rebuilding FormattedText's whole span/bullet
  // tree AND re-jumping the message list's scroll position that often --
  // each rebuild can reflow already-drawn lines as new characters wrap or
  // a bullet group forms, and that many scroll-position writes per second
  // compounds into visible jitter rather than a calm reveal. 60ms
  // (~16-17 ticks/sec) still reads as smooth continuous typing -- most
  // real typewriter-effect implementations land in this range -- while
  // cutting total layout/paint/scroll work during a reply by more than
  // half. perTick is recomputed from this automatically, so the overall
  // reveal speed/duration is unchanged, only the step size is coarser.
  static const _tick = Duration(milliseconds: 60);
  static const _msPerChar = 18;
  static const _maxTotalMs = 2600;

  int _visible = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final length = widget.text.length;
    if (length == 0) return;
    final naturalTotalMs = length * _msPerChar;
    final totalMs = naturalTotalMs > _maxTotalMs ? _maxTotalMs : naturalTotalMs;
    final ticks = (totalMs / _tick.inMilliseconds).ceil().clamp(1, 1 << 20);
    final perTick = (length / ticks).ceil().clamp(1, length);
    _timer = Timer.periodic(_tick, (_) {
      setState(() => _visible = (_visible + perTick).clamp(0, length));
      widget.onTick?.call();
      if (_visible >= length) {
        _timer?.cancel();
        widget.onDone?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormattedText(widget.text.substring(0, _visible), style: widget.style);
  }
}
