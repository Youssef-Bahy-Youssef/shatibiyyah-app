// The v3 reader shell: the page never moves when the chrome toggles; the top bar and
// the player show what the spec says; the verse menu opens from a long-press.
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
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/design/taysir_colors.dart';
import 'package:shatibiyyah/utils/arabic.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/reader/listen_sheet.dart';
import 'package:shatibiyyah/ui/reader/reader_screen.dart';
import 'package:shatibiyyah/ui/shell/about_screen.dart';
import 'package:shatibiyyah/ui/shell/index_screen.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
        windows: windows,
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
      theme: ThemeData(extensions: const [TaysirColors.dark]),
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
    expect(page.top, closeTo(124.9, 0.5));
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

  testWidgets('top bar: short label and «القسم · ص N من ٩٤»; player without a recording', (tester) async {
    final r = await reader(tester);
    await show(tester, r);
    expect(find.text('باب نَقْلِ حَرَكَةِ الْهَمْزَةِ إِلَى السَّاكِنِ قَبْلَهَا'), findsOneWidget);
    expect(find.text('الأصول · ص ١٩ من ٩٤'), findsOneWidget);
    expect(find.text('التلاوة غير منزّلة بعد'), findsOneWidget);
    expect(find.text('المتن والشروح تعمل دون تنزيل'), findsOneWidget);
    expect(find.byTooltip('تشغيل'), findsNothing); // no transport without audio
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

  group('drawer', () {
    testWidgets('☰ opens the seven destinations; the index opens a chapter in the reader', (tester) async {
      final r = await reader(tester);
      await show(tester, r);
      await tester.tap(find.byTooltip('القائمة'));
      await tester.pumpAndSettle();
      for (final label in ['الرئيسية والمكتبة', 'الفهرس', 'التنزيلات', 'التنبيهات', 'الإعدادات', 'رموز القراء', 'حول']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      await tester.tap(find.text('الفهرس'));
      await tester.pumpAndSettle();
      expect(find.byType(IndexScreen), findsOneWidget);
      expect(find.text('الأبيات \u2068٩٥–٤٤٤\u2069، ٢٨ بابًا'), findsOneWidget);
      final list = find.descendant(of: find.byType(IndexScreen), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.text('الحالي'), 300, scrollable: list);
      expect(find.text('الحالي'), findsOneWidget); // verse 226's chapter, in الأصول

      await tester.drag(list, const Offset(0, 5000)); // back to the part chips
      await tester.pumpAndSettle();
      await tester.tap(find.text('فرش الحروف'));
      await tester.pumpAndSettle();
      final first = content.matn.chapters.firstWhere((c) => c.partId == content.matn.parts[2].id);
      await tester.tap(find.text(first.shortLabel));
      await tester.pumpAndSettle();
      expect(find.byType(IndexScreen), findsNothing);
      expect(r.verse, first.fromVerse);
      await unmount(tester);
    });

    testWidgets('a later-phase destination opens «قريبًا»; حول shows the version', (tester) async {
      final r = await reader(tester);
      await show(tester, r);
      await tester.tap(find.byTooltip('القائمة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('الإعدادات'));
      await tester.pumpAndSettle();
      expect(find.text('قريبًا في تحديث قادم'), findsOneWidget);
      await tester.tap(find.byTooltip('رجوع'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('القائمة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('حول'));
      await tester.pumpAndSettle();
      expect(find.byType(AboutScreen), findsOneWidget);
      expect(find.text(versionLabel(kAppVersion)), findsOneWidget);
      await unmount(tester);
    });
  });

  test('the version shown in «حول» is pubspec\'s', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(line.split(':').last.trim().split('+').first, kAppVersion);
    expect(versionLabel('2.0.1'), 'الإصدار ٢٫٠٫١');
  });
}
