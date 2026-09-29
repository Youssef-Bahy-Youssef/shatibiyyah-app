// «مرجع» and «ملاحظة» from the reader: the verse menu opens the sheets, saving shows
// a notice and lands in user.sqlite, a run of verses is bookmarked from the
// selection bar.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/app/personal_data.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/data/user_store.dart';
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
    support = await Directory.systemTemp.createTemp('study_test');
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

  /// Lets real database work started by a tap finish (it continues in the fake zone).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<(ReaderController, PersonalData)> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    late ReaderController r;
    late PersonalData personal;
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('study_user');
      addTearDown(() => dir.delete(recursive: true));
      final store = await UserStore.open(directory: dir.path, factory: databaseFactoryFfi);
      addTearDown(store.close);
      personal = PersonalData(store);
      await personal.load();
      final prefs = await Prefs.create();
      final recording = content.recordings.defaultRecording;
      final windows = await content.windowsFor(recording);
      r = ReaderController(
        content: content,
        recording: recording,
        viewer: PageViewerController(legacyData(content, windows), prefs),
        initialVerse: 226,
      )..personal = personal;
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [TaysirColors.dark]),
      home: ReaderScreen(reader: r),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    return (r, personal);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('«مرجع»: colour and tag, saved, with a notice; again to change or delete', (tester) async {
    final (r, personal) = await open(tester);
    r.openMenu(229);
    await tester.pump();
    await tester.tap(find.text('مرجع'));
    await tester.pumpAndSettle();
    expect(find.text('المرجع'), findsOneWidget);
    expect(find.text('حذف'), findsNothing); // nothing to delete yet
    await tester.tap(find.bySemanticsLabel('لون').at(4)); // rose
    await tester.tap(find.text('إشكال'));
    await tester.pump();
    await tester.tap(find.text('حفظ المرجع'));
    await settle(tester);
    final b = personal.bookmarkAt(229)!;
    expect((b.color, b.tag), (BookmarkColor.rose, BookmarkTag.ishkal));
    expect(personal.ribbons[229], kBookmarkColors[BookmarkColor.rose]);
    expect(find.text('حُفظ المرجع على البيت ٢٢٩'), findsOneWidget);

    r.openMenu(229);
    await tester.pump();
    await tester.tap(find.text('مرجع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف'));
    await settle(tester);
    expect(personal.bookmarkAt(229), isNull);
    await unmount(tester);
  });

  testWidgets('«ملاحظة»: written, saved, listed', (tester) async {
    final (r, personal) = await open(tester);
    r.openMenu(230);
    await tester.pump();
    await tester.tap(find.text('ملاحظة'));
    await tester.pumpAndSettle();
    expect(find.text('ملاحظة على البيت ٢٣٠'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'قارن بالوافي');
    await tester.tap(find.text('حفظ'));
    await settle(tester);
    expect(personal.noteFor(230)!.body, 'قارن بالوافي');
    expect(find.text('حُفظت الملاحظة'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a run of verses is bookmarked from the selection bar', (tester) async {
    final (r, personal) = await open(tester);
    r.startSelection(226);
    r.tapVerse(230);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('مرجع'));
    await tester.pumpAndSettle();
    expect(find.text('الأبيات \u2068٢٢٦–٢٣٠\u2069، ${content.matn.chapterOfVerse(226).shortLabel}'), findsOneWidget);
    await tester.tap(find.text('حفظ المرجع'));
    await settle(tester);
    expect(personal.bookmarkAt(226, to: 230), isNotNull);
    expect(r.selecting, isFalse);
    await unmount(tester);
  });
}
