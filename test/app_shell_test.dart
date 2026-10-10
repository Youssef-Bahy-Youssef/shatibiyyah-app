// Item 3.4 (ADR 0019): the shell. Navigation is the dock's four tabs; the drawer
// and the home screen are gone; the app opens on the reader; a tap on the page
// hides the top bar and the dock, a second tap brings them back; on the other
// tabs the dock always shows.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/domain/playback_engine.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/design/components/dock.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/reader/reader_screen.dart';
import 'package:shatibiyyah/ui/shell/about_screen.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';
import 'package:shatibiyyah/ui/shell/index_screen.dart';
import 'package:shatibiyyah/ui/shell/saved_screen.dart';
import 'package:shatibiyyah/ui/shell/settings_screen.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// An audio port that plays nothing: enough for the reader to offer playback.
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

void main() {
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('app_shell_test');
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

  Future<ReaderController> open(WidgetTester tester, {bool audio = false}) async {
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
            ? PlaybackEngine(_SilentAudio(), PlaybackPlan(windows, const PlaybackScope(226, 234), const PlaybackSettings()))
            : null,
        initialVerse: 226,
      );
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: tzThemeData(TzTheme.paper), home: AppShell(reader: r)));
    await tester.pump(const Duration(milliseconds: 400));
    return r;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  double dockOpacity(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find.byKey(AppShell.dockChromeKey)).opacity;

  testWidgets('opens on the reader; the dock has the four tabs as labelled buttons, «المتن» selected', (tester) async {
    await open(tester);
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.byType(IndexScreen), findsNothing);
    for (final label in ['المتن', 'الفهرس', 'المحفوظ', 'الإعدادات']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(tester.getSemantics(find.text('المتن')),
        matchesSemantics(label: 'المتن', isButton: true, hasSelectedState: true, isSelected: true, hasTapAction: true, hasFocusAction: true, isFocusable: true));
    expect(tester.getSemantics(find.text('الفهرس')),
        matchesSemantics(label: 'الفهرس', isButton: true, hasSelectedState: true, isSelected: false, hasTapAction: true, hasFocusAction: true, isFocusable: true));
    // The dock sits 28 px above the bottom edge under a 34 px home indicator, 10 px from the sides.
    final dock = tester.getRect(find.byKey(Dock.bindingKey));
    expect((dock.left, dock.right, dock.bottom), (10.0, 380.0, 844.0 - 28));
    await unmount(tester);
  });

  testWidgets('each tab shows its screen; «المتن» returns to the reader where it was', (tester) async {
    final r = await open(tester);
    await tester.tap(find.text('الفهرس'));
    await tester.pumpAndSettle();
    expect(find.byType(IndexScreen), findsOneWidget);
    expect(find.byType(ReaderScreen), findsNothing);
    await tester.tap(find.text('المحفوظ'));
    await tester.pumpAndSettle();
    expect(find.byType(SavedScreen), findsOneWidget);
    await tester.tap(find.text('الإعدادات'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.tap(find.text('المتن'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(r.verse, 226);
    await unmount(tester);
  });

  testWidgets('a chapter chosen in the index opens in the reader', (tester) async {
    final r = await open(tester);
    await tester.tap(find.text('الفهرس'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('فرش الحروف'));
    await tester.pumpAndSettle();
    final first = content.matn.chapters.firstWhere((c) => c.partId == content.matn.parts[2].id);
    await tester.tap(find.text(first.shortLabel));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.byType(IndexScreen), findsNothing);
    expect(r.verse, first.fromVerse);
    await unmount(tester);
  });

  testWidgets('a tap on the page hides the top bar and the dock; a second tap shows them', (tester) async {
    final r = await open(tester);
    expect(dockOpacity(tester), 1);
    r.toggleChrome();
    await tester.pump(const Duration(milliseconds: 400));
    expect(r.chromeVisible, isFalse);
    expect(dockOpacity(tester), 0);
    expect(find.text('باب نَقْلِ حَرَكَةِ الْهَمْزَةِ إِلَى السَّاكِنِ قَبْلَهَا').hitTestable(), findsNothing);
    await tester.tap(find.text('الفهرس'), warnIfMissed: false); // hidden: not a target
    await tester.pumpAndSettle();
    expect(find.byType(IndexScreen), findsNothing);
    r.toggleChrome();
    await tester.pump(const Duration(milliseconds: 400));
    expect(r.chromeVisible, isTrue);
    expect(dockOpacity(tester), 1);
    await unmount(tester);
  });

  testWidgets('the dock always shows on the other tabs, and coming back to the reader shows its chrome', (tester) async {
    final r = await open(tester);
    r.toggleChrome();
    await tester.pump(const Duration(milliseconds: 400));
    expect(dockOpacity(tester), 0);
    tester.state<AppShellState>(find.byType(AppShell)).select(DockTab.contents);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(IndexScreen), findsOneWidget);
    expect(dockOpacity(tester), 1);
    await tester.tap(find.text('المتن'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(r.chromeVisible, isTrue);
    expect(dockOpacity(tester), 1);
    await unmount(tester);
  });

  testWidgets('without a recording the dock offers «تنزيل»; with one it names the verse and plays', (tester) async {
    await open(tester);
    expect(find.text('استمع إلى المتن'), findsOneWidget);
    expect(find.text('تنزيل'), findsOneWidget);
    await unmount(tester);

    final r = await open(tester, audio: true);
    expect(find.textContaining('البيت ٢٢٦', findRichText: true), findsOneWidget);
    expect(find.textContaining('١ من ٩', findRichText: true), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('تشغيل'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(r.playing, isTrue);
    expect(find.bySemanticsLabel('إيقاف مؤقت'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('settings: «التنبيهات» without its service opens «قريبًا»; «حول» shows the version', (tester) async {
    await open(tester);
    await tester.tap(find.text('الإعدادات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('التنبيهات'));
    await tester.pumpAndSettle();
    expect(find.text('قريبًا في تحديث قادم'), findsOneWidget);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.tap(find.text('حول التطبيق'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text(versionLabel(kAppVersion)), findsOneWidget);
    await unmount(tester);
  });
}
