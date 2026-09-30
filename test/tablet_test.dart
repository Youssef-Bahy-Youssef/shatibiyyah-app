// Tablets (plan P8, commentary-split-screen): from 600 dp «الشرح» opens the panel
// beside the page, which follows the playing or selected verse unless the student
// is scrolling in it or turned following off; the divider moves between 30 % and
// 70 % and is kept per orientation. «قارن الشروح»: columns when wide, pages when not.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/data/settings_store.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/commentary/commentary_screen.dart';
import 'package:shatibiyyah/ui/commentary/compare_screen.dart';
import 'package:shatibiyyah/ui/design/taysir_colors.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/reader/reader_screen.dart';
import 'package:shatibiyyah/ui/reader/split_panel.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:shatibiyyah/utils/arabic.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('tablet_test');
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

  Future<ReaderController> reader(WidgetTester tester, {int verse = 226}) async {
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
        store: SettingsStore(prefs),
        initialVerse: verse,
      );
    });
    return r;
  }

  Future<void> show(WidgetTester tester, Widget home, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [TaysirColors.dark]),
        home: home,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Lets the real database reads started in the fake zone finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }

  /// The first verse of the Al-Wafi passage that explains [verse] (what the panel's header shows).
  Future<int> passageStart(WidgetTester tester, int verse) async {
    final blocks = await tester.runAsync(() => content.books.blocksForVerse(content.books.defaultBook.id, verse));
    return blocks!.first.fromVerse!;
  }

  const landscape = Size(1024, 768);

  testWidgets('tablet: «الشرح» opens the panel beside the page; Back closes it', (tester) async {
    final r = await reader(tester);
    await show(tester, ReaderScreen(reader: r), landscape);
    r.openMenu(226);
    await tester.pump();
    await tester.tap(find.text('الشرح'));
    await settle(tester);
    expect(find.byType(SplitPanel), findsOneWidget);
    expect(find.byType(CommentaryScreen), findsNothing); // not a new screen
    expect(find.text('شرح البيت ${ar(await passageStart(tester, 226))}'), findsOneWidget);
    // The page stays on the right (the start side), the panel on the left.
    expect(tester.getCenter(find.byType(PageViewer)).dx, greaterThan(tester.getCenter(find.byType(SplitPanel)).dx));

    final pop = await tester.binding.handlePopRoute();
    await tester.pump();
    expect(pop, isTrue);
    expect(r.splitOpen, isFalse);
    expect(find.byType(SplitPanel), findsNothing);
    await unmount(tester);
  });

  testWidgets('phone: «الشرح» still opens the commentary screen', (tester) async {
    final r = await reader(tester);
    await show(tester, ReaderScreen(reader: r), const Size(390, 844));
    r.openMenu(226);
    await tester.pump();
    await tester.tap(find.text('الشرح'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CommentaryScreen), findsOneWidget);
    expect(r.splitOpen, isFalse);
    await unmount(tester);
  });

  testWidgets('the panel follows the verse, holds while the student scrolls, and stops when told', (tester) async {
    final r = await reader(tester);
    await show(tester, ReaderScreen(reader: r), landscape);
    r.openSplit(226);
    await settle(tester);
    expect(r.splitFollow, isTrue);

    final far = await passageStart(tester, 300);
    r.tapVerse(300); // what playback or a tap does to the reader's verse
    await settle(tester);
    expect(find.text('شرح البيت ${ar(far)}'), findsOneWidget);

    // Scrolling in the panel holds the next move until the student has stopped for a while.
    await tester.drag(find.byType(ListView).last, const Offset(0, -200));
    await tester.pump();
    final other = await passageStart(tester, 400);
    r.tapVerse(400);
    await settle(tester);
    expect(find.text('شرح البيت ${ar(far)}'), findsOneWidget);
    await tester.pump(kHoldAfterScroll);
    await settle(tester);
    await settle(tester); // the passage is read from the database after the hold
    expect(find.text('شرح البيت ${ar(other)}'), findsOneWidget);

    // «يتبع التلاوة» off: the reader moves on, the panel stays.
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(r.splitFollow, isFalse);
    r.tapVerse(500);
    await settle(tester);
    expect(find.text('شرح البيت ${ar(other)}'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('another verse than the reader\'s, or «التالي» in the panel, pins it', (tester) async {
    final r = await reader(tester);
    await show(tester, ReaderScreen(reader: r), landscape);
    r.openSplit(250);
    await settle(tester);
    expect(r.splitFollow, isFalse); // opened on 250 while the reader is on 226
    expect(r.splitVerse, 250);

    r.setSplitFollow(true);
    await settle(tester);
    final list = find.byType(ListView).last;
    await tester.scrollUntilVisible(
      find.text('التالي'),
      400,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    await tester.tap(find.text('التالي'));
    await settle(tester);
    expect(r.splitFollow, isFalse);
    expect(r.splitVerse, greaterThan(226));
    await unmount(tester);
  });

  testWidgets('the divider moves the page\'s share between 30 % and 70 %, kept per orientation', (tester) async {
    final r = await reader(tester);
    await show(tester, ReaderScreen(reader: r), landscape);
    r.openSplit(226);
    await settle(tester);
    final divider = find.byType(SplitDivider);
    final before = tester.getSize(find.byType(PageViewer)).width;
    await tester.drag(divider, const Offset(-100, 0)); // towards the panel: the page widens
    await tester.pump();
    expect(tester.getSize(find.byType(PageViewer)).width, greaterThan(before));
    final kept = r.store!.splitFraction(landscape: true);
    expect(kept, greaterThan(kSplitDefault));
    expect(r.store!.splitFraction(landscape: false), kSplitDefault); // the other orientation untouched

    await tester.drag(divider, const Offset(-2000, 0));
    await tester.pump();
    expect(r.store!.splitFraction(landscape: true), kSplitMax);

    await tester.tap(find.byTooltip('إغلاق التقسيم'));
    await tester.pump();
    expect(r.splitOpen, isFalse);
    await unmount(tester);
  });

  testWidgets('«قارن الشروح»: three columns on a wide screen, with the sync switch', (tester) async {
    await show(tester, CompareScreen(content: content, verse: 226), const Size(1366, 1024));
    await settle(tester);
    for (final b in content.books.books) {
      expect(find.text(b.title), findsOneWidget);
    }
    expect(find.text('مزامنة التمرير'), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    await unmount(tester);
  });

  testWidgets('«قارن الشروح» on a narrow screen: the books are pages on the same verse', (tester) async {
    await show(tester, CompareScreen(content: content, verse: 226), const Size(390, 844));
    await settle(tester);
    expect(find.byType(PageView), findsOneWidget);
    expect(find.text(content.books.books.first.title), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(content.books.books[1].shortTitle));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text(content.books.books[1].title), findsOneWidget);
    expect(find.text('مزامنة التمرير'), findsNothing);
    await unmount(tester);
  });

  testWidgets('the panel\'s «قارن الشروح» opens the comparison on its verse', (tester) async {
    final r = await reader(tester);
    await show(tester, ReaderScreen(reader: r), landscape);
    r.openSplit(226);
    await settle(tester);
    await tester.tap(find.byTooltip('قارن الشروح'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.byType(CompareScreen), findsOneWidget);
    await unmount(tester);
  });
}
