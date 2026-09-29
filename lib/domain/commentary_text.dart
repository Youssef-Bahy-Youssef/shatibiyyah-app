// lib/domain/commentary_text.dart — turns a commentary segment into readable paragraphs.
//
// Segments are stored as one run of text (no line breaks; up to 26K characters in
// إبراز المعاني). Following the prototype, a paragraph ends at the first sentence
// end (. ؟ ! ؛) once it has grown past ~420 characters. Footnote markers are cut
// out as their own runs at their anchors (UTF-16 offsets = Dart string indices),
// so the reader can style and tap them. Pure; tested in commentary_text_test.dart.
import '../data/commentary_repository.dart' show Footnote;

class TextRun {
  final String text;

  /// Set when this run is a footnote marker.
  final Footnote? footnote;
  const TextRun(this.text, [this.footnote]);
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

List<CommentaryParagraph> layoutSegment(String text, List<Footnote> footnotes, {int target = kParagraphTarget}) {
  final echo = _verseEcho.firstMatch(text);
  final start = echo?.end ?? 0;
  final body = text.substring(start);

  // Anchored markers of this segment, shifted onto `body`, in reading order.
  final markers = <({int at, int end, Footnote note})>[];
  for (final f in footnotes) {
    final anchor = f.anchorUtf16, marker = f.marker;
    if (anchor == null || marker == null) continue;
    final at = anchor - start;
    if (at < 0 || at + marker.length > body.length || body.substring(at, at + marker.length) != marker) continue;
    markers.add((at: at, end: at + marker.length, note: f));
  }
  markers.sort((a, b) => a.at.compareTo(b.at));

  // Paragraph ranges: cut after a sentence end once the paragraph passes `target`.
  final ranges = <(int, int)>[];
  var paraStart = 0;
  for (final m in _sentenceEnd.allMatches(body)) {
    final cut = m.start + 1; // keep the punctuation, drop the whitespace
    if (cut - paraStart > target) {
      ranges.add((paraStart, cut));
      paraStart = m.end;
    }
  }
  if (paraStart < body.length) ranges.add((paraStart, body.length));

  final paragraphs = <CommentaryParagraph>[];
  for (final (from, to) in ranges) {
    final runs = <TextRun>[];
    var cursor = from;
    for (final m in markers) {
      if (m.at < from || m.end > to) continue;
      if (m.at > cursor) runs.add(TextRun(body.substring(cursor, m.at)));
      runs.add(TextRun(body.substring(m.at, m.end), m.note));
      cursor = m.end;
    }
    if (cursor < to) runs.add(TextRun(body.substring(cursor, to)));
    final paragraph = CommentaryParagraph(runs);
    if (paragraph.plainText.trim().isNotEmpty) paragraphs.add(paragraph);
  }
  return paragraphs;
}
