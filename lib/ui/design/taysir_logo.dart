// lib/ui/design/taysir_logo.dart — the Taysir mark (features-v3 app-logo).
//
// A gold eight-pointed star around a dark disc holding an open book with a gold
// bookmark ribbon and a small star. Drawn from the prototype's Logo component
// (a 200×200 SVG), path for path. `mark` is the bare emblem (drawer header);
// `icon` sets it on a dark rounded tile (about screen, splash).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum LogoVariant { mark, icon }

class TaysirLogo extends StatelessWidget {
  final double size;
  final LogoVariant variant;
  const TaysirLogo({super.key, this.size = 48, this.variant = LogoVariant.mark});

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(size: Size.square(size), painter: const _LogoPainter());
    return Semantics(
      label: 'شعار تيسير الشاطبية',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: variant == LogoVariant.mark
            ? mark
            : DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * 0.23),
                  gradient: const RadialGradient(
                    center: Alignment(0, -0.6),
                    radius: 1.2,
                    colors: [Color(0xFF3F2F15), Color(0xFF1B1307)],
                    stops: [0, 0.7],
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, 10)),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.all(size * 0.13),
                  child: CustomPaint(painter: const _LogoPainter()),
                ),
              ),
      ),
    );
  }
}

/// Parses the absolute M/L/C/Z subset the logo's SVG paths use.
Path _svg(String d) {
  final path = Path();
  final tokens = RegExp(r'[MLCZ]|-?\d+(?:\.\d+)?').allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  var cmd = 'M';
  double n() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (RegExp(r'[MLCZ]').hasMatch(tokens[i])) cmd = tokens[i++];
    switch (cmd) {
      case 'M':
        path.moveTo(n(), n());
        cmd = 'L'; // implicit lineto after a moveto
      case 'L':
        path.lineTo(n(), n());
      case 'C':
        path.cubicTo(n(), n(), n(), n(), n(), n());
      case 'Z':
        path.close();
    }
  }
  return path;
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  static const _gold = [Color(0xFFFFE3B3), Color(0xFFFFB743), Color(0xFFB36F0E)];
  static final _outerStar = _svg(
    'M100.0 12.0 L125.8 37.8 L162.2 37.8 L162.2 74.2 L188.0 100.0 L162.2 125.8 '
    'L162.2 162.2 L125.8 162.2 L100.0 188.0 L74.2 162.2 L37.8 162.2 L37.8 125.8 L12.0 100.0 L37.8 74.2 '
    'L37.8 37.8 L74.2 37.8 Z',
  );
  static final _innerStar = _svg(
    'M100.0 24.0 L122.3 46.3 L153.7 46.3 L153.7 77.7 L176.0 100.0 L153.7 122.3 '
    'L153.7 153.7 L122.3 153.7 L100.0 176.0 L77.7 153.7 L46.3 153.7 L46.3 122.3 L24.0 100.0 L46.3 77.7 '
    'L46.3 46.3 L77.7 46.3 Z',
  );
  static final _rosette = _svg(
    'M125.3 39.0 L135.7 64.3 L161.0 74.7 L150.5 100.0 L161.0 125.3 L135.7 135.7 '
    'L125.3 161.0 L100.0 150.5 L74.7 161.0 L64.3 135.7 L39.0 125.3 L49.5 100.0 L39.0 74.7 L64.3 64.3 '
    'L74.7 39.0 L100.0 49.5 Z',
  );
  static final _sparkle = _svg(
    'M100 72 L102.6 79.4 L110 82 L102.6 84.6 L100 92 L97.4 84.6 L90 82 L97.4 79.4 Z',
  );
  static final _leftPage = _svg('M100 101 C88 93 74 92 62 96 L62 124 C74 120 88 121 100 129 Z');
  static final _rightPage = _svg('M100 101 C112 93 126 92 138 96 L138 124 C126 120 112 121 100 129 Z');
  static final _lines = _svg(
    'M68 104 C77 101.5 86 102 94 106 M68 111 C77 108.5 86 109 94 113 '
    'M68 118 C77 115.5 86 116 94 120 M106 106 C114 102 123 101.5 132 104 '
    'M106 113 C114 109 123 108.5 132 111 M106 120 C114 116 123 115.5 132 118',
  );
  static final _ribbon = _svg('M104 104 L104 138 L108 134 L112 138 L112 102 Z');
  static const _dots = [
    Offset(130.6, 26.1), Offset(173.9, 69.4), Offset(173.9, 130.6), Offset(130.6, 173.9), //
    Offset(69.4, 173.9), Offset(26.1, 130.6), Offset(26.1, 69.4), Offset(69.4, 26.1),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200, size.height / 200);
    const box = Rect.fromLTWH(12, 12, 176, 176);
    final gold = Paint()
      ..shader = ui.Gradient.linear(box.topLeft, box.bottomRight, _gold, const [0, 0.45, 1]);

    for (final d in _dots) {
      canvas.drawCircle(d, 3.6, gold);
    }
    canvas.drawPath(_outerStar, gold);
    canvas.drawPath(
      _outerStar,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..shader = ui.Gradient.linear(box.bottomLeft, box.topRight, const [
          Color(0xFF7A4A06),
          Color(0xFFFADBAE),
        ]),
    );
    canvas.drawPath(
      _innerStar,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF7A4A06).withValues(alpha: 0.45),
    );
    canvas.drawPath(_rosette, Paint()..color = const Color(0xFFFFD48A).withValues(alpha: 0.35));
    canvas.drawPath(
      _rosette,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF7A4A06).withValues(alpha: 0.35),
    );

    const centre = Offset(100, 100);
    canvas.drawCircle(
      centre,
      50,
      Paint()
        ..shader = ui.Gradient.radial(const Offset(100, 92), 60, const [
          Color(0xFF3F2F15),
          Color(0xFF140D05),
        ]),
    );
    canvas.drawCircle(
      centre,
      50,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = const Color(0xFFFADBAE),
    );
    canvas.drawCircle(
      centre,
      44,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFFFAB2E).withValues(alpha: 0.55),
    );
    canvas.drawPath(_sparkle, Paint()..color = const Color(0xFFFFAB2E));

    final page = Paint()
      ..shader = ui.Gradient.linear(const Offset(0, 92), const Offset(0, 129), const [
        Color(0xFFFFFBF2),
        Color(0xFFEADCC0),
      ]);
    canvas.drawPath(_leftPage, page);
    canvas.drawPath(_rightPage, page);
    canvas.drawPath(
      _lines,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFB39A6B),
    );
    canvas.drawLine(
      const Offset(100, 101),
      const Offset(100, 129),
      Paint()
        ..strokeWidth = 1.6
        ..color = const Color(0xFF965F0D),
    );
    canvas.drawPath(_ribbon, Paint()..color = const Color(0xFFFFAB2E));
    canvas.drawPath(
      _ribbon,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF965F0D),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
