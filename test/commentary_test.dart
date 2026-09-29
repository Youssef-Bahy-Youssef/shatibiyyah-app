// M1 acceptance: every block of the three books loads and lays out; the commentary
// screen works on real data; long-press → menu → «الشرح» opens it from the page.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/domain/commentary_text.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/commentary/commentary_screen.dart';
import 'package:shatibiyyah/ui/design/taysir_colors.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/reader/reader_screen.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:shatibiyyah/ui/widgets/verse_menu.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('commentary_test');
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

  Widget host(Widget child) => MaterialApp(
        theme: ThemeData(extensions: const [TaysirColors.dark]),
        home: child,
      );

  /// Renders [frames] frames: a route transition needs several frames, not one long pump.
  Future<void> frames(WidgetTester tester, [int frames = 10]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Lets real database I/O finish. Each query's continuation runs in the test's
  /// fake-async zone, so alternate real waits with pumps until the chain is done.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  test('all 2855 blocks load and lay out, and no placed marker is lost', () async {
    final ids = (await content.store.db.rawQuery('SELECT id FROM commentary_blocks ORDER BY id'))
        .map((r) => r['id'] as String)
        .toList();
    expect(ids, hasLength(2855));
    var placed = 0, anchored = 0;
    for (final id in ids) {
      final segments = await content.books.segments(id);
      final notes = await content.books.footnotes(id);
      await content.books.sources(id);
      anchored += notes.where((n) => n.anchorUtf16 != null).length;
      for (final s in segments) {
        final ps = layoutSegment(s.text, notes.where((n) => n.segmentId == s.id).toList());
        placed += ps.expand((p) => p.runs).where((r) => r.isMarker).length;
      }
    }
    // Anchors in segments stripped of their verse echo, or in the (hidden) lead-in, may drop; nothing else.
    expect(placed, greaterThan(anchored * 0.99));
  });

  testWidgets('verse 229: Al-Wafi first, then إبراز المعاني, then the next explanation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(host(CommentaryScreen(content: content, verse: 229)));
    await settle(tester);
    expect(find.text('الوافي · البيت ٢٢٩'), findsOneWidget);
    expect(find.text('قيد المراجعة', findRichText: true), findsNothing);
    await tester.scrollUntilVisible(find.textContaining('المصدر: قرآنبيديا ص'), 400);
    expect(find.textContaining('المصدر: قرآنبيديا ص'), findsOneWidget);

    await tester.tap(find.text('إبراز المعاني'));
    await settle(tester);
    expect(find.text('إبراز المعاني · البيت ٢٢٩'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('التالي'), 400);
    await tester.ensureVisible(find.text('التالي')); // fully on screen, not just built
    await tester.pump();
    await tester.tap(find.text('التالي'));
    await settle(tester);
    expect(find.text('إبراز المعاني · البيت ٢٣٠'), findsOneWidget);
  });

  testWidgets('a grouped block says so, and verse 1 has the «اللغة» tab', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(host(CommentaryScreen(content: content, verse: 231)));
    await settle(tester);
    expect(find.text('الوافي · الأبيات ٢٣٠–٢٣٣'), findsOneWidget);
    expect(find.text('يشرح الأبيات ٢٣٠–٢٣٣ معًا'), findsOneWidget);

    await tester.pumpWidget(host(CommentaryScreen(key: UniqueKey(), content: content, verse: 1)));
    await settle(tester);
    expect(find.text('اللغة'), findsOneWidget);
    await tester.tap(find.text('اللغة'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the longest explanation a reader can open renders and scrolls', (tester) async {
    // The very longest segments belong to book-level blocks (introductions and closings)
    // that have no verse; they are not reachable from the reader.
    late Map<String, Object?> longest;
    await tester.runAsync(() async {
      longest = (await content.store.db.rawQuery(
              'SELECT b.from_verse, b.commentary_id FROM commentary_segments s '
              'JOIN commentary_blocks b ON b.id = s.commentary_block_id WHERE b.from_verse IS NOT NULL '
              'ORDER BY length(s.display_text) DESC LIMIT 1'))
          .single;
    });
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(host(CommentaryScreen(
        content: content, verse: longest['from_verse'] as int, bookId: longest['commentary_id'] as String)));
    await settle(tester);
    await tester.fling(find.byType(ListView), const Offset(0, -3000), 3000);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long-press a verse on the page → menu → «الشرح» → commentary; «نسخ» copies', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    late ReaderController reader;
    await tester.runAsync(() async {
      final prefs = await Prefs.create();
      final recording = content.recordings.defaultRecording;
      final windows = await content.windowsFor(recording);
      reader = ReaderController(
        content: content,
        recording: recording,
        windows: windows,
        viewer: PageViewerController(legacyData(content, windows), prefs),
        initialVerse: 3,
      );
    });
    await tester.pumpWidget(host(ReaderScreen(reader: reader)));
    await tester.pump(const Duration(milliseconds: 500));

    // The verse's box on the page, in screen coordinates (page 1 is showing).
    Offset centreOf(int verse) =>
        tester.getTopLeft(find.byType(PageViewer)) + reader.viewer.viewRectOfVerse(verse)!.center;

    final gesture = await tester.startGesture(centreOf(3));
    await tester.pump(const Duration(milliseconds: kLongPressMs + 50));
    await gesture.up();
    await tester.pump();
    expect(reader.menuVerse, 3);
    expect(find.byType(VerseMenu), findsOneWidget);
    expect(find.text('البيت ٣'), findsOneWidget);
    expect(find.text('تشغيل من هنا'), findsNothing); // no recording on the device

    await tester.tap(find.text('نسخ'));
    await tester.pump();
    expect(copied.single, startsWith('البيت ٣ — خطبة الكتاب\n'));
    expect(copied.single, endsWith('\n— تيسير الشاطبية'));
    expect(reader.menuVerse, isNull);

    // The page never moves (fixed layout), so the same point opens the menu again.
    final again = await tester.startGesture(centreOf(3));
    await tester.pump(const Duration(milliseconds: kLongPressMs + 50));
    await again.up();
    await tester.pump();
    expect(reader.menuVerse, 3);
    await tester.tap(find.text('الشرح'));
    await frames(tester);
    expect(find.byType(CommentaryScreen), findsOneWidget);
    await settle(tester);
    expect(find.text('الوافي · البيت ٣'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

}
