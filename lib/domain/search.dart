// lib/domain/search.dart — «البحث» (features-v3 search): verses, chapters and the
// three books at once, blind to vowel marks and hamza seats.
//
// The query goes through normalizeMatching, the same normalization the pipeline
// stored in content.sqlite, so «بدات» finds «بَدَأْتُ». Verses and chapter titles are
// matched in memory; the books (2.4 M characters) with SQL on
// commentary_segments.normalized_text, one hit per block, a page at a time.
// A query of digits alone is a verse or page number (queryNumber); the user's
// notes are matched in memory (notesMatching).
import 'package:sqflite/sqflite.dart' show Sqflite;

import '../data/app_content.dart';
import '../data/matn_repository.dart';
import '../data/user_store.dart' show Note;
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

/// Book passages per page (the count still reports all of them).
const int kCommentaryPageSize = 30;

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

    final total = Sqflite.firstIntValue(await content.store.db.rawQuery(
          'SELECT COUNT(DISTINCT s.commentary_block_id) FROM commentary_segments s '
          'JOIN commentary_blocks b ON b.id = s.commentary_block_id WHERE $_matches',
          [q],
        )) ??
        0;
    final hits = total == 0 ? const <CommentaryHit>[] : await commentaryPage(q, 0);
    return (results: SearchResults(q, chapters, verses, hits), commentaryTotal: total);
  }

  /// Book passages [offset] to [offset] + [kCommentaryPageSize] for the normalized
  /// query [q], in the poem's order: one per block, its first matching segment. The
  /// grouping is SQLite's, so only a page of text crosses to Dart (a common word
  /// matches over a thousand blocks).
  Future<List<CommentaryHit>> commentaryPage(String q, int offset) async {
    final rows = await content.store.db.rawQuery(
      'SELECT s.display_text AS display, b.commentary_id AS book, b.from_verse AS from_verse, '
      'b.to_verse AS to_verse, MIN(s.order_index) '
      'FROM commentary_segments s JOIN commentary_blocks b ON b.id = s.commentary_block_id '
      'JOIN commentaries c ON c.id = b.commentary_id '
      'WHERE $_matches GROUP BY s.commentary_block_id '
      'ORDER BY b.from_verse, c.display_order, b.source_order LIMIT ? OFFSET ?',
      [q, kCommentaryPageSize, offset],
    );
    final titles = {for (final b in content.books.books) b.id: b.shortTitle};
    return [
      for (final r in rows)
        CommentaryHit(
          r['book'] as String,
          titles[r['book']] ?? '',
          r['from_verse'] as int,
          (r['to_verse'] as int?) ?? r['from_verse'] as int,
          snippetAround(r['display'] as String, q),
        ),
    ];
  }

  static const _matches = "instr(s.normalized_text, ?) > 0 AND b.from_verse IS NOT NULL "
      "AND s.segment_type != 'citation_lead_in'";
}

/// The verse or page number a query asks for when it is only digits (Arabic-Indic,
/// Persian or Latin), else null.
int? queryNumber(String query) {
  final t = query.trim();
  if (t.isEmpty || t.length > 4) return null;
  var n = 0;
  for (final c in t.runes) {
    final d = c >= 0x30 && c <= 0x39
        ? c - 0x30
        : c >= 0x660 && c <= 0x669
            ? c - 0x660
            : c >= 0x6F0 && c <= 0x6F9
                ? c - 0x6F0
                : -1;
    if (d < 0) return null;
    n = n * 10 + d;
  }
  return n;
}

/// The user's notes whose text contains the normalized query [q], in verse order.
List<Note> notesMatching(Iterable<Note> notes, String q) =>
    [for (final n in notes) if (normalizeMatching(n.body).contains(q)) n]..sort((a, b) => a.verse.compareTo(b.verse));

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
