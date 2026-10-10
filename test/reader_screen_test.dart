// The reader: the page sits between the top bar and the dock, which always show; the top bar shows what
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
import 'package:shatibiyyah/ui/design/components/chapter_head.dart';
import 'package:shatibiyyah/ui/design/components/chapter_row.dart';
import 'package:shatibiyyah/ui/design/components/verse_unit.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/reader/listen_sheet.dart';
import 'package:shatibiyyah/ui/reader/reader_screen.dart';
import 'package:shatibiyyah/ui/shell/about_screen.dart';
import 'package:shatibiyyah/ui/shell/index_screen.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';
import 'package:shatibiyyah/ui/design/components/anchored_popover.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';

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

  testWidgets('the page rect is the spec example; a tap on the page moves nothing and hides nothing', (tester) async {
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

    final bar = find.text('نقل حركة الهمزة إلى الساكن قبلها');
    final barRect = tester.getRect(bar);
    await tester.tapAt(page.topLeft + const Offset(3, 3)); // the page's margin
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getRect(find.byType(PageViewer)), page);
    expect(bar.hitTestable(), findsOneWidget);
    expect(tester.getRect(bar), barRect);
    await unmount(tester);
  });

  testWidgets('top bar: the chapter in short, the gilt folio «ص ١٩» and «القسم · الباب N من ٧٨»', (tester) async {
    final r = await reader(tester);
    await show(tester, r);
    // In short form: no «باب», no tashkeel; the full title is printed on the page below.
    expect(find.text('نقل حركة الهمزة إلى الساكن قبلها'), findsOneWidget);
    expect(find.text('ص ١٩'), findsOneWidget);
    expect(find.text('الأصول · الباب ١١ من ${ar(content.matn.chapters.length)}'), findsOneWidget);
    expect(tester.widget<Text>(find.text('ص ١٩')).style!.color, TzColors.night.gilt); // gilt at night; ink on paper (ADR 0019)
    expect(find.byTooltip('بحث'), findsOneWidget);
    expect(find.byTooltip('العرض'), findsOneWidget);
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
    r.tapPage(); // a tap on the page while the menu is open closes the menu
    await tester.pump();
    expect(r.menuVerse, isNull);
    await unmount(tester);
  });

  testWidgets('turning the page by hand updates the top bar: page number and its chapter', (tester) async {
    final r = await reader(tester);
    await show(tester, r);
    r.viewer.setPage(21, true);
    await tester.pump(const Duration(milliseconds: 400));
    final first = content.layout.versesOnPage(21).first;
    final ch = content.matn.chapterOfVerse(first);
    expect(find.text('ص ٢١'), findsOneWidget);
    expect(find.text('${content.matn.partOf(ch).title} · الباب ${ar(ch.orderIndex)} من ${ar(content.matn.chapters.length)}'),
        findsOneWidget);
    expect(find.text(chapterBarTitle(ch.shortLabel)), findsOneWidget);
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

    Finder unit(int v) => find.byWidgetPredicate((w) => w is VerseUnit && w.number == ar(v));

    testWidgets('shows the poem as verse units in place of the page', (tester) async {
      await textMode(tester);
      final head = tester.widget<ChapterHead>(find.byType(ChapterHead).first);
      expect((head.order, head.title), ('١١', 'بَابُ نَقْلِ حَرَكَةِ الْهَمْزَةِ إِلَى السَّاكِنِ قَبْلَهَا'));
      final first = tester.widget<VerseUnit>(unit(226)), v = content.matn.verse(226);
      expect((first.first, first.second), (v.firstHemistich, v.secondHemistich));
      expect(find.byType(PageViewer), findsNothing); // offstage, still mounted
      expect(find.byType(PageViewer, skipOffstage: false), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a tap moves the reader, a double tap opens the menu at the unit', (tester) async {
      final r = await textMode(tester);
      await tester.tap(unit(227));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));
      expect(r.verse, 227);
      expect(r.menuVerse, isNull);
      await tester.pumpAndSettle(); // the column glides the verse clear of the dock's zone

      await tester.tap(unit(226));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(unit(226));
      await tester.pump();
      expect(r.menuVerse, 226);
      expect(r.verse, 227); // opening the menu does not move the reader
      expect(find.text('البيت ٢٢٦'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('back on the page, a tapped verse is the only one marked: its ring ends and the wash reaches it', (tester) async {
      final r = await reader(tester);
      await show(tester, r);
      final viewer = tester.state(find.byType(PageViewer));
      r.setTextMode(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      r.setTextMode(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.state(find.byType(PageViewer)), same(viewer), reason: 'the page stayed mounted under the text');

      await tester.tapAt(tester.getTopLeft(find.byType(PageViewer)) + r.viewer.viewRectOfVerse(227)!.center);
      await tester.pump();
      expect(r.verse, 227);
      expect(r.viewer.pulse, isNotNull);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(r.viewer.pulse, isNull, reason: 'the tap ring is over after 460 ms');
      expect(r.viewer.prevBox, isNull, reason: 'the wash has left verse 226');
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

  testWidgets('«استمع» asks how far: the verse, the chapter or the poem', (tester) async {
    final r = await reader(tester, audio: true);
    await show(tester, r);
    r.openMenu(229);
    await tester.pump();
    await tester.tap(find.text('استمع'));
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

  group('verse popover (3.5)', () {
    for (final (size, padding) in [(const Size(390, 844), const FakeViewPadding(top: 44, bottom: 34)), (const Size(360, 640), const FakeViewPadding(top: 24, bottom: 16))]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()}: below verse 229 and above verse 234, the arrow at the verse, never over it', (tester) async {
        final r = await reader(tester);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = padding;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(theme: tzThemeData(TzTheme.paper), home: ReaderScreen(reader: r)));
        await tester.pump(const Duration(milliseconds: 300));
        for (final (verse, below) in [(229, true), (234, false)]) {
          r.openMenu(verse);
          await tester.pump(const Duration(milliseconds: 300));
          final anchor = r.viewer.viewRectOfVerse(verse)!.shift(tester.getTopLeft(find.byType(PageViewer)));
          final popover = tester.renderObject<RenderAnchoredPopover>(find.byType(AnchoredPopoverLayout));
          final body = tester.getRect(find.byKey(AnchoredPopover.bodyKey));
          expect(popover.below, below, reason: '$verse');
          expect(popover.arrowCenterX, inInclusiveRange(anchor.left, anchor.right), reason: '$verse');
          expect(body.top, greaterThanOrEqualTo(0), reason: '$verse');
          expect(body.bottom, lessThanOrEqualTo(size.height), reason: '$verse');
          if (size.height >= 844) {
            // The prototype's phone: a clear 12 px gap, never over the verse.
            expect(below ? body.top - anchor.bottom : anchor.top - body.bottom, closeTo(12, 0.5), reason: '$verse');
            expect(body.overlaps(anchor), isFalse, reason: '$verse');
          } else {
            // A small phone: the roomier side, kept on the screen; it may cover the edge of a
            // verse at the page's foot, never more than 16 px of it.
            expect(body.overlaps(anchor.deflate(16)), isFalse, reason: '$verse');
          }
          expect(body.left, closeTo(12, 0.5));
          expect(size.width - body.right, closeTo(12, 0.5));
          r.closeMenu();
          await tester.pump(const Duration(milliseconds: 300));
        }
        await unmount(tester);
      });
    }

    testWidgets('the popover: khatam, «البيت ٢٢٩», where it is, the four tiles with «الشرح» filled, then copy, share, select', (tester) async {
      final r = await reader(tester);
      await show(tester, r);
      r.openMenu(229);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('البيت ٢٢٩'), findsOneWidget);
      expect(find.text('باب نقل حركة الهمزة إلى الساكن قبلها · ص ١٩'), findsOneWidget);
      expect(find.text(content.matn.verse(229).firstHemistich), findsOneWidget);
      expect(find.text(content.matn.verse(229).secondHemistich), findsOneWidget);
      for (final label in ['الشرح', 'استمع', 'المرجع', 'ملاحظة', 'نسخ', 'مشاركة', 'تحديد أبيات']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // RTL: «الشرح» is the first tile, at the start (right); «نسخ» the first of the row below.
      expect(tester.getCenter(find.text('الشرح')).dx, greaterThan(tester.getCenter(find.text('ملاحظة')).dx));
      expect(tester.getCenter(find.text('نسخ')).dx, greaterThan(tester.getCenter(find.text('تحديد أبيات')).dx));
      // Without a recording «استمع» is there but disabled.
      expect(tester.getSemantics(find.text('استمع')), matchesSemantics(label: 'استمع', isButton: true, hasEnabledState: true, isEnabled: false));
      await unmount(tester);
    });
  });

  testWidgets('the playing wash glides from the old verse to the new one in 320 ms', (tester) async {
    final r = await reader(tester);
    await show(tester, r);
    final box226 = r.viewer.activeBox!;
    r.tapVerse(227);
    final t0 = r.viewer.hiliteStart;
    final box227 = r.viewer.activeBox!;
    expect(r.viewer.playingRectAt(t0), box226);
    expect(r.viewer.playingRectAt(t0 + 320), box227);
    final mid = r.viewer.playingRectAt(t0 + 160)!;
    expect(mid.top, greaterThan(box226.top));
    expect(mid.top, lessThan(box227.top));
    await unmount(tester);
  });

  group('selection', () {
    testWidgets('«تحديد أبيات», then a second verse: the header counts, the bar replaces the dock', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      final r = await reader(tester);
      await show(tester, r);
      r.openMenu(226);
      await tester.pump();
      await tester.tap(find.text('تحديد أبيات'));
      await tester.pump();
      expect(r.menuVerse, isNull);
      expect(r.selection, (from: 226, to: 226));
      expect(r.viewer.selection, (from: 226, to: 226));
      expect(find.text('المس البيت الأخير لتحديد نطاق يبدأ من ٢٢٦'), findsOneWidget);
      expect(find.text('بيت واحد محدد'), findsOneWidget);

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
      expect(r.viewer.chapterSel, index); // lit on the page
      // The popover does not repeat the title lit right above it (ADR 0011): the
      // number in a khatam, the ordinal, the size, the range, the page, the first words.
      expect(find.text('الباب الحادي عشر'), findsOneWidget);
      expect(find.text('٩ أبيات · \u2068٢٢٦–٢٣٤\u2069 · ص ١٩'), findsOneWidget);
      expect(find.textContaining('يبدأ بـ'), findsOneWidget);
      expect(find.text(content.matn.verse(226).firstHemistich), findsOneWidget);
      expect(find.text('بَابُ نَقْلِ حَرَكَةِ الْهَمْزَةِ إِلَى السَّاكِنِ قَبْلَهَا'), findsNothing);
      // Anchored to the heading: the arrow at its centre, the body below it.
      final headingRect = r.viewer.viewRectOfChapter(index)!.shift(tester.getTopLeft(find.byType(PageViewer)));
      final popover = tester.renderObject<RenderAnchoredPopover>(find.byType(AnchoredPopoverLayout));
      expect(popover.arrowCenterX, closeTo(headingRect.center.dx, 0.5));
      expect(tester.getRect(find.byKey(AnchoredPopover.bodyKey)).top, closeTo(headingRect.bottom + 12, 0.5));
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
      await tester.enterText(find.byType(TextField), '1160'); // the filter: the chapter holding that verse
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ChapterRow)); // «الخاتمة», the one row left
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
