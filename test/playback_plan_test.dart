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
      'PlayRange(v1, 950→2000)', // pre-roll on the initial jump
      'PlayRange(v2, 2000→3000, cont)',
      'PlayRange(v3, 3000→3800, cont)', // verse 3 ends where the title begins
      'PlayRange(v4, 3800→5000, title→4000, cont)',
      'PlayRange(v5, 5000→6000, cont)',
      'Finished',
    ]);
  });

  test('titles off: the title is skipped by a jump', () {
    final plan = PlaybackPlan(windows, const PlaybackScope(3, 4), const PlaybackSettings(playTitles: false));
    expect(run(plan), ['PlayRange(v3, 2950→3800)', 'PlayRange(v4, 4000→5000)', 'Finished']);
  });

  test('verse repeat with no gap restarts the verse at once; counters count up', () {
    final plan = PlaybackPlan(windows, const PlaybackScope(1, 2), const PlaybackSettings(verseRepeats: 3));
    expect(describe(plan.start()), 'PlayRange(v1, 950→2000)');
    expect(plan.verseRepetition, 1);
    expect(describe(plan.advance()), 'PlayRange(v1, 950→2000)');
    expect(plan.verseRepetition, 2);
    expect(describe(plan.advance()), 'PlayRange(v1, 950→2000)');
    expect(plan.verseRepetition, 3);
    expect(describe(plan.advance()), 'PlayRange(v2, 2000→3000, cont)'); // the third play ended at 2000
    expect(plan.verseRepetition, 1);
  });

  test('the gap goes between verses, and playback resumes where it paused', () {
    final plan = PlaybackPlan(windows, const PlaybackScope(1, 3), const PlaybackSettings(gapMs: 500));
    expect(run(plan), [
      'PlayRange(v1, 950→2000)',
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
      'PlayRange(v2, 1950→3000)',
      'PlayRange(v3, 3000→3800, cont)',
      'PlayRange(v2, 1950→3000)',
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
      expect(describe(plan.advance()), 'PlayRange(v1, 950→2000)');
    }
  });

  test('a jump resets the verse counter and uses the pre-roll', () {
    final plan = PlaybackPlan(windows, const PlaybackScope(1, 5), const PlaybackSettings(verseRepeats: 3));
    plan.start();
    plan.advance(); // second play of verse 1
    expect(describe(plan.jumpTo(3)), 'PlayRange(v3, 2950→3800)');
    expect(plan.verseRepetition, 1);
    expect(describe(plan.jumpTo(4)), 'PlayRange(v4, 4000→5000)'); // no pre-roll into the title
  });

  // ADR 0005: every jump starts 50 ms before the verse's cue, and never before
  // the previous verse's own cue. Continuous playback adds none.
  test('the pre-roll is 50 ms: a tapped verse, a section start, a repeat', () {
    expect(const PlaybackSettings().preRollMs, 50);
    final plan = PlaybackPlan(windows, const PlaybackScope(2, 3), const PlaybackSettings(verseRepeats: 2));
    expect((plan.start() as PlayRange).fromMs, windows.cue(2) - 50); // a section start
    expect((plan.advance() as PlayRange).fromMs, windows.cue(2) - 50); // the verse again
    final next = plan.advance() as PlayRange; // on to verse 3, with no seek
    expect((next.fromMs, next.continuous), (windows.cue(3), true));
    expect((plan.jumpTo(2) as PlayRange).fromMs, windows.cue(2) - 50); // a tap
  });

  test('the pre-roll stops at the previous verse\'s cue', () {
    final close = PlaybackWindows(
      cues: Int32List.fromList([-1, 1000, 1030, 2000]),
      durationMs: 3000,
      titleAtFirstVerse: const {},
    );
    final plan = PlaybackPlan(close, const PlaybackScope(1, 3), const PlaybackSettings());
    expect((plan.jumpTo(2) as PlayRange).fromMs, 1000); // 30 ms after verse 1's cue: not before it
    expect((plan.jumpTo(3) as PlayRange).fromMs, 1950);
    expect((plan.jumpTo(1) as PlayRange).fromMs, 950);
  });

  // ADRs 0003, 0004: verse × N inside section × M; the gap separates every two
  // plays; a round restarts as the section first started; a jump resets the counters.
  group('section and repeat rules (ADRs 0003, 0004)', () {
    test('a section that starts at verse 3 repeats from verse 3, not from its chapter\'s first verse', () {
      final plan = PlaybackPlan(windows, const PlaybackScope(3, 5), const PlaybackSettings(sectionRepeats: 2));
      expect(run(plan), [
        'PlayRange(v3, 2950→3800)',
        'PlayRange(v4, 3800→5000, title→4000, cont)',
        'PlayRange(v5, 5000→6000, cont)',
        'PlayRange(v3, 2950→3800)',
        'PlayRange(v4, 3800→5000, title→4000, cont)',
        'PlayRange(v5, 5000→6000, cont)',
        'Finished',
      ]);
    });

    test('N = 2, M = 2: each verse twice, the whole section twice', () {
      final plan = PlaybackPlan(windows, const PlaybackScope(1, 2), const PlaybackSettings(verseRepeats: 2, sectionRepeats: 2));
      final played = <(int, int, int)>[];
      PlanAction a = plan.start();
      while (a is! Finished) {
        if (a is PlayRange) played.add((a.verse, plan.verseRepetition, plan.sectionRepetition));
        a = plan.advance();
      }
      expect(played, [(1, 1, 1), (1, 2, 1), (2, 1, 1), (2, 2, 1), (1, 1, 2), (1, 2, 2), (2, 1, 2), (2, 2, 2)]);
    });

    test('the gap separates repeats of the same verse too, and one round from the next', () {
      final plan = PlaybackPlan(windows, const PlaybackScope(1, 2), const PlaybackSettings(verseRepeats: 2, sectionRepeats: 2, gapMs: 500));
      expect(run(plan, steps: 40), [
        'PlayRange(v1, 950→2000)', 'Silence(500)', 'PlayRange(v1, 950→2000)', 'Silence(500)', //
        'PlayRange(v2, 2000→3000, cont)', 'Silence(500)', 'PlayRange(v2, 1950→3000)', 'Silence(500)', //
        'PlayRange(v1, 950→2000)', 'Silence(500)', 'PlayRange(v1, 950→2000)', 'Silence(500)', //
        'PlayRange(v2, 2000→3000, cont)', 'Silence(500)', 'PlayRange(v2, 1950→3000)', //
        'Finished', // nothing waits after the last play
      ]);
    });

    test('a section begun with its title starts every round with the title; a verse repeat never replays it', () {
      final plan = PlaybackPlan(
          windows, const PlaybackScope(4, 5, fromChapterTitle: true), const PlaybackSettings(verseRepeats: 2, sectionRepeats: 2));
      expect(run(plan), [
        'PlayRange(v4, 3800→5000, title→4000)',
        'PlayRange(v4, 4000→5000)', // the verse again, from its cue: the title is before it
        'PlayRange(v5, 5000→6000, cont)',
        'PlayRange(v5, 4950→6000)',
        'PlayRange(v4, 3800→5000, title→4000)',
        'PlayRange(v4, 4000→5000)',
        'PlayRange(v5, 5000→6000, cont)',
        'PlayRange(v5, 4950→6000)',
        'Finished',
      ]);
    });

    test('«تلاوة عناوين الأبواب» off: no title at a crossing, nor at the start of a chapter\'s section', () {
      const off = PlaybackSettings(playTitles: false);
      expect(run(PlaybackPlan(windows, const PlaybackScope(3, 4), off)), ['PlayRange(v3, 2950→3800)', 'PlayRange(v4, 4000→5000)', 'Finished']);
      expect(describe(PlaybackPlan(windows, const PlaybackScope(4, 5, fromChapterTitle: true), off).start()), 'PlayRange(v4, 4000→5000)');
    });

    test('a jump resets both counters; a change of settings in the middle does not', () {
      final plan = PlaybackPlan(windows, const PlaybackScope(1, 2), const PlaybackSettings(verseRepeats: 3, sectionRepeats: 3));
      plan.start();
      for (var i = 0; i < 7; i++) {
        plan.advance(); // into the second round, second play of verse 1
      }
      expect((plan.verse, plan.verseRepetition, plan.sectionRepetition), (1, 2, 2));
      plan.settings = plan.settings.copyWith(gapMs: 1000); // as a new gap, or anything but a jump
      expect((plan.verseRepetition, plan.sectionRepetition), (2, 2));
      plan.jumpTo(2);
      expect((plan.verse, plan.verseRepetition, plan.sectionRepetition), (2, 1, 1));
    });
  });
}
