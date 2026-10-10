// Settings persistence, PlaybackSettings.copyWith, and the tools sheet.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/data/settings_store.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/design/app_theme.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/reader/tools_sheet.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

void main() {
  sqfliteFfiInit();

  group('SettingsStore', () {
    test('defaults, ∞ repeats and per-reciter speed round-trip', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsStore(await Prefs.create());
      expect((s.verseRepeats, s.sectionRepeats, s.gapMs, s.playTitles, s.themeChoice), (1, 1, 0, true, ThemeChoice.auto));
      s.verseRepeats = null;
      s.sectionRepeats = 5;
      s.setSpeedFor('rec:a', 1.25);
      s.themeChoice = ThemeChoice.paper;
      final again = SettingsStore(s.prefs);
      expect(again.verseRepeats, isNull);
      expect(again.sectionRepeats, 5);
      expect(again.speedFor('rec:a'), 1.25);
      expect(again.speedFor('rec:b'), 1); // another reciter keeps its own
      expect(again.themeChoice, ThemeChoice.paper);
    });

    test('values outside the option sets fall back', () async {
      SharedPreferences.setMockInitialValues({'v2.repeat.verse': '7', 'v2.gap_ms': '5000', 'v2.speed.x': '3'});
      final s = SettingsStore(await Prefs.create());
      expect((s.verseRepeats, s.gapMs, s.speedFor('x')), (1, 0, 1));
    });

    test('every offered value is kept (ADRs 0004, 0005: one to five times or ∞; 0.25× to 2×)', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsStore(await Prefs.create());
      for (final n in kVerseRepeatOptions) {
        s.verseRepeats = n;
        s.sectionRepeats = n;
        expect((SettingsStore(s.prefs).verseRepeats, SettingsStore(s.prefs).sectionRepeats), (n, n));
      }
      for (final v in kSpeedOptions) {
        s.setSpeedFor('x', v);
        expect(SettingsStore(s.prefs).speedFor('x'), v);
      }
    });

    test('cycle wraps', () {
      expect(cycle(kVerseRepeatOptions, 5), null);
      expect(cycle<int?>(kVerseRepeatOptions, null), 1);
    });
  });

  test('copyWith: an explicit null (∞) differs from leaving a field alone', () {
    const s = PlaybackSettings(verseRepeats: 3, sectionRepeats: 2);
    expect(s.copyWith(gapMs: 1000).verseRepeats, 3);
    expect(s.copyWith(verseRepeats: null).verseRepeats, isNull);
    expect(s.copyWith(verseRepeats: null).sectionRepeats, 2);
  });

  group('tools sheet', () {
    late Directory support;
    late AppContent content;
    setUpAll(() async {
      support = await Directory.systemTemp.createTemp('tools_test');
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

    testWidgets('theme switches app-wide; night brightness stops at 40 %', (tester) async {
      SharedPreferences.setMockInitialValues({});
      late ReaderController r;
      await tester.runAsync(() async {
        final prefs = await Prefs.create();
        final rec = content.recordings.defaultRecording;
        final windows = await content.windowsFor(rec);
        r = ReaderController(
          content: content,
          recording: rec,
          viewer: PageViewerController(legacyData(content, windows), prefs),
          store: SettingsStore(prefs),
        );
      });
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(ValueListenableBuilder<ReaderTheme>(
        valueListenable: appTheme,
        builder: (_, theme, _) => MaterialApp(
          theme: tzThemeData(tzThemeFor(theme)),
          home: Scaffold(body: ToolsSheet(reader: r)),
        ),
      ));
      await tester.tap(find.text('ورقية'));
      await tester.pump();
      expect(appTheme.value, ReaderTheme.paper);
      expect(r.store!.themeChoice, ThemeChoice.paper);

      for (var i = 0; i < 8; i++) {
        await tester.tap(find.bySemanticsLabel('أخفت'));
        await tester.pump();
      }
      expect(r.brightness, 40);
      expect(find.text('الصوت'), findsNothing); // the player is its own sheet (item 3.7)
      appTheme.value = ReaderTheme.dark;
    });
  });
}
