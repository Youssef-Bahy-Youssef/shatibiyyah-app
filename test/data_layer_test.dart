// The data layer over the real bundled snapshot (assets/content/content.sqlite),
// opened with the FFI SQLite factory so it runs under `flutter test`.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/commentary_repository.dart';
import 'package:shatibiyyah/data/content_store.dart';
import 'package:shatibiyyah/data/layout_repository.dart';
import 'package:shatibiyyah/data/matn_repository.dart';
import 'package:shatibiyyah/data/recording_repository.dart';
import 'package:shatibiyyah/data/rumuz_repository.dart';
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
  late RumuzRepository rumuz;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('content_store_test');
    store = await ContentStore.open(loadAsset: _loadFromDisk, supportDir: support, factory: databaseFactoryFfi);
    matn = await MatnRepository.load(store.db);
    layout = await LayoutRepository.load(store.db);
    books = await CommentaryRepository.load(store.db);
    recordings = await RecordingRepository.load(store.db);
    rumuz = await RumuzRepository.load(store.db);
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

  group('AppContent', () {
    test('a recording\'s windows are read once, at open', () async {
      final dir = await Directory.systemTemp.createTemp('app_content_test');
      final content = await AppContent.open(loadAsset: _loadFromDisk, supportDir: dir, factory: databaseFactoryFfi);
      addTearDown(() async {
        await content.store.close();
        await dir.delete(recursive: true);
      });
      for (final r in content.recordings.recordings) {
        expect(content.isUsable(r), isTrue);
        final windows = await content.windowsFor(r);
        expect(windows.lastVerse, 1173);
        // What the boot and a change of reciter ask for is what was found at open.
        expect(await content.windowsOrNull(r), same(windows));
      }
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

    // ADR 0011: a heading box is the frame of a printed title. The old app's boxes
    // had 15 strips of 33 to 38 px under their titles, and الخاتمة's was the line
    // of verse 1159.
    test('every heading box frames a title: tall enough, over its first verse, on no verse', () {
      final without = <String>[];
      for (final c in matn.chapters) {
        final header = layout.headerRegion(c.id);
        if (header == null) {
          without.add(c.shortLabel);
          continue;
        }
        final first = layout.verseRegion(c.fromVerse);
        expect(header.page, first.page, reason: c.shortLabel);
        expect(header.rect.height, greaterThanOrEqualTo(40), reason: c.shortLabel);
        expect(header.rect.bottom, lessThanOrEqualTo(first.rect.top), reason: c.shortLabel);
        for (final v in layout.versesOnPage(header.page)) {
          expect(layout.verseRegion(v).rect.overlaps(header.rect), isFalse, reason: '${c.shortLabel} on verse $v');
        }
      }
      expect(without, ['الخاتمة']); // the page prints no title for it
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
    test('two recordings, Qaryu the default and first (ADR 0034); each hosted on two HTTPS mirrors', () {
      expect(recordings.recordings.map((r) => r.slug), ['abdulhamid-alqaryu-1', 'muhammad-atiq-1']);
      expect(recordings.defaultRecording.slug, 'abdulhamid-alqaryu-1');
      for (final r in recordings.recordings) {
        final d = r.delivery!;
        // The hosted file is the timed file itself (no re-encode): same bytes, same hash.
        expect((d.sha256, d.bytes), (r.audioSha256, r.audioBytes), reason: r.slug);
        expect(d.urls, hasLength(2), reason: r.slug);
        expect(d.urls.every((u) => u.startsWith('https://') && u.endsWith('/${r.slug}-v1.mp3')), isTrue, reason: r.slug);
        expect(d.urls.first, startsWith('https://github.com/')); // GitHub first, the Internet Archive second
      }
    });

    test('the audio-v2 release first, then archive.org; Alqaryu is the CBR re-encode (F-01)', () {
      for (final r in recordings.recordings) {
        expect(r.delivery!.urls, [
          'https://github.com/Youssef-Bahy-Youssef/taysir-audio/releases/download/audio-v2/${r.slug}-v1.mp3',
          'https://archive.org/download/taysir-shatibiyyah-audio-v1/${r.slug}-v1.mp3',
        ], reason: r.slug);
      }
      final alqaryu = recordings.recordings.singleWhere((r) => r.slug == 'abdulhamid-alqaryu-1');
      final d = alqaryu.delivery!;
      expect(d.sha256, '95db96bfb49e63331b902953d684872e835be0c35060af6f52a849f1a1bc764b');
      expect(d.bytes, 125120817);
      expect((alqaryu.durationMs, d.durationMs), (10426723, 10426723));
      expect((alqaryu.timebaseStatus, alqaryu.timebaseOffsetMs), ('verified', 27));
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

  // The spans of snapshot schema 3 (plans 2.2, 2.3, 2.6; plan 2.4's lookups).
  group('spans', () {
    test('the snapshot is schema 3', () => expect(store.manifest.schemaVersion, 3));

    test('verse 226: «لِوَرْشٍ» is a name in the first hemistich, naming Warsh', () {
      final spans = rumuz.spansOf(226);
      expect(spans, hasLength(1));
      final s = spans.single;
      expect((s.hemistich, s.isName, s.symbol), (1, true, null));
      expect(matn.verse(226).firstHemistich.substring(s.start, s.end), 'لِوَرْشٍ');
      expect([for (final id in s.readerIds) rumuz.reader(id)!.name], ['ورش']);
    });

    test('verse 230: two letter symbols in the second hemistich, each with its code and readers', () {
      final spans = rumuz.spansOf(230);
      final second = matn.verse(230).secondHemistich;
      expect([for (final s in spans) (s.hemistich, s.symbol, second.substring(s.start, s.end))], [(2, 'ك', 'كَ'), (2, 'ظ', 'ظَ')]);
      expect(spans.every((s) => !s.isName), isTrue);
      final kaf = rumuz.byCode('ك')!;
      expect(spans.first.readerIds, kaf.readerIds);
      expect(rumuz.reader(kaf.readerIds.single)!.name, 'ابن عامر');
      expect(rumuz.byCode('ظ')!.readerIds, hasLength(4));
    });

    test('every span lies inside its hemistich', () {
      var total = 0, verses = 0;
      for (var n = 1; n <= matn.lastVerse; n++) {
        final v = matn.verse(n), spans = rumuz.spansOf(n);
        if (spans.isNotEmpty) verses++;
        for (final s in spans) {
          total++;
          final half = s.hemistich == 1 ? v.firstHemistich : v.secondHemistich;
          expect(s.start >= 0 && s.start < s.end && s.end <= half.length, isTrue, reason: 'verse $n');
          if (!s.isName) expect(rumuz.byCode(s.symbol!), isNotNull, reason: 'verse $n');
        }
      }
      expect((total, verses), (2193, 817));
    });

    test('Quranic quotations of a block: approved spans inside their segment', () async {
      final wafi = books.defaultBook;
      final block = (await books.blocksForVerse(wafi.id, 226)).first;
      final segments = {for (final s in await books.segments(block.id)) s.id: s};
      final spans = await books.quranSpans(block.id);
      expect(spans, isNotEmpty);
      for (final q in spans) {
        final text = segments[q.segmentId]!.text;
        expect(q.outerStart <= q.start && q.start < q.end && q.end <= q.outerEnd && q.outerEnd <= text.length, isTrue);
        expect(q.surah >= 1 && q.surah <= 114 && q.ayah >= 1, isTrue);
        expect(text.substring(q.start, q.end).trim().split(RegExp(r'\s+')).length, greaterThanOrEqualTo(2));
      }
    });

    test('matn quotes of a block: each names its verse, hemistich and the canonical words', () async {
      final wafi = books.defaultBook;
      final block = (await books.blocksForVerse(wafi.id, 226)).first;
      final segments = {for (final s in await books.segments(block.id)) s.id: s};
      final quotes = await books.matnQuotes(block.id);
      expect(quotes, isNotEmpty);
      final said = <String>{};
      for (final q in quotes) {
        final text = segments[q.segmentId]!.text;
        expect(q.outerStart <= q.start && q.start < q.end && q.end <= q.outerEnd && q.outerEnd <= text.length, isTrue);
        expect(q.verse, 226);
        final v = matn.verse(q.verse);
        final half = q.hemistich == 1 ? v.firstHemistich : v.secondHemistich;
        expect(q.verseStart >= 0 && q.verseStart < q.verseEnd && q.verseEnd <= half.length, isTrue);
        said.add('${text.substring(q.start, q.end)} → ${half.substring(q.verseStart, q.verseEnd)}');
      }
      // Al-Wafi's «(مسهلا)» and «(واحذفه)» point at the verse's own vocalized words.
      expect(said, containsAll(['مسهلا → مُسْهِلَا', 'واحذفه → واحْذِفْهُ']));
    });

    test('the counts of the full build', () async {
      Future<int> count(String table) async =>
          (await store.db.rawQuery('SELECT count(*) AS n FROM $table')).first['n']! as int;
      expect((await count('rumuz_spans'), await count('quran_spans'), await count('matn_quote_spans')), (2193, 4124, 1819));
    });
  });
}
