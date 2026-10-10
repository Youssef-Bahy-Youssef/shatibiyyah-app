// lib/ui/design/components/rubric.dart — reader names and symbols in the rubric
// ink (ADR 0021; v2.js rubricate(), v2.css .rb). A name is coloured whole; a
// letter symbol colours only its letter and gets a dotted underline, the rest
// of its word stays in the verse ink. Each mark applies to its first occurrence.
// A quoted phrase being read can be washed in gilt (v2.css mark.mqhl).
import 'package:flutter/painting.dart';

/// A reader name or symbol to set in the rubric ink: found by its text, or (from
/// the span data) given by its offsets inside one hemistich.
class Rubric {
  /// The name, or the symbol's letter.
  final String text;

  /// For a letter symbol: the word the letter begins.
  final String? inWord;

  /// For a mark from the span data: where it is (UTF-16, end exclusive) and in
  /// which hemistich (1 or 2).
  final int? start, end, hemistich;

  /// A symbol's letter gets a dotted underline; a name does not.
  final bool isSymbol;

  /// What a symbol stands for, said aloud and shown in its tip: «رمز كَ: ابن عامر».
  final String? label;

  const Rubric.name(this.text)
      : inWord = null,
        start = null,
        end = null,
        hemistich = null,
        isSymbol = false,
        label = null;
  const Rubric.symbol(this.text, {required String this.inWord})
      : start = null,
        end = null,
        hemistich = null,
        isSymbol = true,
        label = null;
  const Rubric.at(int this.start, int this.end, {required int this.hemistich, this.isSymbol = false, this.label})
      : text = '',
        inWord = null;

  /// Whether [other] is the mark at the same place.
  bool sameMark(Rubric? other) =>
      other != null && start != null && other.start == start && other.end == end && other.hemistich == hemistich;

  /// Whether the mark belongs to [half] (1 or 2): a mark found by its text belongs to both.
  bool inHemistich(int half) => hemistich == null || hemistich == half;
}

/// The marks of [marks] for hemistich [half] (1 or 2).
List<Rubric> rubricsOf(List<Rubric> marks, int half) => [for (final m in marks) if (m.inHemistich(half)) m];

/// [text] as spans, with each mark of [marks] found in it set in [rubric].
List<InlineSpan> rubricate(String text, List<Rubric> marks, Color rubric) {
  final hits = <(int, int, TextStyle)>[];
  for (final m in marks) {
    final int at, to;
    if (m.start case final from?) {
      (at, to) = (from, m.end!);
      if (at < 0 || to > text.length || at >= to) continue;
    } else {
      at = text.indexOf(m.inWord ?? m.text);
      if (at < 0) continue;
      to = at + m.text.length;
    }
    hits.add((
      at,
      to,
      TextStyle(
        color: rubric,
        decoration: m.isSymbol ? TextDecoration.underline : null,
        decorationStyle: m.isSymbol ? TextDecorationStyle.dotted : null,
        decorationColor: m.isSymbol ? rubric : null,
        decorationThickness: m.isSymbol ? 1.5 : null,
      ),
    ));
  }
  hits.sort((a, b) => a.$1.compareTo(b.$1));
  final spans = <InlineSpan>[];
  var i = 0;
  for (final (start, end, style) in hits) {
    if (start < i) continue;
    if (start > i) spans.add(TextSpan(text: text.substring(i, start)));
    spans.add(TextSpan(text: text.substring(start, end), style: style));
    i = end;
  }
  if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
  return spans;
}
