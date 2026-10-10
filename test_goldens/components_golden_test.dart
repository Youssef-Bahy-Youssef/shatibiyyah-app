// Goldens of the core components (item 3.3) in paper and in night (jade), each
// laid out as its render of the prototype in test_goldens/prototype/ (made from
// v2.js's own component functions) and reviewed side by side with it.
//
//   flutter test test_goldens/components_golden_test.dart [--update-goldens]
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/anchored_popover.dart';
import 'package:shatibiyyah/ui/design/components/khatam.dart';
import 'package:shatibiyyah/ui/design/components/min_segmented.dart';
import 'package:shatibiyyah/ui/design/components/ornament.dart';
import 'package:shatibiyyah/ui/design/components/stat_tile.dart';
import 'package:shatibiyyah/ui/design/components/tz_button.dart';
import 'package:shatibiyyah/ui/design/components/tz_switch.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'golden_fonts.dart';

/// Each golden: its width and height (the prototype render's, in logical
/// pixels) and the component as the prototype shows it.
final Map<String, (double, double, Widget Function())> components = {
  'khatam': (390, 90, () => const _Khatams()),
  'popover': (390, 150, () => const _Popover()),
  'switch': (
    390,
    60,
    () => Padding(
      // The prototype's 26 px row centred 25 px down; the 48 px target is centred on it.
      padding: const EdgeInsets.fromLTRB(12, 1, 12, 11),
      child: Row(
        children: [
          TzSwitch(value: true, onWord: 'تُتلى', offWord: 'لا تُتلى', onChanged: (_) {}),
          const SizedBox(width: 24),
          TzSwitch(value: false, onWord: 'ظاهر', offWord: 'مخفي', onChanged: (_) {}),
        ],
      ),
    ),
  ),
  'min_segmented': (
    390,
    68,
    () => Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), // 12 around the 44 px pill: its 48 px target adds 2 each side
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: MinSegmented<String>(
          options: const {'page': 'الصفحة', 'text': 'النص'},
          selected: 'text',
          onSelect: (_) {},
        ),
      ),
    ),
  ),
  'stat_tile': (
    390,
    90,
    () => Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, (v, l, b)) in const [
            ('١٫٢٥×', 'السرعة', null),
            ('٣', 'تكرار البيت', '٢/٣'),
            ('١', 'تكرار المقطع', null),
            ('٢ ث', 'الفاصل', null),
          ].indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: StatTile(value: v, label: l, badge: b, onTap: () {}),
            ),
          ],
        ],
      ),
    ),
  ),
  'button': (
    390,
    72,
    () => Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            flex: 13,
            child: TzButton.primary(label: 'تشغيل الباب', icon: 'play', iconFilled: true, onPressed: () {}),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 10,
            child: TzButton.tonal(label: 'الشرح', icon: 'book', onPressed: () {}),
          ),
        ],
      ),
    ),
  ),
  'gilt_rule': (
    390,
    60,
    () => const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Padding(padding: EdgeInsets.fromLTRB(20, 6, 20, 0), child: GiltRule()),
          Padding(padding: EdgeInsets.only(top: 8, bottom: 6), child: GiltRule(centered: true)),
        ],
      ),
    ),
  ),
};

/// As the prototype's .pop at top 22 with its arrow at x 120 (RTL text inside).
class _Popover extends StatelessWidget {
  const _Popover();
  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return Stack(
      children: [
        Positioned.fill(
          child: AnchoredPopover(
            anchor: const Rect.fromLTWH(100, 0, 40, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('البيت ٢٢٩', style: TzType.label.copyWith(color: c.ink)),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 6),
                  child: Text('نافذة تشير إلى ما فُتحت منه', style: TzType.caption.copyWith(color: c.ink3)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Khatams extends StatelessWidget {
  const _Khatams();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        const Khatam('٢٢٦', size: 56),
        const SizedBox(width: 18),
        const Khatam('١١', size: 56, current: true),
        const SizedBox(width: 18),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: TzTheme.of(context).colors.cover, borderRadius: BorderRadius.circular(14)),
          child: const Khatam('٤٢٪', size: 48, onCover: true, progress: 0.42),
        ),
        const SizedBox(width: 18),
        const Khatam('٢٢٩', size: 26),
      ],
    ),
  );
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

  for (final MapEntry(key: name, value: (w, h, build)) in components.entries) {
    for (final (theme, tz) in [('paper', TzTheme.paper), ('night', TzTheme.dark)]) {
      testWidgets('${name}_$theme', (tester) async {
        // flutter_test draws shadows without blur unless told otherwise; these goldens show the real ones.
        debugDisableShadows = false;
        try {
          tester.view.physicalSize = Size(w, h);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: tzThemeData(tz),
              home: MediaQuery(
                data: MediaQueryData(size: Size(w, h), disableAnimations: true),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Scaffold(
                    body: RepaintBoundary(
                      key: key,
                      child: ColoredBox(
                        color: tz.colors.bg,
                        child: SizedBox(width: w, height: h, child: build()),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await settleSvgs(tester);
          await expectLater(find.byKey(key), matchesGoldenFile('goldens/components/${name}_$theme.png'));
        } finally {
          debugDisableShadows = true;
        }
      });
    }
  }
}
