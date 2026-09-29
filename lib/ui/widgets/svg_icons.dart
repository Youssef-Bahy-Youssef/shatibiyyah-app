// lib/ui/widgets/svg_icons.dart — the transport / chip glyphs, drawn from the exact SVG
// <path> data in index.html so the shapes match the PWA pixel-for-pixel (all viewBox 0 0 24 24).
import 'package:flutter/material.dart';

enum SvgIcon { play, pause, prev, next, stop, chevronRight }

class SvgIconWidget extends StatelessWidget {
  final SvgIcon icon;
  final double size;
  final Color color;
  const SvgIconWidget(this.icon, {super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _IconPainter(icon, color)),
    );
  }
}

class _IconPainter extends CustomPainter {
  final SvgIcon icon;
  final Color color;
  _IconPainter(this.icon, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24.0;
    canvas.save();
    canvas.scale(k);
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    for (final p in _paths(icon)) {
      canvas.drawPath(p, fill);
    }
    canvas.restore();
  }

  List<Path> _paths(SvgIcon i) {
    switch (i) {
      case SvgIcon.play:
        // <path d="M7 5l13 7-13 7z"/>
        return [
          Path()
            ..moveTo(7, 5)
            ..lineTo(20, 12)
            ..lineTo(7, 19)
            ..close()
        ];
      case SvgIcon.pause:
        // <path d="M7 5h3.6v14H7z"/><path d="M13.4 5H17v14h-3.6z"/>
        return [
          _rect(7, 5, 3.6, 14),
          _rectTo(13.4, 5, 17, 14),
        ];
      case SvgIcon.prev:
        // <path d="M6 5h2.4v14H6z"/><path d="M20.5 5L9 12l11.5 7z"/>
        return [
          _rect(6, 5, 2.4, 14),
          Path()
            ..moveTo(20.5, 5)
            ..lineTo(9, 12)
            ..lineTo(20.5, 19)
            ..close()
        ];
      case SvgIcon.next:
        // <path d="M15.6 5H18v14h-2.4z"/><path d="M3.5 5L15 12 3.5 19z"/>
        return [
          _rectTo(15.6, 5, 18, 14),
          Path()
            ..moveTo(3.5, 5)
            ..lineTo(15, 12)
            ..lineTo(3.5, 19)
            ..close()
        ];
      case SvgIcon.stop:
        // <rect x="6" y="6" width="12" height="12" rx="2"/>
        return [
          Path()
            ..addRRect(RRect.fromRectAndRadius(
                const Rect.fromLTWH(6, 6, 12, 12), const Radius.circular(2)))
        ];
      case SvgIcon.chevronRight:
        return [
          Path()
            ..moveTo(7, 5)
            ..lineTo(20, 12)
            ..lineTo(7, 19)
            ..close()
        ];
    }
  }

  Path _rect(double x, double y, double w, double h) =>
      Path()..addRect(Rect.fromLTWH(x, y, w, h));
  Path _rectTo(double x, double y, double right, double h) =>
      Path()..addRect(Rect.fromLTRB(x, y, right, y + h));

  @override
  bool shouldRepaint(covariant _IconPainter old) =>
      old.icon != icon || old.color != color;
}
