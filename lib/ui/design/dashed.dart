// lib/ui/design/dashed.dart — dashed outlines: a selection is dashed, distinct from
// the solid outline of the playing verse (features-v3 multi-verse-selection).
import 'package:flutter/widgets.dart';

/// Strokes [rrect] as dashes of [dash] separated by [gap] (logical pixels).
void drawDashedRRect(Canvas canvas, RRect rrect, Paint paint, {double dash = 6, double gap = 4}) {
  for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
    for (var d = 0.0; d < metric.length; d += dash + gap) {
      canvas.drawPath(metric.extractPath(d, d + dash), paint);
    }
  }
}

/// A dashed rounded border around [child].
class DashedBorder extends StatelessWidget {
  final Color color;
  final double width;
  final double radius;
  final Widget child;
  const DashedBorder({super.key, required this.color, this.width = 2, this.radius = 16, required this.child});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(foregroundPainter: _DashedPainter(color, width, radius), child: child);
}

class _DashedPainter extends CustomPainter {
  final Color color;
  final double width;
  final double radius;
  const _DashedPainter(this.color, this.width, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final inset = width / 2;
    final rect = Rect.fromLTWH(inset, inset, size.width - width, size.height - width);
    drawDashedRRect(
      canvas,
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_DashedPainter old) => old.color != color || old.width != width || old.radius != radius;
}
