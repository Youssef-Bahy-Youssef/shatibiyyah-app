// The reader: the page never moves when the chrome toggles; the top bar shows what
// the spec says; the verse menu opens from a long-press. The dock is the shell's
// (app_shell_test.dart).
import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/domain/playback_engine.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/models/chapter.dart';
import 'package:shatibiyyah/models/verse.dart';
import 'package:shatibiyyah/services/data_service.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/utils/arabic.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/reader/listen_sheet.dart';
import 'package:shatibiyyah/ui/reader/reader_screen.dart';
import 'package:shatibiyyah/ui/shell/about_screen.dart';
import 'package:shatibiyyah/ui/shell/index_screen.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

/// An audio port that plays nothing: enough for the reader to offer playback.
class SilentAudio implements AudioPort {
  bool _playing = false;
  @override
  Stream<int> get positionMs => const Stream.empty();
  @override
  int get currentPositionMs => 0;
  @override
  bool get playing => _playing;
  @override
  Stream<bool> get playingChanges => const Stream.empty();
  @override
  Future<void> seek(int ms) async {}
  @override
  Future<void> play() async => _playing = true;
  @override
  Future<void> pause() async => _playing = false;
  @override
  Future<void> setSpeed(double speed) async {}
}

void main() {
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('reader_screen_test');
    content = await AppContent.open(
      loadAsset: (key) async => ByteData.sublistView(await File(key).readAsBytes()),
      supportDir: support,
      factory: databaseFactoryFfi,
    );
  });

  tearDownAll(() async {
    await content.store.close();
    await support.delete(recursive: true);
  });

  Future<ReaderController> reader(WidgetTester tester, {int verse = 226, bool audio = false}) async {
    SharedPreferences.setMockInitialValues({});
    late ReaderController r;
    await tester.runAsync(() async {
      final prefs = await Prefs.create();
      final recording = content.recordings.defaultRecording;
      final windows = await content.windowsFor(recording);
      r = ReaderController(
        content: content,
        recording: recording,
        viewer: PageViewerController(legacyData(content, windows), prefs),
        engine: audio
            ? PlaybackEngine(SilentAudio(), PlaybackPlan(windows, PlaybackScope(verse, verse), const PlaybackSettings()))
            : null,
        initialVerse: verse,
      );
    });
    return r;
  }

  Future<void> show(WidgetTester tester, ReaderController r) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 40, bottom: 20);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: tzThemeData(TzTheme.dark),
      home: ReaderScreen(reader: r),
    ));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('the page rect is the spec example and never moves when the chrome toggles', (tester) async {
    final r = await reader(tester);
    await show(tester, r);
    // The stack holding the page and chrome must fill the screen: at 0×0 its clip hid
    // everything on a device while every rect below still measured right.
    final stack = find
        .ancestor(
          of: find.byType(PageViewer),
          matching: find.descendant(of: find.byType(ReaderScreen), matching: find.byType(Stack)),
        )
        .last;
    expect(tester.getSize(stack), const Size(390, 844));
    final page = tester.getRect(find.byType(PageViewer));
    expect(page.left, closeTo(8, 0.5));
    expect(page.top, closeTo(104.9, 0.5)); // under a 56 px bar at 40; 156 px kept for the dock
    expect(page.width, closeTo(374, 0.5));
    expect(page.height, closeTo(574.2, 0.5));

    r.toggleChrome(); // hide
    await tester.pump(const Duration(milliseconds: 300));
    expect(r.chromeVisible, isFalse);
    expect(tester.getRect(find.byType(PageViewer)), page);
    expect(find.text('١٩'), findsOneWidget); // the faint page number while hidden

    r.toggleChrome(); // show
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getRect(find.byType(PageViewer)), page);
    await unmount(tester);
  });

  testWidgets('top bar: short label and «القسم · ص N من ٩٤»', (tester) async {
    final r = await reader(tester);
    await show(tester, r);
    expect(find.text('باب نَقْلِ حَرَكَةِ الْهَمْزَةِ إِلَى السَّاكِنِ قَبْلَهَا'), findsOneWidget);
    expect(find.text('الأصول · ص ١٩ من ٩٤'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a verse tap moves the reader; a long-press opens the menu over the page', (tester) async {
    final r = await reader(tester);
    await show(tester, r);
    r.tapVerse(229);
    await tester.pump();
    expect(r.verse, 229);
    r.openMenu(229);
    await tester.pump();
    expect(find.text('البيت ٢٢٩'), findsOneWidget);
    expect(find.text('الشرح'), findsOneWidget);
    r.toggleChrome(); // a tap on the page while the menu is open closes the menu
    await tester.pump();
    expect(r.menuVerse, isNull);
    expect(r.chromeVisible, isTrue);
    await unmount(tester);
  });

  testWidgets('turning the page by hand updates the top bar: page number and its chapter', (tester) async {
    final r = await reader(tester);
    await show(tester, r);
    r.viewer.setPage(21, true);
    await tester.pump(const Duration(milliseconds: 400));
    final first = content.layout.versesOnPage(21).first;
    expect(find.text('الأصول · ص ٢١ من ٩٤'), findsOneWidget);
    expect(find.text(content.matn.chapterOfVerse(first).shortLabel), findsOneWidget);
    expect(r.verse, 226); // browsing does not move the reader
    await unmount(tester);
  });

  group('text mode', () {
    Future<ReaderController> textMode(WidgetTester tester) async {
      final r = await reader(tester);
      await show(tester, r);
      r.setTextMode(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return r;
    }

    String sadr(int v) => content.matn.verse(v).firstHemistich;

    testWidgets('shows the chapter as rows in place of the page; the chrome stays', (tester) async {
      final r = await textMode(tester);
      expect(find.text('الباب ١١، ٩ أبيات'), findsOneWidget);
      expect(find.text('بَابُ نَقْلِ حَرَكَةِ الْهَمْزَةِ إِلَى السَّاكِنِ قَبْلَهَا'), findsOneWidget);
      expect(find.text(sadr(226)), findsOneWidget);
      expect(find.text(content.matn.verse(226).secondHemistich), findsOneWidget);
      expect(find.byType(PageViewer), findsNothing); // offstage, still mounted
      expect(find.byType(PageViewer, skipOffstage: false), findsOneWidget);
      r.toggleChrome();
      await tester.pump();
      expect(r.chromeVisible, isTrue);
      await unmount(tester);
    });

    testWidgets('a tap moves the reader, a double tap opens the menu at the row', (tester) async {
      final r = await textMode(tester);
      await tester.ensureVisible(find.text(sadr(229)));
      await tester.pump();
      await tester.tap(find.text(sadr(229)));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));
      expect(r.verse, 229);
      expect(r.menuVerse, isNull);

      await tester.ensureVisible(find.text(sadr(230)));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(sadr(230)));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text(sadr(230)));
      await tester.pump();
      expect(r.menuVerse, 230);
      expect(r.verse, 229); // opening the menu does not move the reader
      expect(find.text('البيت ٢٣٠'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('font size steps by a quarter within 0.75×–2×', (tester) async {
      final r = await textMode(tester);
      expect(find.text('١×'), findsOneWidget);
      await tester.tap(find.text('أ+'));
      await tester.pump();
      expect(r.textScale, 1.25);
      expect(find.text('١٫٢٥×'), findsOneWidget);
      r.setTextScale(0.75);
      await tester.pump();
      await tester.tap(find.text('أ−')); // disabled at the minimum
      await tester.pump();
      expect(r.textScale, 0.75);
      await unmount(tester);
    });

    testWidgets('the chapter buttons browse; the reader moving brings the view back', (tester) async {
      final r = await textMode(tester);
      await tester.scrollUntilVisible(find.text('الباب التالي'), 200);
      await tester.tap(find.text('الباب التالي'));
      await tester.pump();
      expect(find.text('الباب ١٢، ٢٠ بيتًا'), findsOneWidget);
      expect(r.verse, 226); // browsing does not move the reader
      r.tapVerse(228);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('الباب ١١، ٩ أبيات'), findsOneWidget);
      await unmount(tester);
    });
  });

  testWidgets('Back closes the verse menu and stays in the reader', (tester) async {
    final r = await reader(tester);
    await show(tester, r);
    r.openMenu(229);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(r.menuVerse, isNull);
    expect(find.byType(ReaderScreen), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('«تشغيل من هنا» asks how far: the verse, the chapter or the poem', (tester) async {
    final r = await reader(tester, audio: true);
    await show(tester, r);
    r.openMenu(229);
    await tester.pump();
    await tester.tap(find.text('تشغيل من هنا'));
    await tester.pumpAndSettle();
    expect(r.menuVerse, isNull);
    expect(find.text('الاستماع إلى؟'), findsOneWidget);
    expect(find.text('البيت ٢٢٩'), findsOneWidget);
    expect(find.text('من ٢٢٩ إلى ٢٣٤'), findsOneWidget);
    expect(find.text('من ٢٢٩ إلى ١١٧٣'), findsOneWidget);

    await tester.tap(find.text('إلى نهاية الباب'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60)); // the playing shamsa never settles
    }
    expect(find.text('الاستماع إلى؟'), findsNothing);
    expect((r.engine!.plan.scope.fromVerse, r.engine!.plan.scope.toVerse), (229, 234));
    expect(r.verse, 229);
    expect(r.engine!.audio.playing, isTrue);

    // On a chapter's last verse «إلى نهاية الباب» would repeat «البيت فقط».
    expect([for (final o in listenOptions(r, 234)) o.title], ['البيت فقط', 'إلى نهاية المتن']);
    await unmount(tester);
  });

  group('selection', () {
    testWidgets('«بداية نطاق», then a second verse: the header counts, the bar replaces the player', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      final r = await reader(tester);
      await show(tester, r);
      r.openMenu(226);
      await tester.pump();
      await tester.tap(find.text('بداية نطاق'));
      await tester.pump();
      expect(r.menuVerse, isNull);
      expect(r.selection, (from: 226, to: 226));
      expect(r.viewer.selection, (from: 226, to: 226));
      expect(find.text('المس البيت الأخير لتحديد نطاق يبدأ من ٢٢٦'), findsOneWidget);
      expect(find.text('بيت واحد محدد'), findsOneWidget);

      r.toggleChrome(); // a tap on the page does not hide the selection's controls
      expect(r.chromeVisible, isTrue);

      r.tapVerse(229); // sets the end; the reader stays where it was
      await tester.pump(const Duration(milliseconds: 300));
      expect(r.selection, (from: 226, to: 229));
      expect(r.verse, 226);
      expect(find.text('٤ أبيات محددة'), findsOneWidget);
      expect(find.text('الأبيات ٢٢٦–٢٢٩ · اضغط بيتًا آخر للتمديد'), findsOneWidget);
      expect(find.textContaining('المس البيت الأخير'), findsNothing);
      expect(find.text('تشغيل'), findsNothing); // no recording: no play action

      await tester.tap(find.text('الباب كاملًا'));
      await tester.pump();
      expect(r.selection, (from: 226, to: 234));
      expect(find.text('٩ أبيات محددة'), findsOneWidget);

      await tester.tap(find.text('نسخ'));
      await tester.pump();
      expect(copied.single, startsWith('الأبيات ٢٢٦–٢٣٤ — '));
      expect(copied.single, contains('\n٢٢٧. ${content.matn.verse(227).firstHemistich}\n'));
      expect(copied.single, endsWith('\n— تيسير الشاطبية'));
      expect(r.selecting, isFalse);
      expect(r.viewer.selection, isNull);
      await unmount(tester);
    });

    testWidgets('Back clears the selection; with a recording, تشغيل plays the run', (tester) async {
      final r = await reader(tester, audio: true);
      await show(tester, r);
      r.startSelection(228);
      r.tapVerse(230);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(r.selecting, isFalse);
      expect(find.byType(ReaderScreen), findsOneWidget);

      r.startSelection(230);
      r.tapVerse(228); // backwards works too
      await tester.pump(const Duration(milliseconds: 300));
      expect(r.selection, (from: 228, to: 230));
      await tester.tap(find.text('تشغيل'));
      await tester.pump(const Duration(milliseconds: 60));
      expect((r.engine!.plan.scope.fromVerse, r.engine!.plan.scope.toVerse), (228, 230));
      expect(r.selecting, isFalse);
      expect(r.verse, 228);
      await unmount(tester);
    });
  });

  test('selectedVersesCount agrees with the number', () {
    expect(
      [for (final n in [1, 2, 3, 11, 100]) selectedVersesCount(n)],
      ['بيت واحد محدد', 'بيتان محددان', '٣ أبيات محددة', '١١ بيتًا محددًا', '١٠٠ بيت محدد'],
    );
  });

  group('chapter heading and notices', () {
    testWidgets('a tap on the heading drawn on the page opens its card; Back closes it', (tester) async {
      final r = await reader(tester);
      await show(tester, r);
      final index = content.matn.chapters.indexWhere((c) => c.fromVerse == 226);
      final box = r.viewer.data.chapterBox(index)!; // on page 19, with verse 226
      final eff = r.viewer.baseScale * r.viewer.zoom;
      final at = tester.getTopLeft(find.byType(PageViewer)) +
          Offset(box.center.dx * eff + r.viewer.tx, box.center.dy * eff + r.viewer.ty);
      await tester.tapAt(at);
      await tester.pump();
      expect(r.headingChapter?.fromVerse, 226);
      expect(r.viewer.chapterSel, index); // outlined on the page
      expect(find.text('بَابُ نَقْلِ حَرَكَةِ الْهَمْزَةِ إِلَى السَّاكِنِ قَبْلَهَا'), findsOneWidget);
      expect(find.text('الباب ١١، الأبيات \u2068٢٢٦–٢٣٤\u2069، ص ١٩'), findsOneWidget);
      expect(find.text('الشرح'), findsOneWidget);
      expect(find.text('تشغيل الباب'), findsNothing); // no recording

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(r.headingChapter, isNull);
      expect(r.viewer.chapterSel, isNull);
      expect(find.byType(ReaderScreen), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('«تشغيل الباب» plays the chapter from its title; crossing into the next chapter says so',
        (tester) async {
      final r = await reader(tester, audio: true);
      await show(tester, r);
      r.openHeading(content.matn.chapters.indexWhere((c) => c.fromVerse == 226));
      await tester.pump();
      await tester.tap(find.text('تشغيل الباب'));
      await tester.pump(const Duration(milliseconds: 60));
      final scope = r.engine!.plan.scope;
      expect((scope.fromVerse, scope.toVerse, scope.fromChapterTitle), (226, 234, true));
      expect(r.headingChapter, isNull);

      r.engine!.plan.scope = const PlaybackScope(226, 254);
      r.engine!.jumpTo(235); // as if playback went on past 234
      await tester.pump();
      expect(r.verse, 235);
      expect(find.text('بدأ باب جديد · ${content.matn.chapterOfVerse(235).title}'), findsOneWidget);
      // The engine's listener was attached inside runAsync (see reader()), so the notice's
      // timer runs on the real clock.
      await tester.runAsync(() => Future<void>.delayed(kNoticeDuration + const Duration(milliseconds: 100)));
      await tester.pump();
      expect(find.textContaining('بدأ باب جديد'), findsNothing);

      r.tapVerse(226); // the student's own jump is not announced
      await tester.pump();
      expect(find.textContaining('بدأ باب جديد'), findsNothing);
      await unmount(tester);
    });
  });

  // Plan 1.5 (ADR 0011, F-03): a verse tap wins over a heading tap, and a chapter
  // with no heading (الخاتمة has none printed) neither breaks the reader nor hides
  // verse 1159, whose line its old rectangle covered.
  group('verse taps and chapters without a heading', () {
    Offset onPage(WidgetTester tester, ReaderController r, Rect box) {
      final eff = r.viewer.baseScale * r.viewer.zoom;
      return tester.getTopLeft(find.byType(PageViewer)) +
          Offset(box.center.dx * eff + r.viewer.tx, box.center.dy * eff + r.viewer.ty);
    }

    Rect verseBox(ReaderController r, int verse) {
      final b = r.viewer.data.getBox(verse)!;
      return Rect.fromLTWH(b.x, b.y, b.w, b.h);
    }

    testWidgets('tap on verse 1159 opens the verse menu', (tester) async {
      final r = await reader(tester, verse: 1159);
      await show(tester, r);
      expect(r.viewer.currentPage, 93);
      await tester.tapAt(onPage(tester, r, verseBox(r, 1159)));
      await tester.pump(const Duration(milliseconds: 400)); // past the double-tap window
      expect(r.headingChapter, isNull); // not the الخاتمة card
      expect(r.verse, 1159);
      r.openMenu(1159);
      await tester.pump();
      expect(find.text('البيت ١١٥٩'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('الخاتمة from the index opens page 93 with no outline', (tester) async {
      late ReaderController r;
      await tester.runAsync(() async {
        // The snapshot as item 1.4 will make it: الخاتمة has no heading row.
        final dir = await Directory.systemTemp.createTemp('no_heading');
        addTearDown(() => dir.delete(recursive: true));
        final copy = await File('assets/content/content.sqlite').copy('${dir.path}/content.sqlite');
        final db = await databaseFactoryFfi.openDatabase(copy.path);
        await db.rawDelete("DELETE FROM chapter_header_regions WHERE chapter_id = 'chapter:shatibiyyah:077'");
        await db.close(); // no VACUUM: the size stays what content.json says
        final stripped = await AppContent.open(
          loadAsset: (key) async =>
              ByteData.sublistView(await File(key.endsWith('.sqlite') ? copy.path : key).readAsBytes()),
          supportDir: await Directory('${dir.path}/support').create(),
          factory: databaseFactoryFfi,
        );
        addTearDown(stripped.store.close);
        expect(stripped.layout.headerRegion('chapter:shatibiyyah:077'), isNull);
        SharedPreferences.setMockInitialValues({});
        final prefs = await Prefs.create();
        final windows = await stripped.windowsFor(stripped.recordings.defaultRecording);
        r = ReaderController(
          content: stripped,
          recording: stripped.recordings.defaultRecording,
          viewer: PageViewerController(legacyData(stripped, windows), prefs),
          initialVerse: 226,
        );
      });
      await show(tester, r);
      // The index as its own route (the dock's tab is app_shell_test's).
      Navigator.of(tester.element(find.byType(ReaderScreen)))
          .push(MaterialPageRoute<void>(builder: (_) => IndexScreen(reader: r)));
      await tester.pumpAndSettle();
      final chips = find.byWidgetPredicate((w) => w is Scrollable && axisDirectionToAxis(w.axisDirection) == Axis.horizontal);
      await tester.scrollUntilVisible(find.text('الخاتمة'), 200, scrollable: chips.first);
      await tester.tap(find.text('الخاتمة').first); // the part chip
      await tester.pumpAndSettle();
      await tester.tap(find.text('الخاتمة').last); // its one chapter
      await tester.pumpAndSettle();
      expect(find.byType(IndexScreen), findsNothing);
      expect(r.verse, 1160);
      expect(r.viewer.currentPage, 93);
      final khatima = r.viewer.data.chapters.length - 1;
      expect(r.viewer.data.chapterBox(khatima), isNull);
      expect(r.viewer.data.chaptersOnPage(93), isNot(contains(khatima))); // nothing to outline
      expect(r.viewer.chapterSel, isNull);

      await tester.tapAt(onPage(tester, r, verseBox(r, 1159)));
      await tester.pump(const Duration(milliseconds: 400));
      expect((r.verse, r.headingChapter), (1159, null));
      await unmount(tester);
    });

    test('a chapter is placed by its heading\'s page, not its first verse\'s', () {
      Verse v(int id, int page) => Verse(id: id, page: page, x: 0, y: 100.0 * id, width: 900, height: 70);
      final data = ShatibiyyahData([v(1, 1), v(2, 2), v(3, 2)], [null, null, null, null], const [
        Chapter(name: 'أ', startVerse: 1, endVerse: 1, verseCount: 1, startTime: null,
            page: 1, x: 0, y: 0, width: 900, height: 80),
        // Its heading is printed at the foot of page 1; its first verse opens page 2.
        Chapter(name: 'ب', startVerse: 2, endVerse: 3, verseCount: 2, startTime: null,
            page: 1, x: 0, y: 1600, width: 900, height: 80),
        Chapter(name: 'ج', startVerse: 3, endVerse: 3, verseCount: 1, startTime: null), // no heading
      ], durationSeconds: 0);
      expect(data.chaptersOnPage(1), [0, 1]);
      expect(data.chaptersOnPage(2), isEmpty);
      expect(data.pageOfChapter(1), 1);
      expect(data.pageOfChapter(2), 2); // no heading: the page of its first verse
    });
  });

  test('the version shown in «حول» is pubspec\'s', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(line.split(':').last.trim().split('+').first, kAppVersion);
    expect(versionLabel('2.0.1'), 'الإصدار ٢٫٠٫١');
  });
}
