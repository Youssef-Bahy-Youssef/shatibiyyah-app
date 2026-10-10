// lib/ui/design/components/share_card.dart — the share card (item 3.11, ADRs
// 0010, 0023; v2.js shareCard() and fitCard(), v2.css .scard, .sc-*).
//
// One image of 1–10 verses from one chapter, laid out at its export size (1080
// px wide) and scaled for the preview. A double gilt frame with corner
// lozenges; the khatam (the verse's number, or the chapter's for several
// verses), the chapter's title and a caption; the verses; an optional quoted
// opening of a commentary; the footer with the app's mark.
//
// The verses are fitted: from the format's largest size down to a 32 px floor,
// in the stacked layout (as in text mode) and as side-by-side pairs, keeping
// whichever allows the larger size (a tie goes to the pair from five verses
// up). A size fits when the body has room and no hemistich wraps.
//
// The card has its own palette (v2.css .scard): paper, or night with the
// reader's chosen ink for names. The numbers below are the prototype's, in px
// of the 1080-wide card.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../utils/arabic.dart';
import '../tokens.g.dart';
import 'khatam.dart';
import 'rubric.dart';
import 'verse_unit.dart' show Hemistich;

/// The export sizes: where the card is posted decides which.
enum CardFormat {
  square(1080, 1080, 'مربع', '١:١', 60, 4),
  portrait(1080, 1350, 'طولي', '٤:٥', 64, 6),
  story(1080, 1920, 'قصة', '٩:١٦', 68, 10);

  final double width, height;
  final String ar, ratio;

  /// The verse size the fitter starts from.
  final double maxSize;

  /// The most verses the format holds at the floor (measured on the matn).
  final int maxVerses;
  const CardFormat(this.width, this.height, this.ar, this.ratio, this.maxSize, this.maxVerses);

  /// The smallest verse size a card may use.
  static const double minSize = 32;

  Size get size => Size(width, height);
}

class CardVerse {
  final String first, second;
  final List<Rubric> rubrics;
  const CardVerse(this.first, this.second, {this.rubrics = const []});
}

/// The opening of a book's explanation, quoted, and whose it is.
class CardExcerpt {
  final String text, source;
  const CardExcerpt({required this.text, required this.source});
}

class ShareCardData {
  final CardFormat format;
  final int firstVerse, lastVerse;
  final List<CardVerse> verses;
  final String chapterTitle, chapterOrdinal;

  /// The chapter's number for the khatam of several verses («١١»; empty for the introduction).
  final String chapterNumber;
  final CardExcerpt? excerpt;

  const ShareCardData(
      {required this.format,
      required this.firstVerse,
      required this.lastVerse,
      required this.verses,
      required this.chapterTitle,
      required this.chapterOrdinal,
      required this.chapterNumber,
      this.excerpt});

  bool get many => verses.length > 1;

  /// «البيت ٢٢٦» or «الأبيات ٢٢٦–٢٢٩».
  String get label => many ? 'الأبيات ${isolatedRange(firstVerse, lastVerse)}' : 'البيت ${ar(firstVerse)}';
}

/// The card's own colours (v2.css .scard and .scard.night).
class ShareCardPalette {
  final Color background, glow, ink, ink2, ink3, gilt, rubric;
  const ShareCardPalette(
      {required this.background,
      required this.glow,
      required this.ink,
      required this.ink2,
      required this.ink3,
      required this.gilt,
      required this.rubric});

  static const paper = ShareCardPalette(
    background: Color(0xFFF6F1E6),
    glow: Color(0xFFFBF8F1),
    ink: Color(0xFF18191D),
    ink2: Color(0xFF4A4D55),
    ink3: Color(0xFF6A6D74),
    gilt: Color(0xFFA9843F),
    rubric: Color(0xFF8E2A5A),
  );

  /// Night: names take the reader's chosen night ink (ADR 0020).
  factory ShareCardPalette.night(TzNightInk ink) => ShareCardPalette(
        background: const Color(0xFF0E1117),
        glow: const Color(0xFF151A23),
        ink: const Color(0xFFE3DDD2),
        ink2: const Color(0xFFB2B7BF),
        ink3: const Color(0xFF8C929B),
        gilt: const Color(0xFFC9A962),
        rubric: ink.accent,
      );
}

/// What the fitter chose: the verse size, the layout, and whether even the floor overflows.
class CardFit {
  final double size;
  final bool pair, overflow;
  const CardFit({required this.size, required this.pair, required this.overflow});
}

TextStyle _text(double size, double height, {FontWeight weight = FontWeight.w400, Color? color}) =>
    TextStyle(fontFamily: TzFont.text, fontSize: size, height: height, fontWeight: weight, color: color);
TextStyle _ui(double size, double height, {Color? color}) =>
    TextStyle(fontFamily: TzFont.ui, fontSize: size, height: height, fontWeight: FontWeight.w500, color: color);

/// The card's measures for [data]: every height the fitter and the widget share.
class _Geometry {
  final ShareCardData data;
  _Geometry(this.data);

  static const double side = 104, gap = 26, pairGap = 56, excerptSize = 32, excerptLine = 1.8;
  static const int excerptLines = 4;

  bool get many => data.many;
  int get n => data.verses.length;
  double get top => data.format == CardFormat.story ? (many ? 200 : 250) : 96;
  double get bottom => data.format == CardFormat.story ? (many ? 200 : 250) : 88;
  double get contentWidth => data.format.width - 2 * side;

  double get khatam => many ? 64 : 84;
  double get titleSize => many ? 34 : 40;
  TextStyle get titleStyle => _text(titleSize, 1.55, weight: FontWeight.w700);
  static final TextStyle captionStyle = _ui(24, 1.4);

  late final int titleLines = _lines(data.chapterTitle, titleStyle, contentWidth);
  double get headHeight => khatam + 6 + 6 + titleLines * titleSize * 1.55 + 6 + 24 * 1.4;

  /// The rule above the footer (1.5), its padding (22) and the mark (46).
  static const double footHeight = 22 + 1.5 + 46;

  double get bodyHeight => data.format.height - top - bottom - headHeight - footHeight;
  double get bodyPad => many ? 10 : 18;

  double lineHeight(bool pair) => pair ? 1.7 : (many ? 1.68 : 1.9);
  double get padBlock => many ? 0 : 1;
  double get sepSize => many ? 9 : 12;
  double sepMargin(double z) => (many ? 0.06 : 0.18) * z;

  double versesHeight(double z, bool pair) {
    final verse = pair ? z * 1.7 : 2 * (z * lineHeight(false) + 2 * padBlock);
    return n * verse + (n - 1) * (sepSize + 2 * sepMargin(z));
  }

  late final List<String> excerptText =
      data.excerpt == null ? const [] : clampLines(data.excerpt!.text, _text(excerptSize, excerptLine), contentWidth, excerptLines);
  double get excerptHeight => data.excerpt == null
      ? 0
      : gap + 14 + 14 + excerptText.length * excerptSize * excerptLine + 10 + 22 * 1.4;

  /// A hemistich's width on one line at [z].
  double natural(String text, double z) =>
      (TextPainter(text: TextSpan(text: text, style: _text(z, 1.9)), textDirection: TextDirection.rtl)..layout()).width;

  bool fits(double z, bool pair) {
    if (2 * bodyPad + versesHeight(z, pair) + excerptHeight > bodyHeight + 1) return false;
    final column = pair ? (contentWidth - pairGap) / 2 : contentWidth * 0.92;
    return data.verses.every((v) => natural(v.first, z) <= column && natural(v.second, z) <= column);
  }

  static int _lines(String text, TextStyle style, double width) =>
      (TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.rtl, textAlign: TextAlign.center)
            ..layout(maxWidth: width))
          .computeLineMetrics()
          .length;
}

/// [text] as it breaks into lines of [width], at most [maxLines] of them; a
/// clamped text ends with «…».
List<String> clampLines(String text, TextStyle style, double width, int maxLines) {
  final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.rtl)..layout(maxWidth: width);
  final lines = <String>[];
  var at = 0;
  while (at < text.length && lines.length < maxLines) {
    final range = painter.getLineBoundary(TextPosition(offset: at));
    final end = math.max(range.end, at + 1);
    lines.add(text.substring(at, math.min(end, text.length)).trim());
    at = end;
  }
  if (at < text.length && lines.isNotEmpty) {
    // Clamped: the last line gives up its last word for the ellipsis.
    final words = lines.last.split(' ');
    if (words.length > 1) words.removeLast();
    lines[lines.length - 1] = '${words.join(' ').replaceFirst(RegExp(r'[،؛:.]$'), '')}…';
  }
  return lines;
}

/// Fits [data]'s verses (ADR 0023).
CardFit fitShareCard(ShareCardData data) {
  final g = _Geometry(data);
  double largest(bool pair) {
    for (var z = data.format.maxSize; z >= CardFormat.minSize; z -= 2) {
      if (g.fits(z, pair)) return z;
    }
    return 0;
  }

  final stack = largest(false), pair = g.n > 1 ? largest(true) : 0.0;
  final usePair = pair > stack || (pair == stack && g.n >= 5 && pair > 0);
  final size = usePair ? pair : stack;
  return CardFit(size: math.max(size, CardFormat.minSize), pair: usePair, overflow: size == 0);
}

/// One verse on the card.
class ShareCardVerse extends StatelessWidget {
  final CardVerse verse;
  final TextStyle style;
  final bool pair;
  final double padBlock;
  final Color rubric;
  const ShareCardVerse(
      {super.key, required this.verse, required this.style, required this.pair, required this.padBlock, required this.rubric});

  @override
  Widget build(BuildContext context) {
    Hemistich line(String text, {required bool atEnd}) => Hemistich(
          text: text,
          rubrics: verse.rubrics,
          style: style,
          widthFactor: pair ? 1 : 0.92,
          atEnd: atEnd,
          rubricColor: rubric,
          padBlock: pair ? 0 : padBlock,
        );
    return pair
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: line(verse.first, atEnd: false)),
              const SizedBox(width: _Geometry.pairGap),
              Expanded(child: line(verse.second, atEnd: false)),
            ],
          )
        : Column(mainAxisSize: MainAxisSize.min, children: [line(verse.first, atEnd: false), line(verse.second, atEnd: true)]);
  }
}

class ShareCard extends StatelessWidget {
  final ShareCardData data;
  final ShareCardPalette palette;
  const ShareCard({super.key, required this.data, this.palette = ShareCardPalette.paper});

  static const bodyKey = ValueKey('share-card-body');

  @override
  Widget build(BuildContext context) {
    final g = _Geometry(data), p = palette, fit = fitShareCard(data);
    final z = fit.size;
    final verse = _text(z, g.lineHeight(fit.pair), color: p.ink);
    return Semantics(
      image: true,
      label: '${data.label} من ${data.chapterTitle}',
      excludeSemantics: true,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          // The card is an image: it never follows the system's text size.
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: SizedBox(
            width: data.format.width,
            height: data.format.height,
            child: CustomPaint(
              painter: _Ground(p),
              // The card stands on its own: no ambient text style reaches it.
              child: DefaultTextStyle(
               style: _text(z, 1.9, color: p.ink).copyWith(decoration: TextDecoration.none),
               child: Padding(
                padding: EdgeInsets.fromLTRB(_Geometry.side, g.top, _Geometry.side, g.bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The head: khatam, title, caption.
                    Center(
                      child: CustomPaint(
                        size: Size.square(g.khatam),
                        painter: KhatamPainter(
                          label: data.many ? data.chapterNumber : ar(data.firstVerse),
                          stroke: p.gilt,
                          text: p.ink,
                          ringTrack: p.gilt,
                          ringColor: p.gilt,
                          textDirection: TextDirection.rtl,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(data.chapterTitle,
                        textAlign: TextAlign.center, style: g.titleStyle.copyWith(color: p.ink)),
                    const SizedBox(height: 6),
                    Text('${data.chapterOrdinal} · ${data.label}',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: _Geometry.captionStyle
                            .copyWith(color: p.ink2, fontFeatures: const [FontFeature.tabularFigures()])),
                    // The body: the verses, centred, and the excerpt under them.
                    Expanded(
                      child: ClipRect(
                        key: bodyKey,
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: g.bodyPad),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final (i, v) in data.verses.indexed) ...[
                                if (i > 0)
                                  Padding(
                                    padding: EdgeInsets.symmetric(vertical: g.sepMargin(z)),
                                    child: Center(child: _Lozenge(g.sepSize, p.gilt.withValues(alpha: 0.8))),
                                  ),
                                ShareCardVerse(verse: v, style: verse, pair: fit.pair, padBlock: g.padBlock, rubric: p.rubric),
                              ],
                              if (data.excerpt case final excerpt?) ...[
                                const SizedBox(height: _Geometry.gap),
                                _Excerpt(lines: g.excerptText, source: excerpt.source, width: g.contentWidth, palette: p),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    // The footer: the app's mark, and the poem and its author.
                    Container(
                      padding: const EdgeInsets.only(top: 22),
                      decoration:
                          BoxDecoration(border: Border(top: BorderSide(color: p.gilt.withValues(alpha: 0.45), width: 1.5))),
                      child: Row(
                        children: [
                          CustomPaint(
                            size: const Size.square(46),
                            painter: KhatamPainter(
                                label: '',
                                stroke: p.gilt,
                                text: p.ink,
                                ringTrack: p.gilt,
                                ringColor: p.gilt,
                                textDirection: TextDirection.rtl,
                                strokeWidth: 2),
                          ),
                          const SizedBox(width: 14),
                          Text('تيسير الشاطبية', style: _text(38, 1, weight: FontWeight.w700, color: p.ink)),
                          const Spacer(),
                          Text('حرز الأماني ووجه التهاني · الإمام الشاطبي', style: _ui(21, 1.3, color: p.ink3)),
                        ],
                      ),
                    ),
                  ],
                ),
               ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The quoted opening: a short gilt rule, up to four justified lines (the last
/// one centred), and the source.
class _Excerpt extends StatelessWidget {
  final List<String> lines;
  final String source;
  final double width;
  final ShareCardPalette palette;
  const _Excerpt({required this.lines, required this.source, required this.width, required this.palette});

  @override
  Widget build(BuildContext context) {
    final style = _text(_Geometry.excerptSize, _Geometry.excerptLine, color: palette.ink2);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(width * 0.18, 0, width * 0.18, 14),
          child: CustomPaint(size: const Size(double.infinity, 14), painter: _Rule(palette.gilt)),
        ),
        for (final (i, line) in lines.indexed)
          SizedBox(
            width: width,
            child: Text(line,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                style: i == lines.length - 1 ? style : style.copyWith(wordSpacing: _spread(line, style))),
          ),
        const SizedBox(height: 10),
        Text('— $source', textAlign: TextAlign.center, style: _ui(22, 1.4, color: palette.ink3)),
      ],
    );
  }

  /// The word spacing that makes [line] fill the width (a justified line).
  double _spread(String line, TextStyle style) {
    final spaces = ' '.allMatches(line).length;
    if (spaces == 0) return 0;
    final natural =
        (TextPainter(text: TextSpan(text: line, style: style), textDirection: TextDirection.rtl)..layout()).width;
    return math.max(0, (width - natural) / spaces);
  }
}

class _Lozenge extends StatelessWidget {
  final double size;
  final Color color;
  const _Lozenge(this.size, this.color);

  @override
  Widget build(BuildContext context) =>
      Transform.rotate(angle: math.pi / 4, child: Container(width: size, height: size, color: color));
}

/// The excerpt's rule: a 1.5 px gilt line at 60 % with an 11 px lozenge at its middle.
class _Rule extends CustomPainter {
  final Color gilt;
  const _Rule(this.gilt);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = gilt.withValues(alpha: 0.6)
          ..strokeWidth = 1.5);
    canvas.save();
    canvas.translate(size.width / 2, y);
    canvas.rotate(math.pi / 4);
    canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: 11, height: 11), Paint()..color = gilt);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Rule old) => old.gilt != gilt;
}

/// The card's ground: a soft glow from the top, then the double gilt frame with a lozenge at each corner.
class _Ground extends CustomPainter {
  final ShareCardPalette p;
  const _Ground(this.p);

  @override
  void paint(Canvas canvas, Size size) {
    // radial-gradient(120% 80% at 50% 0%, glow 0%, background 70%)
    canvas.drawRect(Offset.zero & size, Paint()..color = p.background);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width / 2, 0);
    canvas.scale(size.width * 1.2, size.height * 0.8);
    canvas.drawCircle(
        Offset.zero, 1, Paint()..shader = ui.Gradient.radial(Offset.zero, 1, [p.glow, p.background], const [0, 0.7]));
    canvas.restore();

    final line = Paint()..style = PaintingStyle.stroke;
    // The outer line: 40 px in, 2 px at 70 %.
    canvas.drawRRect(
        RRect.fromRectAndRadius((Offset.zero & size).deflate(41), const Radius.circular(6)),
        line
          ..strokeWidth = 2
          ..color = p.gilt.withValues(alpha: 0.7));
    // The inner line: 10 px inside it, 1 px at 45 %.
    canvas.drawRRect(
        RRect.fromRectAndRadius((Offset.zero & size).deflate(52.5), const Radius.circular(3)),
        line
          ..strokeWidth = 1
          ..color = p.gilt.withValues(alpha: 0.45));
    // A 14 px lozenge on each corner of the outer line.
    final fill = Paint()..color = p.gilt;
    for (final corner in [
      const Offset(41, 41),
      Offset(size.width - 41, 41),
      Offset(41, size.height - 41),
      Offset(size.width - 41, size.height - 41),
    ]) {
      canvas.save();
      canvas.translate(corner.dx, corner.dy);
      canvas.rotate(math.pi / 4);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: 14, height: 14), fill);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Ground old) => old.p != p;
}
