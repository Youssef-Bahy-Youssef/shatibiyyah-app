// lib/services/data_service.dart — the legacy reader's data model, now built from content.sqlite.
//
// Originally a port of js/data.js that parsed verses.json / chapters.json /
// timestamps.json. Those files are retired: lib/data/legacy_adapter.dart builds
// this object from the repositories (78 canonical chapters, the snapshot's page
// regions, the reviewed cues of the selected recording). The derived lookups
// below are unchanged, so the existing screens keep working until P4 replaces them.
//   verseMap         id   -> Box{ page, x, y, w, h, chapterId }
//   pageMap          page -> sorted id[]
//   chapterPageRange idx  -> { first, last } page
//   verseTimes[v]    start time (s) of verse v   (dense array)
import 'dart:ui';

import '../models/chapter.dart';
import '../models/verse.dart';

/// ported from data.js: export class ShatibiyyahData
class ShatibiyyahData {
  final int lastVerse;
  final double defaultDuration;
  final List<Chapter> chapters;

  /// start_verse -> chapter, for clean range cuts at chapter headers
  final Map<int, Chapter> startAtVerse = {};

  /// verseTimes[v] = start time (seconds) of verse v
  late final List<double?> verseTimes;

  final Map<int, Box> verseMap = {};
  final Map<int, List<int>> pageMap = {};
  int pageCount = 0;

  /// chapterIdx -> { first, last } page numbers
  final Map<int, List<int>> chapterPageRange = {}; // [first,last]

  /// page -> [chapterIdx,…] whose HEADER sits on that page
  final Map<int, List<int>> chaptersByPage = {};

  /// [startSeconds] is indexed by verse number (index 0 unused); [durationSeconds]
  /// is the recording's length, or 0 when no recording is available.
  ShatibiyyahData(List<Verse> verses, List<double?> startSeconds, this.chapters,
      {required double durationSeconds})
      : lastVerse = verses.length,
        defaultDuration = durationSeconds {
    // start_verse -> chapter
    for (final c in chapters) {
      startAtVerse[c.startVerse] = c;
    }

    // verseTimes
    verseTimes = List<double?>.filled(lastVerse + 2, null);
    for (var v = 1; v < startSeconds.length && v < verseTimes.length; v++) {
      verseTimes[v] = startSeconds[v];
    }

    // verseMap + pageMap from the bounding boxes
    int maxPage = 0;
    for (final o in verses) {
      final ch = chapterIndexForVerse(o.id);
      verseMap[o.id] = Box(o.page, o.x, o.y, o.width, o.height, ch);
      (pageMap[o.page] ??= []).add(o.id);
      if (o.page > maxPage) maxPage = o.page;
    }
    for (final ids in pageMap.values) {
      ids.sort();
    }
    pageCount = maxPage;

    // chapterPageRange: chapterIdx -> { first, last } page numbers
    for (int i = 0; i < chapters.length; i++) {
      final c = chapters[i];
      final first = pageOfVerse(c.startVerse);
      final last = pageOfVerse(c.endVerse);
      if (first != null && last != null) chapterPageRange[i] = [first, last];
    }

    // chaptersByPage: a heading lives on the page its region names (ADR 0011). A
    // chapter with no heading (الخاتمة) has nothing on any page to draw or tap.
    for (int i = 0; i < chapters.length; i++) {
      final p = chapters[i].page;
      if (p == null || chapterBox(i) == null) continue;
      (chaptersByPage[p] ??= []).add(i);
    }
  }

  /// ported from data.js: getChapterForVerse(v) — deepest (highest start_verse) covering v.
  Chapter? getChapterForVerse(int v) {
    final i = chapterIndexForVerse(v);
    return i >= 0 ? chapters[i] : null;
  }

  /// ported from data.js: chapterIndexForVerse(v)
  int chapterIndexForVerse(int v) {
    int best = -1;
    int bestStart = -1;
    for (int i = 0; i < chapters.length; i++) {
      final c = chapters[i];
      if (c.startVerse <= v && v <= c.endVerse) {
        if (best < 0 || c.startVerse > bestStart) {
          best = i;
          bestStart = c.startVerse;
        }
      }
    }
    return best;
  }

  Box? getBox(int id) => verseMap[id]; // ported from data.js: getBox(id)

  /// { first, last } page numbers for a chapter index (null if underivable).
  List<int>? pageRangeOfChapter(int i) => chapterPageRange[i];

  int? pageOfVerse(int id) => verseMap[id]?.page; // ported from data.js: pageOfVerse(id)

  List<int> versesOnPage(int page) => pageMap[page] ?? const []; // versesOnPage(page)

  /// ported from data.js: chapterBox(i) — header rect in image space, or null.
  Rect? chapterBox(int i) {
    if (i < 0 || i >= chapters.length) return null;
    final c = chapters[i];
    if (c.x == null || c.width == null) return null;
    return Rect.fromLTWH(c.x!, c.y!, c.width!, c.height!);
  }

  /// The page of chapter [i]'s heading, or of its first verse when it has none.
  int? pageOfChapter(int i) {
    if (i < 0 || i >= chapters.length) return null;
    return chapters[i].page ?? pageOfVerse(chapters[i].startVerse);
  }

  /// ported from data.js: chaptersOnPage(page)
  List<int> chaptersOnPage(int page) => chaptersByPage[page] ?? const [];
}
