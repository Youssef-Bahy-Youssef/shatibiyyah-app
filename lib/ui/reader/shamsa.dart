// lib/ui/reader/shamsa.dart — the gold 16-point medallion around the playing verse number.
//
// Geometry from the prototype (Shamsa.dc.html, 200-unit box): a 16-point star with
// tips at r=86 and valleys at r=66, a second star offset by half a step, eight dots
// at r=95, and a solid centre disc so no line crosses the number. The star turns
// once a minute while a verse plays (not with reduced motion). A chip below shows
// the verse repeat («البيت ٢/٥»); an outer ring shows section-repeat progress.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart' show naskh, kufi;
import '../../utils/arabic.dart';
import '../design/taysir_colors.dart';

class Shamsa extends StatefulWidget {
  final double size;
  final int verse;
  final bool playing;
  final String? chip; // e.g. «البيت ٢/٥»
  final double? ring; // 0..1 section progress, null = none

  const Shamsa({super.key, required this.size, required this.verse, this.playing = false, this.chip, this.ring});

  @override
  State<Shamsa> createState() => _ShamsaState();
}

class _ShamsaState extends State<Shamsa> with SingleTickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 60));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(Shamsa old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.playing && !reduce) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final s = widget.size;
    final small = s < 80;
    final discR = small ? 60.0 : 56.0;
    final digits = widget.verse.toString().length;
    final fontSize = s * (discR * 2 / 200) * (digits >= 4 ? 0.36 : digits == 3 ? 0.46 : 0.58);
    return Semantics(
      label: 'البيت ${ar(widget.verse)}${widget.playing ? '، قيد التلاوة' : ''}',
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -s * 0.12,
              right: -s * 0.12,
              top: -s * 0.12,
              bottom: -s * 0.12,
              child: AnimatedOpacity(
                opacity: widget.playing ? 0.7 : 0.25,
                duration: const Duration(milliseconds: 500),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [t.gold.withValues(alpha: 0.32), t.gold.withValues(alpha: 0)],
                      stops: const [0, 0.65],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(child: CustomPaint(painter: _RingPainter(t, widget.ring))),
            Positioned.fill(
              child: RotationTransition(
                turns: _spin,
                child: CustomPaint(painter: _StarPainter(t, small: small, size: s)),
              ),
            ),
            Positioned.fill(child: CustomPaint(painter: _DiscPainter(t, discR, small ? 7 : 6))),
            Center(
              child: Padding(
                padding: EdgeInsets.only(top: fontSize * 0.1),
                child: Text(ar(widget.verse),
                    style: naskh(size: fontSize, weight: FontWeight.w700, color: t.goldBright, height: 1)),
              ),
            ),
            if (widget.chip != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: -9,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
                    decoration: BoxDecoration(color: t.gold, borderRadius: BorderRadius.circular(999)),
                    child: Text(widget.chip!, style: kufi(size: 12, weight: 600, color: t.onGold, height: 1.5)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Offset _polar(double r, double a, double scale) =>
    Offset((100 + r * math.cos(a)) * scale, (100 + r * math.sin(a)) * scale);

class _StarPainter extends CustomPainter {
  final TaysirColors t;
  final bool small;
  final double size;
  _StarPainter(this.t, {required this.small, required this.size});

  @override
  void paint(Canvas canvas, Size box) {
    final k = box.width / 200;
    Path star(double tip, double valley, double offset) {
      final path = Path();
      for (var i = 0; i < 32; i++) {
        final a = i * math.pi / 16 - math.pi / 2 + offset;
        final p = _polar(i.isOdd ? valley : tip, a, k);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      return path..close();
    }

    final outer = star(86, 66, 0);
    canvas.drawPath(outer, Paint()..color = t.gold.withValues(alpha: 0.16));
    canvas.drawPath(
        outer,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeJoin = StrokeJoin.round
          ..color = t.gold);
    if (!small) {
      canvas.drawPath(
          star(74, 62, math.pi / 32),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = t.goldDeep);
      final dot = Paint()..color = t.gold;
      final r = math.max(2.2, 260 / size) * k;
      for (var i = 0; i < 8; i++) {
        canvas.drawCircle(_polar(95, i * math.pi / 4 - math.pi / 2, k), r, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.t != t || old.small != small;
}

class _DiscPainter extends CustomPainter {
  final TaysirColors t;
  final double discR, inset;
  _DiscPainter(this.t, this.discR, this.inset);

  @override
  void paint(Canvas canvas, Size box) {
    final k = box.width / 200;
    final c = Offset(100 * k, 100 * k);
    canvas.drawCircle(
        c,
        90 * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = t.goldDeep);
    canvas.drawCircle(c, discR * k, Paint()..color = t.panel);
    canvas.drawCircle(
        c,
        discR * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = t.gold);
    canvas.drawCircle(
        c,
        (discR - inset) * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = t.goldDeep.withValues(alpha: 0.8));
  }

  @override
  bool shouldRepaint(_DiscPainter old) => old.t != t || old.discR != discR;
}

class _RingPainter extends CustomPainter {
  final TaysirColors t;
  final double? progress;
  _RingPainter(this.t, this.progress);

  @override
  void paint(Canvas canvas, Size box) {
    final p = progress;
    if (p == null) return;
    final k = box.width / 200;
    final rect = Rect.fromCircle(center: Offset(100 * k, 100 * k), radius: 98 * k);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * k
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, stroke..color = t.line);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * p.clamp(0, 1), false, stroke..color = t.gold);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.t != t;
}
