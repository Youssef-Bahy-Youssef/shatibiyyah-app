// Shared by the component tests (item 3.3): pump a component in a theme, RTL,
// optionally with reduced motion, and check the accessibility guidelines.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import '../../test_goldens/golden_fonts.dart';

bool _fontsLoaded = false;

Future<void> pumpTz(WidgetTester tester, Widget child,
    {TzTheme tz = TzTheme.paper, bool reducedMotion = false, double width = 390, bool settle = true}) async {
  // Measure with the app's real faces, not flutter_test's box font.
  if (!_fontsLoaded) {
    await tester.runAsync(loadGoldenFonts);
    _fontsLoaded = true;
  }
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: tzThemeData(tz),
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 844), disableAnimations: reducedMotion),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Align(alignment: Alignment.topCenter, child: child)),
      ),
    ),
  ));
  if (settle) await tester.pumpAndSettle();
}

/// Every tappable thing is at least 48 × 48 and labelled.
Future<void> expectAccessible(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
}

/// After one frame with reduced motion, nothing is still animating.
Future<void> expectInstant(WidgetTester tester) async {
  await tester.pump();
  expect(tester.hasRunningAnimations, isFalse);
}
