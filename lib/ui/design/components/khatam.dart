// lib/ui/design/components/khatam.dart — the khatam (item 3.3, ADR 0019).
//
// An eight-point star made of two squares (outer radius 0.475 × size), holding
// a verse, chapter or step number. Outline (gilt) on the page; filled lapis when
// current; on the binding in gilt-on-cover, with a ring for download progress.
// Geometry as v2.js `khatam()`.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';
import 'tz_motion.dart';

/// The star's 16 corners in a [size] box, the first straight up.
List<Offset> khatamPoints(double size) {
  final c = size / 2, h = size * 0.335;
  final outer = h * math.sqrt2, inner = h / math.cos(math.pi / 8);
  return [
    for (var k = 0; k < 16; k++)
      Offset(
        c + (k.isOdd ? inner : outer) * math.cos(math.pi * k / 8 - math.pi / 2),
        c + (k.isOdd ? inner : outer) * math.sin(math.pi * k / 8 - math.pi / 2),
      ),
  ];
}

/// The number's size: smaller as it gets longer.
double khatamFontSize(double size, String label) =>
    size * (label.length > 2 ? 0.26 : (label.length > 1 ? 0.3 : 0.34));

class Khatam extends StatelessWidget {
  final String label;
  final double size;

  /// Filled lapis: the current verse or chapter.
  final bool current;

  /// On the binding (the dock, the stepper).
  final bool onCover;

  /// A failure on the binding.
  final bool error;

  /// 0…1: a download ring around a smaller star (on the binding).
  final double? progress;

  /// The khatam is decorative unless labelled.
  final String? semanticLabel;

  const Khatam(this.label,
      {super.key, this.size = 36, this.current = false, this.onCover = false, this.error = false, this.progress, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final tz = TzTheme.of(context), c = tz.colors;
    final Color stroke, text;
    Color? fill;
    if (error) {
      stroke = text = c.errOnCover;
    } else if (onCover) {
      (stroke, text) = (c.giltOnCover, c.onCover);
    } else if (current) {
      (stroke, fill, text) = (c.lapis, c.lapis, c.bg);
    } else {
      (stroke, text) = (c.gilt, c.ink);
    }
    Widget paint(double? p) => CustomPaint(
          size: Size.square(size),
          painter: KhatamPainter(
            label: label,
            stroke: stroke,
            fill: fill,
            text: text,
            progress: p,
            ringTrack: c.coverLine,
            ringColor: c.giltOnCover,
            textDirection: Directionality.of(context),
          ),
        );
    final target = progress;
    final star = target == null
        ? paint(null)
        : TweenAnimationBuilder<double>(
            tween: Tween(end: target.clamp(0, 1).toDouble()),
            duration: tzDuration(context, TzMotion.long),
            curve: TzMotion.standard,
            builder: (_, p, _) => paint(p),
          );
    return semanticLabel == null
        ? ExcludeSemantics(child: star)
        : Semantics(label: semanticLabel, image: true, child: ExcludeSemantics(child: star));
  }
}

class KhatamPainter extends CustomPainter {
  final String label;
  final Color stroke, text, ringTrack, ringColor;
  final Color? fill;
  final double? progress;
  final TextDirection textDirection;

  const KhatamPainter({
    required this.label,
    required this.stroke,
    required this.text,
    required this.ringTrack,
    required this.ringColor,
    required this.textDirection,
    this.fill,
    this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide, c = s / 2;
    final ringed = progress != null;
    if (ringed) {
      final r = c - 1.5;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(Offset(c, c), r, ring..color = ringTrack);
      canvas.drawArc(Rect.fromCircle(center: Offset(c, c), radius: r), -math.pi / 2, 2 * math.pi * progress!, false,
          ring
            ..color = ringColor
            ..strokeCap = StrokeCap.round);
    }
    canvas.save();
    if (ringed) {
      canvas.translate(c, c);
      canvas.scale(0.74);
      canvas.translate(-c, -c);
    }
    final star = Path()..addPolygon(khatamPoints(s), true);
    if (fill != null) canvas.drawPath(star, Paint()..color = fill!);
    canvas.drawPath(
        star,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..strokeJoin = StrokeJoin.round
          ..color = stroke);
    canvas.restore();
    if (label.isEmpty) return;
    final fs = khatamFontSize(s, label) * (ringed ? 0.85 : 1);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(fontFamily: TzFont.ui, fontWeight: FontWeight.w600, fontSize: fs, color: text, height: 1),
      ),
      textDirection: textDirection,
    )..layout();
    // v2.js puts the baseline at c + 0.36 × font size.
    final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    tp.paint(canvas, Offset(c - tp.width / 2, c + fs * 0.36 - baseline));
  }

  @override
  bool shouldRepaint(KhatamPainter old) =>
      old.label != label ||
      old.stroke != stroke ||
      old.fill != fill ||
      old.text != text ||
      old.progress != progress ||
      old.ringTrack != ringTrack ||
      old.ringColor != ringColor;
}
