// The data layer over the real bundled snapshot (assets/content/content.sqlite),
// opened with the FFI SQLite factory so it runs under `flutter test`.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/data/commentary_repository.dart';
import 'package:shatibiyyah/data/content_store.dart';
import 'package:shatibiyyah/data/layout_repository.dart';
import 'package:shatibiyyah/data/matn_repository.dart';
import 'package:shatibiyyah/data/recording_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<ByteData> _loadFromDisk(String key) async {
  final bytes = await File(key).readAsBytes();
  return ByteData.sublistView(bytes);
}

void main() {
  sqfliteFfiInit();
  late Directory support;
  late ContentStore store;
  late MatnRepository matn;
  late LayoutRepository layout;
  late CommentaryRepository books;
  late RecordingRepository recordings;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('content_store_test');
    store = await ContentStore.open(loadAsset: _loadFromDisk, supportDir: support, factory: databaseFactoryFfi);
    matn = await MatnRepository.load(store.db);
    layout = await LayoutRepository.load(store.db);
    books = await CommentaryRepository.load(store.db);
    recordings = await RecordingRepository.load(store.db);
  });

  tearDownAll(() async {
    await store.close();
    await support.delete(recursive: true);
  });

  group('ContentStore', () {
    test('installs one copy named after the content hash', () {
      final files = Directory('${support.path}/content').listSync().whereType<File>().toList();
      expect(files.map((f) => f.uri.pathSegments.last), [store.manifest.fileName]);
    });

    test('reopening reuses the installed copy', () async {
      final again = await ContentStore.open(
          loadAsset: _loadFromDisk, supportDir: support, factory: databaseFactoryFfi);
      expect(again.manifest.contentSha256, store.manifest.contentSha256);
    });
  });

  group('MatnRepository', () {
    test('1173 verses, 78 chapters, 4 parts', () {
      expect(matn.lastVerse, 1173);
      expect(matn.chapters, hasLength(78));
      expect(matn.parts.map((p) => p.slug), ['intro', 'usul', 'farsh', 'closing']);
    });

    test('verse 226 and its chapter', () {
      final v = matn.verse(226);
      expect(v.firstHemistich, 'وَحَرِّكْ لِوَرْشٍ كُلَّ سَاكِنٍ آخِرٍ');
      final c = matn.chapterOfVerse(226);
      expect((c.fromVerse, c.toVerse, c.orderIndex), (226, 234, 11));
      expect(matn.partOf(c).title, 'الأصول');
    });

    test('the النور merge: verse 913 belongs to سورة النور 912–919', () {
      final c = matn.chapterOfVerse(913);
      expect((c.fromVerse, c.toVerse), (912, 919));
    });

    test('short label of the introduction', () {
      expect(matn.chapters.first.shortLabel, 'خطبة الكتاب');
    });
  });

  group('LayoutRepository', () {
    test('94 pages; verse 226 on page 19 where the prototype draws it', () {
      expect(layout.pageCount, 94);
      final r = layout.verseRegion(226);
      expect(r.page, 19);
      expect((r.rect.left, r.rect.top, r.rect.width, r.rect.height), (70.0, 220.0, 996.0, 75.0));
      expect(layout.versesOnPage(19), containsAllInOrder([226, 237]));
    });

    test('hit-testing a point inside verse 229 on page 19', () {
      expect(layout.verseAt(19, const Offset(500, 560)), 229);
    });

    test('chapter 11 header on page 19', () {
      final id = matn.chapters[11].id;
      expect(layout.headerRegion(id)!.page, 19);
      expect(layout.headersOnPage(19), contains(id));
    });
  });

  group('CommentaryRepository', () {
    test('three books in order, Al-Wafi the default', () {
      expect(books.books.map((b) => b.shortTitle), ['الوافي', 'إبراز المعاني', 'سراج القارئ']);
      expect(books.defaultBook.slug, 'al-wafi');
    });

    test('verse 231 is explained by Al-Wafi\'s grouped block 230–233', () async {
      final blocks = await books.blocksForVerse(books.defaultBook.id, 231);
      expect(blocks.first.id, 'block:shatibiyyah:al-wafi:230-233');
      expect(blocks.first.grouped, isTrue);
      expect(blocks.first.relation, 'explains');
    });

    test('every verse has an explanation in every book', () async {
      for (final book in books.books) {
        final missing = await store.db.rawQuery(
            'SELECT COUNT(*) AS n FROM matn_verses v WHERE NOT EXISTS (SELECT 1 FROM commentary_block_verses bv '
            "JOIN commentary_blocks b ON b.id = bv.commentary_block_id WHERE bv.matn_verse_id = v.id "
            "AND b.commentary_id = ? AND bv.relation_type = 'explains')",
            [book.id]);
        expect(missing.first['n'], 0, reason: book.slug);
      }
    });

    test('verse 1 in Al-Wafi has a language segment', () async {
      final block = (await books.blocksForVerse(books.defaultBook.id, 1)).first;
      final segments = await books.segments(block.id);
      expect(segments.any((s) => s.isLanguage), isTrue);
    });

    test('footnote anchors land on their marker (Dart string indices)', () async {
      final rows = await store.db.rawQuery(
          'SELECT s.display_text, f.anchor_utf16, f.marker FROM footnotes f '
          'JOIN commentary_segments s ON s.id = f.commentary_segment_id WHERE f.anchor_utf16 IS NOT NULL');
      expect(rows.length, greaterThan(1700));
      for (final r in rows) {
        final text = r['display_text'] as String;
        final at = r['anchor_utf16'] as int;
        final marker = r['marker'] as String;
        expect(text.substring(at, at + marker.length), marker);
      }
    });

    test('previous / next block and the source line', () async {
      final block = (await books.blocksForVerse(books.defaultBook.id, 226)).first;
      expect((await books.neighbour(block, -1))!.toVerse, 225);
      expect((await books.neighbour(block, 1))!.fromVerse, 227);
      final sources = await books.sources(block.id);
      expect(sources.first.url, startsWith('https://quranpedia.net/book/436/'));
    });
  });

  group('RecordingRepository', () {
    test('two recordings, Atiq the default; no delivery file yet', () {
      expect(recordings.recordings, hasLength(2));
      expect(recordings.defaultRecording.slug, 'muhammad-atiq-1');
      expect(recordings.recordings.every((r) => r.delivery == null), isTrue);
    });

    test('cues are complete and strictly increasing', () async {
      for (final r in recordings.recordings) {
        final cues = await recordings.cues(r.id, matn.lastVerse);
        for (var v = 1; v <= matn.lastVerse; v++) {
          expect(cues[v], greaterThanOrEqualTo(0), reason: '${r.slug} verse $v');
          if (v > 1) expect(cues[v], greaterThan(cues[v - 1]), reason: '${r.slug} verse $v');
        }
      }
    });

    test('77 spoken chapter titles per recording', () async {
      for (final r in recordings.recordings) {
        expect((await recordings.announcements(r.id)).length, 77);
      }
    });
  });
}
