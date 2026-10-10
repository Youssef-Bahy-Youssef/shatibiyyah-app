// ignore_for_file: invalid_use_of_visible_for_testing_member
// Golden images of the v3 reader in each of its states (P4 acceptance: every reader
// state, both themes, both sizes), rendered with the real fonts, icons and pages.
//
//   flutter test test_goldens                    # compare
//   flutter test test_goldens --update-goldens   # accept the current rendering
//
// Goldens depend on the platform and the Flutter version (text rasterization), so
// they live outside test/ and plain `flutter test` does not run them; these were
// made on macOS with Flutter 3.44. `tool/check.sh --goldens` runs them.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/app/personal_data.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/data/settings_store.dart';
import 'package:shatibiyyah/data/user_store.dart';
import 'package:shatibiyyah/domain/playback_engine.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/design/app_theme.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/commentary/compare_screen.dart';
import 'package:shatibiyyah/ui/reader/reader_screen.dart';
import 'package:shatibiyyah/ui/search/search_screen.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';
import 'package:shatibiyyah/ui/design/components/dock.dart' show DockTab;
import 'package:shatibiyyah/app/reminders.dart';
import 'package:shatibiyyah/services/notifications.dart';
import 'package:shatibiyyah/ui/shell/backup_screen.dart';
import 'package:shatibiyyah/ui/shell/reminders_screen.dart';
import 'package:shatibiyyah/ui/shell/rumuz_screen.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'golden_fonts.dart';

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

class _SilentAudio implements AudioPort {
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

/// A reader state: what to do to a fresh reader (on verse 226, page 19) before the shot.
typedef _Setup = void Function(ReaderController r, AppContent content);

final Map<String, _Setup> _states = {
  'page': (_, _) {},
  'chrome_hidden': (r, _) => r.toggleChrome(),
  'menu': (r, _) => r.openMenu(229),
  'text_mode': (r, _) => r.setTextMode(true),
  'selection': (r, _) {
    r.startSelection(226);
    r.tapVerse(229);
  },
  'heading': (r, c) => r.openHeading(c.matn.chapters.indexWhere((ch) => ch.fromVerse == 226)),
  'playing': (r, _) => r.playScope(const PlaybackScope(226, 234)),
};

void main() {
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadGoldenFonts();
    support = await Directory.systemTemp.createTemp('reader_goldens');
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

  const sizes = {
    '390x844': (Size(390, 844), FakeViewPadding(top: 47, bottom: 34)),
    '360x640': (Size(360, 640), FakeViewPadding(top: 24, bottom: 16)),
  };

  for (final (size, theme) in [('390x844', ReaderTheme.dark), ('390x844', ReaderTheme.paper), ('360x640', ReaderTheme.dark)]) {
    for (final MapEntry(key: state, value: setup) in _states.entries) {
      final name = '${state}_${theme.name}_$size';
      testWidgets(name, (tester) async {
        final (screen, padding) = sizes[size]!;
        tester.view.physicalSize = screen;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = padding;
        addTearDown(tester.view.reset);
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
            engine: state == 'playing'
                ? PlaybackEngine(_SilentAudio(), PlaybackPlan(windows, const PlaybackScope(226, 234), const PlaybackSettings()))
                : null,
            initialVerse: 226,
          );
        });
        r.setTheme(theme);
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: tzThemeData(tzThemeFor(theme)),
          // Reduced motion, as a user can ask for: the playing shamsa stops spinning, so
          // the image does not depend on how far a rotation had got.
          builder: (context, child) =>
              MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
          home: AppShell(reader: r),
        ));
        // The scanned page is an asset image: decode it for real, then draw.
        await tester.runAsync(() => precacheImage(
              const AssetImage('assets/pages/page019.webp'),
              tester.element(find.byType(ReaderScreen)),
            ));
        setup(r, content);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 60)); // chrome fades, text-mode scroll
        }
        await expectLater(find.byType(AppShell), matchesGoldenFile('goldens/$name.png'));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3)); // let notices and animations end
      });
    }
  }

  // «رموز القراء»: the letters tab as it opens, and the words tab.
  for (final theme in [ReaderTheme.dark, ReaderTheme.paper]) {
    for (final tab in [null, 'الكلمات']) {
      final name = 'rumuz_${tab == null ? 'letters' : 'words'}_${theme.name}_390x844';
      testWidgets(name, (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
        addTearDown(tester.view.reset);
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
            initialVerse: 226,
          );
        });
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: tzThemeData(tzThemeFor(theme)),
          builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
          home: RumuzScreen(reader: r),
        ));
        if (tab != null) await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        await expectLater(find.byType(RumuzScreen), matchesGoldenFile('goldens/$name.png'));
      });
    }
  }

  // «البحث»: the empty state with recent queries, and a number's results.
  for (final (state, query) in [('recent', null), ('number', '٢٢٩')]) {
    final name = 'search_${state}_dark_390x844';
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'flutter.v2.search.recent': '["ورش","بدأت","الإمالة"]',
      });
      late ReaderController r;
      await tester.runAsync(() async {
        final prefs = await Prefs.create();
        final recording = content.recordings.defaultRecording;
        final windows = await content.windowsFor(recording);
        r = ReaderController(
          content: content,
          recording: recording,
          viewer: PageViewerController(legacyData(content, windows), prefs),
          initialVerse: 226,
        );
      });
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: tzThemeData(tzThemeFor(ReaderTheme.dark)),
        home: SearchScreen(reader: r),
      ));
      await tester.pump();
      if (query != null) {
        await tester.enterText(find.byType(TextField), query);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 1)); // the cursor settles
      await expectLater(find.byType(SearchScreen), matchesGoldenFile('goldens/$name.png'));
    });
  }

  // «المحفوظ» (the bookmarks tab, then the empty notes tab) and «الفهرس» in the
  // shell, over a user.sqlite with the reference's three bookmarks and no note.
  for (final screen in ['saved_bookmarks', 'saved_notes', 'index']) {
    for (final theme in [ReaderTheme.dark, ReaderTheme.paper]) {
      final name = '${screen}_${theme.name}_390x844';
      testWidgets(name, (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        late ReaderController r;
        late UserStore user;
        await tester.runAsync(() async {
          final dir = await Directory.systemTemp.createTemp('golden_user');
          addTearDown(() => dir.delete(recursive: true));
          user = await UserStore.open(directory: dir.path, factory: databaseFactoryFfi);
          final recording = content.recordings.defaultRecording;
          final personal = PersonalData(user);
          await personal.load();
          await personal.saveBookmark(683, color: BookmarkColor.values[3], tag: BookmarkTag.ishkal);
          await personal.saveBookmark(120, to: 123, color: BookmarkColor.values[2], tag: BookmarkTag.hifz);
          await personal.saveBookmark(229, color: BookmarkColor.values[0], tag: BookmarkTag.muraja);
          final prefs = await Prefs.create();
          final windows = await content.windowsFor(recording);
          r = ReaderController(
            content: content,
            recording: recording,
            viewer: PageViewerController(legacyData(content, windows), prefs),
            user: user,
            initialVerse: 226,
          )..personal = personal;
        });
        addTearDown(() => tester.runAsync(user.close));
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: tzThemeData(tzThemeFor(theme)),
          builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
          home: AppShell(reader: r, initialTab: screen == 'index' ? DockTab.contents : DockTab.saved),
        ));
        await tester.pumpAndSettle();
        if (screen == 'saved_notes') {
          await tester.tap(find.text('الملاحظات ٠'));
          await tester.pumpAndSettle();
        }
        await expectLater(find.byType(AppShell), matchesGoldenFile('goldens/$name.png'));
      });
    }
  }

  // «الإعدادات» and «نسخ احتياطي» (before any backup).
  for (final screen in ['settings', 'backup']) {
    for (final theme in [ReaderTheme.dark, ReaderTheme.paper]) {
      final name = '${screen}_${theme.name}_390x844';
      testWidgets(name, (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        appTheme.value = theme;
        addTearDown(() => appTheme.value = ReaderTheme.dark);
        late ReaderController r;
        await tester.runAsync(() async {
          final prefs = await Prefs.create();
          final recording = content.recordings.defaultRecording;
          final windows = await content.windowsFor(recording);
          r = ReaderController(
            content: content,
            recording: recording,
            viewer: PageViewerController(legacyData(content, windows), prefs),
            initialVerse: 226,
          );
        });
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: tzThemeData(tzThemeFor(theme)),
          home: screen == 'settings' ? AppShell(reader: r, initialTab: DockTab.settings) : BackupScreen(reader: r),
        ));
        await tester.pumpAndSettle();
        await expectLater(find.byType(screen == 'settings' ? AppShell : BackupScreen),
            matchesGoldenFile('goldens/$name.png'));
      });
    }
  }

  // «التنبيهات» with «فائدة اليوم» on (the time row) and a fixed day's preview.
  for (final theme in [ReaderTheme.dark, ReaderTheme.paper]) {
    final name = 'reminders_${theme.name}_390x844';
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({'flutter.v2.reminders.chapter': '1'});
      late Reminders reminders;
      await tester.runAsync(() async {
        reminders = Reminders(
          prefs: await Prefs.create(),
          port: _NoNotifications(),
          content: content,
          verse: () => 226,
          clock: () => DateTime(2026, 9, 30, 8),
        );
      });
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: tzThemeData(tzThemeFor(theme)),
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: RemindersScreen(reminders: reminders),
      ));
      await tester.pumpAndSettle();
      await expectLater(find.byType(RemindersScreen), matchesGoldenFile('goldens/$name.png'));
    });
  }

  // Tablets (plan P8): the reader, the split (page and commentary) and «قارن الشروح»,
  // at 768×1024 and 1024×1366 in both orientations.
  for (final size in const [Size(768, 1024), Size(1024, 768), Size(1024, 1366), Size(1366, 1024)]) {
    for (final state in ['reader', 'split', 'compare']) {
      final name = 'tablet_${state}_${size.width.toInt()}x${size.height.toInt()}';
      testWidgets(name, (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
        addTearDown(tester.view.reset);
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
            initialVerse: 226,
          );
        });
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: tzThemeData(tzThemeFor(ReaderTheme.dark)),
          builder: (context, child) =>
              MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
          home: state == 'compare' ? CompareScreen(content: content, verse: 226) : AppShell(reader: r),
        ));
        if (state != 'compare') {
          await tester.runAsync(() => precacheImage(
                const AssetImage('assets/pages/page019.webp'),
                tester.element(find.byType(ReaderScreen)),
              ));
        }
        if (state == 'split') r.openSplit(226);
        // The passages are read from the database: let the reads finish.
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
          await tester.pump(const Duration(milliseconds: 60));
        }
        await expectLater(
          find.byType(state == 'compare' ? CompareScreen : AppShell),
          matchesGoldenFile('goldens/$name.png'),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 10));
      });
    }
  }
}
