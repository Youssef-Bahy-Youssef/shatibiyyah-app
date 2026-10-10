// lib/domain/commentary_text.dart — turns a commentary segment into readable paragraphs.
//
// Segments are stored as one run of text (no line breaks; up to 26K characters in
// إبراز المعاني). Following the prototype, a paragraph ends at the first sentence
// end (. ؟ ! ؛) once it has grown past ~420 characters. Three kinds of marked
// text are cut out as their own runs at their offsets (UTF-16 = Dart string
// indices), so the reader can style and tap them:
//   - footnote markers, at their anchors;
//   - Quranic quotations (ADR 0014): the words, without the book's own marks
//     around them, which ﴿ ﴾ replace;
//   - the book's quotations of the verse (ADR 0022): the words, without their
//     brackets, which the chip replaces.
// A paragraph never ends inside a marked run. Pure; tested in commentary_text_test.dart.
import '../data/commentary_repository.dart' show Footnote, MatnQuoteSpan, QuranSpan;

class TextRun {
  final String text;

  /// Set when this run is a footnote marker.
  final Footnote? footnote;

  /// Set when this run is a Quranic quotation.
  final QuranSpan? quran;

  /// Set when this run quotes the verse being explained.
  final MatnQuoteSpan? quote;
  const TextRun(this.text, [this.footnote]) : quran = null, quote = null;
  const TextRun.quran(this.text, QuranSpan this.quran) : footnote = null, quote = null;
  const TextRun.quote(this.text, MatnQuoteSpan this.quote) : footnote = null, quran = null;
  bool get isMarker => footnote != null;
}

class CommentaryParagraph {
  final List<TextRun> runs;
  const CommentaryParagraph(this.runs);
  String get plainText => runs.map((r) => r.text).join();
}

/// A few Al-Wafi segments open by echoing the verse («٢٢٩ - وشىء … .......»).
final RegExp _verseEcho = RegExp(r'^[٠-٩]+ - [^.]*\.{3,}\s*');
final RegExp _sentenceEnd = RegExp(r'[.؟!؛]\s+(?=\S)');

const int kParagraphTarget = 420;

List<CommentaryParagraph> layoutSegment(String text, List<Footnote> footnotes,
    {int target = kParagraphTarget, List<QuranSpan> quran = const [], List<MatnQuoteSpan> quotes = const []}) {
  final echo = _verseEcho.firstMatch(text);
  final start = echo?.end ?? 0;
  final body = text.substring(start);

  // The marked runs of this segment, shifted onto `body`: what they replace
  // ([at], [end]) and the run that stands there. In reading order, none overlapping.
  final marks = <({int at, int end, TextRun run})>[];
  for (final f in footnotes) {
    final anchor = f.anchorUtf16, marker = f.marker;
    if (anchor == null || marker == null) continue;
    final at = anchor - start;
    if (at < 0 || at + marker.length > body.length || body.substring(at, at + marker.length) != marker) continue;
    marks.add((at: at, end: at + marker.length, run: TextRun(marker, f)));
  }
  bool inside(int a, int b, int oa, int ob) => 0 <= oa && oa <= a && a < b && b <= ob && ob <= body.length;
  for (final q in quran) {
    final a = q.start - start, b = q.end - start, oa = q.outerStart - start, ob = q.outerEnd - start;
    if (inside(a, b, oa, ob)) marks.add((at: oa, end: ob, run: TextRun.quran(body.substring(a, b), q)));
  }
  for (final q in quotes) {
    final a = q.start - start, b = q.end - start, oa = q.outerStart - start, ob = q.outerEnd - start;
    if (inside(a, b, oa, ob)) marks.add((at: oa, end: ob, run: TextRun.quote(body.substring(a, b), q)));
  }
  marks.sort((a, b) => a.at.compareTo(b.at));
  final kept = <({int at, int end, TextRun run})>[];
  for (final m in marks) {
    if (kept.isEmpty || m.at >= kept.last.end) kept.add(m);
  }

  // Paragraph ranges: cut after a sentence end once the paragraph passes `target`,
  // never inside a marked run.
  final ranges = <(int, int)>[];
  var paraStart = 0;
  for (final m in _sentenceEnd.allMatches(body)) {
    final cut = m.start + 1; // keep the punctuation, drop the whitespace
    if (cut - paraStart > target && !kept.any((k) => k.at < m.end && cut < k.end)) {
      ranges.add((paraStart, cut));
      paraStart = m.end;
    }
  }
  if (paraStart < body.length) ranges.add((paraStart, body.length));

  final paragraphs = <CommentaryParagraph>[];
  for (final (from, to) in ranges) {
    final runs = <TextRun>[];
    var cursor = from;
    for (final m in kept) {
      if (m.at < from || m.end > to) continue;
      if (m.at > cursor) runs.add(TextRun(body.substring(cursor, m.at)));
      runs.add(m.run);
      cursor = m.end;
    }
    if (cursor < to) runs.add(TextRun(body.substring(cursor, to)));
    final paragraph = CommentaryParagraph(runs);
    if (paragraph.plainText.trim().isNotEmpty) paragraphs.add(paragraph);
  }
  return paragraphs;
}
