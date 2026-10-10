// The frame a reader symbol sits in (item 3.15, ADR 0024; v2.css .sf, tokens.json
// symbolFrame): a tint and a hairline of the symbol's own rubric ink, painted
// behind the letter. It holds the letter with its tashkeel, moves no glyph,
// never meets the frame on the next line, and with the tip open takes the
// chosen-verse tint and a solid ring. A reader's name has none.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/matn_strip.dart';
import 'package:shatibiyyah/ui/design/components/phrase_wash.dart';
import 'package:shatibiyyah/ui/design/components/rubric.dart';
import 'package:shatibiyyah/ui/design/components/share_card.dart';
import 'package:shatibiyyah/ui/design/components/verse_unit.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'harness.dart';

const v230 = ('وَقُلْ عَادًا الأُوْلَى بِإِسْكَانِ لامِهِ', 'وَتَنْوِينُهُ بِالْكَسْرِ كَاسِيهِ ظَلَّلَا');
// Nine letter symbols: the most of any verse.
const v284 = ('وَفِي ارْكَبْ هُدَى بَرٍّ قَرِيبٍ بِخُلْفِهِمْ', 'كَمَا ضاَعَ جاَ يَلْهَثْ لَهُ دَارِ جُهَّلَا');
// Word symbols with a letter symbol right after them.
const v398 = ('أَرَهْطِي سَمَا مَوْلىً وَمَالِي سَمَا لِوىً', 'لَعَلِّي سَمَا كُفْؤًا مَعِي نَفْرُ الْعُلَا');
// Two word symbols side by side, then two letters.
const v1027 = ('وَفِي تَشْتَهِيهِ تَشْتَهِيْ حَقُّ صُحْبَةٍ', 'وَفِي تُرْجَعُونَ الْغَيْبُ شَايَعَ دُخْلُلَا');

/// The symbol [letters] at the start of [word] in hemistich [half] of [verse].
Rubric symbolIn((String, String) verse, int half, String word, String letters) {
  final at = (half == 1 ? verse.$1 : verse.$2).indexOf(word);
  assert(at >= 0);
  return Rubric.at(at, at + letters.length, hemistich: half, isSymbol: true, label: 'رمز $letters');
}

final marks230 = [symbolIn(v230, 2, 'كَاسِيهِ', 'كَ'), symbolIn(v230, 2, 'ظَلَّلَا', 'ظَ')];
final marks284 = [
  symbolIn(v284, 1, 'هُدَى', 'هُ'),
  symbolIn(v284, 1, 'بَرٍّ', 'بَ'),
  symbolIn(v284, 1, 'قَرِيبٍ', 'قَ'),
  symbolIn(v284, 2, 'كَمَا', 'كَ'),
  symbolIn(v284, 2, 'ضاَعَ', 'ض'),
  symbolIn(v284, 2, 'جاَ', 'ج'),
  symbolIn(v284, 2, 'لَهُ', 'لَ'),
  symbolIn(v284, 2, 'دَارِ', 'دَ'),
  symbolIn(v284, 2, 'جُهَّلَا', 'جُ'),
];
final marks398 = [
  symbolIn(v398, 1, 'سَمَا مَوْلىً', 'سَمَا'),
  symbolIn(v398, 1, 'مَوْلىً', 'مَ'),
  symbolIn(v398, 1, 'سَمَا لِوىً', 'سَمَا'),
  symbolIn(v398, 1, 'لِوىً', 'لِ'),
  symbolIn(v398, 2, 'سَمَا', 'سَمَا'),
  symbolIn(v398, 2, 'كُفْؤًا', 'كُ'),
  symbolIn(v398, 2, 'نَفْرُ', 'نَفْرُ'),
];
final marks1027 = [
  symbolIn(v1027, 1, 'حَقُّ', 'حَقُّ'),
  symbolIn(v1027, 1, 'صُحْبَةٍ', 'صُحْبَةٍ'),
  symbolIn(v1027, 2, 'شَايَعَ', 'شَ'),
  symbolIn(v1027, 2, 'دُخْلُلَا', 'دُ'),
];

VerseUnit unit((String, String) verse, List<Rubric> marks, {double size = 20, Rubric? active, bool playing = false}) =>
    VerseUnit(number: '٢٣٠', first: verse.$1, second: verse.$2, rubrics: marks, fontSize: size, activeSymbol: active, playing: playing);

Iterable<RenderPhraseWash> washes(WidgetTester tester) => tester.renderObjectList<RenderPhraseWash>(find.byType(PhraseWash));

/// Every frame on screen, in global coordinates, with the paragraph it is painted behind.
List<({SymbolFrame frame, RRect box, RenderParagraph text})> frames(WidgetTester tester) => [
      for (final w in washes(tester))
        for (final f in w.frames)
          (frame: f, box: f.box.shift(w.localToGlobal(Offset.zero)), text: w.child! as RenderParagraph),
    ];

/// The baseline of the line of [text] that holds [offset], from the top of the paragraph.
double baselineAt(RenderParagraph text, int offset) {
  final painter = TextPainter(text: text.text, textDirection: text.textDirection, textAlign: text.textAlign)
    ..layout(minWidth: text.size.width, maxWidth: text.size.width);
  final target = painter.getLineBoundary(TextPosition(offset: offset));
  for (final m in painter.computeLineMetrics()) {
    final here = painter.getLineBoundary(painter.getPositionForOffset(Offset(painter.width / 2, m.baseline - 2)));
    if (here.start == target.start) return m.baseline;
  }
  fail('no line of the paragraph holds offset $offset');
}

double _lum(Color c) {
  double f(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  testWidgets('a symbol sits in a frame of its own ink and loses the dotted line; a name has no frame', (tester) async {
    final name = Rubric.at(v230.$1.indexOf('عَادًا'), v230.$1.indexOf('عَادًا') + 6, hemistich: 1);
    await pumpTz(tester, SizedBox(width: 366, child: unit(v230, [name, ...marks230])));
    final got = frames(tester);
    expect(got, hasLength(2));
    final rubric = TzColors.paper.rubric;
    for (final f in got) {
      expect((f.frame.fill, f.frame.line, f.frame.lineWidth, f.frame.ring),
          (rubric.withValues(alpha: TzSymbolFrame.fill), rubric.withValues(alpha: TzSymbolFrame.line), TzSymbolFrame.lineWidth, false));
      expect(f.box.tlRadiusX, closeTo(TzSymbolFrame.radius * 20, 0.01));
    }
    // Both are in the second hemistich; the name's hemistich paints nothing behind its text.
    expect(washes(tester).first.frames, isEmpty);
    final spans = (washes(tester).last.child! as RenderParagraph).text as TextSpan;
    final kaf = spans.children!.cast<TextSpan>().firstWhere((s) => s.text == 'كَ').style!;
    expect((kaf.color, kaf.decoration), (rubric, null));
  });

  testWidgets('the frame holds the letter: 1.3 em above the baseline, 0.52 em below, 0.09 em past each side', (tester) async {
    for (final (verse, marks) in [(v230, marks230), (v284, marks284), (v1027, marks1027)]) {
      await pumpTz(tester, SizedBox(width: 366, child: unit(verse, marks)));
      final got = frames(tester);
      expect(got, hasLength(marks.length));
      for (var i = 0; i < marks.length; i++) {
        final f = got[i], m = marks[i];
        final local = f.box.outerRect.shift(-f.text.localToGlobal(Offset.zero));
        final glyphs = f.text
            .getBoxesForSelection(TextSelection(baseOffset: m.start!, extentOffset: m.end!))
            .map((b) => b.toRect())
            .reduce((a, b) => a.expandToInclude(b));
        final baseline = baselineAt(f.text, m.start!);
        expect(local.top, closeTo(baseline - TzSymbolFrame.above * 20, 0.6), reason: 'top of mark $i');
        expect(local.bottom, closeTo(baseline + TzSymbolFrame.below * 20, 0.6), reason: 'bottom of mark $i');
        expect(local.left, closeTo(glyphs.left - TzSymbolFrame.pad * 20, 0.01), reason: 'left of mark $i');
        expect(local.right, closeTo(glyphs.right + TzSymbolFrame.pad * 20, 0.01), reason: 'right of mark $i');
        // The letter's own box, between the lines above and below, is inside.
        expect(local.left < glyphs.left && local.right > glyphs.right, isTrue);
        expect(local.top < baseline - 20 && local.bottom > baseline + 0.4 * 20, isTrue);
      }
    }
  });

  testWidgets('no glyph moves: the line is laid out the same with frames and without', (tester) async {
    for (final size in [17.0, 20.0, 28.0]) {
      for (final (verse, marks) in [(v230, marks230), (v284, marks284), (v1027, marks1027)]) {
        Future<List<(Size, double?, List<Rect>)>> lines(List<Rubric> rubrics) async {
          await pumpTz(tester, SizedBox(width: 366, child: unit(verse, rubrics, size: size)));
          return [
            for (final w in washes(tester))
              (
                w.size,
                ((w.child! as RenderParagraph).text.style!).wordSpacing,
                [
                  for (final b in (w.child! as RenderParagraph).getBoxesForSelection(
                      TextSelection(baseOffset: 0, extentOffset: (w.child! as RenderParagraph).text.toPlainText().length)))
                    b.toRect(),
                ],
              ),
          ];
        }

        final framed = await lines(marks);
        final plain = await lines(const []);
        expect(framed.length, plain.length);
        for (var i = 0; i < framed.length; i++) {
          expect(framed[i].$1, plain[i].$1, reason: 'size $size, hemistich ${i + 1}');
          expect(framed[i].$2, plain[i].$2, reason: 'justification at $size');
          final a = framed[i].$3.reduce((x, y) => x.expandToInclude(y)), b = plain[i].$3.reduce((x, y) => x.expandToInclude(y));
          expect((a.left, a.right, a.top, a.bottom), (b.left, b.right, b.top, b.bottom));
        }
      }
    }
  });

  testWidgets('at every text size frames never meet: not on the next line, not side by side', (tester) async {
    for (final size in [17.0, 18.5, 20.0, 22.0, 25.0, 28.0]) {
      for (final (verse, marks) in [(v284, marks284), (v398, marks398), (v1027, marks1027)]) {
        await pumpTz(tester, SizedBox(width: 366, child: unit(verse, marks, size: size)));
        final boxes = [for (final f in frames(tester)) f.box.outerRect];
        expect(boxes, hasLength(marks.length));
        for (var i = 0; i < boxes.length; i++) {
          for (var j = i + 1; j < boxes.length; j++) {
            expect(boxes[i].overlaps(boxes[j]), isFalse, reason: 'frames $i and $j at $size');
          }
        }
      }
    }
    // «حَقُّ صُحْبَةٍ»: two word symbols a space apart keep a gap between their frames.
    await pumpTz(tester, SizedBox(width: 366, child: unit(v1027, marks1027)));
    final two = [for (final f in frames(tester).take(2)) f.box.outerRect];
    expect(two[0].left - two[1].right, greaterThan(1));
  });

  test('on lines set tighter than the frame is tall it shrinks in proportion; otherwise it is whole', () {
    final whole = symbolFrameReach(em: 20, lineHeight: 20 * 1.95);
    expect((whole.above, whole.below), (TzSymbolFrame.above * 20, TzSymbolFrame.below * 20));
    final strip = symbolFrameReach(em: 20, lineHeight: 20 * 1.85); // the matn strip: exactly fits
    expect(strip.above + strip.below, closeTo(1.82 * 20, 1e-9));
    final dense = symbolFrameReach(em: 60, lineHeight: 60 * 1.68); // the share card's dense layout
    expect(dense.above + dense.below, closeTo((1.68 - TzSymbolFrame.lineGap) * 60, 1e-9));
    expect(dense.above / dense.below, closeTo(TzSymbolFrame.above / TzSymbolFrame.below, 1e-9));
    expect(dense.above / 60, closeTo(1.179, 0.001)); // v2.css .scard.many --sf-top: 1.35 − 1.179
    final none = symbolFrameReach(em: 20, lineHeight: null);
    expect((none.above, none.below), (TzSymbolFrame.above * 20, TzSymbolFrame.below * 20));
  });

  testWidgets('with its tip open the same box takes the chosen-verse tint and a solid ring', (tester) async {
    await pumpTz(tester, SizedBox(width: 366, child: unit(v230, marks230)));
    final rest = frames(tester).first.box;
    await pumpTz(tester, SizedBox(width: 366, child: unit(v230, marks230, active: marks230.first)));
    var got = frames(tester);
    expect(got.first.box, rest);
    expect((got.first.frame.fill, got.first.frame.line, got.first.frame.lineWidth, got.first.frame.ring),
        (TzColors.paper.lapisWash, TzColors.paper.lapis, TzSymbolFrame.activeLineWidth, true));
    expect(got.last.frame.ring, isFalse); // the other symbol of the verse rests
    // Nothing else is lit behind the letter: the frame is the wash.
    expect(washes(tester).expand((w) => w.painted), isEmpty);

    await pumpTz(tester, SizedBox(width: 366, child: unit(v230, marks230, active: marks230.first)),
        tz: TzTheme.dark.copyWith(nightInk: TzNightPage.wisteria));
    got = frames(tester);
    final ink = TzNightPage.wisteria.accent;
    expect((got.first.frame.fill, got.first.frame.line, got.first.frame.ring), (ink.withValues(alpha: 0.16), ink, true));
    expect((got.last.frame.fill, got.last.frame.line),
        (ink.withValues(alpha: TzSymbolFrame.fill), ink.withValues(alpha: TzSymbolFrame.line)));
  });

  testWidgets('the matn strip frames its symbols; inside a lit quotation the frame keeps its line and drops its fill', (tester) async {
    Widget strip({String? highlight}) => SizedBox(
          width: 362,
          child: MatnStrip(number: '٢٣٠', hemistichs: v230, caption: 'البيت ٢٣٠ · المتن', rubrics: marks230, highlight: highlight),
        );
    await pumpTz(tester, strip());
    var got = frames(tester);
    final rubric = TzColors.paper.rubric;
    expect([for (final f in got) f.frame.fill], [rubric.withValues(alpha: TzSymbolFrame.fill), rubric.withValues(alpha: TzSymbolFrame.fill)]);
    // 0.92 of the verse size on a 1.85 line: the whole frame still fits its line.
    expect(got.first.box.height, closeTo((TzSymbolFrame.above + TzSymbolFrame.below) * 20 * 0.92, 0.01));

    await pumpTz(tester, strip(highlight: 'كَاسِيهِ ظَلَّلَا'));
    got = frames(tester);
    expect([for (final f in got) (f.frame.fill.a, f.frame.line)], [(0.0, rubric.withValues(alpha: TzSymbolFrame.line)), (0.0, rubric.withValues(alpha: TzSymbolFrame.line))]);
    expect(washes(tester).expand((w) => w.painted).single.$2, TzColors.paper.giltWash);
  });

  testWidgets('the share card frames its symbols in the card\'s own rubric', (tester) async {
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final palette in [ShareCardPalette.paper, ShareCardPalette.night(TzNightPage.lapis)]) {
      final style = TzType.verse.copyWith(fontSize: 60, height: 1.9, color: palette.ink);
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: SizedBox(
              width: 900,
              child: ShareCardVerse(
                verse: CardVerse(v230.$1, v230.$2, rubrics: marks230),
                style: style,
                pair: false,
                padBlock: 1,
                rubric: palette.rubric,
              ),
            ),
          ),
        ),
      ));
      final got = frames(tester);
      expect(got, hasLength(2));
      expect((got.first.frame.fill, got.first.frame.line),
          (palette.rubric.withValues(alpha: TzSymbolFrame.fill), palette.rubric.withValues(alpha: TzSymbolFrame.line)));
      expect(got.first.box.height, closeTo((TzSymbolFrame.above + TzSymbolFrame.below) * 60, 0.01));
    }
  });

  test('the letter keeps at least 4.5:1 on its frame, on every surface and in every night ink', () {
    Color over(Color top, Color under) => Color.alphaBlend(top, under);
    final least = <String, double>{};
    void check(String theme, Color ink, Map<String, Color> surfaces) {
      for (final MapEntry(key: name, value: surface) in surfaces.entries) {
        final ratio = contrast(ink, over(ink.withValues(alpha: TzSymbolFrame.fill), surface));
        expect(ratio, greaterThanOrEqualTo(TzSymbolFrame.minContrast), reason: '$theme on $name');
        least[theme] = math.min(least[theme] ?? ratio, ratio);
      }
    }

    const p = TzColors.paper, n = TzColors.night;
    check('paper', p.rubric, {
      'the page': p.bg,
      'the playing verse': over(p.giltWashSoft, p.bg),
      'the chosen verse': over(p.lapisWash, p.bg),
      'the matn strip': p.matnBg,
      'a sheet': p.surface,
      'the share card': ShareCardPalette.paper.background,
    });
    for (final ink in TzNightPage.inks) {
      check(ink.id, ink.accent, {
        'the page': n.bg,
        'the playing verse': over(n.giltWashSoft, n.bg),
        'the chosen verse': over(ink.accent.withValues(alpha: 0.16), n.bg),
        'the matn strip': n.matnBg,
        'a sheet': n.surface,
        'the share card': ShareCardPalette.night(ink).background,
      });
    }
    // The measured floors, so a token change shows what it costs.
    expect(least['paper'], closeTo(5.31, 0.05));
    expect(least.values.reduce(math.min), greaterThan(4.9));
  });
}
