// The section as time (the dock's bar, the player's scrubber): nothing where it
// starts, all of it where its last verse ends, each verse as wide as it is long.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/domain/playback_windows.dart';
import 'package:shatibiyyah/domain/section_time.dart';

void main() {
  // Six verses. Chapter one's title is spoken from 0 to 1 s; chapter two starts at
  // verse 4 and its title is spoken from 12 to 14 s, so verse 3 ends at 12 s.
  final windows = PlaybackWindows(
    cues: Int32List.fromList([-1, 1000, 5000, 8000, 14000, 20000, 26000]),
    durationMs: 30000,
    titleAtFirstVerse: {1: 0, 4: 12000},
  );
  const run = PlaybackScope(2, 5);

  test('a run of verses: from its first cue to its last verse\'s end, the title inside it heard', () {
    final t = SectionTime(windows, run);
    expect(t.totalMs, 26000 - 5000);
    expect([for (var v = 2; v <= 5; v++) t.cueMs(v)], [0, 3000, 9000, 15000]);
    expect(t.elapsedMs(5000, 2), 0);
    expect(t.elapsedMs(9000, 3), 4000);
    expect(t.elapsedMs(13000, 4), 8000); // in the title before verse 4
    expect(t.elapsedMs(25000, 5), 20000);
    expect(t.fraction(t.elapsedMs(25000, 5)), closeTo(20 / 21, 1e-9));
  });

  test('it starts empty and ends full', () {
    final t = SectionTime(windows, run);
    expect(t.elapsedMs(4950, 2), 0); // the pre-roll before the first verse
    expect(t.fraction(t.elapsedMs(5000, 2)), 0);
    // The player is stopped a few ms before or after the last verse's end.
    expect(t.elapsedMs(25985, 5), 20985);
    expect(t.elapsedMs(26030, 5), t.totalMs);
    expect(t.elapsedMs(25985, 5, ended: true), t.totalMs);
    expect(t.fraction(t.totalMs), 1);
  });

  test('each verse takes the share of the bar that it takes of the time', () {
    final t = SectionTime(windows, const PlaybackScope(1, 3));
    double share(int v) => t.fraction(t.elapsedMs(windows.verseEnd(v), v)) - t.fraction(t.cueMs(v));
    expect([share(1), share(2), share(3)], [closeTo(4 / 11, 1e-9), closeTo(3 / 11, 1e-9), closeTo(4 / 11, 1e-9)]);
  });

  test('a title that is not played is not time of the section', () {
    final t = SectionTime(windows, run, titles: false);
    expect(t.totalMs, 21000 - 2000);
    expect([for (var v = 2; v <= 5; v++) t.cueMs(v)], [0, 3000, 7000, 13000]);
    expect(t.elapsedMs(11990, 3), 6990);
    expect(t.elapsedMs(14000, 4), 7000); // the seek over the title moves nothing
    expect(t.elapsedMs(25985, 5), 18985);
  });

  test('a chapter from its spoken title; from its first cue when titles are off', () {
    const chapter = PlaybackScope(1, 3, fromChapterTitle: true);
    final spoken = SectionTime(windows, chapter);
    expect((spoken.totalMs, spoken.cueMs(1)), (12000, 1000));
    expect((spoken.elapsedMs(0, 1), spoken.elapsedMs(500, 1), spoken.elapsedMs(1500, 1)), (0, 500, 1500));
    final silent = SectionTime(windows, chapter, titles: false);
    expect((silent.totalMs, silent.cueMs(1)), (11000, 0));
    expect((silent.elapsedMs(500, 1), silent.elapsedMs(1500, 1)), (0, 500));
  });

  test('between plays the position is the verse\'s end; before a seek lands it is the verse\'s start', () {
    final t = SectionTime(windows, run);
    expect(t.elapsedMs(8010, 2), 3000); // stopped just past verse 2's end, in the gap
    expect(t.elapsedMs(6000, 4), 9000); // «next» pressed twice: the player is still in verse 2
    expect(t.elapsedMs(25990, 2), 0); // the section repeats: the player is still at its end
    expect(t.elapsedMs(25990, 3), 3000); // a tap on an earlier verse
    expect(t.elapsedMs(0, 4), 9000); // nothing played yet
  });

  test('a point of the bar names the verse heard there; a title belongs to the verse after it', () {
    final t = SectionTime(windows, run);
    expect([0, 2999, 3000, 6999, 7000, 8999, 9000, 15000, 21000].map(t.verseAt), [2, 2, 3, 3, 4, 4, 4, 5, 5]);
    final silent = SectionTime(windows, run, titles: false);
    expect([6999, 7000, 12999, 13000].map(silent.verseAt), [3, 4, 4, 5]);
  });

  test('one verse is a section too', () {
    final t = SectionTime(windows, const PlaybackScope(6, 6));
    expect((t.totalMs, t.elapsedMs(26000, 6), t.elapsedMs(28000, 6)), (4000, 0, 2000));
    expect(t.elapsedMs(29990, 6, ended: true), 4000);
  });
}
