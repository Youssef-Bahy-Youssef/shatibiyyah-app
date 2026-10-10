// Item 3.8 against the handoff (ADR 0021): text mode's reading and playing
// states, the «العرض» sheet with its six sizes and live sample, and the longest
// verses at the largest size.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/ui/design/components/chapter_head.dart';
import 'package:shatibiyyah/ui/design/components/dock.dart';
import 'package:shatibiyyah/ui/design/components/khatam.dart';
import 'package:shatibiyyah/ui/design/components/min_segmented.dart';
import 'package:shatibiyyah/ui/design/components/ornament.dart';
import 'package:shatibiyyah/ui/design/components/text_size_grid.dart';
import 'package:shatibiyyah/ui/design/components/tz_button.dart';
import 'package:shatibiyyah/ui/design/components/tz_picker.dart';
import 'package:shatibiyyah/ui/design/components/tz_sheet.dart';
import 'package:shatibiyyah/ui/design/components/verse_unit.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';
import 'package:shatibiyyah/ui/reader/display_sheet.dart';
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
  Finder unit(int verse) => find.byWidgetPredicate((w) => w is VerseUnit && w.number == ar(verse));

  Future<ReaderController> textMode(WidgetTester tester, {bool audio = true}) async {
    final r = await data.reader(tester, audio: audio, bookmarks: false);
    r.setTextMode(true);
    await pumpPhone(tester, AppShell(reader: r));
    return r;
  }

  testWidgets('textmode-reading: «النص» in the top bar; the chapter\'s head, then its verses as units', (tester) async {
    final spec = HandoffSpec.load('textmode-reading-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    final r = await textMode(tester);
    final c = Conformance(spec);

    // The top bar is the reader's, its folio tag saying «النص» in place of the page.
    final folio = spec.component('Folio tag');
    c.line('folio', rect(tester, find.byKey(ReaderScreen.folioKey)), folio.rect);
    expect(find.descendant(of: find.byKey(ReaderScreen.folioKey), matching: find.text('النص')), findsOneWidget);
    c.line('title', rect(tester, find.text(spec.cls('t-chapter').text!)), spec.cls('t-chapter').rect);

    // The chapter's head: khatam, caption, the full title, the centred gilt rule.
    final head = find.byType(ChapterHead).first;
    final ch = r.chapter;
    c.box('head', rect(tester, head), spec.component('ChapterHead').rect, tol: 1.5);
    c.box('head khatam', rect(tester, find.descendant(of: head, matching: find.byType(Khatam))), spec.id(17).rect);
    final caption = find.descendant(of: head, matching: find.text('الباب الحادي عشر · الأبيات ${isolatedRange(226, 234)} · ٩ أبيات'));
    c.same('caption line', (rect(tester, caption).top - spec.id(19).rect.top).abs() <= 1 && rect(tester, caption).height == 16, true);
    c.same('caption centred', (rect(tester, caption).center.dx - 195).abs() <= 1, true);
    final title = rect(tester, find.descendant(of: head, matching: find.text(ch.title)));
    c.same('title: one line of the verse size under the caption',
        (title.top - spec.cls('ch-title').rect.top).abs() <= 1.5 && (title.height - spec.cls('ch-title').rect.height).abs() <= 1.5, true);
    c.box('gilt rule', rect(tester, find.descendant(of: head, matching: find.byType(GiltRule))), spec.component('GiltRule').rect, tol: 1.5);

    // The verses in view: a 26 dp khatam at the start, the first hemistich from
    // the start, the second to the end, each 93 % of the column.
    final units = [for (final n in spec.nodes) if (n.component == 'VerseUnit' && n.json['covered'] != true) n];
    for (final (i, node) in units.take(4).indexed) {
      final verse = 226 + i;
      final v = data.content.matn.verse(verse);
      final w = tester.widget<VerseUnit>(unit(verse));
      c.box('unit $verse', rect(tester, unit(verse)), node.rect, tol: 1.5);
      final parts = spec.childrenOf(node);
      c.box('khatam $verse', rect(tester, find.descendant(of: unit(verse), matching: find.byType(Khatam))),
          spec.childrenOf(parts[0]).first.rect, tol: 1.5);
      final lines = spec.childrenOf(parts[1]);
      c.box('first hemistich $verse', rect(tester, find.descendant(of: unit(verse), matching: find.byKey(VerseUnit.hemistichKeys[0]))), lines[0].rect, tol: 1.5);
      c.box('second hemistich $verse', rect(tester, find.descendant(of: unit(verse), matching: find.byKey(VerseUnit.hemistichKeys[1]))), lines[1].rect, tol: 1.5);
      c.same('unit $verse: its words, the default size, at rest', (w.first, w.second, w.fontSize, w.playing, w.chosen),
          (v.firstHemistich, v.secondHemistich, 20.0, false, false));
    }

    // Text mode keeps the dock, with what is loaded.
    c.box('dock', rect(tester, find.byKey(Dock.bindingKey)), spec.component('Dock').rect);
    c.done();
    await unmount(tester);
  });

  testWidgets('textmode-playing: the recited verse on the soft gilt wash, a gilt bar outside its start edge', (tester) async {
    final spec = HandoffSpec.load('textmode-playing-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    final r = await textMode(tester);
    await tester.runAsync(() => r.playScope(const PlaybackScope(226, 234)));
    await tester.runAsync(() => r.tapVerse(227));
    await tester.pump(const Duration(milliseconds: 400));
    final c = Conformance(spec);

    final playing = spec.cls('vu playing');
    expect(tester.widget<VerseUnit>(unit(227)).playing, isTrue);
    expect(tester.widget<VerseUnit>(unit(226)).playing, isFalse);
    final surface = rect(tester, find.descendant(of: unit(227), matching: find.byKey(VerseUnit.surfaceKey)));
    c.same('wash: the whole unit', (surface.left, surface.width, surface.height), (playing.rect.left, playing.rect.width, playing.rect.height));
    final bar = rect(tester, find.descendant(of: unit(227), matching: find.byKey(VerseUnit.barKey)));
    c.same('bar: 3 dp, 8 dp outside the start edge, 14 dp short at each end',
        (bar.width, bar.left - surface.right, bar.top - surface.top, surface.bottom - bar.bottom), (3.0, 5.0, 14.0, 14.0));
    final wash = tester.widget<AnimatedContainer>(find.descendant(of: unit(227), matching: find.byKey(VerseUnit.surfaceKey)));
    c.same('wash colour', (wash.decoration! as BoxDecoration).color, TzTheme.paper.colors.giltWashSoft);
    c.done();
    await unmount(tester);
  });

  testWidgets('textmode-display: «العرض» with the page/text choice, six sizes and a live sample', (tester) async {
    final spec = HandoffSpec.load('textmode-display-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    final r = await textMode(tester);
    await tester.tap(find.byTooltip('العرض'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final c = Conformance(spec);
    final sheet = find.byType(DisplaySheet);
    Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);

    // The design's sheet also carries the rubric switch (52 dp), which waits for
    // the span data (item 2.3). So the sheet is shorter: everything is measured
    // from its top.
    final top = rect(tester, inSheet(find.byKey(TzSheet.surfaceKey))).top;
    final from = spec.component('TzSheet (picker)').rect.top;
    Rect at(SpecNode n) => n.rect.translate(0, top - from);
    c.same('the sheet ends at the bottom edge', rect(tester, inSheet(find.byKey(TzSheet.surfaceKey))).bottom, 844.0);
    c.box('grab', rect(tester, inSheet(find.byKey(TzSheet.grabKey))), at(spec.component('SheetGrab')), tol: 1.5);
    c.line('title', rect(tester, inSheet(find.text('العرض'))), at(spec.cls('t-title')), tol: 1.5);
    c.box('page or text', rect(tester, inSheet(find.byKey(MinSegmented.pillKey))), at(spec.component('MinSegmented')), tol: 1.5);
    expect(tester.widget<MinSegmented<bool>>(inSheet(find.byType(MinSegmented<bool>))).selected, isTrue);
    c.line('«حجم نص المتن»', rect(tester, inSheet(find.text('حجم نص المتن'))), at(spec.cls('t-label')), tol: 1.5);
    c.box('sizes', rect(tester, inSheet(find.byType(TextSizeGrid))), at(spec.component('TextSizePicker')), tol: 1.5);
    final sizes = spec.childrenOf(spec.component('TextSizePicker'));
    expect(sizes, hasLength(6));
    for (final (i, percent) in ['٨٥٪', '٩٣٪', '١٠٠٪', '١١٠٪', '١٢٥٪', '١٤٠٪'].indexed) {
      c.box('size $percent', rect(tester, inSheet(find.bySemanticsLabel(percent))), at(sizes[i]), tol: 1.5);
    }
    c.box('sample', rect(tester, find.byKey(DisplaySheet.sampleKey)), at(spec.cls('sample')), tol: 1.5);
    final sample = inSheet(find.byType(VerseUnit));
    c.box('sample verse', rect(tester, sample), at(spec.childrenOf(spec.childrenOf(spec.cls('sample')).first).first), tol: 1.5);
    expect(tester.widget<VerseUnit>(sample).number, '٢٢٦'); // the reader's verse
    expect(inSheet(find.widgetWithText(TzButton, 'تم')), findsOneWidget);
    expect(inSheet(find.byType(TzPicker)), findsOneWidget);
    c.done();

    // A size applies at once, to the sample and to the text behind the sheet.
    await tester.tap(inSheet(find.bySemanticsLabel('١٤٠٪')));
    await tester.pump();
    expect(r.verseSize, 28);
    expect(tester.widget<VerseUnit>(sample).fontSize, 28);
    expect(tester.widget<VerseUnit>(unit(226).first).fontSize, 28);
    await unmount(tester);
  });

  testWidgets('textmode-large: verses 496, 336 and 1056 at 28: every line inside its own line box, nothing fixed', (tester) async {
    final spec = HandoffSpec.load('textmode-large-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    final matn = data.content.matn;
    await pumpPhone(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: [
            for (final n in [496, 336, 1056])
              VerseUnit(number: ar(n), first: matn.verse(n).firstHemistich, second: matn.verse(n).secondHemistich, fontSize: 28),
          ]),
        ),
      ),
    );
    final units = [for (final n in spec.nodes) if (n.component == 'VerseUnit') n];
    expect(units, hasLength(3));
    for (final (i, n) in [496, 336, 1056].indexed) {
      // As many lines as the design wrapped to: its unit's height, within a line.
      final box = rect(tester, unit(n));
      expect((box.height - units[i].rect.height).abs(), lessThanOrEqualTo(28 * 1.95 + 2), reason: 'unit $n is ${box.height}, design ${units[i].rect.height}');
      for (final p in tester.renderObjectList<RenderParagraph>(find.descendant(of: unit(n), matching: find.byType(RichText)))) {
        if (p.text.toPlainText().length < 6) continue; // the khatam's number
        final painter = TextPainter(text: p.text, textDirection: TextDirection.rtl)..layout(maxWidth: p.size.width);
        final lines = painter.computeLineMetrics();
        expect(p.size.height, closeTo(lines.length * 28 * 1.95, 1), reason: 'verse $n: $lines.length lines of 1.95');
        for (final line in lines) {
          // The font's own ascent and descent (the stacked marks included) fit the 1.95 line.
          expect(line.unscaledAscent + line.descent, lessThanOrEqualTo(line.height + 0.5), reason: 'verse $n, line ${line.lineNumber}');
        }
      }
    }
    await unmount(tester);
  });
}
