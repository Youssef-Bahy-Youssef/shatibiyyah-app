// lib/ui/design/components/commentary_inline.dart — the marked text of a
// commentary (item 3.9, ADRs 0014, 0022; v2.css .c-body, .seg-h, .q, .mq, .fn,
// .fnotes, .legend). Three kinds of quoted text, one look each:
//   - the book's quotation of the verse: a vellum chip that lights the phrase in
//     the matn strip;
//   - a Quranic quotation: lapis, in ﴿ ﴾;
//   - a reader's name or symbol: the rubric ink.
// A footnote is a lapis marker in the text; the notes are collected under it.
import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';
import 'ornament.dart';

/// A commentary's running text at the reader's verse size (v2.css .c-body: 0.92 ×, line 1.9).
TextStyle commentaryStyle(TzColors c, double verseSize) =>
    TzType.commentary.copyWith(fontSize: verseSize * 0.92, height: 1.9, color: c.ink);

/// A Quranic quotation: the words in lapis 700 between gilt ﴿ ﴾.
InlineSpan quranSpan(String words, TzColors c) => TextSpan(children: [
      TextSpan(text: '﴿\u200A', style: TextStyle(color: c.gilt, fontWeight: FontWeight.w400)),
      TextSpan(text: words, style: TextStyle(color: c.lapis, fontWeight: FontWeight.w700)),
      TextSpan(text: '\u200A﴾', style: TextStyle(color: c.gilt, fontWeight: FontWeight.w400)),
    ]);

/// A verse reference as the book writes it after a quotation: «[البقرة: ١٤]».
final _reference = RegExp(r'\[[^\[\]\n:]{2,20}: ?[0-9٠-٩]{1,3}(?: ?[-–،و] ?[0-9٠-٩]{1,3})*\]');

/// Running text with its verse references small and quiet (v2.css .ref), each
/// kept on one line.
List<InlineSpan> withReferences(String text, TzColors c) {
  final spans = <InlineSpan>[];
  var at = 0;
  for (final m in _reference.allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
    spans.add(TextSpan(text: m[0]!.replaceAll(' ', ' '), style: TzType.caption.copyWith(color: c.ink3)));
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}

/// A segment's heading (v2.css .seg-h): a small gilt lozenge and the word.
class SegmentHeading extends StatelessWidget {
  final String text;
  const SegmentHeading(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            Lozenge(size: 6, radius: 1, color: c.gilt),
            const SizedBox(width: 8),
            Flexible(child: Text(text, style: TzType.caption.copyWith(color: c.ink2, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }
}

/// The book's quotation of the verse, inline (v2.css .mq): the words on the matn
/// vellum over a gilt underline; a gilt edge all round while its phrase is lit.
class QuoteChip extends StatelessWidget {
  final String words;
  final TextStyle style;
  final bool on;
  final VoidCallback? onTap;
  const QuoteChip({super.key, required this.words, required this.style, this.on = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return Semantics(
      link: true,
      label: 'من البيت: $words',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: c.matnBg,
            borderRadius: BorderRadius.circular(6),
            border: on ? Border.all(color: c.gilt, width: 1.5) : null,
          ),
          foregroundDecoration: on
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border(bottom: BorderSide(color: c.gilt.withValues(alpha: 0.7), width: 1.5)),
                ),
          child: Text(words, style: style.copyWith(fontWeight: FontWeight.w700, color: c.verseInk)),
        ),
      ),
    );
  }
}

/// A footnote's marker in the text (v2.css .fn): a small lapis pill, raised.
class FootnoteMarker extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const FootnoteMarker({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return Semantics(
      link: true,
      label: 'حاشية $label',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 1, bottom: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(color: c.lapis, borderRadius: BorderRadius.circular(TzRadius.pill)),
            child: Text(label,
                textScaler: TextScaler.noScaling,
                style: TzType.caption.copyWith(
                    fontSize: 10,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: c.onAction,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ),
      ),
    );
  }
}

/// The notes of a passage, under its text (v2.css .fnotes): each under its lapis number.
class FootnoteList extends StatelessWidget {
  /// (marker, text, key) per note; the key lets a marker bring its note into view.
  final List<({String? marker, String text, Key? key})> notes;
  const FootnoteList({super.key, required this.notes});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final style = TzType.label.copyWith(fontWeight: FontWeight.w400, height: 22 / TzType.label.fontSize!, color: c.ink2);
    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.lineSoft))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final n in notes)
            Padding(
              key: n.key,
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (n.marker case final m?) ...[
                    Text(m,
                        style: style.copyWith(
                            fontWeight: FontWeight.w700, color: c.lapis, fontFeatures: const [FontFeature.tabularFigures()])),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: Text(n.text, style: style)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The key to the three kinds of quoted text (v2.css .legend).
class CommentaryLegend extends StatelessWidget {
  const CommentaryLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final tz = TzTheme.of(context), c = tz.colors;
    final label = TzType.caption.copyWith(fontSize: 11.5, height: 16 / 11.5, color: c.ink3);
    Widget item(Widget sample, String word) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [sample, const SizedBox(width: 5), Text(word, style: label)],
        );
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
        child: Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            item(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(color: c.matnBg, borderRadius: BorderRadius.circular(6)),
                // Drawn inside the chip (an inset line): it adds no height.
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border(bottom: BorderSide(color: c.gilt.withValues(alpha: 0.7), width: 1.5)),
                ),
                child: Text('متن',
                    style: TextStyle(
                        fontFamily: TzFont.text, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w700, color: c.verseInk)),
              ),
              'من البيت',
            ),
            item(
              Text.rich(
                TextSpan(
                    style: TextStyle(fontFamily: TzFont.ui, fontSize: 13, height: 16 / 13),
                    children: [quranSpan('آية', c)]),
                // The ﴿ ﴾ come from another face: the line keeps the sample's own height.
                strutStyle: const StrutStyle(fontFamily: TzFont.ui, fontSize: 13, height: 16 / 13, forceStrutHeight: true),
              ),
              'قرآن',
            ),
            item(Text('ورش', style: label.copyWith(color: tz.rubric, fontWeight: FontWeight.w700)), 'قارئ أو رمز'),
          ],
        ),
      ),
    );
  }
}
