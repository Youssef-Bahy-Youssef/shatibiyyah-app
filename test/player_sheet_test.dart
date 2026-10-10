// Item 3.7: the player sheet's behaviour. Each of the four tiles opens a picker
// that sets and keeps its value; the counter shows on verse repeat; the
// scrubber moves to the verse under the finger; the dock's row opens the sheet
// and says what a download is doing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/data/settings_store.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/services/download_manager.dart';
import 'package:shatibiyyah/ui/design/components/dock.dart';
import 'package:shatibiyyah/ui/design/components/section_scrubber.dart';
import 'package:shatibiyyah/ui/design/components/stat_tile.dart';
import 'package:shatibiyyah/ui/design/components/tz_picker.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';
import 'package:shatibiyyah/ui/reader/player_sheet.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';

import 'handoff/fixtures.dart';
import 'handoff/handoff.dart';

void main() {
  final data = HandoffContent();
  setUpAll(data.open);
  tearDownAll(data.close);

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<ReaderController> openPlayer(WidgetTester tester) async {
    final r = await data.reader(tester, audio: true);
    await pumpPhone(tester, AppShell(reader: r));
    await tester.runAsync(() => r.playScope(const PlaybackScope(226, 234)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.bySemanticsLabel(RegExp('^فتح المشغّل')));
    await settle(tester);
    expect(find.byType(PlayerSheet), findsOneWidget);
    return r;
  }

  StatTile tile(WidgetTester tester, String label) => tester.widget<StatTile>(find.widgetWithText(StatTile, label));

  test('the offered values: eight speeds; one to five times or without end; a gap up to 3 s', () {
    expect(kSpeedOptions, [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]);
    expect(kVerseRepeatOptions, [1, 2, 3, 4, 5, null]);
    expect(kSectionRepeatOptions, [1, 2, 3, 4, 5, null]);
    expect(kGapOptionsMs, [0, 1000, 2000, 3000]);
  });

  testWidgets('each tile opens its picker; a choice applies at once and is kept', (tester) async {
    final r = await openPlayer(tester);
    Future<void> pick(String tileLabel, String option, String rule) async {
      await tester.tap(find.widgetWithText(StatTile, tileLabel));
      await settle(tester);
      expect(find.descendant(of: find.byType(TzPicker), matching: find.text(tileLabel)), findsOneWidget);
      expect(find.textContaining(rule), findsOneWidget);
      await tester.tap(find.widgetWithText(PickerOption, option));
      await tester.pump();
      expect(tester.widget<PickerOption>(find.widgetWithText(PickerOption, option)).selected, isTrue); // still open
      await tester.tap(find.text('تم'));
      await settle(tester);
      expect(find.byType(TzPicker), findsNothing);
    }

    await pick('السرعة', '١٫٧٥×', 'تُحفظ لكل تلاوة');
    expect((r.speed, r.store!.speedFor(r.recording.id), tile(tester, 'السرعة').value), (1.75, 1.75, '١٫٧٥×'));

    await pick('تكرار البيت', '٤', 'يُعاد كل بيت');
    expect((r.settings.verseRepeats, r.store!.verseRepeats, tile(tester, 'تكرار البيت').value), (4, 4, '٤'));
    expect(tile(tester, 'تكرار البيت').badge, '١/٤'); // the counter: which time of how many

    await pick('تكرار البيت', '∞', 'يُعاد كل بيت');
    expect((r.settings.verseRepeats, r.store!.verseRepeats, tile(tester, 'تكرار البيت').value), (null, null, '∞'));
    expect(tile(tester, 'تكرار البيت').badge, '١/∞');

    await pick('تكرار البيت', '١', 'يُعاد كل بيت');
    expect(tile(tester, 'تكرار البيت').badge, isNull); // once: nothing to count

    await pick('تكرار المقطع', '٢', 'يُعاد المقطع');
    expect((r.settings.sectionRepeats, r.store!.sectionRepeats, tile(tester, 'تكرار المقطع').value), (2, 2, '٢'));
    expect(tile(tester, 'تكرار المقطع').badge, '١/٢');

    await pick('الفاصل', '٣ ث', 'سكتة');
    expect((r.settings.gapMs, r.store!.gapMs, tile(tester, 'الفاصل').value), (3000, 3000, '٣ ث'));
    await pick('الفاصل', 'بدون', 'سكتة');
    expect((r.settings.gapMs, tile(tester, 'الفاصل').value), (0, 'بدون'));
    await unmount(tester);
  });

  testWidgets('transport, the titles switch, and closing', (tester) async {
    final r = await openPlayer(tester);
    final sheet = find.byType(PlayerSheet);
    Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);

    expect(r.playing, isTrue);
    await tester.tap(inSheet(find.bySemanticsLabel('إيقاف مؤقت')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    expect(r.playing, isFalse);
    expect(inSheet(find.bySemanticsLabel('تشغيل')), findsOneWidget);

    await tester.tap(inSheet(find.bySemanticsLabel('البيت التالي')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    expect(r.verse, 227);
    expect(find.text('البيت ٢ من ٩'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(PlayerSheet.heroKey)).data, startsWith(data.content.matn.verse(227).firstHemistich));
    await tester.tap(inSheet(find.bySemanticsLabel('البيت السابق')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    expect(r.verse, 226);

    expect(r.settings.playTitles, isTrue);
    await tester.tap(inSheet(find.text('تُتلى')));
    await tester.pump();
    expect((r.settings.playTitles, r.store!.playTitles), (false, false));
    expect(inSheet(find.text('لا تُتلى')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('إغلاق المشغّل'));
    await settle(tester);
    expect(find.byType(PlayerSheet), findsNothing);
    await unmount(tester);
  });

  testWidgets('the last verse of the section has no «التالي»', (tester) async {
    final r = await data.reader(tester, audio: true);
    await pumpPhone(tester, AppShell(reader: r));
    await tester.runAsync(() => r.playScope(const PlaybackScope(233, 234)));
    await tester.runAsync(() => r.tapVerse(234));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.bySemanticsLabel(RegExp('^فتح المشغّل')));
    await settle(tester);
    expect(find.text('البيت ٢ من ٢'), findsOneWidget);
    expect(find.byKey(PlayerSheet.upNextKey), findsNothing);
    expect(find.byKey(SectionScrubber.tickKey), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the scrubber goes to the verse under the finger', (tester) async {
    final r = await openPlayer(tester);
    final windows = r.engine!.windows;
    final track = tester.getRect(find.byKey(SectionScrubber.trackKey));
    // RTL: the section starts at the right end of the track. Aim inside verse 230's time.
    final start = windows.cue(226), end = windows.verseEnd(234);
    final f = ((windows.cue(230) + windows.verseEnd(230)) / 2 - start) / (end - start);
    await tester.tapAt(Offset(track.right - track.width * f, track.center.dy));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    expect(r.verse, 230);
    expect(find.text('البيت ٥ من ٩'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('scrubber: the fill, the knob and the ticks follow the fractions; RTL fills from the right', (tester) async {
    double? sought;
    await pumpPhone(
      tester,
      Scaffold(
        body: Center(
          child: SizedBox(
            width: 346,
            child: SectionScrubber(
                progress: 0.25, ticks: const [0.5, 0.75], start: '٠:٠٦', middle: 'البيت ١ من ٣', end: '١:٢٢', onSeek: (f) => sought = f),
          ),
        ),
      ),
    );
    final track = tester.getRect(find.byKey(SectionScrubber.trackKey));
    final fill = tester.getRect(find.byKey(SectionScrubber.fillKey));
    expect((track.size, fill.right), (const Size(346, 4), track.right));
    expect(fill.width, closeTo(346 * 0.25, 0.01));
    expect(tester.getRect(find.byKey(SectionScrubber.knobKey)).center.dx, closeTo(track.right - 346 * 0.25, 0.01));
    expect([for (final e in find.byKey(SectionScrubber.tickKey).evaluate()) tester.getRect(find.byWidget(e.widget)).center.dx.round()],
        [(track.right - 346 * 0.5).round(), (track.right - 346 * 0.75).round()]);
    await tester.tapAt(Offset(track.right - 346 * 0.6, track.center.dy));
    expect(sought, closeTo(0.6, 0.01));
    // One item for a screen reader, with its place as the value.
    expect(tester.getSemantics(find.byType(SectionScrubber)), matchesSemantics(label: 'موضع التلاوة في المقطع', value: 'البيت ١ من ٣'));
    await unmount(tester);
  });

  for (final (theme, tz) in [('paper', TzTheme.paper), ('night', TzTheme.dark)]) {
    testWidgets('accessible ($theme): labelled targets of 48 or more, text contrast, in the sheet and its pickers', (tester) async {
      final handle = tester.ensureSemantics();
      final r = await data.reader(tester, audio: true);
      r.setVerseRepeats(3);
      await pumpPhone(tester, AppShell(reader: r), tz: tz);
      await tester.runAsync(() => r.playScope(const PlaybackScope(226, 234)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.bySemanticsLabel(RegExp('^فتح المشغّل')));
      await settle(tester);
      Future<void> check() async {
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }

      await check();
      for (final label in ['السرعة', 'تكرار البيت', 'الفاصل']) {
        await tester.tap(find.widgetWithText(StatTile, label));
        await settle(tester);
        await check();
        await tester.tap(find.text('تم'));
        await settle(tester);
      }
      await unmount(tester);
      handle.dispose();
    });
  }

  testWidgets('nothing overflows at 200 % text or on a 360 × 640 phone: the sheet and its pickers scroll', (tester) async {
    for (final (size, scale) in [(const Size(390, 844), 2.0), (const Size(360, 640), 1.0), (const Size(360, 640), 2.0)]) {
      final r = await data.reader(tester, audio: true);
      r.setVerseRepeats(3);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: tzThemeData(TzTheme.paper),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true, textScaler: TextScaler.linear(scale)),
          child: Directionality(textDirection: TextDirection.rtl, child: child!),
        ),
        home: AppShell(reader: r),
      ));
      await tester.runAsync(() => r.playScope(const PlaybackScope(226, 234)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.bySemanticsLabel(RegExp('^فتح المشغّل')));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'the sheet at $size × $scale');
      // The last row is reachable.
      await tester.scrollUntilVisible(find.text('التلاوة'), 120, scrollable: find.descendant(of: find.byType(PlayerSheet), matching: find.byType(Scrollable)).first);
      for (final label in ['السرعة', 'تكرار البيت']) {
        await tester.scrollUntilVisible(find.widgetWithText(StatTile, label), -120,
            scrollable: find.descendant(of: find.byType(PlayerSheet), matching: find.byType(Scrollable)).first);
        await tester.tap(find.widgetWithText(StatTile, label));
        await settle(tester);
        expect(tester.takeException(), isNull, reason: '«$label» at $size × $scale');
        await tester.tap(find.text('تم'));
        await settle(tester);
      }
      await unmount(tester);
    }
  });

  testWidgets('the dock: playing opens the player; downloading, failed, paused and none say so in place', (tester) async {
    final total = data.content.recordings.defaultRecording.localBytes;
    Future<void> show(DownloadProgress p) async {
      final r = await data.reader(tester, download: p);
      await pumpPhone(tester, AppShell(reader: r));
    }

    await show(DownloadProgress(DownloadPhase.downloading, (total / 2).ceil(), total));
    expect(find.text('جارٍ تنزيل التلاوة'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^فتح المشغّل')), findsNothing); // nothing to play yet
    await unmount(tester);

    await show(DownloadProgress(DownloadPhase.failed, (total / 2).ceil(), total, DownloadError.network));
    expect(find.text('تعذّر التنزيل'), findsOneWidget);
    expect(find.text('انقطع الاتصال · سيُستأنف من ٥٠٪'), findsOneWidget);
    await unmount(tester);

    await show(DownloadProgress(DownloadPhase.failed, 0, total, DownloadError.verification));
    expect(find.text('تعذّر التنزيل'), findsOneWidget);
    expect(find.text('تعذّر التحقق من الملف'), findsOneWidget); // the reason, as «التنزيلات» words it
    await unmount(tester);

    // A download that waits says what for (ADR 0007).
    await show(DownloadProgress(DownloadPhase.waitingForNetwork, (total / 2).ceil(), total));
    expect(find.text('جارٍ تنزيل التلاوة'), findsOneWidget);
    expect(find.text('بانتظار الاتصال بالشبكة · يُستأنف تلقائيًا'), findsOneWidget);
    await unmount(tester);
    await show(DownloadProgress(DownloadPhase.waitingForWifi, 0, total));
    expect(find.text('بانتظار شبكة Wi-Fi'), findsOneWidget);
    await unmount(tester);

    await show(DownloadProgress(DownloadPhase.paused, (total / 4).ceil(), total, DownloadError.paused));
    expect(find.text('استمع إلى المتن'), findsOneWidget);
    expect(find.textContaining('متوقف عند ٢٥٪'), findsOneWidget);
    expect(find.text('متابعة'), findsOneWidget);
    await unmount(tester);

    final r = await data.reader(tester, library: true);
    await pumpPhone(tester, AppShell(reader: r));
    expect(find.text('استمع إلى المتن'), findsOneWidget);
    expect(find.text('تنزيل'), findsOneWidget);
    expect(tester.widget<Dock>(find.byType(Dock)).nowPlaying, isA<NpNone>());
    await unmount(tester);
  });
}
