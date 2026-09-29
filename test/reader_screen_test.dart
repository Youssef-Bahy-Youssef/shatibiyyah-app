// The v3 reader shell: the page never moves when the chrome toggles; the top bar and
// the player show what the spec says; the verse menu opens from a long-press.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/design/taysir_colors.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/reader/reader_screen.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
        windows: windows,
        viewer: PageViewerController(legacyData(content, windows), prefs),
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
}
