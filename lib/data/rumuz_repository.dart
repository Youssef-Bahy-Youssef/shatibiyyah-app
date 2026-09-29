// lib/data/rumuz_repository.dart — the reader codes of verses 45–55 (snapshot
// tables readers and rumuz, migration 009): for «رموز القراء».
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

class RumuzRepository {
  final List<Reader> readers; // in order: each imam, then his two transmitters
  final List<Ramz> rumuz; // in the poem's order
  const RumuzRepository(this.readers, this.rumuz);

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
    return RumuzRepository(readers, rumuz);
  }

  List<Ramz> ofKind(RamzKind kind) => [for (final r in rumuz) if (r.kind == kind) r];
}
