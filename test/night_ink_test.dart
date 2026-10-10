// Item 3.6 (ADR 0020): the night ink is the reader's choice. It is the
// preference v2.night.page_accent, jade by default, jade for an unknown value,
// kept across a restart and carried by a backup. Choosing one applies at once
// and reaches the night page, the chosen-verse ring and the rubric.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/data/backup.dart';
import 'package:shatibiyyah/data/settings_store.dart';
import 'package:shatibiyyah/data/user_store.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/design/app_theme.dart';
import 'package:shatibiyyah/ui/design/components/dock.dart';
import 'package:shatibiyyah/ui/design/components/night_ink_option.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_goldens/golden_fonts.dart';
import 'handoff/fixtures.dart';
import 'handoff/handoff.dart';

void main() {
  final data = HandoffContent();
  setUpAll(data.open);
  tearDownAll(data.close);
  tearDown(() {
    appNightInk.value = TzNightPage.jade;
    appTheme.value = ReaderTheme.dark;
  });

  test('the preference: jade by default, jade for an unknown value, kept across a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.create();
    expect(kNightInkPref, TzNightPage.preference);
    expect(nightInkById(SettingsStore(prefs).nightInk), TzNightPage.jade);
    SettingsStore(prefs).nightInk = 'wisteria';
    expect(nightInkById(SettingsStore(await Prefs.create()).nightInk), TzNightPage.wisteria); // a new store, the same device
    prefs.setString(kNightInkPref, 'current'); // the old pink is not offered
    expect(nightInkById(SettingsStore(prefs).nightInk), TzNightPage.jade);
    prefs.setString(kNightInkPref, 'nonsense');
    expect(nightInkById(SettingsStore(prefs).nightInk), TzNightPage.jade);
  });

  test('a backup carries the ink to another device', () async {
    sqfliteFfiInit();
    Future<UserStore> user() async {
      final dir = await Directory.systemTemp.createTemp('ink_backup');
      addTearDown(() => dir.delete(recursive: true));
      final s = await UserStore.open(directory: dir.path, factory: databaseFactoryFfi);
      addTearDown(s.close);
      return s;
    }

    SharedPreferences.setMockInitialValues({'flutter.$kNightInkPref': 'turquoise'});
    final from = await Prefs.create();
    final backup = await exportBackup(await user(), from);
    expect((backup['settings'] as Map)[kNightInkPref], 'turquoise');

    SharedPreferences.setMockInitialValues({});
    final to = await Prefs.create();
    final report = await mergeBackup(await user(), to, backup);
    expect(report.settings, contains(kNightInkPref));
    expect(nightInkById(SettingsStore(to).nightInk), TzNightPage.turquoise);
  });

  testWidgets('choosing an ink applies at once: stored, on the page, in the theme', (tester) async {
    final r = await data.reader(tester);
    await tester.runAsync(loadGoldenFonts);
    tester.view.physicalSize = kHandoffScreen;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = kHandoffPadding;
    addTearDown(tester.view.reset);
    r.setThemeChoice(ThemeChoice.night);
    // The app's own wiring: the theme from the resolved choice and the chosen ink.
    await tester.pumpWidget(ListenableBuilder(
      listenable: Listenable.merge([appTheme, appNightInk]),
      builder: (context, _) => MaterialApp(
        theme: tzThemeData(tzThemeFor(appTheme.value, ink: appNightInk.value)),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Directionality(textDirection: TextDirection.rtl, child: child!)),
        home: AppShell(reader: r, initialTab: DockTab.settings),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('يشم'), findsOneWidget);

    await tester.tap(find.text('لون الحبر الليلي'));
    await tester.pump(); // the sheet's route starts
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byType(NightInkOption).at(3)); // بنفسج
    await tester.pump(); // MaterialApp's theme change starts (200 ms)
    await tester.pump(const Duration(milliseconds: 300));
    expect(r.nightInk, TzNightPage.wisteria);
    expect(r.store!.nightInk, 'wisteria'); // stored before «تم»
    expect(TzTheme.of(tester.element(find.byType(AppShell))).nightInk, TzNightPage.wisteria);
    expect(TzTheme.of(tester.element(find.byType(AppShell))).rubric, TzNightPage.wisteria.accent); // the rubric at night
    expect(tester.getSemantics(find.byType(NightInkOption).at(3)), matchesSemantics(
        label: 'بنفسج\nناعم · بنفسج الغسق', isInMutuallyExclusiveGroup: true, hasCheckedState: true, isChecked: true,
        hasTapAction: true, hasFocusAction: true, isFocusable: true));

    await tester.tap(find.text('تم')); // only closes
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(NightInkOption), findsNothing);
    expect(find.text('بنفسج'), findsOneWidget); // the row names the chosen ink

    // The reading screen draws the night page, and its chosen-verse ring, in that ink.
    await tester.tap(find.text('المتن'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(r.viewer.night, isTrue);
    expect(r.viewer.nightInk, TzNightPage.wisteria);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('«المظهر»: paper, night, or with the system', (tester) async {
    final r = await data.reader(tester);
    await pumpPhone(tester, AppShell(reader: r, initialTab: DockTab.settings));
    expect(r.themeChoice, ThemeChoice.auto); // a new install follows the system
    await tester.tap(find.text('ليلي'));
    await tester.pump();
    expect((r.themeChoice, appTheme.value, r.store!.themeChoice), (ThemeChoice.night, ReaderTheme.dark, ThemeChoice.night));
    await tester.tap(find.text('ورقي'));
    await tester.pump();
    expect((r.themeChoice, appTheme.value), (ThemeChoice.paper, ReaderTheme.paper));
    await tester.tap(find.text('تلقائي'));
    await tester.pump();
    expect(r.themeChoice, ThemeChoice.auto);
    expect(resolveTheme(ThemeChoice.auto, Brightness.dark), ReaderTheme.dark);
    expect(resolveTheme(ThemeChoice.auto, Brightness.light), ReaderTheme.paper);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
