// Item 3.9 against the handoff (ADRs 0014, 0018, 0022): the commentary as a sheet
// tied to its verse. At rest over text mode and over the page, at full height
// with the matn strip, a passage that explains several verses, and another book.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/commentary/commentary_sheet.dart';
import 'package:shatibiyyah/ui/design/components/binding_stepper.dart';
import 'package:shatibiyyah/ui/design/components/commentary_inline.dart';
import 'package:shatibiyyah/ui/design/components/dock.dart';
import 'package:shatibiyyah/ui/design/components/khatam.dart';
import 'package:shatibiyyah/ui/design/components/matn_strip.dart';
import 'package:shatibiyyah/ui/design/components/verse_unit.dart';
import 'package:shatibiyyah/ui/design/tz_icon.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/reader/reader_screen.dart';
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
  final sheet = find.byType(CommentarySheet);
  Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);

  /// Lets the passage load from the real database, then draws it.
  Future<void> loaded(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<ReaderController> open(WidgetTester tester,
      {bool text = true, int verse = 226, String? book, bool full = false, TzTheme tz = TzTheme.paper}) async {
    final r = await data.reader(tester, audio: true, bookmarks: !text);
    r.setTextMode(text);
    if (book != null) r.setCommentaryBook(data.content.books.books.firstWhere((b) => b.shortTitle == book).id);
    await pumpPhone(tester, AppShell(reader: r), tz: tz);
    r.openCommentary(verse);
    await loaded(tester);
    if (full) {
      await tester.tap(find.byTooltip('ملء الشاشة'));
      await loaded(tester);
    }
    return r;
  }

  /// The sheet's own frame and header, the same in every state.
  void header(WidgetTester tester, HandoffSpec spec, Conformance c, {required String book, required String range}) {
    final surface = spec.component('TzSheet (commentary)');
    c.box('sheet', rect(tester, find.byKey(CommentarySheet.surfaceKey)), surface.rect);
    c.box('grab', rect(tester, find.byKey(CommentarySheet.grabKey)), spec.component('SheetGrab').rect);

    // A tab per book from the start edge, the chosen one in ink over a lapis line.
    final tabs = spec.childrenOf(spec.component('CommentaryBookTabs'));
    final colors = TzTheme.paper.colors;
    for (final tab in tabs) {
      final label = find.descendant(of: sheet, matching: find.text(tab.text!));
      final on = tab.text == book;
      c.same('tab «${tab.text}»: across', (rect(tester, label).left - tab.rect.left).abs() <= 1 && (rect(tester, label).right - tab.rect.right).abs() <= 1, true);
      c.same('tab «${tab.text}»: its line of text', (rect(tester, label).top - (tab.rect.top + 10.8)).abs() <= 1, true);
      final style = tester.widget<Text>(label).style!;
      c.same('tab «${tab.text}»: ink', (style.color, style.fontWeight), on ? (colors.ink, FontWeight.w600) : (colors.ink3, FontWeight.w500));
      final target = tester.getSize(find.ancestor(of: label, matching: find.byType(InkWell)).first);
      c.same('tab «${tab.text}»: a 48 dp target', target.height, 48.0);
    }
    final buttons = [for (final n in spec.nodes) if (n.cls == 'ib' && n.rect.top > surface.rect.top) n];
    final size = find.byTooltip(spec.name.contains('half') || spec.name.contains('page') ? 'ملء الشاشة' : 'تصغير');
    c.centre('expand or collapse', rect(tester, size), buttons[0].rect);
    c.centre('close', rect(tester, find.byTooltip('إغلاق الشرح')), buttons[1].rect);
    c.same('targets', (tester.getSize(size), tester.getSize(find.byTooltip('إغلاق الشرح'))), (const Size(48, 48), const Size(48, 48)));

    // The byline at the start, the verse (or verses) at the end.
    final by = spec.childrenOf(spec.cls('c-by t-cap'));
    final byline = rect(tester, find.byKey(CommentarySheet.bylineKey));
    c.same('byline: from the start edge on its line', ((byline.right - by[0].rect.right).abs() <= 1, (byline.top - by[0].rect.top).abs() <= 1, byline.height), (true, true, 16.0));
    c.box('the verse', rect(tester, find.byKey(CommentarySheet.rangeKey)), by[1].rect, tol: 1.5);
    expect(tester.widget<Text>(find.byKey(CommentarySheet.rangeKey)).data, range);
    c.box('progress line', rect(tester, find.byKey(CommentarySheet.progressKey)), spec.cls('c-prog').rect);
  }

  void stepper(WidgetTester tester, HandoffSpec spec, Conformance c) {
    final node = spec.component('BindingStepper');
    c.box('stepper', rect(tester, inSheet(find.byKey(BindingStepper.bindingKey))), node.rect);
    final parts = spec.childrenOf(node);
    expect(inSheet(find.text(parts[0].text!)), findsOneWidget);
    expect(inSheet(find.text(parts[2].text!)), findsOneWidget);
    expect(inSheet(find.text(parts[1].text!)), findsOneWidget);
    final khatam = spec.childrenOf(parts[1]).first;
    final k = inSheet(find.descendant(of: find.byKey(BindingStepper.bindingKey), matching: find.byType(Khatam)));
    c.box('place in the chapter', rect(tester, k), khatam.rect, tol: 1.5);
    c.same('place', tester.widget<Khatam>(k).label, khatam.text);
  }

  testWidgets('commentary-half: under the chosen verse, a notch pointing at it; the dock gives way', (tester) async {
    final spec = HandoffSpec.load('commentary-half-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    await open(tester);
    final c = Conformance(spec);
    header(tester, spec, c, book: 'الوافي', range: 'البيت ٢٢٦');

    // The verse stays where it was, ringed, all of it above the sheet.
    final unit = find.byWidgetPredicate((w) => w is VerseUnit && w.number == ar(226));
    c.box('the verse', rect(tester, unit), spec.cls('vu chosen').rect, tol: 1.5);
    expect(tester.widget<VerseUnit>(unit).chosen, isTrue);
    expect(rect(tester, unit).bottom, lessThan(rect(tester, find.byKey(CommentarySheet.surfaceKey)).top));
    c.centre('notch', rect(tester, find.byKey(CommentarySheet.notchKey)), spec.cls('notch').rect);
    expect(find.byKey(Dock.bindingKey), findsNothing);
    expect(inSheet(find.byType(MatnStrip)), findsNothing); // the matn appears once: behind the sheet

    // The key to the three kinds of quoted text, then the passage.
    c.box('legend', rect(tester, find.byType(CommentaryLegend)), spec.cls('legend').rect);
    final heading = spec.cls('seg-h');
    c.box('heading', rect(tester, find.byType(SegmentHeading)).deflate(0).topLeft & Size(350, rect(tester, find.byType(SegmentHeading)).height),
        Rect.fromLTWH(heading.rect.left, heading.rect.top - 14, 350, 34));
    c.line('heading word', rect(tester, inSheet(find.text('المعنى'))), Rect.fromLTRB(0, heading.rect.top, heading.rect.right - 14, heading.rect.bottom));
    final first = rect(tester, inSheet(find.byType(RichText)).at(_firstParagraph(tester, sheet)));
    final p = spec.nodes.firstWhere((n) => n.json['tag'] == 'p' && n.cls.isEmpty);
    c.same('first paragraph: the column, under the heading', ((first.left - p.rect.left).abs() <= 1, (first.right - p.rect.right).abs() <= 1, (first.top - p.rect.top).abs() <= 1.5), (true, true, true));
    stepper(tester, spec, c);
    c.done();
    await unmount(tester);
  });

  testWidgets('commentary-page: over the page, 102 dp under the ringed verse', (tester) async {
    final spec = HandoffSpec.load('commentary-page-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    await open(tester, text: false);
    final c = Conformance(spec);
    header(tester, spec, c, book: 'الوافي', range: 'البيت ٢٢٦');
    final spot = spec.component('VerseHighlight');
    c.box('ring', rect(tester, find.byKey(ReaderScreen.explainedRingKey)), spot.rect.inflate(2), tol: 1.5);
    final ring = tester.widget<DecoratedBox>(find.descendant(of: find.byKey(ReaderScreen.explainedRingKey), matching: find.byType(DecoratedBox)));
    c.same('ring: 2 dp of lapis', (ring.decoration as BoxDecoration).border, Border.all(color: TzTheme.paper.colors.lapis, width: 2));
    c.centre('notch', rect(tester, find.byKey(CommentarySheet.notchKey)), spec.cls('notch').rect);
    expect(find.byType(CommentaryLegend), findsNothing);
    expect(inSheet(find.byType(MatnStrip)), findsNothing);
    final heading = spec.cls('seg-h');
    c.line('heading word', rect(tester, inSheet(find.text('المعنى'))), Rect.fromLTRB(0, heading.rect.top, heading.rect.right - 14, heading.rect.bottom));
    stepper(tester, spec, c);
    c.done();
    await unmount(tester);
  });

  testWidgets('commentary-full: 10 dp under the status bar, the verse in a strip over the text', (tester) async {
    final spec = HandoffSpec.load('commentary-full-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    await open(tester, full: true);
    final c = Conformance(spec);
    header(tester, spec, c, book: 'الوافي', range: 'البيت ٢٢٦');
    expect(find.byKey(CommentarySheet.notchKey), findsNothing);
    expect(find.byType(CommentaryLegend), findsNothing);

    final strip = spec.component('MatnStrip');
    c.box('strip', rect(tester, inSheet(find.byKey(MatnStrip.surfaceKey))), strip.rect, tol: 1.5);
    c.line('strip caption', rect(tester, inSheet(find.text('البيت ٢٢٦ · المتن'))), spec.text('البيت ٢٢٦ · المتن').rect);
    final khatam = spec.nodes.firstWhere((n) => n.component == 'Khatam' && n.rect.top > strip.rect.top && n.rect.bottom < strip.rect.bottom);
    c.box('strip khatam', rect(tester, inSheet(find.descendant(of: find.byType(MatnStrip), matching: find.byType(Khatam)))), khatam.rect, tol: 1.5);
    final w = tester.widget<MatnStrip>(inSheet(find.byType(MatnStrip)));
    final v = data.content.matn.verse(226);
    c.same('strip: the verse, its reader named in the rubric', (w.hemistichs, w.rubrics.length, w.verses.isEmpty), ((v.firstHemistich, v.secondHemistich), 1, true));
    expect(v.firstHemistich.substring(w.rubrics.single.start!, w.rubrics.single.end!), 'لِوَرْشٍ');

    // The passage starts under the strip.
    final body = spec.cls('c-body');
    final top = rect(tester, find.byType(SegmentHeading)).top;
    c.same('text under the strip', (top - (body.rect.top + 6)).abs() <= 1.5, true);
    expect(tester.widget<TzIcon>(find.descendant(of: find.byTooltip('تصغير'), matching: find.byType(TzIcon))).name, 'collapse');
    stepper(tester, spec, c);
    c.done();
    await unmount(tester);
  });

  testWidgets('commentary-grouped: one passage for verses 230–233, a chip per verse', (tester) async {
    final spec = HandoffSpec.load('commentary-grouped-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    await open(tester, verse: 231, full: true);
    final c = Conformance(spec);
    header(tester, spec, c, book: 'الوافي', range: 'الأبيات ${isolatedRange(230, 233)}');
    final strip = spec.component('MatnStrip');
    c.box('strip', rect(tester, inSheet(find.byKey(MatnStrip.surfaceKey))), strip.rect, tol: 1.5);
    final w = tester.widget<MatnStrip>(inSheet(find.byType(MatnStrip)));
    expect(w.verses, ['٢٣٠', '٢٣١', '٢٣٢', '٢٣٣']);
    c.same('strip: the chosen verse current', (w.current, w.number), (1, '٢٣١'));
    for (final chip in [for (final n in spec.nodes) if (n.cls == 'vchip') n]) {
      c.centre('chip ${chip.text}', rect(tester, inSheet(find.text(chip.text!))), chip.rect, tol: 1.5);
    }
    final heading = spec.cls('seg-h');
    c.line('heading word', rect(tester, inSheet(find.text('المعنى'))), Rect.fromLTRB(0, heading.rect.top, heading.rect.right - 14, heading.rect.bottom), tol: 1.5);
    stepper(tester, spec, c);

    // Another chip shows that verse; the passage stays.
    await tester.tap(inSheet(find.text('٢٣٣')));
    await tester.pump();
    final after = tester.widget<MatnStrip>(inSheet(find.byType(MatnStrip)));
    expect((after.number, after.current, after.hemistichs.$1), ('٢٣٣', 3, data.content.matn.verse(233).firstHemistich));
    c.done();
    await unmount(tester);
  });

  testWidgets('commentary-siraj: another book, its own byline, its verse references quiet', (tester) async {
    final spec = HandoffSpec.load('commentary-siraj-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    await open(tester, book: 'سراج القارئ', full: true);
    final c = Conformance(spec);
    header(tester, spec, c, book: 'سراج القارئ', range: 'البيت ٢٢٦');
    final by = spec.childrenOf(spec.cls('c-by t-cap'));
    c.box('byline', rect(tester, find.byKey(CommentarySheet.bylineKey)).intersect(Rect.fromLTWH(by[0].rect.left - 1, 0, 400, 900)), by[0].rect, tol: 1.5);
    expect(tester.widget<Text>(find.byKey(CommentarySheet.bylineKey)).data, by[0].text);
    c.box('strip', rect(tester, inSheet(find.byKey(MatnStrip.surfaceKey))), spec.component('MatnStrip').rect, tol: 1.5);
    // No heading in this book: the passage starts 6 dp under the strip.
    expect(find.byType(SegmentHeading), findsNothing);
    stepper(tester, spec, c);
    c.done();
    await unmount(tester);
  });

  testWidgets('night: the sheet on the night surface; the page verse ringed in the chosen ink', (tester) async {
    final spec = HandoffSpec.load('commentary-page-night');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    await open(tester, text: false, tz: TzTheme.dark);
    final c = Conformance(spec);
    c.box('sheet', rect(tester, find.byKey(CommentarySheet.surfaceKey)), spec.component('TzSheet (commentary)').rect);
    final ring = tester.widget<DecoratedBox>(find.descendant(of: find.byKey(ReaderScreen.explainedRingKey), matching: find.byType(DecoratedBox)));
    final ink = TzTheme.dark.nightInk.accent;
    c.same('ring: the night ink over its tint', ((ring.decoration as BoxDecoration).border, (ring.decoration as BoxDecoration).color),
        (Border.all(color: ink, width: 2), ink.withValues(alpha: 0.16)));
    c.done();
    await unmount(tester);
  });
}

/// The index, among the sheet's rich texts, of the passage's first paragraph (the justified one).
int _firstParagraph(WidgetTester tester, Finder sheet) {
  final all = tester.widgetList<RichText>(find.descendant(of: sheet, matching: find.byType(RichText))).toList();
  return all.indexWhere((t) => t.textAlign == TextAlign.justify);
}
