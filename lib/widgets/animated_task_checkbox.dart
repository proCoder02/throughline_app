import 'package:flutter/material.dart';

import '../theme.dart';

/// Rotates a Path around its own bounding-box center -- straight from the
/// reference article's own extension (Medium/flutterfx, "Uncheck your
/// doubts: mastering Flutter canvas with a simple checkbox animation").
extension _PathRotate on Path {
  Path rotateFromCenter(double angle) {
    final bounds = getBounds();
    final matrix = Matrix4.identity()
      ..translateByDouble(bounds.center.dx, bounds.center.dy, 0, 1)
      ..rotateZ(angle)
      ..translateByDouble(-bounds.center.dx, -bounds.center.dy, 0, 1);
    return transform(matrix.storage);
  }
}

/// Purely a visual indicator -- it animates itself whenever [checked] flips,
/// but doesn't own the tap (the row around it already does, via the same
/// onTap that used to just swap a static Icon). Same technique as the
/// reference article: the box fills in as a Path (with a small settling
/// rotation), and the checkmark is drawn stroke-by-stroke via
/// PathMetric.extractPath(0, length * t) rather than faded in as a whole
/// glyph -- that's what makes it read as "being checked" rather than "an
/// icon swapped".
class AnimatedTaskCheckbox extends StatefulWidget {
  final bool checked;
  final double size;

  const AnimatedTaskCheckbox({super.key, required this.checked, this.size = 22});

  @override
  State<AnimatedTaskCheckbox> createState() => _AnimatedTaskCheckboxState();
}

class _AnimatedTaskCheckboxState extends State<AnimatedTaskCheckbox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: widget.checked ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant AnimatedTaskCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checked != widget.checked) {
      if (widget.checked) {
        _controller.forward(from: 0);
      } else {
        _controller.reverse(from: 1);
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
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _CheckboxPainter(progress: Curves.easeOutBack.transform(_controller.value)),
      ),
    );
  }
}

class _CheckboxPainter extends CustomPainter {
  final double progress;

  const _CheckboxPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final clamped = progress.clamp(0.0, 1.0);
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(1), Radius.circular(size.width * 0.28));
    // A small settle-in rotation as the box fills, using the reference
    // article's own rotateFromCenter -- eases out to 0 by the time it's
    // fully checked, purely a flourish (unchecking just reverses it).
    final boxPath = (Path()..addRRect(rrect)).rotateFromCenter((1 - clamped) * -0.12);

    canvas.drawPath(
      boxPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = AppColors.dmAccent.withValues(alpha: clamped),
    );
    canvas.drawPath(
      boxPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = Color.lerp(AppColors.dmTextSoft, AppColors.dmAccent, clamped)!,
    );

    // The checkmark only starts drawing once the box is mostly filled, and
    // is revealed stroke-by-stroke (not faded in as a whole glyph) via
    // PathMetric.extractPath -- the actual technique the article is about.
    if (clamped > 0.35) {
      final checkPath = Path()
        ..moveTo(size.width * 0.27, size.height * 0.52)
        ..lineTo(size.width * 0.43, size.height * 0.68)
        ..lineTo(size.width * 0.75, size.height * 0.32);
      final metric = checkPath.computeMetrics().first;
      final t = ((clamped - 0.35) / 0.65).clamp(0.0, 1.0);
      final drawn = metric.extractPath(0, metric.length * t);
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CheckboxPainter oldDelegate) => oldDelegate.progress != progress;
}
