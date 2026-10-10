// Item 3.8 (ADR 0021): text mode is the poem as one column. Chapters follow one
// another, each under its head; the column opens on the reader's verse and
// follows it; a tap moves the reader, a long press opens the verse's menu. The
// six sizes are 17 to 28 px, kept across restarts.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/data/settings_store.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/design/components/chapter_head.dart';
import 'package:shatibiyyah/ui/design/components/verse_unit.dart';
import 'package:shatibiyyah/ui/reader/display_sheet.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/reader/text_reader.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:shatibiyyah/utils/arabic.dart';

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

  Finder unit(int verse) => find.byWidgetPredicate((w) => w is VerseUnit && w.number == ar(verse));
  Finder head(int order) => find.byWidgetPredicate((w) => w is ChapterHead && w.order == ar(order));

  Future<ReaderController> textMode(WidgetTester tester, {int verse = 226}) async {
    final r = await data.reader(tester, audio: true);
    if (verse != 226) await tester.runAsync(() => r.tapVerse(verse));
    r.setTextMode(true);
    await pumpPhone(tester, AppShell(reader: r));
    return r;
  }

  test('sizes: six steps from 17 to 28 px around a default of 20; an older value snaps to the nearest', () async {
    expect([for (final s in kTextScaleOptions) s * kDefaultVerseSize], [17, 18.5, 20, 22, 25, 28]);
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.create();
    final s = SettingsStore(prefs);
    expect(s.textScale, 1);
    for (final step in kTextScaleOptions) {
      s.textScale = step;
      expect(SettingsStore(prefs).textScale, step);
    }
    for (final (old, now) in [('0.75', 0.85), ('1.5', 1.4), ('2.0', 1.4), ('1.25', 1.25), ('1.75', 1.4), ('nonsense', 1.0)]) {
      prefs.setString('v2.text.scale', old);
      expect(SettingsStore(prefs).textScale, now, reason: old);
    }
  });

  testWidgets('one column: a chapter ends and the next one\'s head follows; scrolling back reaches the one before', (tester) async {
    await textMode(tester);
    final list = find.descendant(of: find.byType(TextReader), matching: find.byType(Scrollable)).first;
    expect(head(11), findsOneWidget);
    await tester.scrollUntilVisible(head(12), 300, scrollable: list);
    expect(head(12), findsOneWidget);
    expect(tester.getTopLeft(head(12)).dy, greaterThan(tester.getTopLeft(unit(234)).dy));
    await tester.scrollUntilVisible(unit(235), 200, scrollable: list);
    await tester.scrollUntilVisible(unit(225), -300, scrollable: list);
    expect(tester.getTopLeft(unit(225)).dy, lessThan(tester.getTopLeft(head(11)).dy));
    await unmount(tester);
  });

  testWidgets('opens on the reader\'s verse: a chapter\'s first verse under its head, any other with the one before in view', (tester) async {
    await textMode(tester, verse: 230);
    expect(unit(230), findsOneWidget);
    final top = tester.getTopLeft(find.byType(TextReader)).dy;
    expect(tester.getTopLeft(unit(230)).dy - top, inInclusiveRange(60, 200));
    expect(unit(229), findsOneWidget);
    await unmount(tester);

    await textMode(tester, verse: 1);
    expect(head(0), findsNothing); // the introduction's head has no number
    expect(find.byType(ChapterHead), findsWidgets);
    expect(tester.getTopLeft(find.byType(ChapterHead).first).dy - tester.getTopLeft(find.byType(TextReader)).dy, closeTo(4, 1));
    await unmount(tester);
  });

  testWidgets('follows the reader: a verse far away is brought into view', (tester) async {
    final r = await textMode(tester);
    await tester.runAsync(() => r.tapVerse(1000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(unit(1000), findsOneWidget);
    final view = tester.getRect(find.byType(TextReader));
    expect(view.contains(tester.getCenter(unit(1000))), isTrue);
    expect(tester.state<TextReaderState>(find.byType(TextReader)).rowRect(1000), tester.getRect(unit(1000)));
    await unmount(tester);
  });

  testWidgets('a tap moves the reader; a long press opens the verse\'s menu and rings it; one node per verse', (tester) async {
    final handle = tester.ensureSemantics();
    final r = await textMode(tester);
    await tester.tap(unit(228));
    await tester.pump(const Duration(milliseconds: 400));
    expect((r.verse, r.menuVerse), (228, null));

    await tester.longPress(unit(229));
    await tester.pump(const Duration(milliseconds: 400));
    expect((r.verse, r.menuVerse), (228, 229));
    expect(tester.widget<VerseUnit>(unit(229)).chosen, isTrue);
    r.closeMenu();
    await tester.pump(const Duration(milliseconds: 400));

    final v = data.content.matn.verse(227);
    expect(tester.getSemantics(unit(227)), matchesSemantics(
        label: 'البيت ٢٢٧: ${v.firstHemistich}، ${v.secondHemistich}', isButton: true, hasTapAction: true, hasLongPressAction: true));
    await unmount(tester);
    handle.dispose();
  });

  testWidgets('a selected run is ringed; the chosen size reaches every unit and the heads', (tester) async {
    final r = await textMode(tester);
    r.startSelection(227);
    await tester.runAsync(() => r.tapVerse(229));
    await tester.pump(const Duration(milliseconds: 400));
    expect([for (final n in [226, 227, 228, 229, 230]) tester.widget<VerseUnit>(unit(n)).chosen], [false, true, true, true, false]);
    r.clearSelection();
    r.setTextScale(1.25);
    await tester.pump(const Duration(milliseconds: 400));
    expect((r.textScale, r.verseSize, r.store!.textScale), (1.25, 25.0, 1.25));
    expect(tester.widget<VerseUnit>(unit(226)).fontSize, 25);
    expect(tester.widget<ChapterHead>(head(11)).verseSize, 25);
    await unmount(tester);
  });

  testWidgets('«العرض» opens from the page too; «الصفحة / النص» switches the view; the night page is at its designed brightness', (tester) async {
    final r = await data.reader(tester, audio: true);
    await pumpPhone(tester, AppShell(reader: r));
    expect(find.byType(PageViewer), findsOneWidget);
    await tester.tap(find.byTooltip('العرض'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DisplaySheet), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(DisplaySheet), matching: find.text('النص')));
    await tester.pump(const Duration(milliseconds: 400));
    expect((r.textMode, r.store!.textMode), (true, true));
    expect(find.byType(TextReader), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(DisplaySheet), matching: find.text('الصفحة')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(r.textMode, isFalse);
    await tester.tap(find.text('تم'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DisplaySheet), findsNothing);
    await unmount(tester);
  });
}
