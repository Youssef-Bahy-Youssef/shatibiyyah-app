// The handoff's states as goldens (plan 3.14): each state of
// design/redesign/handoff/screens/, paper and night, on the prototype's phone
// (390×844 dp) at 2×, under the same name, so each can sit beside its render.
// The status bar and the home indicator are phone chrome and are not drawn.
// An item adds its states here when it lands; tool/handoff_compare.py pairs them.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';

import '../test/handoff/fixtures.dart';
import 'golden_fonts.dart';

/// A state of the handoff: whether a recording is on the device, and what to do
/// to the reader before the shot.
typedef _State = ({bool audio, Future<void> Function(WidgetTester, ReaderController, HandoffContent) setup});

final Map<String, _State> _states = {
  'reader-playing': (audio: true, setup: (tester, r, _) => tester.runAsync(() => r.playScope(const PlaybackScope(226, 234)))),
  'reader-none': (audio: false, setup: (_, _, _) async {}),
  'verse': (audio: true, setup: (_, r, _) async => r.openMenu(229)),
  'heading': (audio: true, setup: (_, r, d) async => r.openHeading(d.content.matn.chapters.indexWhere((c) => c.fromVerse == 226))),
};

void main() {
  final data = HandoffContent();
  final boundary = GlobalKey();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadGoldenFonts();
    await data.open();
  });
  tearDownAll(data.close);

  for (final MapEntry(key: state, value: spec) in _states.entries) {
    for (final (theme, tz) in [('paper', TzTheme.paper), ('night', TzTheme.dark)]) {
      final name = '$state-$theme';
      testWidgets(name, (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
        addTearDown(tester.view.reset);
        // Shadows with their blur, as on a device (flutter_test draws them flat by default).
        debugDisableShadows = false;
        final r = await data.reader(tester, audio: spec.audio);
        await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: tzThemeData(tz),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Directionality(textDirection: TextDirection.rtl, child: child!),
            ),
            home: AppShell(reader: r),
          ),
        ));
        // The scanned page is an asset image: decode it for real, then draw.
        await tester.runAsync(
            () => precacheImage(const AssetImage('assets/pages/page019.webp'), tester.element(find.byType(AppShell))));
        await spec.setup(tester, r, data);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
        // At 2×, as the handoff's images are.
        final ui.Image image = (await tester.runAsync(
            () => (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 2)))!;
        await expectLater(image, matchesGoldenFile('goldens/handoff/$name.png'));
        debugDisableShadows = true;
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      });
    }
  }
}
