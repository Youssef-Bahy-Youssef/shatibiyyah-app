// lib/domain/playback_windows.dart — where each verse and chapter starts and ends in a recording.
//
// Pure and synchronous. The rule is V2 §3.5 / E8, and the V2 Q4/Q6 SQL is its
// test oracle (test/playback_windows_test.dart runs that SQL against the bundled
// snapshot):
//
//   end(v)          = the non-disputed spoken title of the chapter starting at v+1,
//                     if it falls strictly inside (cue(v), cue(v+1)); else cue(v+1);
//                     for the last verse, the end of the file
//   chapter start   = its non-disputed spoken title if that is no later than the
//                     first verse's cue, else the first verse's cue
//   chapter end     = end(last verse)
//
// Pre-roll (a fixed lead before a verse when playback *jumps* to it) is applied
// only by `seekStart`, never inside continuous play.
import 'dart:math' as math;
import 'dart:typed_data';

/// What is audible at a position: a verse, or the spoken title of a chapter.
class PlayingAt {
  final int verse; // the verse whose window contains the position (the next verse during a title)
  final bool inTitle; // true while a chapter's spoken title plays
  const PlayingAt(this.verse, {this.inTitle = false});
  @override
  bool operator ==(Object other) => other is PlayingAt && other.verse == verse && other.inTitle == inTitle;
  @override
  int get hashCode => Object.hash(verse, inTitle);
  @override
  String toString() => 'PlayingAt($verse${inTitle ? ', title' : ''})';
}

class PlaybackWindows {
  /// Start of each verse in ms, indexed by verse number (index 0 unused).
  final Int32List cues;
  final int durationMs;

  /// Non-disputed spoken titles, keyed by the first verse of their chapter.
  final Map<int, int> titleAtFirstVerse;

  PlaybackWindows({required this.cues, required this.durationMs, required Map<int, int> titleAtFirstVerse})
      : titleAtFirstVerse = Map.unmodifiable(titleAtFirstVerse) {
    for (var v = 1; v <= lastVerse; v++) {
      if (cues[v] < 0) throw ArgumentError('verse $v has no cue');
      if (v > 1 && cues[v] <= cues[v - 1]) throw ArgumentError('cues are not increasing at verse $v');
    }
  }

  int get lastVerse => cues.length - 1;

  int cue(int verse) => cues[verse];

  /// Where verse [verse]'s window ends (exclusive).
  int verseEnd(int verse) {
    if (verse >= lastVerse) return durationMs;
    final next = cues[verse + 1];
    final title = titleAtFirstVerse[verse + 1];
    if (title != null && title > cues[verse] && title < next) return title;
    return next;
  }

  /// Where a chapter whose first verse is [firstVerse] starts.
  int chapterStart(int firstVerse, {bool withTitle = true}) {
    final title = titleAtFirstVerse[firstVerse];
    if (withTitle && title != null && title <= cues[firstVerse]) return title;
    return cues[firstVerse];
  }

  /// Where to start playing when jumping straight to [verse]: [preRollMs] early, so
  /// the first syllable is not clipped — but never before the previous verse's own
  /// cue, and never inside a spoken chapter title (then exactly at the cue).
  int seekStart(int verse, {int preRollMs = 0}) {
    if (verse > 1 && titleFollows(verse - 1)) return cues[verse];
    final floor = verse > 1 ? cues[verse - 1] : 0;
    return math.max(floor, cues[verse] - preRollMs);
  }

  /// Whether a spoken title plays between verse [verse] and the next one.
  bool titleFollows(int verse) => verse < lastVerse && verseEnd(verse) < cues[verse + 1];

  /// What is audible at [positionMs] (V2 Q5).
  PlayingAt at(int positionMs) {
    if (positionMs < cues[1]) {
      final title = titleAtFirstVerse[1];
      return PlayingAt(1, inTitle: title != null && positionMs >= title);
    }
    // Last verse whose cue is <= position.
    var lo = 1, hi = lastVerse;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (cues[mid] <= positionMs) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    if (lo < lastVerse && positionMs >= verseEnd(lo)) return PlayingAt(lo + 1, inTitle: true);
    return PlayingAt(lo);
  }
}
