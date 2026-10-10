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
import 'package:shatibiyyah/ui/design/components/phrase_wash.dart';
import 'package:shatibiyyah/ui/design/components/symbol_tip.dart';
import 'package:shatibiyyah/ui/design/components/text_size_grid.dart';
import 'package:shatibiyyah/ui/design/components/tz_button.dart';
import 'package:shatibiyyah/ui/design/components/tz_picker.dart';
import 'package:shatibiyyah/ui/design/components/tz_sheet.dart';
import 'package:shatibiyyah/ui/design/components/tz_switch.dart';
import 'package:shatibiyyah/ui/design/components/verse_unit.dart';
import 'package:shatibiyyah/ui/design/tz_icon.dart';
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

    // Reader names in the rubric ink, where the design sets them.
    final marks = [for (final n in spec.nodes) if (n.component == 'Rubric span' && n.json['covered'] != true) n];
    final verse226 = tester.state<VerseUnitState>(unit(226));
    final warsh = rect(tester, unit(226)) == Rect.zero ? null : verse226.symbolRect(verse226.rubrics.single);
    c.same('«لِوَرْشٍ»: its words across the line',
        ((warsh!.left - marks.first.rect.left).abs() <= 1.5, (warsh.right - marks.first.rect.right).abs() <= 1.5), (true, true));
    final spans = tester.widgetList<RichText>(find.descendant(of: unit(226), matching: find.byType(RichText))).first.text as TextSpan;
    c.same('rubric ink', spans.children!.cast<TextSpan>().firstWhere((s) => s.text == 'لِوَرْشٍ').style!.color, TzTheme.paper.rubric);

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

  testWidgets('textmode-symbol: each symbol in its frame, one lit, its tip 12 dp under it', (tester) async {
    final spec = HandoffSpec.load('textmode-symbol-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    final r = await textMode(tester);
    await tester.runAsync(() => r.tapVerse(229));
    await tester.pumpAndSettle();
    final state = tester.state<VerseUnitState>(unit(230));
    final kaf = state.rubrics.first;
    r.openSymbol(230, kaf);
    await tester.pump();
    final c = Conformance(spec);

    // The letter: the rubric ink in its frame (ADR 0024). The frame is measured from the letter and
    // from its line: the design scrolls its list to another place, and shapes the words a little differently.
    final lit = spec.cls('rb sym on');
    final letter = state.symbolRect(kaf)!;
    c.same('letter width', (letter.width - lit.rect.width).abs() <= 1.5, true);
    final washes = tester.renderObjectList<RenderPhraseWash>(find.descendant(of: unit(230), matching: find.byType(PhraseWash)));
    c.same('nothing else is lit behind the words', washes.expand((w) => w.painted).isEmpty, true);
    final frames = [
      for (final w in washes)
        for (final f in w.frames) (frame: f, box: f.box.outerRect.shift(w.localToGlobal(Offset.zero))),
    ];
    final specFrames = [for (final n in spec.nodes) if (n.component == 'SymbolFrame') n];
    c.same('two symbols, two frames', (frames.length, specFrames.length), (2, 2));
    final line = rect(tester, find.descendant(of: unit(230), matching: find.byKey(VerseUnit.hemistichKeys[1])));
    final specLine = spec.id(spec.id(spec.id(specFrames.first.json['parent'] as int).json['parent'] as int).json['parent'] as int);
    c.same('the frames hang from the second hemistich', specLine.cls, 'hm h2');
    for (var i = 0; i < 2; i++) {
      final f = frames[i], n = specFrames[i], span = spec.id(n.json['parent'] as int);
      final glyphs = state.symbolRect(state.rubrics[i])!;
      c.same('frame $i: height', (f.box.height - n.rect.height).abs() <= 0.5, true);
      c.same('frame $i: under the top of its line', ((f.box.top - line.top) - (n.rect.top - specLine.rect.top)).abs() <= 1, true);
      c.same('frame $i: past the letter on each side',
          ((glyphs.left - f.box.left) - (span.rect.left - n.rect.left)).abs() <= 0.5 &&
              ((f.box.right - glyphs.right) - (n.rect.right - span.rect.right)).abs() <= 0.5,
          true);
      c.same('frame $i: radius', (f.frame.box.tlRadiusX - double.parse((n.json['radius'] as String).replaceFirst('px', ''))).abs() <= 0.01, true);
    }
    // Lit: the lapis wash and a solid 1.5 dp lapis ring. At rest: 9 % and a 28 % hairline of the rubric.
    final paper = TzTheme.paper.colors;
    c.same('the lit frame', (frames[0].frame.fill, frames[0].frame.line, frames[0].frame.lineWidth, frames[0].frame.ring),
        (paper.lapisWash, paper.lapis, 1.5, true));
    c.same('the lit frame in the spec', (specFrames[0].tokens('background').join(), specFrames[0].json['shadow']),
        ('lapis-wash', 'rgb(36, 65, 127) 0px 0px 0px 1.5px'));
    c.same('the frame at rest', (frames[1].frame.fill, frames[1].frame.line, frames[1].frame.lineWidth, frames[1].frame.ring),
        (paper.rubric.withValues(alpha: 0.09), paper.rubric.withValues(alpha: 0.28), 1.0, false));
    c.same('the frame at rest in the spec', (specFrames[1].json['background'], specFrames[1].json['shadow']), (
      'color(srgb 0.556863 0.164706 0.352941 / 0.09)',
      'color(srgb 0.556863 0.164706 0.352941 / 0.28) 0px 0px 0px 1px inset',
    ));
    final second = tester.widgetList<RichText>(find.descendant(of: unit(230), matching: find.byType(RichText))).last.text as TextSpan;
    final span = second.children!.cast<TextSpan>().firstWhere((s) => s.text == 'كَ').style!;
    c.same('letter ink, no line under it', (span.color, span.decoration), (TzTheme.paper.rubric, null));

    // The tip, measured from the letter: the design scrolls its list to another place.
    final tip = spec.component('SymbolTip');
    final box = rect(tester, find.byKey(SymbolTip.surfaceKey));
    c.same('tip: 16 dp from the sides, 70 dp high', (box.left, box.width, box.height), (tip.rect.left, tip.rect.width, tip.rect.height));
    c.same('tip: 12 dp under the letter', (box.top - letter.bottom - (tip.rect.top - lit.rect.bottom)).abs() <= 2, true);
    Rect at(SpecNode n) => n.rect.translate(0, box.top - tip.rect.top);
    c.box('code', rect(tester, find.byKey(SymbolTip.codeKey)), at(spec.cls('code')));
    final caption = spec.nodes.firstWhere((n) => (n.text ?? '').startsWith('رمز حرفي'));
    c.line('who', rect(tester, find.descendant(of: find.byType(SymbolTip), matching: find.text('ابن عامر'))), at(spec.text('ابن عامر')));
    c.line('caption', rect(tester, find.descendant(of: find.byType(SymbolTip), matching: find.text(caption.text!))), at(caption));
    final button = spec.text('رموز القراء');
    final b = find.descendant(of: find.byType(SymbolTip), matching: find.byType(TzButton));
    c.centre('«رموز القراء»', rect(tester, b), at(button));
    c.same('button: a 48 dp target', tester.getSize(b).height, 48.0);
    c.same('code ink', tester.widget<Text>(find.descendant(of: find.byKey(SymbolTip.codeKey), matching: find.byType(Text))).data, 'كَ');
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

    Rect at(SpecNode n) => n.rect;
    c.box('sheet', rect(tester, inSheet(find.byKey(TzSheet.surfaceKey))), spec.component('TzSheet (picker)').rect, tol: 1.5);
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

    // The rubric switch: the icon, the label, the word and the switch; then «تم».
    final row = spec.cls('prow');
    c.box('rubric row', rect(tester, find.byKey(DisplaySheet.rubricRowKey)), row.rect, tol: 1.5);
    final parts = spec.childrenOf(row);
    c.box('row icon', rect(tester, find.descendant(of: find.byKey(DisplaySheet.rubricRowKey), matching: find.byType(TzIcon))), parts[0].rect, tol: 1.5);
    c.line('row label', rect(tester, inSheet(find.text(parts[1].text!))), parts[1].rect, tol: 1.5);
    c.box('switch', rect(tester, inSheet(find.byKey(TzSwitch.trackKey))), spec.component('TzSwitch').rect, tol: 1.5);
    expect(inSheet(find.text('ظاهر')), findsOneWidget);
    c.box('«تم»', rect(tester, inSheet(find.widgetWithText(TzButton, 'تم'))), spec.text('تم').rect, tol: 1.5);
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
