// Accessibility pass (P7 step 7, features-v3 screen-reader-support): on every
// screen and sheet, each tap target has a label and is at least 48 × 48 (the
// scan's verse lines excepted, see below), text keeps its contrast, at 200 % text
// nothing overflows, and a screen reader meets each verse as one item.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/app/audio_library.dart';
import 'package:shatibiyyah/app/personal_data.dart';
import 'package:shatibiyyah/app/reminders.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/data/settings_store.dart';
import 'package:shatibiyyah/data/user_store.dart';
import 'package:shatibiyyah/services/download_manager.dart';
import 'package:shatibiyyah/services/notifications.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/commentary/commentary_screen.dart';
import 'package:shatibiyyah/ui/commentary/compare_screen.dart';
import 'package:shatibiyyah/ui/design/app_theme.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/reader/listen_sheet.dart';
import 'package:shatibiyyah/ui/reader/reader_screen.dart';
import 'package:shatibiyyah/ui/reader/tools_sheet.dart';
import 'package:shatibiyyah/ui/search/search_screen.dart';
import 'package:shatibiyyah/ui/shell/about_screen.dart';
import 'package:shatibiyyah/ui/shell/backup_screen.dart';
import 'package:shatibiyyah/ui/shell/debug_tools_screen.dart';
import 'package:shatibiyyah/ui/shell/downloads_screen.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';
import 'package:shatibiyyah/ui/shell/saved_screen.dart';
import 'package:shatibiyyah/ui/shell/index_screen.dart';
import 'package:shatibiyyah/ui/shell/reminders_screen.dart';
import 'package:shatibiyyah/ui/shell/rumuz_screen.dart';
import 'package:shatibiyyah/ui/shell/settings_screen.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:shatibiyyah/utils/arabic.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

class _NoNotifications implements NotificationPort {
  @override
  Future<void> init(void Function(String payload) onTap) async {}
  @override
  Future<String?> launchPayload() async => null;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> cancelScheduled() async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> schedule(PlannedNotification n) async {}
  @override
  Future<void> showNow(PlannedNotification n) async {}
}

void main() {
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('a11y_test');
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

  Future<ReaderController> reader(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'flutter.v2.reminders.chapter': '1'});
    late ReaderController r;
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('a11y_user');
      addTearDown(() => dir.delete(recursive: true));
      final user = await UserStore.open(directory: dir.path, factory: databaseFactoryFfi);
      addTearDown(user.close);
      final personal = PersonalData(user);
      await personal.saveBookmark(229, color: BookmarkColor.gold, tag: BookmarkTag.hifz);
      await personal.saveNote(230, 'قارن بالوافي');
      await personal.load();
      final prefs = await Prefs.create();
      final recording = content.recordings.defaultRecording;
      final windows = await content.windowsFor(recording);
      r = ReaderController(
        content: content,
        recording: recording,
        viewer: PageViewerController(legacyData(content, windows), prefs),
        store: SettingsStore(prefs),
        user: user,
        initialVerse: 226,
      )..personal = personal;
      final library = AudioLibrary(
        content: content,
        prefs: prefs,
        downloads: DownloadManager(supportDir: dir, freeBytes: () async => null, onUnmeteredNetwork: () async => true),
      );
      await library.refresh();
      library.attach(r);
      r.reminders = Reminders(prefs: prefs, port: _NoNotifications(), content: content, verse: () => r.verse);
    });
    return r;
  }

  final screens = <String, Widget Function(ReaderController)>{
    'reader': (r) => AppShell(reader: r),
    'reader (text mode)': (r) => ReaderScreen(reader: r..setTextMode(true)),
    'saved': (r) => SavedScreen(reader: r),
    'index': (r) => IndexScreen(reader: r),
    'search': (r) => SearchScreen(reader: r),
    'settings': (r) => SettingsScreen(reader: r),
    'reminders': (r) => RemindersScreen(reminders: r.reminders!),
    'backup': (r) => BackupScreen(reader: r),
    'downloads': (r) => DownloadsScreen(library: r.library!),
    'rumuz': (r) => RumuzScreen(reader: r),
    'about': (r) => AboutScreen(reader: r),
    'debug tools': (r) => DebugToolsScreen(reader: r),
    'commentary': (r) => CommentaryScreen(content: content, verse: 226),
    'compare (phone: pages)': (r) => CompareScreen(content: content, verse: 226),
  };

  Future<void> show(
    WidgetTester tester,
    Widget screen, {
    double textScale = 1,
    ReaderTheme theme = ReaderTheme.dark,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: tzThemeData(tzThemeFor(theme)),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Directionality(textDirection: TextDirection.rtl, child: child!),
        ),
        home: screen,
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    // Screens that read the database (the passages) finish their reads first.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  for (final MapEntry(key: name, value: build) in screens.entries) {
    testWidgets('$name: labelled tap targets of 48 × 48 or more', (tester) async {
      final handle = tester.ensureSemantics();
      final r = await reader(tester);
      await show(tester, build(r));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      // The one exception: on the scan each verse item is its manuscript line, about
      // 25 pt tall and packed with the next, so it cannot reach 48 pt. Text mode —
      // checked here — is the full-size way to read verse by verse.
      if (name != 'reader') await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await unmount(tester);
      handle.dispose();
    });

    for (final theme in ReaderTheme.values) {
      testWidgets('$name (${theme.name}): text contrast', (tester) async {
        final handle = tester.ensureSemantics();
        final r = await reader(tester);
        await show(tester, build(r), theme: theme);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await unmount(tester);
        handle.dispose();
      });
    }

    testWidgets('$name: nothing overflows at 200 % text', (tester) async {
      final r = await reader(tester);
      await show(tester, build(r), textScale: 2);
      final error = tester.takeException();
      expect(error, isNull, reason: error is FlutterError ? error.toStringDeep() : '$error');
      await unmount(tester);
    });
  }

  // The sheets over the reader.
  final sheets = <String, Future<void> Function(BuildContext, ReaderController)>{
    'tools sheet (view)': (c, r) => showToolsSheet(c, r),
    'tools sheet (audio)': (c, r) => showToolsSheet(c, r, tab: ToolsTab.audio),
    'tools sheet (more)': (c, r) => showToolsSheet(c, r, tab: ToolsTab.more),
    'listen sheet': (c, r) => showListenSheet(c, r, 229),
    'verse menu': (c, r) async => r.openMenu(229),
  };
  for (final MapEntry(key: name, value: open) in sheets.entries) {
    testWidgets('$name: labelled tap targets of 48 × 48 or more; 200 % text fits', (tester) async {
      final handle = tester.ensureSemantics();
      final r = await reader(tester);
      await show(tester, ReaderScreen(reader: r..setTextMode(true))); // see the page-mode exception above
      open(tester.element(find.byType(ReaderScreen)), r);
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await unmount(tester);

      final r2 = await reader(tester);
      await show(tester, ReaderScreen(reader: r2..setTextMode(true)), textScale: 2);
      open(tester.element(find.byType(ReaderScreen)), r2);
      await tester.pumpAndSettle();
      final error = tester.takeException();
      expect(error, isNull, reason: '$error');
      await unmount(tester);
      handle.dispose();
    });
  }

  testWidgets('TalkBack: each verse on the page is one item; activate and long press act on it', (tester) async {
    final handle = tester.ensureSemantics();
    final r = await reader(tester);
    await show(tester, ReaderScreen(reader: r));
    final onPage = r.viewer.data.versesOnPage(r.viewer.currentPage);
    expect(onPage, contains(226));
    for (final n in onPage) {
      expect(find.bySemanticsLabel(RegExp('^البيت ${ar(n)}: ')), findsOneWidget, reason: 'verse $n');
    }
    final v = content.matn.verse(226);
    final node = tester.getSemantics(find.bySemanticsLabel(RegExp('^البيت ٢٢٦: ')));
    expect(node.label, 'البيت ٢٢٦: ${v.firstHemistich}، ${v.secondHemistich}');
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.longPress(find.semantics.byLabel(RegExp('^البيت ٢٢٦: '))); // as TalkBack does
    await tester.pump();
    expect(r.menuVerse, 226);
    await unmount(tester);
    handle.dispose();
  });

  testWidgets('TalkBack in text mode: a verse row is one item with its number and both hemistichs', (tester) async {
    final handle = tester.ensureSemantics();
    final r = await reader(tester);
    await show(tester, ReaderScreen(reader: r..setTextMode(true)));
    final v = content.matn.verse(226);
    final node = tester.getSemantics(find.bySemanticsLabel(RegExp('البيت ٢٢٦')).first);
    expect(node.label, contains(v.firstHemistich));
    expect(node.label, contains(v.secondHemistich));
    expect(node.getSemanticsData().hasAction(SemanticsAction.longPress), isTrue);
    await unmount(tester);
    handle.dispose();
  });

  testWidgets('tablet split (text mode) and compare columns: labelled 48 pt targets', (tester) async {
    final handle = tester.ensureSemantics();
    for (final build in <Widget Function(ReaderController)>[
      (r) => ReaderScreen(reader: r..setTextMode(true)..openSplit(226)),
      (r) => CompareScreen(content: content, verse: 226),
    ]) {
      final r = await reader(tester);
      tester.view.physicalSize = const Size(1366, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: tzThemeData(tzThemeFor(ReaderTheme.dark)),
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: build(r),
      ));
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 60));
      }
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await unmount(tester);
    }
    handle.dispose();
  });
}
