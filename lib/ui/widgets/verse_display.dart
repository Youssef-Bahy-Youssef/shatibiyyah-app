// lib/ui/widgets/verse_display.dart — now-playing medallion (.stage / .medallion).
// Ported from index.html (the shamsa SVG) + style.css (.medallion / .verse-num /
// .verse-cap / .chapter-name). The shamsa rotates while playing (44s linear spin).
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../theme.dart';
import '../../utils/arabic.dart';

class VerseDisplay extends StatefulWidget {
  final AppController app;
  final bool compact; // mobile row layout
  const VerseDisplay({super.key, required this.app, required this.compact});

  @override
  State<VerseDisplay> createState() => _VerseDisplayState();
}

class _VerseDisplayState extends State<VerseDisplay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 44));
  double _scale = 1; // .verse-num.tick → scale(1.08)
  int _lastVerse = -1;
  final List<StreamSubscription<void>> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.add(widget.app.audio.onPlay.listen((_) {
      if (mounted) _spin.repeat();
    }));
    _subs.add(widget.app.audio.onPause.listen((_) {
      if (mounted) _spin.stop();
    }));
    _subs.add(widget.app.audio.onVerseChange.listen((_) {
      if (!mounted || widget.app.audio.scrubbing) return;
      setState(() => _scale = 1.08);
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _scale = 1);
      });
    }));
    if (!widget.app.isPaused) _spin.repeat();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.app,
      builder: (context, _) {
        final app = widget.app;
        if (app.currentVerse != _lastVerse) _lastVerse = app.currentVerse;
        final playing = !app.isPaused;
        final size = widget.compact ? 62.0 : 150.0;
        final glowInset = -size * 0.14; // CSS .medallion::before { inset:-14% }
        final medallion = SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none, // allow the glow to bleed past the medallion bounds
            alignment: Alignment.center,
            children: [
              // glow (.medallion::before) — negative inset via Positioned (margins can't be <0)
              Positioned(
                left: glowInset,
                right: glowInset,
                top: glowInset,
                bottom: glowInset,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 500),
                    opacity: playing ? 0.7 : 0.25,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0x57FFAB2E), Color(0x00FFAB2E)],
                          stops: [0.0, 0.65],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              CustomPaint(size: Size(size, size), painter: _ShamsaPainter()),
              AnimatedBuilder(
                animation: _spin,
                builder: (context, child) => Transform.rotate(
                    angle: _spin.value * 2 * math.pi, child: child),
                child: CustomPaint(
                    size: Size(size, size), painter: _ShamsaDotsPainter()),
              ),
              AnimatedScale(
                scale: _scale,
                duration: const Duration(milliseconds: 200),
                curve: const Cubic(.22, .61, .36, 1),
                child: Text(
                  ar(app.currentVerse),
                  style: naskh(
                    size: widget.compact ? 29.6 : 57.6, // 1.85rem / 3.6rem
                    weight: FontWeight.w700,
                    color: C.goldBright,
                  ).copyWith(shadows: const [
                    Shadow(color: Color(0x73FFAB2E), blurRadius: 18, offset: Offset(0, 2)),
                  ]),
                ),
              ),
            ],
          ),
        );

        final name = app.chapterName.isEmpty ? '—' : app.chapterName;

        if (widget.compact) {
          // .stage{flex-direction:row} on mobile; verse-cap hidden; name line-clamp 2
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              medallion,
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  name,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: naskh(size: 18.88, weight: FontWeight.w600, color: C.parch, height: 1.3),
                ),
              ),
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            medallion,
            const SizedBox(height: 10),
            Text('البيت',
                style: kufi(size: 11.52, weight: 600, color: C.muted, letterSpacing: 2)),
            const SizedBox(height: 8),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: naskh(size: 24, weight: FontWeight.w600, color: C.parch, height: 1.35),
            ),
          ],
        );
      },
    );
  }
}

// Ported from index.html: <svg class="shamsa" viewBox="0 0 200 200"> — concentric circles
// (r94 #965f0d, r84/r23 #ffab2e) + a 16-point star. Drawn in a 0..200 space, scaled to size.
class _ShamsaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 200.0;
    canvas.save();
    canvas.scale(k);
    final c = const Offset(100, 100);
    Paint p(double w, Color col) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeJoin = StrokeJoin.round
      ..color = col;
    canvas.drawCircle(c, 94, p(1.4, C.goldDeep));
    canvas.drawCircle(c, 84, p(1.0, C.gold));
    // 16-point star polygon (exact points from the SVG)
    const pts = [
      [100, 30], [112, 72], [154, 60], [124, 92], [170, 100], [124, 108],
      [154, 140], [112, 128], [100, 170], [88, 128], [46, 140], [76, 108],
      [30, 100], [76, 92], [46, 60], [88, 72],
    ];
    final path = Path()..moveTo(pts[0][0].toDouble(), pts[0][1].toDouble());
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i][0].toDouble(), pts[i][1].toDouble());
    }
    path.close();
    canvas.drawPath(path, p(1.3, C.gold)..color = C.gold.withValues(alpha: .95));
    canvas.drawCircle(c, 23, p(1.2, C.gold));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// Ported from index.html: <svg class="shamsa-spin"> — 8 filled gold dots (r2.4).
class _ShamsaDotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 200.0;
    canvas.save();
    canvas.scale(k);
    final fill = Paint()..color = C.gold;
    const dots = [
      [100, 11], [100, 189], [11, 100], [189, 100],
      [37, 37], [163, 37], [37, 163], [163, 163],
    ];
    for (final d in dots) {
      canvas.drawCircle(Offset(d[0].toDouble(), d[1].toDouble()), 2.4, fill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
