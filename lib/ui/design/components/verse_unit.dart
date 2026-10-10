// lib/ui/design/components/verse_unit.dart — a verse of the matn as a unit
// (item 3.3, ADR 0021; v2.js verseUnit(), v2.css .vu, .hm).
//
// A 26 px khatam in the start margin, then the two hemistichs: the first starts
// at the start, the second ends at the end, each 93 % of the column wide. A
// hemistich is justified only when its natural width fills at least 84 % of its
// column on one line; short ones stay ragged. At 600 px or wider (the prototype's
// container query) they sit side by side, 2.4 em apart. Reader names and symbols
// are in the rubric ink. Playing is the soft gilt wash with a 3 px gilt bar just
// outside the start edge; chosen is a 2 px ring and a tint (lapis on paper, the
// reader's night ink at night). The background changes in 320 ms.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';
import 'khatam.dart';
import 'phrase_wash.dart';
import 'rubric.dart';
import 'tz_motion.dart';

/// The default verse size in text mode (v2.css --verse-size; ADR 0021).
const double kVerseSize = 20;

/// The word spacing to add so one line of [natural] width fills [column]: none
/// unless it fits on one line and already fills 84 % of it.
double justifyGap({required double natural, required double column, required int spaces}) {
  if (spaces == 0 || natural > column || natural < column * 0.84) return 0;
  return (column - natural) / spaces;
}

/// One hemistich: [widthFactor] of its column, at the start or the end, justified by the 84 % rule.
class Hemistich extends StatelessWidget {
  final String text;
  final List<Rubric> rubrics;
  final TextStyle style;
  final double widthFactor;
  final bool atEnd;

  /// A key for the hemistich's own box (its [widthFactor] of the column).
  final Key? boxKey;

  /// A phrase washed in gilt (a matn quote being read).
  final String? highlight;

  /// The rubric ink, when it is not the theme's (the share card has its own palette).
  final Color? rubricColor;

  /// The space above and below the line (v2.css .hm padding-block).
  final double padBlock;

  /// The symbol whose tip is open: lit from behind (v2.css .rb.sym.on).
  final Rubric? activeSymbol;

  /// A key for the text itself, to find where its words are.
  final Key? textKey;

  const Hemistich({
    super.key,
    required this.text,
    required this.rubrics,
    required this.style,
    this.widthFactor = 0.93,
    this.atEnd = false,
    this.boxKey,
    this.highlight,
    this.rubricColor,
    this.padBlock = 1,
    this.activeSymbol,
    this.textKey,
  });

  @override
  Widget build(BuildContext context) {
    final tz = TzTheme.of(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * widthFactor;
        final spans = rubricate(text, rubrics, rubricColor ?? tz.rubric);
        // The lit phrase (a quotation of the verse, chosen in its commentary).
        final lit = highlight == null || highlight!.isEmpty ? -1 : text.indexOf(highlight!);
        final natural = (TextPainter(
          text: TextSpan(style: style, children: spans),
          textDirection: direction,
        )..layout()).width;
        final gap = justifyGap(natural: natural, column: width, spaces: ' '.allMatches(text).length);
        return Align(
          alignment: atEnd ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
          child: SizedBox(
            key: boxKey,
            width: width,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: padBlock),
              child: PhraseWash(
                washes: [
                  // v2.css mark.mqhl: the gilt wash, 2 px past the words, on a 4 px radius.
                  if (lit >= 0)
                    (start: lit, end: lit + highlight!.length, color: tz.colors.giltWash, spread: 2, radius: 6),
                  // v2.css .rb.sym.on: the lapis wash (the night ink's tint), 3 px past the letter.
                  for (final m in rubrics)
                    if (m.sameMark(activeSymbol))
                      (
                        start: m.start!,
                        end: m.end!,
                        color: tz.night ? tz.nightInk.accent.withValues(alpha: 0.16) : tz.colors.lapisWash,
                        spread: 3,
                        radius: 7,
                      ),
                ],
                child: RichText(
                  key: textKey,
                  textAlign: atEnd ? TextAlign.end : TextAlign.start,
                  textDirection: direction,
                  text: TextSpan(
                    style: style.copyWith(wordSpacing: gap == 0 ? null : gap),
                    children: spans,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class VerseUnit extends StatefulWidget {
  final String number; // «٢٢٦»
  final String first, second;
  final List<Rubric> rubrics;
  final bool playing, chosen;
  final double fontSize;
  final VoidCallback? onTap, onDoubleTap, onLongPress;

  /// A tap on a reader symbol (a mark with [Rubric.isSymbol]): its tip. The
  /// letter is small, so the tap may land up to 24 px from its centre.
  final ValueChanged<Rubric>? onSymbol;

  /// The symbol whose tip is open.
  final Rubric? activeSymbol;

  const VerseUnit({
    super.key,
    required this.number,
    required this.first,
    required this.second,
    this.rubrics = const [],
    this.playing = false,
    this.chosen = false,
    this.fontSize = kVerseSize,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onSymbol,
    this.activeSymbol,
  });

  static const surfaceKey = ValueKey('verse-unit-surface');
  static const barKey = ValueKey('verse-unit-bar');
  static const hemistichKeys = [ValueKey('verse-unit-h1'), ValueKey('verse-unit-h2')];

  @override
  State<VerseUnit> createState() => VerseUnitState();
}

class VerseUnitState extends State<VerseUnit> {
  // The two hemistichs' texts, to find a symbol's letter under a tap.
  final _texts = [GlobalKey(), GlobalKey()];
  Offset? _tapAt;

  /// Where the mark [mark] is on screen, or null when it is not laid out.
  Rect? symbolRect(Rubric mark) {
    final half = mark.hemistich, from = mark.start, to = mark.end;
    if (half == null || from == null || to == null) return null;
    final text = _texts[half - 1].currentContext?.findRenderObject();
    if (text is! RenderParagraph || !text.hasSize) return null;
    final boxes = text.getBoxesForSelection(TextSelection(baseOffset: from, extentOffset: to));
    if (boxes.isEmpty) return null;
    final box = boxes.map((b) => b.toRect()).reduce((a, b) => a.expandToInclude(b));
    return text.localToGlobal(box.topLeft) & box.size;
  }

  /// The symbol under a tap at [at]: the nearest whose letter, widened to a
  /// 48 px target (handoff rule 6), holds the point.
  Rubric? _symbolAt(Offset at) {
    Rubric? best;
    var nearest = double.infinity;
    for (final mark in widget.rubrics) {
      if (!mark.isSymbol) continue;
      final box = symbolRect(mark);
      if (box == null) continue;
      final target = Rect.fromCenter(
          center: box.center,
          width: math.max(box.width, TzSize.touchTarget),
          height: math.max(box.height, TzSize.touchTarget));
      final distance = (at - box.center).distance;
      if (target.contains(at) && distance < nearest) (best, nearest) = (mark, distance);
    }
    return best;
  }

  void _tap() {
    final at = _tapAt;
    final symbol = widget.onSymbol == null || at == null ? null : _symbolAt(at);
    symbol != null ? widget.onSymbol!(symbol) : widget.onTap?.call();
  }

  String get number => widget.number;
  String get first => widget.first;
  String get second => widget.second;
  List<Rubric> get rubrics => widget.rubrics;
  bool get playing => widget.playing;
  bool get chosen => widget.chosen;
  double get fontSize => widget.fontSize;
  VoidCallback? get onTap => widget.onTap;
  VoidCallback? get onDoubleTap => widget.onDoubleTap;
  VoidCallback? get onLongPress => widget.onLongPress;

  @override
  Widget build(BuildContext context) {
    final tz = TzTheme.of(context), c = tz.colors;
    final style = TzType.verse.copyWith(fontSize: fontSize, height: 1.95, color: c.verseInk);
    final (Color? fill, Color? ring) = chosen
        ? (tz.night ? (tz.nightInk.accent.withValues(alpha: 0.16), tz.nightInk.accent) : (c.lapisWash, c.lapis))
        : (playing ? (c.giltWashSoft, null) : (null, null));
    final symbols = widget.onSymbol == null ? const <Rubric>[] : [for (final m in rubrics) if (m.isSymbol && m.label != null) m];
    return Semantics(
      label: 'البيت $number: $first، $second',
      button: onTap != null,
      onTap: onTap,
      onLongPress: onLongPress,
      // The verse stays one item; each of its symbols is an action on it.
      customSemanticsActions: {
        for (final m in symbols) CustomSemanticsAction(label: m.label!): () => widget.onSymbol!(m),
      },
      excludeSemantics: true,
      child: GestureDetector(
        onTapUp: (d) => _tapAt = d.globalPosition,
        onTap: onTap == null && widget.onSymbol == null ? null : _tap,
        onDoubleTap: onDoubleTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              key: VerseUnit.surfaceKey,
              duration: tzDuration(context, TzMotion.long),
              curve: TzMotion.standard,
              // v2.css padding 12/4/14, less the 2 px ring (an inset shadow there, a border here).
              padding: const EdgeInsets.fromLTRB(2, 10, 2, 12),
              decoration: BoxDecoration(
                color: fill ?? c.giltWashSoft.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(TzRadius.control),
                border: Border.all(color: ring ?? (fill ?? c.lapis).withValues(alpha: 0), width: 2),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: (fontSize * 1.95 - 26) / 2),
                    child: Khatam(number, size: 26),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth + 26 + 8 + 8 >= 600;
                        final h1 = Hemistich(
                          boxKey: VerseUnit.hemistichKeys[0],
                          textKey: _texts[0],
                          activeSymbol: widget.activeSymbol,
                          text: first,
                          rubrics: rubricsOf(rubrics, 1),
                          style: style,
                          widthFactor: wide ? 1 : 0.93,
                        );
                        final h2 = Hemistich(
                          boxKey: VerseUnit.hemistichKeys[1],
                          textKey: _texts[1],
                          activeSymbol: widget.activeSymbol,
                          text: second,
                          rubrics: rubricsOf(rubrics, 2),
                          style: style,
                          widthFactor: wide ? 1 : 0.93,
                          atEnd: !wide,
                        );
                        return wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: h1),
                                  SizedBox(width: fontSize * 2.4),
                                  Expanded(child: h2),
                                ],
                              )
                            : Column(mainAxisSize: MainAxisSize.min, children: [h1, h2]);
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (playing)
              PositionedDirectional(
                start: -8,
                top: 14,
                bottom: 14,
                child: Container(
                  key: VerseUnit.barKey,
                  width: 3,
                  decoration: BoxDecoration(color: c.gilt, borderRadius: BorderRadius.circular(2)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
