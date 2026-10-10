// Item 3.7 against the handoff: the player sheet, its speed and repeat pickers,
// and the dock while the recitation downloads or after the download failed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/services/download_manager.dart';
import 'package:shatibiyyah/ui/design/components/dock.dart';
import 'package:shatibiyyah/ui/design/components/khatam.dart';
import 'package:shatibiyyah/ui/design/components/section_scrubber.dart';
import 'package:shatibiyyah/ui/design/components/stat_tile.dart';
import 'package:shatibiyyah/ui/design/components/tz_button.dart';
import 'package:shatibiyyah/ui/design/components/tz_picker.dart';
import 'package:shatibiyyah/ui/design/components/tz_sheet.dart';
import 'package:shatibiyyah/ui/design/components/tz_switch.dart';
import 'package:shatibiyyah/ui/reader/player_sheet.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';
import 'package:shatibiyyah/utils/arabic.dart';

import 'fixtures.dart';
import 'handoff.dart';

void main() {
  final data = HandoffContent();
  setUpAll(data.open);
  tearDownAll(data.close);

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  Rect rect(WidgetTester tester, Finder f) => tester.getRect(f);

  /// The shell with the section 226–234 playing, set as the design's sample
  /// (1.25×, each verse three times, a 2 s gap), and the player open.
  Future<ReaderController> openPlayer(WidgetTester tester) async {
    final r = await data.reader(tester, audio: true);
    r
      ..setSpeed(1.25)
      ..setVerseRepeats(3)
      ..setGap(2000);
    await pumpPhone(tester, AppShell(reader: r));
    await tester.runAsync(() => r.playScope(const PlaybackScope(226, 234)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.bySemanticsLabel(RegExp('^فتح المشغّل')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    return r;
  }

  testWidgets('player-main: the verse as hero, the next verse, the scrubber, transport, four tiles, two rows', (tester) async {
    final spec = HandoffSpec.load('player-main-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    final r = await openPlayer(tester);
    final c = Conformance(spec);
    final sheet = find.byType(PlayerSheet);
    Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);

    c.box('sheet', rect(tester, inSheet(find.byKey(TzSheet.surfaceKey))), spec.component('TzSheet (player)').rect);
    c.box('grab', rect(tester, inSheet(find.byKey(TzSheet.grabKey))), spec.component('SheetGrab').rect);

    // The header: the section and the reciter over the chapter; «إغلاق المشغّل».
    c.line('caption', rect(tester, inSheet(find.text('المقطع ${isolatedRange(226, 234)} · ${r.recording.reciterName}'))), spec.id(21).rect);
    c.line('chapter', rect(tester, inSheet(find.text(plainName(r.chapter.shortLabel)))), spec.cls('t-head').rect);
    c.centre('close', rect(tester, find.bySemanticsLabel('إغلاق المشغّل')), spec.id(23).rect);

    // The hero: the khatam with the verse's number, then its two hemistichs.
    final v = data.content.matn.verse(226);
    c.box('khatam', rect(tester, inSheet(find.byType(Khatam))), spec.component('Khatam').rect);
    expect(tester.widget<Khatam>(inSheet(find.byType(Khatam))).label, '٢٢٦');
    final hero = rect(tester, find.byKey(PlayerSheet.heroKey));
    c.same('hero: two lines of 44 from y 216', (hero.top - 216).abs() <= 1 && (hero.height - 88).abs() <= 1, true);
    expect(tester.widget<Text>(find.byKey(PlayerSheet.heroKey)).data, '${v.firstHemistich}\n${v.secondHemistich}');

    // The next verse, faded, under a dashed line.
    c.line('up next', rect(tester, inSheet(find.text('التالي · البيت ٢٢٧'))), Rect.fromLTWH(22, 323, 346, 16).translate(-(346 - rect(tester, inSheet(find.text('التالي · البيت ٢٢٧'))).width) / 2, 0));
    final next = rect(tester, find.byKey(PlayerSheet.upNextKey));
    c.same('next verse: one line of 30 at y 339', (next.top - 339).abs() <= 1 && (next.height - 30).abs() <= 1, true);
    expect(tester.widget<Text>(find.byKey(PlayerSheet.upNextKey)).data, data.content.matn.verse(227).firstHemistich);

    // The scrubber: the track, a tick at each of the eight later verses, the knob on the track's line.
    final track = spec.cls('track').rect;
    c.box('track', rect(tester, find.byKey(SectionScrubber.trackKey)), track);
    expect(find.byKey(SectionScrubber.tickKey), findsNWidgets(8));
    c.same('knob on the track', (rect(tester, find.byKey(SectionScrubber.knobKey)).center.dy - track.center.dy).abs() <= 1, true);
    c.same('knob 16', rect(tester, find.byKey(SectionScrubber.knobKey)).size, const Size(16, 16));
    final middle = rect(tester, inSheet(find.text('البيت ١ من ٩')));
    c.centre('«البيت ١ من ٩»', middle, spec.text('البيت ١ من ٩').rect);

    // Transport: previous at the start, the big disc, next at the end.
    c.centre('previous', rect(tester, inSheet(find.bySemanticsLabel('البيت السابق'))), spec.id(49).rect);
    c.box('play disc', rect(tester, find.byKey(PlayerSheet.bigPlayKey)), spec.cls('bigplay').rect);
    c.centre('next', rect(tester, inSheet(find.bySemanticsLabel('البيت التالي'))), spec.id(53).rect);

    // The four value tiles, and the counter on verse repeat.
    final tiles = [for (final n in spec.nodes) if (n.component == 'StatTile') n];
    expect(tiles, hasLength(4));
    for (var i = 0; i < 4; i++) {
      c.box('tile ${i + 1}', rect(tester, inSheet(find.byType(StatTile)).at(i)), tiles[i].rect);
    }
    c.centre('«١٫٢٥×»', rect(tester, inSheet(find.text('١٫٢٥×'))), spec.text('١٫٢٥×').rect);
    c.centre('«السرعة»', rect(tester, inSheet(find.text('السرعة'))), spec.text('السرعة').rect);
    c.centre('the counter', rect(tester, inSheet(find.text('١/٣'))), spec.cls('badge').rect, tol: 1.5);
    expect([for (final t in tester.widgetList<StatTile>(inSheet(find.byType(StatTile)))) (t.value, t.label, t.badge)], [
      ('١٫٢٥×', 'السرعة', null),
      ('٣', 'تكرار البيت', '١/٣'),
      ('١', 'تكرار المقطع', null),
      ('٢ ث', 'الفاصل', null),
    ]);

    // The two rows.
    c.line('«عناوين الأبواب»', rect(tester, inSheet(find.text('عناوين الأبواب'))), spec.text('عناوين الأبواب').rect);
    c.box('titles switch', rect(tester, inSheet(find.byKey(TzSwitch.trackKey))), spec.component('TzSwitch').rect);
    c.line('«التلاوة»', rect(tester, inSheet(find.text('التلاوة'))), spec.text('التلاوة').rect);
    c.done();
    await unmount(tester);
  });

  testWidgets('player-repeat: «تكرار البيت» with its rule and six options of 56', (tester) async {
    final spec = HandoffSpec.load('player-repeat-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    await openPlayer(tester);
    await tester.tap(find.widgetWithText(StatTile, 'تكرار البيت'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final c = Conformance(spec);
    final picker = find.byType(TzPicker);
    Finder inPicker(Finder f) => find.descendant(of: picker, matching: f);

    c.box('sheet', rect(tester, inPicker(find.byKey(TzSheet.surfaceKey))), spec.component('TzSheet (picker)').rect, tol: 1.5);
    c.line('title', rect(tester, inPicker(find.text('تكرار البيت'))), spec.cls('t-title').rect, tol: 1.5);
    final rule = rect(tester, inPicker(find.textContaining('يُعاد كل بيت')));
    c.same('rule: two lines under the title', (rule.top - spec.id(84).rect.top).abs() <= 1.5 && (rule.height - 40).abs() <= 1, true);
    final options = spec.childrenOf(spec.cls('opts'));
    expect([for (final o in options) o.text], ['١', '٢', '٣', '٤', '٥', '∞']);
    for (final o in options) {
      c.box('option ${o.text}', rect(tester, inPicker(find.widgetWithText(PickerOption, o.text!))), o.rect, tol: 1.5);
    }
    expect(tester.widget<PickerOption>(inPicker(find.widgetWithText(PickerOption, '٣'))).selected, isTrue);
    c.box('«تم»', rect(tester, inPicker(find.widgetWithText(TzButton, 'تم'))), spec.text('تم').rect, tol: 1.5);
    c.done();
    await unmount(tester);
  });

  testWidgets('player-speed: «السرعة» with its rule and eight speeds, four to a row', (tester) async {
    final spec = HandoffSpec.load('player-speed-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    await openPlayer(tester);
    await tester.tap(find.widgetWithText(StatTile, 'السرعة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final c = Conformance(spec);
    final picker = find.byType(TzPicker);
    Finder inPicker(Finder f) => find.descendant(of: picker, matching: f);

    c.box('sheet', rect(tester, inPicker(find.byKey(TzSheet.surfaceKey))), spec.component('TzSheet (picker)').rect, tol: 1.5);
    c.line('title', rect(tester, inPicker(find.text('السرعة'))), spec.cls('t-title').rect, tol: 1.5);
    final options = spec.childrenOf(spec.cls('opts speeds'));
    expect([for (final o in options) o.text], ['٠٫٢٥×', '٠٫٥×', '٠٫٧٥×', '١×', '١٫٢٥×', '١٫٥×', '١٫٧٥×', '٢×']);
    for (final o in options) {
      c.box('option ${o.text}', rect(tester, inPicker(find.widgetWithText(PickerOption, o.text!))), o.rect, tol: 1.5);
    }
    expect(tester.widget<PickerOption>(inPicker(find.widgetWithText(PickerOption, '١٫٢٥×'))).selected, isTrue);
    c.box('«تم»', rect(tester, inPicker(find.widgetWithText(TzButton, 'تم'))), spec.text('تم').rect, tol: 1.5);
    c.done();
    await unmount(tester);
  });

  // The dock while the recitation is on its way.
  for (final (name, phase) in [('reader-downloading', DownloadPhase.downloading), ('reader-failed', DownloadPhase.failed)]) {
    testWidgets('$name: the dock says what the download is doing, in place', (tester) async {
      final spec = HandoffSpec.load('$name-paper');
      if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
      final total = data.content.recordings.defaultRecording.localBytes;
      final r = await data.reader(tester,
          download: DownloadProgress(phase, (total * 0.42).ceil(), total, phase == DownloadPhase.failed ? DownloadError.network : null));
      await pumpPhone(tester, AppShell(reader: r));
      final c = Conformance(spec);
      final row = find.byKey(Dock.rowKey);
      Finder inRow(Finder f) => find.descendant(of: row, matching: f);

      c.box('dock', rect(tester, find.byKey(Dock.bindingKey)), spec.component('Dock').rect);
      c.box('row', rect(tester, row), spec.component('Dock now-playing row').rect);
      c.box('khatam', rect(tester, inRow(find.byType(Khatam))), spec.component('Khatam').rect);
      c.line('title', rect(tester, inRow(find.text(spec.id(22).text!))), spec.id(22).rect);
      final words = phase == DownloadPhase.downloading
          ? '${ar((total * 0.42 / 1e6).round())} من ${megabytes(total)} · يكمل في الخلفية' // «٦١ من ١٤٥ م.ب» in the design
          : 'انقطع الاتصال · سيُستأنف من ٤٢٪';
      c.line('subtitle', rect(tester, inRow(find.text(words))), spec.id(23).rect);
      if (phase == DownloadPhase.downloading) {
        expect(tester.widget<Khatam>(inRow(find.byType(Khatam))).label, '٤٢٪');
        expect(tester.widget<Khatam>(inRow(find.byType(Khatam))).progress, closeTo(0.42, 0.001));
        c.centre('pause', rect(tester, inRow(find.bySemanticsLabel('إيقاف مؤقت'))), spec.id(24).rect);
        await tester.tap(inRow(find.bySemanticsLabel('إيقاف مؤقت')));
        expect((r.library! as FixedLibrary).pauseCalls, 1);
      } else {
        expect(tester.widget<Khatam>(inRow(find.byType(Khatam))).error, isTrue);
        c.box('«إعادة»', rect(tester, find.byKey(Dock.pillKey)), spec.cls('dbtn').rect, tol: 1.5);
        await tester.tap(find.text('إعادة'));
        expect((r.library! as FixedLibrary).downloadCalls, 1);
      }
      c.done();
      await unmount(tester);
    });
  }
}
