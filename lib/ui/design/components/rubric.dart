// lib/ui/design/components/rubric.dart — reader names and symbols in the rubric
// ink (ADR 0021; v2.js rubricate(), v2.css .rb). A name is coloured whole; a
// letter symbol colours only its letter and gets a dotted underline, the rest
// of its word stays in the verse ink. Each mark applies to its first occurrence.
import 'package:flutter/painting.dart';

/// A reader name or symbol to set in the rubric ink.
class Rubric {
  /// The name, or the symbol's letter.
  final String text;

  /// For a letter symbol: the word the letter begins.
  final String? inWord;

  const Rubric.name(this.text) : inWord = null;
  const Rubric.symbol(this.text, {required String this.inWord});

  bool get isSymbol => inWord != null;
}

/// [text] as spans, with each mark of [marks] found in it set in [rubric].
List<InlineSpan> rubricate(String text, List<Rubric> marks, Color rubric) {
  final hits = <(int, int, bool)>[]; // start, end, symbol
  for (final m in marks) {
    final at = text.indexOf(m.inWord ?? m.text);
    if (at < 0) continue;
    hits.add((at, at + m.text.length, m.isSymbol));
  }
  hits.sort((a, b) => a.$1.compareTo(b.$1));
  final spans = <InlineSpan>[];
  var i = 0;
  for (final (start, end, symbol) in hits) {
    if (start < i) continue;
    if (start > i) spans.add(TextSpan(text: text.substring(i, start)));
    spans.add(TextSpan(
      text: text.substring(start, end),
      style: TextStyle(
        color: rubric,
        decoration: symbol ? TextDecoration.underline : null,
        decorationStyle: symbol ? TextDecorationStyle.dotted : null,
        decorationColor: symbol ? rubric : null,
        decorationThickness: symbol ? 1.5 : null,
      ),
    ));
    i = end;
  }
  if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
  return spans;
}
