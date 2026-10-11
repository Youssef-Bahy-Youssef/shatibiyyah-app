// ignore_for_file: invalid_use_of_visible_for_testing_member
// Golden images of «حول» and the tour (its three cards and «اختر التلاوة»), in
// paper and night, at 2× with real shadows as the handoff's goldens are. The
// design has no drawing of these screens: they are built from its components,
// and these images pin how that came out. «حول» is a debug build's, so it has
// the «نسخة التطوير» group a store build leaves out; it is longer than the
// screen, so it is drawn twice, as it opens and at its end, with every row of
// «رأيك ودعمك» (an address and a store page are given to it). See
// reader_golden_test.dart for how goldens depend on the platform.
//
//   flutter test test_goldens/about_tour_golden_test.dart [--update-goldens]
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/app/app_links.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/shell/about_screen.dart';
import 'package:shatibiyyah/ui/shell/tour_screen.dart';

import '../test/handoff/fixtures.dart';
import 'golden_fonts.dart';

void main() {
  final data = HandoffContent();
  final boundary = GlobalKey();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadGoldenFonts();
    await data.open();
  });
  tearDownAll(data.close);

  /// Pumps [build]'s screen in [tz], does [then] to it, and compares it with goldens/about_tour/[name].png.
  Future<void> shoot(WidgetTester tester, String name, TzTheme tz, Widget Function(ReaderController) build,
      {Future<void> Function(WidgetTester)? then}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.reset);
    // Shadows with their blur, as on a device (flutter_test draws them flat by default).
    debugDisableShadows = false;
    final r = await data.reader(tester, library: true, bookmarks: false);
    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: tzThemeData(tz),
        // Reduced motion: a card is drawn as it rests, not part-way into place.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: Directionality(textDirection: TextDirection.rtl, child: child!),
        ),
        home: build(r),
      ),
    ));
    // The scanned page is an asset image: decode it for real, then draw.
    await tester.runAsync(
        () => precacheImage(const AssetImage('assets/pages/page019.webp'), tester.element(find.byType(MaterialApp))));
    await tester.pump(const Duration(milliseconds: 100));
    if (then != null) await then(tester);
    // Card 3 reads the opening of the explanation from the database.
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 60));
    }
    final ui.Image image = (await tester.runAsync(
        () => (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 2)))!;
    try {
      await expectLater(image, matchesGoldenFile('goldens/about_tour/$name.png'));
    } finally {
      debugDisableShadows = true; // the framework checks it is back before the test ends
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  Widget tour(ReaderController r, {bool replay = true}) =>
      TourScreen(content: r.content, library: r.library, prefs: r.store!.prefs, replay: replay);

  Future<void> tap(WidgetTester tester, String label, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.text(label));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Widget about(ReaderController r) => AboutScreen(
        reader: r,
        links: AppLinks(
          supportEmail: 'taysir@example.org',
          listing: Uri.https('play.google.com', '/store/apps/details', {'id': kAndroidPackage}),
          storeName: 'Google Play',
        ),
      );

  for (final (theme, tz) in [('paper', TzTheme.paper), ('night', TzTheme.dark)]) {
    testWidgets('about-$theme', (tester) => shoot(tester, 'about-$theme', tz, about));
    testWidgets(
        'about-end-$theme',
        (tester) => shoot(tester, 'about-end-$theme', tz, about, then: (tester) async {
              await tester.drag(find.byType(ListView), const Offset(0, -2000));
              await tester.pump(const Duration(milliseconds: 100));
            }));
    for (var card = 1; card <= 3; card++) {
      testWidgets('tour-$card-$theme',
          (tester) => shoot(tester, 'tour-$card-$theme', tz, tour, then: (tester) => tap(tester, 'التالي', times: card - 1)));
    }
    // The first run's last step, with no recording on the device yet.
    testWidgets('tour-reciter-$theme',
        (tester) => shoot(tester, 'tour-reciter-$theme', tz, (r) => tour(r, replay: false), then: (tester) => tap(tester, 'تخطَّ')));
  }
}
