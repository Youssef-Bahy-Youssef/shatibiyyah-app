// Goldens of the core components (item 3.3) in paper and in night (jade), each
// laid out as its render of the prototype in test_goldens/prototype/ (made from
// v2.js's own component functions) and reviewed side by side with it.
//
//   flutter test test_goldens/components_golden_test.dart [--update-goldens]
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/khatam.dart';
import 'package:shatibiyyah/ui/design/components/ornament.dart';
import 'package:shatibiyyah/ui/design/components/tz_button.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'golden_fonts.dart';

/// Each golden: its width and height (the prototype render's, in logical
/// pixels) and the component as the prototype shows it.
final Map<String, (double, double, Widget Function())> components = {
  'khatam': (390, 90, () => const _Khatams()),
  'button': (390, 72, () => Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(flex: 13, child: TzButton.primary(label: 'تشغيل الباب', icon: 'play', iconFilled: true, onPressed: () {})),
          const SizedBox(width: 8),
          Expanded(flex: 10, child: TzButton.tonal(label: 'الشرح', icon: 'book', onPressed: () {})),
        ]),
      )),
  'gilt_rule': (390, 60, () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          Padding(padding: EdgeInsets.fromLTRB(20, 6, 20, 0), child: GiltRule()),
          Padding(padding: EdgeInsets.only(top: 8, bottom: 6), child: GiltRule(centered: true)),
        ]),
      )),
};

class _Khatams extends StatelessWidget {
  const _Khatams();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
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
        ]),
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
        tester.view.physicalSize = Size(w, h);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: tzThemeData(tz),
          home: MediaQuery(
            data: MediaQueryData(size: Size(w, h), disableAnimations: true),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: RepaintBoundary(
                  key: key,
                  child: ColoredBox(color: tz.colors.bg, child: SizedBox(width: w, height: h, child: build())),
                ),
              ),
            ),
          ),
        ));
        await settleSvgs(tester);
        await expectLater(find.byKey(key), matchesGoldenFile('goldens/components/${name}_$theme.png'));
      });
    }
  }
}
