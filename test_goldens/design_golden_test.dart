// Golden images of the design system (items 3.2–3.3), in paper and night, at 2×,
// each reviewed side by side with its render of the prototype
// (design/redesign/index.html) once, then pinned. See reader_golden_test.dart for
// how goldens depend on the platform.
//
//   flutter test test_goldens/design_golden_test.dart [--update-goldens]
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_icon.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'golden_fonts.dart';

/// The prototype's "Icon set" card, in its order: the glyph names, filled ones marked.
const _iconCard = [
  ('play', true), ('pause', true), ('next', true), ('prev', true), ('book', false), ('book-f', true), //
  ('list', false), ('list-f', true), ('bookmark', false), ('gear', false), ('search', false), ('aa', false),
  ('listen', false), ('pen', false), ('copy', false), ('share', false), ('select', false), ('repeat', false),
  ('gauge', false), ('gap', false), ('mic', false), ('user', false), ('trash', false), ('down', false),
  ('retry', false), ('back', false), ('fwd', false), ('chev', false),
];

/// The card as v2.css lays it out (.card, .icons): 1180 px wide, 20 px padding,
/// tiles of at least 64 px with 8 px gaps on the page background.
class _IconCard extends StatelessWidget {
  const _IconCard();

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    const width = 1180.0, pad = 20.0, gap = 8.0, inner = width - 2 * pad - 2; // 1 px border
    const columns = (inner + gap) ~/ (64 + gap);
    const tile = (inner - (columns - 1) * gap) / columns;
    return Directionality(
      textDirection: TextDirection.ltr, // the presentation page, not the app
      child: Container(
        width: width,
        padding: const EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ICON SET: ONE GRID, ONE STROKE',
                style: TextStyle(fontFamily: TzFont.ui, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.96, color: c.ink3)),
            const SizedBox(height: 10),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (name, filled) in _iconCard)
                  Container(
                    width: tile,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      children: [
                        TzIcon(name, filled: filled, size: 22, color: c.ink),
                        const SizedBox(height: 4),
                        Text(name, style: TextStyle(fontFamily: TzFont.ui, fontSize: 10.5, height: 1.6, color: c.ink3)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '24 px grid, 1.6 stroke, round caps and joins. Transport glyphs and the active tab are filled; everything '
              'else is stroked. Glyphs that point are mirrored for RTL: “next verse” points left.',
              style: TextStyle(fontFamily: TzFont.ui, fontSize: 13, height: 1.6, color: c.ink2),
            ),
          ],
        ),
      ),
    );
  }
}

/// SVGs decode off the fake clock: let the real event loop run, then draw.
Future<void> settleSvgs(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadGoldenFonts();
  });

  for (final (theme, tz) in [('paper', TzTheme.paper), ('night', TzTheme.dark)]) {
    testWidgets('icon_sheet_$theme', (tester) async {
      tester.view.physicalSize = const Size(1180 * 2, 236 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: tzThemeData(tz),
        home: const Scaffold(body: Align(alignment: Alignment.topLeft, child: _IconCard())),
      ));
      await settleSvgs(tester);
      await expectLater(find.byType(_IconCard), matchesGoldenFile('goldens/icon_sheet_$theme.png'));
    });
  }
}
