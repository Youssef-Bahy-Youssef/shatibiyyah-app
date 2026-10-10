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
import 'package:shatibiyyah/utils/arabic.dart';
import 'package:shatibiyyah/ui/design/taysir_colors.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/reader/reader_screen.dart';
import 'package:shatibiyyah/ui/shell/home_screen.dart';
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
    await tester.tap(find.text('تعديل المرجع'));
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

  testWidgets('home: continue card, then bookmarks and notes, each opening its verse', (tester) async {
    final (r, personal) = await open(tester);
    await tester.runAsync(() async {
      await personal.saveBookmark(229, color: BookmarkColor.green, tag: BookmarkTag.muraja);
      await personal.saveNote(230, 'قارن بالوافي');
    });
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [TaysirColors.dark]),
      home: Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => HomeScreen(reader: r))),
    ));
    await tester.pump();
    expect(find.text('تابع من حيث توقفت'), findsOneWidget);
    expect(find.text('البيت ٢٢٦، ص ١٩'), findsOneWidget);
    expect(find.text('المراجع (١)'), findsOneWidget);
    expect(find.text('الملاحظات (١)'), findsOneWidget);
    expect(find.text('مراجعة'), findsOneWidget); // the tag

    await tester.tap(find.text('الملاحظات (١)'));
    await tester.pump();
    expect(find.text('قارن بالوافي'), findsOneWidget);

    expect(find.text('السجل'), findsNothing); // the history tab is gone (ADR 0008)

    await tester.tap(find.text('المراجع (١)'));
    await tester.pump();
    await tester.tap(find.text('البيت ٢٢٩'));
    await tester.pump();
    expect(r.verse, 229);
    await unmount(tester);
  });

  // ── deleting bookmarks (plan 1.3, ADR 0009 rules 1–3, F-50/F-51) ──

  Future<Bookmark> rangeBookmark(WidgetTester tester, PersonalData personal) async {
    await tester.runAsync(() => personal.saveBookmark(226, to: 234, color: BookmarkColor.blue, tag: BookmarkTag.muraja));
    await tester.pump();
    return personal.bookmarks.single;
  }

  testWidgets('range bookmark deleted from its middle verse', (tester) async {
    final (r, personal) = await open(tester);
    await rangeBookmark(tester, personal);
    r.openMenu(230);
    await tester.pump();
    await tester.tap(find.text('تعديل المرجع'));
    await tester.pumpAndSettle();
    expect(find.text('الأبيات \u2068٢٢٦–٢٣٤\u2069'), findsOneWidget); // the covering bookmark, listed
    await tester.tap(find.text('حذف'));
    await settle(tester);
    expect(personal.bookmarks, isEmpty);
    expect(find.text('أُزيل المرجع'), findsOneWidget);
    expect(find.text('تراجع'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('save on a covered verse edits, count stays 1', (tester) async {
    final (r, personal) = await open(tester);
    final before = await rangeBookmark(tester, personal);
    r.openMenu(230);
    await tester.pump();
    await tester.tap(find.text('تعديل المرجع'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('لون').at(4)); // rose
    await tester.tap(find.text('حفظ المرجع'));
    await settle(tester);
    expect(personal.bookmarks, hasLength(1));
    final after = personal.bookmarks.single;
    expect((after.uuid, after.fromVerse, after.toVerse, after.color, after.tag),
        (before.uuid, 226, 234, BookmarkColor.rose, BookmarkTag.muraja));
    await unmount(tester);
  });

  Future<void> openHome(WidgetTester tester, ReaderController r) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [TaysirColors.dark]),
      home: Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => HomeScreen(reader: r))),
    ));
    await tester.pump();
  }

  testWidgets('swipe-delete then undo restores the same uuid', (tester) async {
    final (r, personal) = await open(tester);
    final before = await rangeBookmark(tester, personal);
    await openHome(tester, r);
    await tester.drag(find.text('الأبيات \u2068٢٢٦–٢٣٤\u2069'), const Offset(500, 0));
    await tester.pumpAndSettle(); // the row slides away, then is dismissed
    await settle(tester);
    expect(personal.bookmarks, isEmpty);
    expect(find.text('لا مراجع بعد'), findsOneWidget);
    expect(find.text('أُزيل المرجع'), findsOneWidget);

    await tester.tap(find.text('تراجع'));
    await settle(tester);
    final back = personal.bookmarks.single;
    expect((back.uuid, back.fromVerse, back.toVerse, back.color, back.tag),
        (before.uuid, 226, 234, BookmarkColor.blue, BookmarkTag.muraja));

    // A long press offers «تعديل» and «حذف»; a tap still opens the verse.
    await tester.longPress(find.text('الأبيات \u2068٢٢٦–٢٣٤\u2069'));
    await tester.pumpAndSettle();
    expect(find.text('تعديل'), findsOneWidget);
    await tester.tap(find.text('حذف'));
    await settle(tester);
    expect(personal.bookmarks, isEmpty);
    expect(find.text('أُزيل المرجع'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6)); // the undo lasts 5 s
    await tester.pumpAndSettle();
    expect(find.text('تراجع'), findsNothing);
    await unmount(tester);
  });

  testWidgets('ribbon disappears after delete', (tester) async {
    final (r, personal) = await open(tester);
    await rangeBookmark(tester, personal);
    expect(personal.ribbons.keys, [226]);
    r.openMenu(232);
    await tester.pump();
    await tester.tap(find.text('تعديل المرجع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف'));
    await settle(tester);
    expect(personal.ribbons, isEmpty);
    r.openMenu(232);
    await tester.pump();
    expect(find.text('مرجع'), findsOneWidget); // nothing covers it any more
    await unmount(tester);
  });

  testWidgets('a failed save keeps the sheet open, the text intact, and says «تعذّر الحفظ» (F-55)', (tester) async {
    final (r, personal) = await open(tester);
    await tester.runAsync(personal.store.close); // every write now throws a DatabaseException

    r.openMenu(230);
    await tester.pump();
    await tester.tap(find.text('ملاحظة'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'قارن بالوافي');
    await tester.tap(find.text('حفظ'));
    await settle(tester);
    expect(find.text('ملاحظة على البيت ٢٣٠'), findsOneWidget); // still open
    expect(find.text('قارن بالوافي'), findsOneWidget);
    expect(find.text('تعذّر الحفظ'), findsOneWidget);
    Navigator.of(tester.element(find.text('ملاحظة على البيت ٢٣٠'))).pop();
    await tester.pumpAndSettle();

    r.openMenu(229);
    await tester.pump();
    await tester.tap(find.text('مرجع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ المرجع'));
    await settle(tester);
    expect(find.text('المرجع'), findsOneWidget); // still open
    expect(find.text('تعذّر الحفظ'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a failed delete keeps the bookmark and the sheet, and says «تعذّر الحفظ» (1.3 with F-55)', (tester) async {
    final (r, personal) = await open(tester);
    final before = await rangeBookmark(tester, personal);
    await tester.runAsync(personal.store.close); // every write now throws a DatabaseException

    r.openMenu(230);
    await tester.pump();
    await tester.tap(find.text('تعديل المرجع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف'));
    await settle(tester);
    expect(find.text('تعذّر الحفظ'), findsOneWidget); // the sheet is still open
    expect(find.text('أُزيل المرجع'), findsNothing);
    expect(personal.bookmarks.single.uuid, before.uuid); // still there, ribbon included
    expect(personal.ribbons.containsKey(226), isTrue); // the ribbon sits on the bookmark's first verse
    await unmount(tester);
  });

  testWidgets('home: empty states say how to add', (tester) async {
    final (r, _) = await open(tester);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [TaysirColors.dark]),
      home: HomeScreen(reader: r),
    ));
    await tester.pump();
    expect(find.text('لا مراجع بعد'), findsOneWidget);
    await tester.tap(find.text('الملاحظات (٠)'));
    await tester.pump();
    expect(find.text('لا ملاحظات بعد'), findsOneWidget);
    await unmount(tester);
  });

  test('minutes and days in Arabic', () {
    expect([for (final n in [1, 2, 3, 12]) minutesCount(n)], ['دقيقة واحدة', 'دقيقتان', '٣ دقائق', '١٢ دقيقة']);
    final now = DateTime(2026, 9, 30, 12);
    expect(dayLabel(DateTime(2026, 9, 30, 9), now: now), 'اليوم');
    expect(dayLabel(DateTime(2026, 9, 29, 23), now: now), 'أمس');
    expect(dayLabel(DateTime(2026, 9, 25), now: now), 'الجمعة');
    expect(dayLabel(DateTime(2026, 9, 1), now: now), '\u2066١/٩\u2069');
    expect(clockTime(DateTime(2026, 9, 30, 9, 5)), '\u2066٩:٠٥\u2069');
  });
}
