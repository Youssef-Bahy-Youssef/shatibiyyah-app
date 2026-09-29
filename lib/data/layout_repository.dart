// lib/data/layout_repository.dart — where each verse and chapter heading sits on the scans.
//
// Every page image is 1130×1735 px; rectangles are in those native pixels. Held in
// memory (1173 + 78 rows) because the page viewer hit-tests on every tap.
import 'dart:ui' show Offset, Rect;

import 'package:sqflite/sqflite.dart';

const double kPageWidth = 1130;
const double kPageHeight = 1735;

class PageRegion {
  final int page;
  final Rect rect;
  const PageRegion(this.page, this.rect);
}

class LayoutRepository {
  final Map<int, PageRegion> _verseRegion; // verse number -> region
  final Map<String, PageRegion> _headerRegion; // chapter id -> region
  final Map<int, List<int>> _versesOnPage; // page -> verse numbers, ascending
  final Map<int, List<String>> _headersOnPage; // page -> chapter ids
  final int pageCount;

  LayoutRepository._(this._verseRegion, this._headerRegion, this._versesOnPage, this._headersOnPage,
      this.pageCount);

  static Future<LayoutRepository> load(Database db) async {
    Rect rect(Map<String, Object?> r) => Rect.fromLTWH(
        (r['x'] as int).toDouble(), (r['y'] as int).toDouble(),
        (r['width'] as int).toDouble(), (r['height'] as int).toDouble());

    final verseRegion = <int, PageRegion>{};
    final versesOnPage = <int, List<int>>{};
    for (final r in await db.rawQuery(
        'SELECT v.verse_number, r.page_number, r.x, r.y, r.width, r.height '
        'FROM verse_regions r JOIN matn_verses v ON v.id = r.matn_verse_id ORDER BY v.verse_number')) {
      final number = r['verse_number'] as int;
      final page = r['page_number'] as int;
      verseRegion[number] = PageRegion(page, rect(r));
      (versesOnPage[page] ??= []).add(number);
    }
    final headerRegion = <String, PageRegion>{};
    final headersOnPage = <int, List<String>>{};
    for (final r in await db.rawQuery(
        'SELECT h.chapter_id, h.page_number, h.x, h.y, h.width, h.height FROM chapter_header_regions h '
        'JOIN chapters c ON c.id = h.chapter_id ORDER BY c.order_index')) {
      final id = r['chapter_id'] as String;
      final page = r['page_number'] as int;
      headerRegion[id] = PageRegion(page, rect(r));
      (headersOnPage[page] ??= []).add(id);
    }
    final pageCount = versesOnPage.keys.fold<int>(0, (a, b) => a > b ? a : b);
    return LayoutRepository._(verseRegion, headerRegion, versesOnPage, headersOnPage, pageCount);
  }

  PageRegion verseRegion(int verse) => _verseRegion[verse]!;

  int pageOfVerse(int verse) => _verseRegion[verse]!.page;

  List<int> versesOnPage(int page) => _versesOnPage[page] ?? const [];

  int firstVerseOnPage(int page) => versesOnPage(page).first;

  PageRegion? headerRegion(String chapterId) => _headerRegion[chapterId];

  List<String> headersOnPage(int page) => _headersOnPage[page] ?? const [];

  /// The verse whose rectangle contains [point] (native page pixels), if any.
  int? verseAt(int page, Offset point, {double slop = 0}) {
    for (final v in versesOnPage(page)) {
      if (_verseRegion[v]!.rect.inflate(slop).contains(point)) return v;
    }
    return null;
  }
}
