// lib/data/rumuz_repository.dart — the reader codes of verses 45–55 (snapshot
// tables readers and rumuz, migration 009), for «رموز القراء», and where each
// symbol and reader name sits in the verses (rumuz_spans, schema 3; ADRs 0015,
// 0021): what the rubric ink marks. A verse still in review has no spans.
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

enum RamzKind { letter, groupLetter, word }

class Reader {
  final String id;
  final String name;
  final bool isImam;
  final String? imamId;
  const Reader(this.id, this.name, this.isImam, this.imamId);
}

class Ramz {
  final String code;
  final RamzKind kind;
  final List<String> readerIds;
  final String label;
  final int fromVerse;
  final int toVerse;
  const Ramz(this.code, this.kind, this.readerIds, this.label, this.fromVerse, this.toVerse);
}

/// A reader symbol or a reader's name in a verse: UTF-16 offsets inside one hemistich.
class RumuzSpan {
  final int hemistich; // 1 or 2
  final int start, end;

  /// The code in [RumuzRepository.rumuz]; null for a name.
  final String? symbol;
  final List<String> readerIds;
  const RumuzSpan(this.hemistich, this.start, this.end, this.symbol, this.readerIds);

  bool get isName => symbol == null;
}

class RumuzRepository {
  final List<Reader> readers; // in order: each imam, then his two transmitters
  final List<Ramz> rumuz; // in the poem's order
  final Map<int, List<RumuzSpan>> _spans; // by verse number, in reading order
  const RumuzRepository(this.readers, this.rumuz, [this._spans = const {}]);

  /// The symbols and names of verse [verse], in reading order; empty when it has none or is in review.
  List<RumuzSpan> spansOf(int verse) => _spans[verse] ?? const [];

  Ramz? byCode(String code) {
    for (final r in rumuz) {
      if (r.code == code) return r;
    }
    return null;
  }

  Reader? reader(String id) {
    for (final r in readers) {
      if (r.id == id) return r;
    }
    return null;
  }

  static Future<RumuzRepository> load(Database db) async {
    final readers = [
      for (final r in await db.rawQuery('SELECT id, name, kind, imam_id FROM readers ORDER BY order_index'))
        Reader(r['id'] as String, r['name'] as String, r['kind'] == 'imam', r['imam_id'] as String?),
    ];
    final rumuz = [
      for (final r in await db.rawQuery(
          'SELECT code, kind, reader_ids_json, label, source_from_verse, source_to_verse FROM rumuz ORDER BY order_index'))
        Ramz(
          r['code'] as String,
          switch (r['kind']) { 'letter' => RamzKind.letter, 'group_letter' => RamzKind.groupLetter, _ => RamzKind.word },
          (jsonDecode(r['reader_ids_json'] as String) as List).cast<String>(),
          r['label'] as String,
          r['source_from_verse'] as int,
          r['source_to_verse'] as int,
        ),
    ];
    final spans = <int, List<RumuzSpan>>{};
    for (final r in await db.rawQuery(
        'SELECT v.verse_number, s.hemistich, s.start_utf16, s.end_utf16, s.symbol, s.reader_ids_json '
        'FROM rumuz_spans s JOIN matn_verses v ON v.id = s.matn_verse_id '
        'ORDER BY v.verse_number, s.hemistich, s.start_utf16')) {
      spans.putIfAbsent(r['verse_number'] as int, () => []).add(RumuzSpan(
            r['hemistich'] as int,
            r['start_utf16'] as int,
            r['end_utf16'] as int,
            r['symbol'] as String?,
            (jsonDecode(r['reader_ids_json'] as String) as List).cast<String>(),
          ));
    }
    return RumuzRepository(readers, rumuz, spans);
  }

  List<Ramz> ofKind(RamzKind kind) => [for (final r in rumuz) if (r.kind == kind) r];
}
