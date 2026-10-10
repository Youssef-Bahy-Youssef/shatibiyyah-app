// Khatam (item 3.3, ADR 0019): the eight-point star from two squares (outer
// radius 0.475 × size) holding a number; outline, filled (current) and
// progress-ring variants, on the page or on the binding.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/khatam.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'harness.dart';

KhatamPainter painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(find.descendant(of: find.byType(Khatam), matching: find.byType(CustomPaint))).painter
        as KhatamPainter;

void main() {
  test('two squares make the star: 16 points, outer radius 0.475 × size, as v2.js draws it', () {
    final pts = khatamPoints(56);
    expect(pts, hasLength(16));
    final c = const Offset(28, 28);
    final radii = [for (final p in pts) (p - c).distance];
    expect(radii.reduce(math.max) / 56, closeTo(0.475, 0.002));
    expect(pts.first.dx, closeTo(28, 1e-9)); // the first point straight up
    expect(pts.first.dy, lessThan(28));
  });

  test('the number shrinks with its length, as in v2.js', () {
    expect(khatamFontSize(56, '٢'), closeTo(56 * 0.34, 1e-9));
    expect(khatamFontSize(56, '١١'), closeTo(56 * 0.30, 1e-9));
    expect(khatamFontSize(56, '٢٢٦'), closeTo(56 * 0.26, 1e-9));
  });

  testWidgets('outline: gilt stroke, ink number; decorative by default', (tester) async {
    await pumpTz(tester, const Khatam('٢٢٦', size: 56));
    final p = painter(tester);
    expect((p.stroke, p.fill, p.text, p.progress), (TzColors.paper.gilt, null, TzColors.paper.ink, null));
    expect(tester.getSize(find.byType(Khatam)), const Size(56, 56));
    expect(find.bySemanticsLabel(RegExp('.')), findsNothing);
  });

  testWidgets('current: filled lapis with the page colour for the number', (tester) async {
    await pumpTz(tester, const Khatam('١١', size: 56, current: true), tz: TzTheme.dark);
    final p = painter(tester);
    expect((p.stroke, p.fill, p.text), (TzColors.night.lapis, TzColors.night.lapis, TzColors.night.bg));
  });

  testWidgets('on the binding, with a download ring; error tone for a failure', (tester) async {
    await pumpTz(tester, const Khatam('٤٢٪', size: 48, onCover: true, progress: 0.42, semanticLabel: 'تنزيل ٤٢٪'));
    final p = painter(tester);
    expect((p.stroke, p.text, p.progress), (TzColors.paper.giltOnCover, TzColors.paper.onCover, 0.42));
    expect(find.bySemanticsLabel('تنزيل ٤٢٪'), findsOneWidget);
    await pumpTz(tester, const Khatam('!', size: 42, onCover: true, error: true));
    expect((painter(tester).stroke, painter(tester).text), (TzColors.paper.errOnCover, TzColors.paper.errOnCover));
  });

  testWidgets('the ring moves over 320 ms; instantly under reduced motion', (tester) async {
    await pumpTz(tester, const Khatam('٤٠', onCover: true, progress: 0.4));
    await pumpTz(tester, const Khatam('٦٠', onCover: true, progress: 0.6), settle: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(painter(tester).progress, inExclusiveRange(0.4, 0.6));
    await tester.pumpAndSettle();
    expect(painter(tester).progress, 0.6);

    await pumpTz(tester, const Khatam('٤٠', onCover: true, progress: 0.4), reducedMotion: true);
    await pumpTz(tester, const Khatam('٦٠', onCover: true, progress: 0.6), reducedMotion: true, settle: false);
    await expectInstant(tester);
    expect(painter(tester).progress, 0.6);
  });

  testWidgets('RTL or LTR, the number stays centred (it is drawn, not laid out)', (tester) async {
    await pumpTz(tester, const Directionality(textDirection: TextDirection.ltr, child: Khatam('٢٢٦')));
    await expectAccessible(tester);
  });
}
