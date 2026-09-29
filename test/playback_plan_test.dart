// PlaybackPlan on a synthetic recording small enough to check every millisecond:
// verses 1–5 cue at 1000…5000 ms, the chapter starting at verse 4 has a spoken
// title at 3800 ms, and the file ends at 6000 ms.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/domain/playback_windows.dart';

final windows = PlaybackWindows(
  cues: Int32List.fromList([-1, 1000, 2000, 3000, 4000, 5000]),
  durationMs: 6000,
  titleAtFirstVerse: const {4: 3800},
);

String describe(PlanAction a) => a.toString();

List<String> run(PlaybackPlan plan, {int steps = 20}) {
  final out = [describe(plan.start())];
  for (var i = 0; i < steps && plan.verse > 0; i++) {
    final a = plan.advance();
    out.add(describe(a));
    if (a is Finished) break;
  }
  return out;
}

void main() {
  test('plays straight through, with the spoken title before verse 4', () {
    final plan = PlaybackPlan(windows, const PlaybackScope(1, 5), const PlaybackSettings());
    expect(run(plan), [
      'PlayRange(v1, 750→2000)', // pre-roll on the initial jump
      'PlayRange(v2, 2000→3000, cont)',
      'PlayRange(v3, 3000→3800, cont)', // verse 3 ends where the title begins
      'PlayRange(v4, 3800→5000, title→4000, cont)',
      'PlayRange(v5, 5000→6000, cont)',
      'Finished',
    ]);
  });

  test('titles off: the title is skipped by a jump', () {
    final plan = PlaybackPlan(windows, const PlaybackScope(3, 4), const PlaybackSettings(playTitles: false));
    expect(run(plan), ['PlayRange(v3, 2750→3800)', 'PlayRange(v4, 4000→5000)', 'Finished']);
  });

  test('verse repeat restarts the verse at once; counters count up', () {
    final plan = PlaybackPlan(windows, const PlaybackScope(1, 2), const PlaybackSettings(verseRepeats: 3));
    expect(describe(plan.start()), 'PlayRange(v1, 750→2000)');
    expect(plan.verseRepetition, 1);
    expect(describe(plan.advance()), 'PlayRange(v1, 750→2000)');
    expect(plan.verseRepetition, 2);
    expect(describe(plan.advance()), 'PlayRange(v1, 750→2000)');
    expect(plan.verseRepetition, 3);
    expect(describe(plan.advance()), 'PlayRange(v2, 2000→3000, cont)'); // the third play ended at 2000
    expect(plan.verseRepetition, 1);
  });

  test('the gap goes between verses, and playback resumes where it paused', () {
    final plan = PlaybackPlan(windows, const PlaybackScope(1, 3), const PlaybackSettings(gapMs: 500));
    expect(run(plan), [
      'PlayRange(v1, 750→2000)',
      'Silence(500)',
      'PlayRange(v2, 2000→3000, cont)',
      'Silence(500)',
      'PlayRange(v3, 3000→3800, cont)',
      'Finished',
    ]);
  });

  test('section repeat: the scope twice, then finished', () {
    final plan = PlaybackPlan(windows, const PlaybackScope(2, 3), const PlaybackSettings(sectionRepeats: 2));
    expect(run(plan), [
      'PlayRange(v2, 1750→3000)',
      'PlayRange(v3, 3000→3800, cont)',
      'PlayRange(v2, 1750→3000)',
      'PlayRange(v3, 3000→3800, cont)',
      'Finished',
    ]);
  });

  test('a chapter played from its heading starts at the spoken title', () {
    final plan = PlaybackPlan(windows, const PlaybackScope(4, 5, fromChapterTitle: true), const PlaybackSettings());
    expect(describe(plan.start()), 'PlayRange(v4, 3800→5000, title→4000)');
  });

  test('infinite verse repeat never advances', () {
    final plan = PlaybackPlan(windows, const PlaybackScope(1, 5), const PlaybackSettings(verseRepeats: null));
    plan.start();
    for (var i = 0; i < 10; i++) {
      expect(describe(plan.advance()), 'PlayRange(v1, 750→2000)');
    }
  });

  test('a jump resets the verse counter and uses the pre-roll', () {
    final plan = PlaybackPlan(windows, const PlaybackScope(1, 5), const PlaybackSettings(verseRepeats: 3));
    plan.start();
    plan.advance(); // second play of verse 1
    expect(describe(plan.jumpTo(3)), 'PlayRange(v3, 2750→3800)');
    expect(plan.verseRepetition, 1);
    expect(describe(plan.jumpTo(4)), 'PlayRange(v4, 4000→5000)'); // no pre-roll into the title
  });
}
