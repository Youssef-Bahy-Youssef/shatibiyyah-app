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
import 'package:shatibiyyah/data/user_store.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/services/download_manager.dart';
import 'package:shatibiyyah/ui/design/app_theme.dart';
import 'package:shatibiyyah/ui/design/components/dock.dart';
import 'package:shatibiyyah/ui/design/components/stat_tile.dart';
import 'package:shatibiyyah/ui/design/components/verse_unit.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';
import 'package:shatibiyyah/ui/shell/saved_screen.dart';
import 'package:shatibiyyah/utils/arabic.dart';

import '../test/handoff/fixtures.dart';
import 'golden_fonts.dart';

/// A state of the handoff: the tab it is on, whether a recording is on the device,
/// and what to do before the shot.
typedef _State = ({
  DockTab tab,
  bool audio,
  DownloadPhase? download,
  Future<void> Function(WidgetTester, ReaderController, HandoffContent) setup
});

/// The player open on the section 226–234, set as the design's sample: 1.25×,
/// each verse three times, a 2 s gap. Then [tile]'s picker, if any.
Future<void> _player(WidgetTester tester, ReaderController r, [String? tile]) async {
  r
    ..setSpeed(1.25)
    ..setVerseRepeats(3)
    ..setGap(2000);
  await tester.runAsync(() => r.playScope(const PlaybackScope(226, 234)));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.bySemanticsLabel(RegExp('^فتح المشغّل')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  if (tile == null) return;
  await tester.tap(find.widgetWithText(StatTile, tile));
}

Future<void> _nothing(WidgetTester _, ReaderController _, HandoffContent _) async {}

/// «المحفوظ» as the design draws it: a bookmark on verse 1001 just swiped away
/// (its undo notice showing), and the first row held 100 px aside over «حذف».
Future<void> _savedSwiped(WidgetTester tester, ReaderController r, HandoffContent _) async {
  await tester.runAsync(() => r.personal!.saveBookmark(1001, color: BookmarkColor.values[1], tag: BookmarkTag.muraja));
  await tester.pump();
  await tester.drag(find.text('البيت ١٠٠١'), const Offset(-390, 0));
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 200));
  }
  final gesture = await tester.startGesture(tester.getCenter(find.byType(SavedRow).first));
  addTearDown(gesture.removePointer);
  await gesture.moveBy(const Offset(-30, 0)); // taken as the start of a drag
  await gesture.moveBy(const Offset(-100, 0));
}

final Map<String, _State> _states = {
  'reader-playing': (
    tab: DockTab.matn,
    audio: true,
    download: null,
    setup: (tester, r, _) => tester.runAsync(() => r.playScope(const PlaybackScope(226, 234)))
  ),
  'reader-none': (tab: DockTab.matn, audio: false, download: null, setup: _nothing),
  'reader-downloading': (tab: DockTab.matn, audio: false, download: DownloadPhase.downloading, setup: _nothing),
  'reader-failed': (tab: DockTab.matn, audio: false, download: DownloadPhase.failed, setup: _nothing),
  'verse': (tab: DockTab.matn, audio: true, download: null, setup: (_, r, _) async => r.openMenu(229)),
  'heading': (
    tab: DockTab.matn,
    audio: true,
    download: null,
    setup: (_, r, d) async => r.openHeading(d.content.matn.chapters.indexWhere((c) => c.fromVerse == 226))
  ),
  'player-main': (tab: DockTab.matn, audio: true, download: null, setup: (tester, r, _) => _player(tester, r)),
  'player-repeat': (tab: DockTab.matn, audio: true, download: null, setup: (tester, r, _) => _player(tester, r, 'تكرار البيت')),
  'player-speed': (tab: DockTab.matn, audio: true, download: null, setup: (tester, r, _) => _player(tester, r, 'السرعة')),
  'textmode-reading': (tab: DockTab.matn, audio: true, download: null, setup: (_, r, _) async => r.setTextMode(true)),
  'textmode-playing': (
    tab: DockTab.matn,
    audio: true,
    download: null,
    setup: (tester, r, _) async {
      r.setTextMode(true);
      await tester.runAsync(() => r.playScope(const PlaybackScope(226, 234)));
      await tester.runAsync(() => r.tapVerse(227));
    }
  ),
  'textmode-display': (
    tab: DockTab.matn,
    audio: true,
    download: null,
    setup: (tester, r, _) async {
      r.setTextMode(true);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('العرض'));
    }
  ),
  'index': (
    tab: DockTab.contents,
    audio: true,
    download: null,
    setup: (tester, r, _) => tester.runAsync(() => r.playScope(const PlaybackScope(226, 234)))
  ),
  'saved-bookmarks': (tab: DockTab.saved, audio: false, download: null, setup: _savedSwiped),
  'saved-notes': (tab: DockTab.saved, audio: false, download: null, setup: (tester, _, _) => tester.tap(find.text('الملاحظات ٠'))),
  'settings-main': (tab: DockTab.settings, audio: false, download: null, setup: _nothing),
  'settings-picker': (
    tab: DockTab.settings,
    audio: false,
    download: null,
    setup: (tester, _, _) => tester.tap(find.text(TzNightPage.pickerTitle))
  ),
};

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
  Future<void> shoot(WidgetTester tester, String name, _State state, TzTheme tz) async {
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

  for (final MapEntry(key: name, value: state) in _states.entries) {
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
          (tester) => shoot(tester, 'inks/$name-night-${ink.id}', _states[name]!, tzThemeFor(ReaderTheme.dark, ink: ink)));
    }
  }
}
