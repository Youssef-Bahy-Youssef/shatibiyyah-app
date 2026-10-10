// lib/data/commentary_repository.dart — the three bundled books, queried on demand.
//
// A block may explain one verse or a run of verses («يشرح الأبيات ٢٣٠–٢٣٣ معًا»);
// commentary_block_verses is the truth for which verses it covers. A footnote's
// anchor_utf16, when set, points at its marker digits inside the segment's
// display_text; when null the footnote is listed after the block.
import 'package:sqflite/sqflite.dart';

class Book {
  final String id;
  final String slug;
  final String title;
  final String shortTitle;
  final String? author;
  final String? authorFull;
  final int? deathYearH;
  final int displayOrder;
  final bool isDefault;
  final String? licenseNote;
  const Book(this.id, this.slug, this.title, this.shortTitle, this.author, this.authorFull, this.deathYearH,
      this.displayOrder, this.isDefault, this.licenseNote);
}

class BlockRef {
  final String id;
  final String bookId;
  final int sourceOrder;
  final int? fromVerse;
  final int? toVerse;
  final String reviewStatus;
  final String relation; // explains | quotes | references
  const BlockRef(this.id, this.bookId, this.sourceOrder, this.fromVerse, this.toVerse, this.reviewStatus,
      this.relation);

  bool get grouped => fromVerse != null && toVerse != null && toVerse! > fromVerse!;
  bool get needsReview => reviewStatus == 'needs_review' || reviewStatus == 'unresolved';
}

class Segment {
  final String id;
  final int orderIndex;
  final String type; // meaning, language, language_and_meaning, generic, preamble, …
  final String? heading;
  final String text;
  const Segment(this.id, this.orderIndex, this.type, this.heading, this.text);

  bool get isLanguage => type == 'language' || type == 'language_and_meaning';
}

class Footnote {
  final String id;
  final String? segmentId;
  final int orderIndex;
  final String? marker;
  final int? anchorUtf16;
  final String text;
  const Footnote(this.id, this.segmentId, this.orderIndex, this.marker, this.anchorUtf16, this.text);
}

class BlockSource {
  final String provider;
  final int sourcePage;
  final String? url;
  final int? printedPage;
  const BlockSource(this.provider, this.sourcePage, this.url, this.printedPage);
}

/// A Quranic quotation in a segment (ADR 0014): UTF-16 offsets into its text.
/// [start]…[end] are the words; [outerStart]…[outerEnd] also cover the book's
/// own marks around them, which ﴿ ﴾ replace.
class QuranSpan {
  final String segmentId;
  final int start, end, outerStart, outerEnd;
  final int surah, ayah;
  const QuranSpan(this.segmentId, this.start, this.end, this.outerStart, this.outerEnd, this.surah, this.ayah);
}

/// A commentary's quotation of the verse it explains (ADR 0022): where it is in
/// the segment, and the canonical words it quotes, inside one hemistich of [verse].
class MatnQuoteSpan {
  final String segmentId;
  final int start, end, outerStart, outerEnd;
  final int verse, hemistich, verseStart, verseEnd;
  const MatnQuoteSpan(this.segmentId, this.start, this.end, this.outerStart, this.outerEnd, this.verse,
      this.hemistich, this.verseStart, this.verseEnd);
}

class CommentaryRepository {
  final Database db;
  final List<Book> books; // in display order
  CommentaryRepository._(this.db, this.books);

  static Future<CommentaryRepository> load(Database db) async {
    final rows = await db.rawQuery(
        'SELECT id, slug, title, short_title, author, author_full, death_year_h, display_order, is_default, '
        'license_note FROM commentaries ORDER BY display_order');
    return CommentaryRepository._(db, [
      for (final r in rows)
        Book(r['id'] as String, r['slug'] as String, r['title'] as String, r['short_title'] as String,
            r['author'] as String?, r['author_full'] as String?, r['death_year_h'] as int?,
            r['display_order'] as int, r['is_default'] == 1, r['license_note'] as String?),
    ]);
  }

  Book get defaultBook => books.firstWhere((b) => b.isDefault, orElse: () => books.first);

  /// The blocks of [bookId] that concern verse [verseNumber]: explanations first.
  Future<List<BlockRef>> blocksForVerse(String bookId, int verseNumber) async {
    final rows = await db.rawQuery(
        'SELECT b.id, b.commentary_id, b.source_order, b.from_verse, b.to_verse, b.review_status, '
        'bv.relation_type FROM commentary_block_verses bv '
        'JOIN commentary_blocks b ON b.id = bv.commentary_block_id '
        "WHERE bv.matn_verse_id = ? AND b.commentary_id = ? "
        "ORDER BY bv.relation_type <> 'explains', b.source_order",
        ['verse:shatibiyyah:$verseNumber', bookId]);
    return rows.map(_blockRef).toList(growable: false);
  }

  /// The previous (-1) or next (+1) block of the same book, in book order.
  Future<BlockRef?> neighbour(BlockRef block, int direction) async {
    final rows = await db.rawQuery(
        'SELECT id, commentary_id, source_order, from_verse, to_verse, review_status, '
        "'explains' AS relation_type FROM commentary_blocks "
        'WHERE commentary_id = ? AND source_order ${direction < 0 ? '<' : '>'} ? AND from_verse IS NOT NULL '
        'ORDER BY source_order ${direction < 0 ? 'DESC' : 'ASC'} LIMIT 1',
        [block.bookId, block.sourceOrder]);
    return rows.isEmpty ? null : _blockRef(rows.first);
  }

  Future<List<Segment>> segments(String blockId) async {
    final rows = await db.rawQuery(
        'SELECT id, order_index, segment_type, source_heading, display_text FROM commentary_segments '
        "WHERE commentary_block_id = ? AND trim(display_text) <> '' ORDER BY order_index",
        [blockId]);
    return [
      for (final r in rows)
        Segment(r['id'] as String, r['order_index'] as int, r['segment_type'] as String,
            r['source_heading'] as String?, r['display_text'] as String),
    ];
  }

  Future<List<Footnote>> footnotes(String blockId) async {
    final rows = await db.rawQuery(
        'SELECT id, commentary_segment_id, order_index, marker, anchor_utf16, display_text FROM footnotes '
        'WHERE commentary_block_id = ? ORDER BY order_index',
        [blockId]);
    return [
      for (final r in rows)
        Footnote(r['id'] as String, r['commentary_segment_id'] as String?, r['order_index'] as int,
            r['marker'] as String?, r['anchor_utf16'] as int?, r['display_text'] as String),
    ];
  }

  /// The approved Quranic quotations in [blockId]'s segments, in reading order.
  Future<List<QuranSpan>> quranSpans(String blockId) async {
    final rows = await db.rawQuery(
        'SELECT q.commentary_segment_id, q.start_utf16, q.end_utf16, q.outer_start_utf16, q.outer_end_utf16, '
        'q.surah, q.ayah FROM quran_spans q JOIN commentary_segments s ON s.id = q.commentary_segment_id '
        'WHERE s.commentary_block_id = ? ORDER BY s.order_index, q.start_utf16',
        [blockId]);
    return [
      for (final r in rows)
        QuranSpan(r['commentary_segment_id'] as String, r['start_utf16'] as int, r['end_utf16'] as int,
            r['outer_start_utf16'] as int, r['outer_end_utf16'] as int, r['surah'] as int, r['ayah'] as int),
    ];
  }

  /// The approved quotations of the verse in [blockId]'s segments, in reading order.
  Future<List<MatnQuoteSpan>> matnQuotes(String blockId) async {
    final rows = await db.rawQuery(
        'SELECT q.commentary_segment_id, q.start_utf16, q.end_utf16, q.outer_start_utf16, q.outer_end_utf16, '
        'v.verse_number, q.hemistich, q.verse_start_utf16, q.verse_end_utf16 FROM matn_quote_spans q '
        'JOIN commentary_segments s ON s.id = q.commentary_segment_id '
        'JOIN matn_verses v ON v.id = q.matn_verse_id '
        'WHERE s.commentary_block_id = ? ORDER BY s.order_index, q.start_utf16',
        [blockId]);
    return [
      for (final r in rows)
        MatnQuoteSpan(r['commentary_segment_id'] as String, r['start_utf16'] as int, r['end_utf16'] as int,
            r['outer_start_utf16'] as int, r['outer_end_utf16'] as int, r['verse_number'] as int,
            r['hemistich'] as int, r['verse_start_utf16'] as int, r['verse_end_utf16'] as int),
    ];
  }

  Future<List<BlockSource>> sources(String blockId) async {
    final rows = await db.rawQuery(
        'SELECT source_provider, source_page, source_url, printed_page FROM block_sources '
        'WHERE commentary_block_id = ? ORDER BY source_provider, source_page',
        [blockId]);
    return [
      for (final r in rows)
        BlockSource(r['source_provider'] as String, r['source_page'] as int, r['source_url'] as String?,
            r['printed_page'] as int?),
    ];
  }

  static BlockRef _blockRef(Map<String, Object?> r) => BlockRef(
        r['id'] as String,
        r['commentary_id'] as String,
        r['source_order'] as int,
        r['from_verse'] as int?,
        r['to_verse'] as int?,
        r['review_status'] as String,
        r['relation_type'] as String,
      );
}
