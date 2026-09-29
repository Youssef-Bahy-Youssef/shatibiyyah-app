// lib/domain/search.dart — «البحث» (features-v3 search): verses, chapters and the
// three books at once, blind to vowel marks and hamza seats.
//
// The query goes through normalizeMatching, the same normalization the pipeline
// stored in content.sqlite, so «بدات» finds «بَدَأْتُ». Verses and chapter titles are
// matched in memory; the books (2.4 M characters) with SQL on
// commentary_segments.normalized_text, one hit per block.
import '../data/app_content.dart';
import '../data/matn_repository.dart';
import 'normalizer.dart';

/// A book passage that matches: where it is and a snippet of its text around the match.
class CommentaryHit {
  final String bookId;
  final String bookTitle;
  final int fromVerse;
  final int toVerse;
  final String snippet;
  const CommentaryHit(this.bookId, this.bookTitle, this.fromVerse, this.toVerse, this.snippet);
}

class SearchResults {
  final String query; // normalized
  final List<MatnChapter> chapters;
  final List<int> verses;
  final List<CommentaryHit> commentary;
  const SearchResults(this.query, this.chapters, this.verses, this.commentary);

  static const empty = SearchResults('', [], [], []);
  bool get isEmpty => chapters.isEmpty && verses.isEmpty && commentary.isEmpty;
}

/// Shortest normalized query that is searched (a single letter matches everything).
const int kMinQueryLength = 2;

/// Book passages returned at most (the count still reports all of them).
const int kMaxCommentaryHits = 30;

class Searcher {
  final AppContent content;
  late final Map<String, String> _chapterNorm = {
    for (final c in content.matn.chapters) c.id: normalizeMatching('${c.title} ${c.shortLabel}'),
  };

  Searcher(this.content);

  Future<({SearchResults results, int commentaryTotal})> search(String query) async {
    final q = normalizeMatching(query);
    if (q.length < kMinQueryLength) return (results: SearchResults.empty, commentaryTotal: 0);
    final chapters = [for (final c in content.matn.chapters) if (_chapterNorm[c.id]!.contains(q)) c];
    final verses = [for (final v in content.matn.verses) if (v.normalizedText.contains(q)) v.number];

    final rows = await content.store.db.rawQuery(
      'SELECT s.commentary_block_id AS block, s.display_text AS display, b.commentary_id AS book, '
      'b.from_verse AS from_verse, b.to_verse AS to_verse '
      'FROM commentary_segments s JOIN commentary_blocks b ON b.id = s.commentary_block_id '
      'JOIN commentaries c ON c.id = b.commentary_id '
      "WHERE instr(s.normalized_text, ?) > 0 AND b.from_verse IS NOT NULL AND s.segment_type != 'citation_lead_in' "
      'ORDER BY b.from_verse, c.display_order, b.source_order, s.order_index',
      [q],
    );
    final titles = {for (final b in content.books.books) b.id: b.shortTitle};
    final seen = <String>{};
    final hits = <CommentaryHit>[];
    for (final r in rows) {
      if (!seen.add(r['block'] as String)) continue; // one hit per block
      if (hits.length < kMaxCommentaryHits) {
        final from = r['from_verse'] as int;
        hits.add(CommentaryHit(r['book'] as String, titles[r['book']] ?? '', from,
            (r['to_verse'] as int?) ?? from, snippetAround(r['display'] as String, q)));
      }
    }
    return (results: SearchResults(q, chapters, verses, hits), commentaryTotal: seen.length);
  }
}

/// About [before] and [after] characters of [display] around the first place its
/// normalized form contains [normalizedQuery], with «…» where it was cut.
String snippetAround(String display, String normalizedQuery, {int before = 40, int after = 70}) {
  final mapped = normalizeMatchingMapped(display);
  final i = mapped.text.indexOf(normalizedQuery);
  if (i < 0) return display.length <= before + after ? display : '${display.substring(0, before + after)}…';
  final start = (mapped.source[i] - before).clamp(0, display.length);
  final endIndex = i + normalizedQuery.length - 1;
  final end = (mapped.source[endIndex] + 1 + after).clamp(0, display.length);
  return '${start > 0 ? '…' : ''}${display.substring(start, end).trim()}${end < display.length ? '…' : ''}';
}
