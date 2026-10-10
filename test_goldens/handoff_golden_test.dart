// The handoff's states as goldens (plan 3.14): each state of
// design/redesign/handoff/screens/, paper and night, on the prototype's phone
// (390×844 dp) at 2×, under the same name, so each can sit beside its render.
// The status bar and the home indicator are phone chrome and are not drawn.
// An item adds its states here when it lands; tool/handoff_compare.py pairs them.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/data/settings_store.dart';
import 'package:shatibiyyah/services/download_manager.dart';
import 'package:shatibiyyah/ui/design/app_theme.dart';
import 'package:shatibiyyah/ui/design/components/dock.dart';
import 'package:shatibiyyah/ui/design/components/verse_unit.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';
import 'package:shatibiyyah/utils/arabic.dart';

import '../test/handoff/fixtures.dart';
import '../test/handoff/states.dart';
import 'golden_fonts.dart';


/// The night states the handoff shows once per ink (screens/inks/): the page in
/// the ink, the chosen verse's ring, and the picker with that ink chosen.
const List<String> _inkStates = ['reader-playing', 'verse', 'settings-picker'];

void main() {
  final data = HandoffContent();
  final boundary = GlobalKey();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadGoldenFonts();
    await data.open();
  });
  tearDownAll(data.close);

  /// Pumps [state] in [tz] and compares it, at 2× as the handoff's images are, with goldens/handoff/[name].png.
  Future<void> shoot(WidgetTester tester, String name, HandoffState state, TzTheme tz) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.reset);
    // Shadows with their blur, as on a device (flutter_test draws them flat by default).
    debugDisableShadows = false;
    final onSettings = state.tab == DockTab.settings;
    // A download in progress or failed is 42 % in, as the design's sample.
    final total = data.content.recordings.defaultRecording.localBytes;
    final r = await data.reader(tester,
        audio: state.audio,
        library: onSettings || state.audio, // «التلاوة» leads to the reciters
        download: switch (state.download) {
          null => null,
          final phase => DownloadProgress(
              phase, (total * 0.42).ceil(), total, phase == DownloadPhase.failed ? DownloadError.network : null),
        });
    if (tz.night) r.setNightInk(tz.nightInk); // the settings row and the picker name the chosen ink
    addTearDown(() => appNightInk.value = TzNightPage.jade);
    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: tzThemeData(tz),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: Directionality(textDirection: TextDirection.rtl, child: child!),
        ),
        home: AppShell(reader: r, initialTab: state.tab),
      ),
    ));
    await state.setup(tester, r, data);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The scanned page is an asset image (the page itself, and each crop of it at
    // its own size): decode them for real, then draw.
    final shell = tester.element(find.byType(AppShell));
    await tester.runAsync(() async {
      await precacheImage(const AssetImage('assets/pages/page019.webp'), shell);
      for (final e in find.byType(Image, skipOffstage: false).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    final ui.Image image = (await tester.runAsync(
        () => (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 2)))!;
    try {
      await expectLater(image, matchesGoldenFile('goldens/handoff/$name.png'));
    } finally {
      debugDisableShadows = true; // the framework checks it is back before the test ends
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  for (final MapEntry(key: name, value: state) in handoffStates.entries) {
    testWidgets('$name-paper', (tester) => shoot(tester, '$name-paper', state, TzTheme.paper));
    testWidgets('$name-night', (tester) => shoot(tester, '$name-night', state, TzTheme.dark));
  }

  // «أطول الأبيات وأكثرها حركاتٍ متراكبة، بأكبر حجم»: verses 496, 336 and 1056 at 28 px,
  // the column alone (the handoff's image frames it with the reader's bars).
  for (final (theme, tz) in [('paper', TzTheme.paper), ('night', TzTheme.dark)]) {
    testWidgets('textmode-large-$theme', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final matn = data.content.matn;
      await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: tzThemeData(tz),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.fromLTRB(12, 104, 12, 0),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 18, 0, 4),
                    child: Text('أطول الأبيات وأكثرها حركاتٍ متراكبة، بأكبر حجم',
                        textAlign: TextAlign.center, style: TzType.caption.copyWith(color: tz.colors.ink3)),
                  ),
                  for (final n in [496, 336, 1056])
                    VerseUnit(
                        number: ar(n), first: matn.verse(n).firstHemistich, second: matn.verse(n).secondHemistich, fontSize: 28),
                ]),
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      final ui.Image image = (await tester.runAsync(
          () => (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 2)))!;
      await expectLater(image, matchesGoldenFile('goldens/handoff/textmode-large-$theme.png'));
    });
  }

  for (final name in _inkStates) {
    for (final ink in TzNightPage.inks) {
      testWidgets('inks/$name-night-${ink.id}',
          (tester) => shoot(tester, 'inks/$name-night-${ink.id}', handoffStates[name]!, tzThemeFor(ReaderTheme.dark, ink: ink)));
    }
  }
}
