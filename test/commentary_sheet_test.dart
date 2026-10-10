// The commentary sheet (item 3.9, ADRs 0014, 0018, 0022): «الشرح» on a phone opens
// a sheet tied to the verse. The verse stays in view above it; the neighbours are
// a step away; a quotation of the verse lights its phrase; the book is remembered.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/data/settings_store.dart';
import 'package:shatibiyyah/domain/search.dart';
import 'package:shatibiyyah/ui/commentary/commentary_screen.dart';
import 'package:shatibiyyah/ui/search/search_screen.dart';
import 'package:shatibiyyah/ui/commentary/commentary_sheet.dart';
import 'package:shatibiyyah/ui/design/components/binding_stepper.dart';
import 'package:shatibiyyah/ui/design/components/commentary_inline.dart';
import 'package:shatibiyyah/ui/design/components/dock.dart';
import 'package:shatibiyyah/ui/design/components/khatam.dart';
import 'package:shatibiyyah/ui/design/components/matn_strip.dart';
import 'package:shatibiyyah/ui/design/components/verse_unit.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/reader/reader_screen.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';
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

  /// Lets the passage load from the real database, then draws it.
  Future<void> loaded(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<ReaderController> shell(WidgetTester tester, {bool text = true}) async {
    final r = await data.reader(tester, audio: true, bookmarks: false);
    r.setTextMode(text);
    await pumpPhone(tester, AppShell(reader: r));
    return r;
  }

  final sheet = find.byType(CommentarySheet);
  Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
  Finder unit(int verse) => find.byWidgetPredicate((w) => w is VerseUnit && w.number == ar(verse));
  String range(WidgetTester tester) => tester.widget<Text>(find.byKey(CommentarySheet.rangeKey)).data!;
  double top(WidgetTester tester) => tester.getRect(find.byKey(CommentarySheet.surfaceKey)).top;
  Future<void> step(WidgetTester tester, String label) async {
    await tester.tap(inSheet(find.text(label)));
    await loaded(tester);
  }

  testWidgets('«الشرح» in the verse menu opens the sheet on that verse; × and Back close it', (tester) async {
    final r = await shell(tester);
    r.openMenu(227);
    await tester.pump();
    await tester.tap(find.text('الشرح'));
    await loaded(tester);
    expect(sheet, findsOneWidget);
    expect((r.commentaryVerse, r.menuVerse), (227, null));
    expect(find.byKey(Dock.bindingKey), findsNothing); // the sheet's stepper stands in its place
    expect(find.bySemanticsLabel('الشرح: الوافي'), findsOneWidget);

    await tester.tap(find.byTooltip('إغلاق الشرح'));
    await tester.pump();
    expect(sheet, findsNothing);
    expect(r.commentaryVerse, isNull);
    expect(find.byKey(Dock.bindingKey), findsOneWidget);

    // Back closes the sheet before it leaves the reader.
    r.openCommentary(226);
    await loaded(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect((r.commentaryVerse, find.byType(ReaderScreen).evaluate().length), (null, 1));
    await unmount(tester);
  });

  testWidgets('text mode: the verse is ringed and all of it shows above the sheet, also after a step', (tester) async {
    final r = await shell(tester);
    r.openCommentary(226);
    await loaded(tester);
    expect(tester.widget<VerseUnit>(unit(226)).chosen, isTrue);
    expect(tester.getRect(unit(226)).bottom, lessThanOrEqualTo(top(tester)));

    // The passage after 226 explains 227 and 228 together.
    await step(tester, 'البيت ٢٢٧');
    expect((r.commentaryVerse, range(tester)), (227, 'الأبيات ${isolatedRange(227, 228)}'));
    expect(tester.widget<VerseUnit>(unit(227)).chosen, isTrue);
    expect(tester.getRect(unit(227)).bottom, lessThanOrEqualTo(top(tester)));
    expect(tester.getRect(unit(227)).top, greaterThanOrEqualTo(100));

    // Next goes past the whole passage, previous to the verse before it.
    await step(tester, 'البيت ٢٢٩');
    expect((r.commentaryVerse, range(tester)), (229, 'البيت ٢٢٩'));
    expect(tester.getRect(unit(229)).bottom, lessThanOrEqualTo(top(tester)));
    await step(tester, 'البيت ٢٢٨');
    expect((r.commentaryVerse, range(tester)), (228, 'الأبيات ${isolatedRange(227, 228)}'));
    // The reader's own verse (where the recitation is) does not move.
    expect(r.verse, 226);
    await unmount(tester);
  });

  testWidgets('the place in the chapter; the first verse of the poem has no previous', (tester) async {
    final r = await shell(tester);
    r.openCommentary(229);
    await loaded(tester);
    expect(inSheet(find.text('من ٩ في الباب')), findsOneWidget);
    expect(tester.widget<Khatam>(inSheet(find.descendant(of: find.byType(BindingStepper), matching: find.byType(Khatam)))).label, '٤');
    r.openCommentary(1);
    await loaded(tester);
    expect(range(tester), startsWith('البيت ١'));
    expect(inSheet(find.textContaining('البيت ٠')), findsNothing);
    await unmount(tester);
  });

  testWidgets('the page: a verse low on it is carried in the strip; a step turns the page', (tester) async {
    final r = await shell(tester, text: false);
    r.openCommentary(226);
    await loaded(tester);
    expect(find.byKey(ReaderScreen.explainedRingKey), findsOneWidget);
    expect(inSheet(find.byType(MatnStrip)), findsNothing);
    expect(find.byKey(CommentarySheet.notchKey), findsOneWidget);
    // It is also the verse being recited: under the sheet it shows its ring alone.
    expect((r.verse, r.viewer.showPlaying), (226, false));

    // Verse 237 is the last line of page 19: behind the sheet at rest.
    r.openCommentary(237);
    await loaded(tester);
    expect(tester.getRect(find.byKey(ReaderScreen.explainedRingKey)).bottom, greaterThan(top(tester)));
    expect(tester.widget<MatnStrip>(inSheet(find.byType(MatnStrip))).number, '٢٣٧');
    expect(find.byKey(CommentarySheet.notchKey), findsNothing);
    expect(r.viewer.showPlaying, isTrue); // the recited verse is another one: its wash stays
    final page = r.viewer.currentPage;
    await step(tester, 'البيت ٢٣٨');
    expect((r.commentaryVerse, r.viewer.currentPage), (238, page + 1));
    expect(r.viewer.currentPage, data.content.layout.pageOfVerse(238));
    await unmount(tester);
  });

  testWidgets('a quotation of the verse is a chip: a tap opens the strip with its phrase lit', (tester) async {
    final r = await shell(tester);
    r.openCommentary(226);
    await loaded(tester);
    final chip = inSheet(find.byWidgetPredicate((w) => w is QuoteChip && w.words == 'مسهلا'));
    expect(chip, findsOneWidget);
    expect(tester.widget<QuoteChip>(chip).on, isFalse);
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.tap(chip);
    await loaded(tester);

    // Full height: the strip is there, the phrase washed in its hemistich.
    expect(find.byTooltip('تصغير'), findsOneWidget);
    final strip = tester.widget<MatnStrip>(inSheet(find.byType(MatnStrip)));
    final second = data.content.matn.verse(226).secondHemistich;
    expect((strip.highlightHemistich, strip.highlight), (2, second.substring(38, 47)));
    expect(tester.widget<QuoteChip>(chip).on, isTrue);
    // The chip is deep in the text: the strip stays pinned under the header while the text scrolls.
    expect(tester.getRect(inSheet(find.byKey(MatnStrip.surfaceKey))).top, closeTo(top(tester) + CommentarySheet.headerExtent + 10, 0.5));
    expect(tester.getRect(chip).top, greaterThan(tester.getRect(inSheet(find.byKey(MatnStrip.surfaceKey))).bottom));
    expect(tester.widget<QuoteChip>(inSheet(find.byWidgetPredicate((w) => w is QuoteChip && w.words == 'واحذفه'))).on, isFalse);
    expect(tester.getSemantics(chip), matchesSemantics(label: 'من البيت: مسهلا', isLink: true, hasTapAction: true));

    // «تصغير» brings it back to rest: the verse shows behind it again.
    await tester.tap(find.byTooltip('تصغير'));
    await loaded(tester);
    expect(inSheet(find.byType(MatnStrip)), findsNothing);
    expect(find.byTooltip('ملء الشاشة'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a passage for several verses: a quotation shows its own verse in the strip', (tester) async {
    final r = await shell(tester);
    r.openCommentary(230);
    await loaded(tester);
    final chip = inSheet(find.byWidgetPredicate((w) => w is QuoteChip && w.words == 'وتهمز واوه'));
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.tap(chip);
    await loaded(tester);
    final strip = tester.widget<MatnStrip>(inSheet(find.byType(MatnStrip)));
    expect((strip.number, strip.current, strip.highlightHemistich), ('٢٣٢', 2, 1));
    expect(strip.highlight, data.content.matn.verse(232).firstHemistich.substring(24, 42));
    expect(strip.caption, 'يشرح الأبيات ${isolatedRange(230, 233)}');
    await unmount(tester);
  });

  testWidgets('the book: a tab changes it and the choice is kept (ADR 0018)', (tester) async {
    final r = await shell(tester);
    r.openCommentary(226);
    await loaded(tester);
    expect(tester.widget<Text>(find.byKey(CommentarySheet.bylineKey)).data, 'عبد الفتاح القاضي · ت ١٤٠٣هـ');
    await tester.tap(inSheet(find.text('سراج القارئ')));
    await loaded(tester);
    expect(tester.widget<Text>(find.byKey(CommentarySheet.bylineKey)).data, 'ابن القاصح العذري · ت ٨٠١هـ');
    final siraj = data.content.books.books.firstWhere((b) => b.shortTitle == 'سراج القارئ').id;
    expect((r.commentaryBook, SettingsStore(r.store!.prefs).commentaryBook), (siraj, siraj));
    expect(tester.getSemantics(inSheet(find.text('سراج القارئ'))),
        matchesSemantics(label: 'سراج القارئ', isButton: true, hasSelectedState: true, isSelected: true, hasTapAction: true, hasFocusAction: true, isFocusable: true));

    // Closed and opened on another verse: the same book.
    r.closeCommentary();
    await tester.pump();
    r.openCommentary(240);
    await loaded(tester);
    expect(tester.widget<Text>(find.byKey(CommentarySheet.bylineKey)).data, startsWith('ابن القاصح'));
    await unmount(tester);
  });

  testWidgets('the text is the reader\'s size; a footnote marker brings its note into view', (tester) async {
    final r = await shell(tester);
    r.setTextScale(1.25);
    r.openCommentary(226);
    await loaded(tester);
    final paragraph = tester
        .widgetList<RichText>(inSheet(find.byType(RichText)))
        .firstWhere((t) => t.textAlign == TextAlign.justify);
    expect((paragraph.text as TextSpan).children!.single.style!.fontSize, closeTo(r.verseSize * 0.92, 0.001));
    expect(r.verseSize, 25);

    // Al-Wafi has two notes on this passage, collected under its text.
    expect(inSheet(find.byType(FootnoteMarker)), findsNWidgets(2));
    final notes = inSheet(find.byType(FootnoteList));
    final view = tester.getRect(find.byKey(CommentarySheet.surfaceKey));
    expect(tester.getRect(notes).top, greaterThan(view.bottom)); // far below at rest
    await tester.ensureVisible(inSheet(find.byType(FootnoteMarker)).first);
    await tester.pump();
    await tester.tap(inSheet(find.byType(FootnoteMarker)).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final after = tester.getRect(notes);
    expect(after.top, lessThan(view.bottom));
    await unmount(tester);
  });

  testWidgets('reading moves the progress line; dragging the sheet down closes it', (tester) async {
    final r = await shell(tester);
    r.openCommentary(226);
    await loaded(tester);
    double fill() => tester
        .getSize(find.descendant(of: find.byKey(CommentarySheet.progressKey), matching: find.byType(DecoratedBox)))
        .width;
    final start = fill();
    // At rest the line already shows the part of the passage in view.
    expect(start, inExclusiveRange(1, 358 * 0.5));
    // The first drag takes the sheet to full height, the next ones read on.
    await tester.dragFrom(Offset(195, top(tester) + 200), const Offset(0, -500));
    await loaded(tester);
    expect(find.byTooltip('تصغير'), findsOneWidget);
    await tester.drag(inSheet(find.byType(MatnStrip)), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final read = fill();
    expect(read, greaterThan(start));
    expect(tester.getSemantics(find.byKey(CommentarySheet.progressKey)).label, 'موضع القراءة');
    // Another passage starts at its top.
    await step(tester, 'البيت ٢٢٧');
    expect(fill(), lessThan(read));
    await step(tester, 'البيت ٢٢٦');

    await tester.tap(find.byTooltip('تصغير'));
    await loaded(tester);
    // A rebuild from the reader (the recitation ticks) does not cut a drag short.
    final drag = await tester.startGesture(tester.getCenter(find.byKey(CommentarySheet.grabKey)));
    await drag.moveBy(const Offset(0, -60));
    await tester.pump();
    r.showNotice('…');
    await tester.pump();
    await drag.moveBy(const Offset(0, -60));
    await tester.pump();
    expect(top(tester), closeTo(418 - 120, 2));
    await drag.moveBy(const Offset(0, 120));
    await drag.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(top(tester), closeTo(418, 1));
    await tester.drag(find.byKey(CommentarySheet.grabKey), const Offset(0, 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(r.commentaryVerse, isNull);
    expect(sheet, findsNothing);
    await unmount(tester);
  });
  testWidgets('a search hit in a book opens the sheet on its verse, in that book', (tester) async {
    final r = await shell(tester);
    final hit = (await tester.runAsync(() => Searcher(data.content).search('مسهلا')))!
        .results
        .commentary
        .firstWhere((h) => !data.content.books.books.firstWhere((b) => b.id == h.bookId).isDefault);
    await tester.tap(find.byTooltip('بحث'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'مسهلا');
    await tester.pump(const Duration(milliseconds: 250));
    await loaded(tester);
    final card = find.text(hit.snippet);
    await tester.scrollUntilVisible(card, 500, scrollable: find.byType(Scrollable).last);
    await tester.tap(card);
    await loaded(tester);
    await tester.pump(const Duration(milliseconds: 500)); // the search screen's way out

    // Back on the reader, the passage in a sheet over it; no pushed screen.
    expect(find.byType(SearchScreen), findsNothing);
    expect(find.byType(CommentaryScreen), findsNothing);
    expect(sheet, findsOneWidget);
    expect((r.commentaryVerse, r.commentaryBook), (hit.fromVerse, hit.bookId));
    final book = data.content.books.books.firstWhere((b) => b.id == hit.bookId);
    expect(find.bySemanticsLabel('الشرح: ${book.shortTitle}'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the sheet ends with the passage and its notes: no source line', (tester) async {
    final r = await shell(tester);
    r.openCommentary(226);
    await loaded(tester);
    expect(inSheet(find.textContaining('المصدر', findRichText: true)), findsNothing);
    expect(inSheet(find.byType(FootnoteList)), findsOneWidget);
    await unmount(tester);
  });
}
