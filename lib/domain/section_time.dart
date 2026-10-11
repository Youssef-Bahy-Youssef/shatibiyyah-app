// lib/domain/section_time.dart — a section as the time its listener hears.
//
// Pure and synchronous. The dock's bar and the player's scrubber both read the
// section here, so they agree: nothing where the section starts, [totalMs]
// where its last verse ends, and each verse as wide as it is long.
//
//   heard time = the verses' windows (PlaybackWindows), one after the other,
//                and each spoken title the plan plays: a chapter's inside the
//                section, and the first one when the section is a chapter
//                played from its title. With titles off they are left out,
//                as the plan seeks over them.
//
// Repeats and the silent gap are not time of the section: a repeat goes back to
// its verse's start, and through a gap the position stands at the verse's end.
import 'dart:typed_data';

import 'playback_plan.dart';
import 'playback_windows.dart';

/// A player stopped at a verse's end, or asked to seek and not yet there, may
/// stand a little past that end (ADR 0005 holds a stop within 40 ms). Up to
/// this far past it is the verse's end; further is another place in the file.
const int kPastEndSlackMs = 250;

class SectionTime {
  final PlaybackWindows windows;
  final PlaybackScope scope;

  /// The heard time of the whole section.
  final int totalMs;
  final Int32List _cueAt; // per verse: heard time before its cue
  final Int32List _lead; // per verse: how much of that is its spoken title

  SectionTime._(this.windows, this.scope, this.totalMs, this._cueAt, this._lead);

  /// [titles]: whether spoken chapter titles are played (PlaybackSettings.playTitles).
  factory SectionTime(PlaybackWindows windows, PlaybackScope scope, {bool titles = true}) {
    final count = scope.toVerse - scope.fromVerse + 1;
    final cueAt = Int32List(count), lead = Int32List(count);
    var heard = 0;
    for (var i = 0; i < count; i++) {
      final v = scope.fromVerse + i;
      final cue = windows.cue(v);
      final from = !titles
          ? cue
          : i > 0
              ? windows.verseEnd(v - 1)
              : scope.fromChapterTitle
                  ? windows.chapterStart(v)
                  : cue;
      lead[i] = cue - from;
      heard += lead[i];
      cueAt[i] = heard;
      heard += windows.verseEnd(v) - cue;
    }
    return SectionTime._(windows, scope, heard, cueAt, lead);
  }

  int _index(int verse) => verse.clamp(scope.fromVerse, scope.toVerse) - scope.fromVerse;

  /// The heard time at which [verse] begins.
  int cueMs(int verse) => _cueAt[_index(verse)];

  /// The heard time with the player at [positionMs] and the plan on [verse].
  ///
  /// The position counts while it is in the verse's own stretch of the file
  /// (its title, when played, and its window). Anywhere else the player has not
  /// arrived yet (a jump, a repeat) and the answer is where the verse is entered.
  /// [ended]: the section has been played to its end.
  int elapsedMs(int positionMs, int verse, {bool ended = false}) {
    if (ended) return totalMs;
    final i = _index(verse), v = scope.fromVerse + i;
    final cue = windows.cue(v), end = windows.verseEnd(v);
    if (positionMs < cue - _lead[i] || positionMs > end + kPastEndSlackMs) return i == 0 ? 0 : _cueAt[i];
    return _cueAt[i] + (positionMs < end ? positionMs : end) - cue;
  }

  /// [elapsedMs] as a part of the whole, 0…1.
  double fraction(int elapsedMs) => (elapsedMs / totalMs).clamp(0.0, 1.0);

  /// The verse heard at [elapsedMs]; during a spoken title, the verse after it.
  int verseAt(int elapsedMs) {
    var i = _cueAt.length - 1;
    while (i > 0 && _cueAt[i] - _lead[i] > elapsedMs) {
      i--;
    }
    return scope.fromVerse + i;
  }
}
