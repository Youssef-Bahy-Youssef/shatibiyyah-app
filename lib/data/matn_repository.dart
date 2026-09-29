// lib/data/matn_repository.dart — verses, chapters and parts, held in memory.
//
// 1173 verses, 78 chapters and 4 parts are loaded once at startup, so every
// lookup the reader makes on each verse change is synchronous. IDs are the
// content database's stable IDs (verse:shatibiyyah:226, chapter:shatibiyyah:011).
import 'package:sqflite/sqflite.dart';

class MatnVerse {
  final String id;
  final int number;
  final String chapterId;
  final String firstHemistich;
  final String secondHemistich;
  final String normalizedText;
  const MatnVerse(this.id, this.number, this.chapterId, this.firstHemistich, this.secondHemistich,
      this.normalizedText);
}

class MatnChapter {
  final String id;
  final int orderIndex;
  final String title;
  final String shortLabel;
  final String partId;
  final int fromVerse;
  final int toVerse;
  const MatnChapter(this.id, this.orderIndex, this.title, this.shortLabel, this.partId, this.fromVerse,
      this.toVerse);

  int get verseCount => toVerse - fromVerse + 1;
  bool contains(int verse) => fromVerse <= verse && verse <= toVerse;
}

class MatnPart {
  final String id;
  final String slug;
  final int orderIndex;
  final String title;
  final int fromVerse;
  final int toVerse;
  const MatnPart(this.id, this.slug, this.orderIndex, this.title, this.fromVerse, this.toVerse);
}

class MatnRepository {
  final List<MatnVerse> verses; // index = verse number - 1
  final List<MatnChapter> chapters; // in order
  final List<MatnPart> parts; // in order
  final Map<String, MatnChapter> _chapterById;
  final List<int> _chapterIndexOfVerse; // verse number -> index into chapters

  MatnRepository._(this.verses, this.chapters, this.parts)
      : _chapterById = {for (final c in chapters) c.id: c},
        _chapterIndexOfVerse = List<int>.filled(verses.length + 1, -1) {
    for (var i = 0; i < chapters.length; i++) {
      for (var v = chapters[i].fromVerse; v <= chapters[i].toVerse; v++) {
        _chapterIndexOfVerse[v] = i;
      }
    }
  }

  static Future<MatnRepository> load(Database db) async {
    final verseRows = await db.rawQuery(
        'SELECT id, verse_number, chapter_id, first_hemistich, second_hemistich, normalized_text '
        'FROM matn_verses ORDER BY verse_number');
    final chapterRows = await db.rawQuery(
        'SELECT id, order_index, title, short_label, part_id, from_verse, to_verse FROM chapters ORDER BY order_index');
    final partRows = await db.rawQuery(
        'SELECT id, slug, order_index, title, from_verse, to_verse FROM matn_parts ORDER BY order_index');
    final verses = [
      for (final r in verseRows)
        MatnVerse(r['id'] as String, r['verse_number'] as int, r['chapter_id'] as String,
            r['first_hemistich'] as String, r['second_hemistich'] as String, r['normalized_text'] as String),
    ];
    for (var i = 0; i < verses.length; i++) {
      if (verses[i].number != i + 1) {
        throw StateError('verse numbers are not contiguous at ${verses[i].number}');
      }
    }
    return MatnRepository._(
      verses,
      [
        for (final r in chapterRows)
          MatnChapter(r['id'] as String, r['order_index'] as int, r['title'] as String, r['short_label'] as String,
              r['part_id'] as String, r['from_verse'] as int, r['to_verse'] as int),
      ],
      [
        for (final r in partRows)
          MatnPart(r['id'] as String, r['slug'] as String, r['order_index'] as int, r['title'] as String,
              r['from_verse'] as int, r['to_verse'] as int),
      ],
    );
  }

  int get lastVerse => verses.length;

  MatnVerse verse(int number) => verses[number - 1];

  MatnChapter chapterOfVerse(int number) => chapters[_chapterIndexOfVerse[number]];

  MatnChapter chapter(String id) => _chapterById[id]!;

  MatnPart partOf(MatnChapter chapter) => parts.firstWhere((p) => p.id == chapter.partId);

  List<MatnChapter> chaptersInPart(MatnPart part) =>
      chapters.where((c) => c.partId == part.id).toList(growable: false);
}
