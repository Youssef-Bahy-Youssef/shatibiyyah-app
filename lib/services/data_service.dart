// lib/services/data_service.dart — pure data layer for الشاطبية.
// 100% port of js/data.js. Loads the three source files and pre-builds O(1) lookups:
//   verseMap         id   -> Box{ page, x, y, w, h, chapterId }
//   pageMap          page -> sorted id[]
//   chapterPageRange idx  -> { first, last } page
//   verseTimes[v]    start time (s) of verse v   (dense array)
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/services.dart' show rootBundle;

import '../models/chapter.dart';
import '../models/verse.dart';

const int kLastVerse = 1173; // ported from data.js: LAST_VERSE
const double kDefaultDuration = 8916; // ported from data.js: DEFAULT_DURATION

/// ported from data.js: export async function loadData()
Future<ShatibiyyahData> loadData() async {
  final results = await Future.wait([
    rootBundle.loadString('assets/data/verses.json'),
    rootBundle.loadString('assets/data/timestamps.json'),
    rootBundle.loadString('assets/data/chapters.json'),
  ]);
  final verses = (json.decode(results[0]) as List)
      .map((e) => Verse.fromJson(e as Map<String, dynamic>))
      .toList();
  final timestamps = json.decode(results[1]) as Map<String, dynamic>;
  final chapters = (json.decode(results[2]) as List)
      .map((e) => Chapter.fromJson(e as Map<String, dynamic>))
      .toList();
  return ShatibiyyahData(verses, timestamps, chapters);
}

/// ported from data.js: export class ShatibiyyahData
class ShatibiyyahData {
  final int lastVerse = kLastVerse;
  final double defaultDuration = kDefaultDuration;
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

  ShatibiyyahData(
      List<Verse> verses, Map<String, dynamic> timestamps, this.chapters) {
    // start_verse -> chapter
    for (final c in chapters) {
      startAtVerse[c.startVerse] = c;
    }

    // verseTimes
    verseTimes = List<double?>.filled(lastVerse + 2, null);
    timestamps.forEach((k, v) {
      final i = int.tryParse(k);
      if (i != null && i < verseTimes.length) verseTimes[i] = (v as num).toDouble();
    });

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

    // chaptersByPage: header lives on pageOfVerse(start_verse)
    for (int i = 0; i < chapters.length; i++) {
      final p = pageOfVerse(chapters[i].startVerse);
      if (p == null) continue;
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

  /// ported from data.js: pageOfChapter(i)
  int? pageOfChapter(int i) {
    if (i < 0 || i >= chapters.length) return null;
    return pageOfVerse(chapters[i].startVerse);
  }

  /// ported from data.js: chaptersOnPage(page)
  List<int> chaptersOnPage(int page) => chaptersByPage[page] ?? const [];
}
