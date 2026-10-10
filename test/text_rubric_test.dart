// Reader names and symbols in the rubric ink (plan 3.8's rubric, ADRs 0015, 0021;
// handoff textmode-reading, textmode-display, textmode-symbol, share-*): in text
// mode and on the share card, from the span data. A symbol opens its tip. The
// «العرض» sheet has the switch.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/data/settings_store.dart';
import 'package:shatibiyyah/ui/design/components/share_card.dart';
import 'package:shatibiyyah/ui/design/components/symbol_chip.dart';
import 'package:shatibiyyah/ui/design/components/symbol_tip.dart';
import 'package:shatibiyyah/ui/design/components/tz_switch.dart';
import 'package:shatibiyyah/ui/design/components/verse_unit.dart';
import 'package:shatibiyyah/ui/reader/display_sheet.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/reader/verse_rubrics.dart';
import 'package:shatibiyyah/ui/share/share_sheet.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';
import 'package:shatibiyyah/ui/shell/rumuz_screen.dart';
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

  Future<ReaderController> textMode(WidgetTester tester, {int verse = 226}) async {
    final r = await data.reader(tester, audio: true, bookmarks: false);
    r.setTextMode(true);
    if (verse != 226) await tester.runAsync(() => r.tapVerse(verse));
    await pumpPhone(tester, AppShell(reader: r));
    return r;
  }

  Finder unit(int verse) => find.byWidgetPredicate((w) => w is VerseUnit && w.number == ar(verse));

  /// The words of [verse]'s marks, in reading order.
  List<String> marked(WidgetTester tester, int verse) {
    final w = tester.widget<VerseUnit>(unit(verse).first);
    final v = data.content.matn.verse(verse);
    return [
      for (final m in w.rubrics) (m.hemistich == 1 ? v.firstHemistich : v.secondHemistich).substring(m.start!, m.end!),
    ];
  }

  test('the marks of a verse come from the span data: names whole, a symbol its letter', () {
    final v230 = data.content.matn.verse(230);
    final marks = verseRubrics(data.content, 230);
    expect([for (final m in marks) (m.hemistich, v230.secondHemistich.substring(m.start!, m.end!), m.isSymbol)],
        [(2, 'كَ', true), (2, 'ظَ', true)]);
    expect([for (final m in marks) m.label], ['رمز كَ: ابن عامر', 'رمز ظَ: الكوفيون وابن كثير']);
    final name = verseRubrics(data.content, 226).single;
    expect((name.isSymbol, name.label, data.content.matn.verse(226).firstHemistich.substring(name.start!, name.end!)),
        (false, null, 'لِوَرْشٍ'));
  });

  testWidgets('text mode sets them in the rubric ink; the switch in «العرض» hides them and is kept', (tester) async {
    final r = await textMode(tester);
    expect(marked(tester, 226), ['لِوَرْشٍ']);
    expect(marked(tester, 227), ['حَمْزَةٍ', 'خَلَفٌ']);
    expect(r.showRubric, isTrue);

    await tester.tap(find.byTooltip('العرض'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final sheet = find.byType(DisplaySheet);
    expect(find.descendant(of: sheet, matching: find.text('إبراز رموز القراء وأسمائهم')), findsOneWidget);
    final sw = find.descendant(of: sheet, matching: find.byType(TzSwitch));
    expect((tester.widget<TzSwitch>(sw).value, tester.widget<TzSwitch>(sw).onWord, tester.widget<TzSwitch>(sw).offWord),
        (true, 'ظاهر', 'مخفي'));
    // The sample shows what the switch does.
    expect(tester.widget<VerseUnit>(find.descendant(of: sheet, matching: find.byType(VerseUnit))).rubrics, hasLength(1));
    await tester.tap(sw);
    await tester.pump();
    expect(tester.widget<VerseUnit>(find.descendant(of: sheet, matching: find.byType(VerseUnit))).rubrics, isEmpty);
    expect(marked(tester, 227), isEmpty);
    expect((r.showRubric, SettingsStore(r.store!.prefs).showRubric), (false, false));
    await unmount(tester);
  });

  testWidgets('a symbol opens its tip under it; «رموز القراء» opens the list; a tap elsewhere closes it', (tester) async {
    final r = await textMode(tester, verse: 229);
    await tester.pumpAndSettle();
    final state = tester.state<VerseUnitState>(unit(230));
    final kaf = tester.widget<VerseUnit>(unit(230)).rubrics.first;
    final at = state.symbolRect(kaf)!;
    expect(at.width, lessThan(20)); // one letter

    await tester.tapAt(at.center);
    await tester.pump(const Duration(milliseconds: 400)); // a tap waits out the double tap
    await tester.pump(const Duration(milliseconds: 300));
    expect(r.verse, 229); // the verse was not chosen: the symbol took the tap
    final tip = find.byType(SymbolTip);
    final w = tester.widget<SymbolTip>(tip);
    expect((w.code, w.title, w.caption), ('كَ', 'ابن عامر', 'رمز حرفي · من «أبجد»، البيت ٤٥'));
    final box = tester.getRect(find.byKey(SymbolTip.surfaceKey));
    expect((box.left, box.right), (16.0, 374.0));
    expect(box.top, closeTo(state.symbolRect(kaf)!.bottom + 12, 1.5));
    expect(kaf.sameMark(tester.widget<VerseUnit>(unit(230)).activeSymbol), isTrue);

    // The other symbol of the verse: a group's letter.
    await tester.tapAt(const Offset(195, 110)); // outside: closes
    await tester.pump(const Duration(milliseconds: 400));
    expect(tip, findsNothing);
    final zha = tester.widget<VerseUnit>(unit(230)).rubrics.last;
    await tester.tapAt(tester.state<VerseUnitState>(unit(230)).symbolRect(zha)!.center);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<SymbolTip>(tip).title, 'الكوفيون وابن كثير');

    await tester.tap(find.descendant(of: tip, matching: find.text('رموز القراء')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(RumuzScreen), findsOneWidget);
    expect(r.symbol, isNull);
    // The list opens on this symbol: the groups' tab, «ظ» marked.
    expect([for (final c in tester.widgetList<SymbolChip>(find.byType(SymbolChip))) (c.code, c.active)],
        [('ث', false), ('خ', false), ('ذ', false), ('ظ', true), ('غ', false), ('ش', false)]);
    await unmount(tester);
  });

  testWidgets('a tap on the verse beside a symbol still chooses the verse; Back closes the tip', (tester) async {
    final r = await textMode(tester, verse: 229);
    await tester.pumpAndSettle();
    final rect = tester.getRect(unit(230));
    await tester.tapAt(rect.centerRight - const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    expect((r.verse, r.symbol), (230, null));

    final kaf = tester.widget<VerseUnit>(unit(230)).rubrics.first;
    r.openSymbol(230, kaf);
    await tester.pump();
    expect(find.byType(SymbolTip), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(SymbolTip), findsNothing);
    await unmount(tester);
  });

  testWidgets('TalkBack: a verse is still one item, and names its symbols as actions', (tester) async {
    final handle = tester.ensureSemantics();
    await textMode(tester, verse: 229);
    await tester.pumpAndSettle();
    final node = tester.getSemantics(unit(230));
    expect(node.label, startsWith('البيت ٢٣٠'));
    final data = node.getSemanticsData();
    expect(data.customSemanticsActionIds, hasLength(2));
    await unmount(tester);
    handle.dispose();
  });

  testWidgets('on the share card each mark colours its own hemistich only', (tester) async {
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final card = shareCardData(data.content, 226, 229, CardFormat.square);
    await tester.pumpWidget(MaterialApp(home: Center(child: ShareCard(data: card))));
    final rubric = ShareCardPalette.paper.rubric;
    final coloured = <String>[
      for (final text in tester.widgetList<RichText>(find.descendant(of: find.byType(ShareCardVerse), matching: find.byType(RichText))))
        for (final span in (text.text as TextSpan).children!.cast<TextSpan>())
          if (span.style?.color == rubric) span.text!,
    ];
    expect(coloured, ['لِوَرْشٍ', 'حَمْزَةٍ', 'خَلَفٌ', 'حَمْزَةٍ', 'لِنَافِعٍ']);
  });

  test('the share card carries the marks of its verses', () {
    final card = shareCardData(data.content, 226, 227, CardFormat.portrait);
    expect([for (final v in card.verses) v.rubrics.length], [1, 2]);
    expect(card.verses.first.rubrics.single.hemistich, 1);
  });
}
