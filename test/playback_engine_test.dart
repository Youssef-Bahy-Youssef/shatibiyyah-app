// PlaybackEngine over a fake audio player driven by fake time: seeks happen only
// for non-continuous actions, gaps are real silences, and quick jumps never land back.
import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/domain/playback_engine.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/domain/playback_windows.dart';

/// Plays in 20 ms ticks while `playing`; records every seek. [outsidePause] and
/// [outsidePlay] act like the lock-screen buttons or an interruption.
class FakeAudio implements AudioPort {
  final _positions = StreamController<int>.broadcast(sync: true);
  final _playingChanges = StreamController<bool>.broadcast(sync: true);
  final seeks = <int>[];
  int _position = 0;
  bool _playing = false;
  Timer? _ticker;

  @override
  Stream<int> get positionMs => _positions.stream;
  @override
  int get currentPositionMs => _position;
  @override
  bool get playing => _playing;
  @override
  Stream<bool> get playingChanges => _playingChanges.stream;

  void _set(bool on) {
    if (_playing == on) return;
    _playing = on;
    _playingChanges.add(on);
  }

  void outsidePause() => _set(false);
  void outsidePlay() => play();

  @override
  Future<void> seek(int ms) async {
    seeks.add(ms);
    _position = ms;
  }

  @override
  Future<void> play() async {
    _set(true);
    _ticker ??= Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (!_playing) return;
      _position += 20;
      _positions.add(_position);
    });
  }

  @override
  Future<void> pause() async => _set(false);

  @override
  Future<void> setSpeed(double speed) async {}

  void dispose() => _ticker?.cancel();
}

/// A player on the fake clock: its position moves with the time and the speed,
/// and it reports it every 200 ms only. It records where it stood each time it
/// was told to stop or to seek while playing.
class ClockAudio implements AudioPort {
  final FakeAsync async;
  ClockAudio(this.async);

  final _positions = StreamController<int>.broadcast(sync: true);
  final _playingChanges = StreamController<bool>.broadcast(sync: true);
  final seeks = <int>[];
  final stops = <({String kind, int at})>[];
  double _speed = 1;
  int _base = 0;
  Duration _since = Duration.zero;
  bool _playing = false;
  Timer? _ticker;

  @override
  Stream<int> get positionMs => _positions.stream;
  @override
  int get currentPositionMs =>
      _playing ? _base + ((async.elapsed - _since).inMicroseconds * _speed / 1000).round() : _base;
  @override
  bool get playing => _playing;
  @override
  Stream<bool> get playingChanges => _playingChanges.stream;

  void _mark() {
    _base = currentPositionMs;
    _since = async.elapsed;
  }

  @override
  Future<void> seek(int ms) async {
    if (_playing) stops.add((kind: 'seek', at: currentPositionMs));
    seeks.add(ms);
    _base = ms;
    _since = async.elapsed;
  }

  @override
  Future<void> play() async {
    if (_playing) return;
    _since = async.elapsed;
    _playing = true;
    _playingChanges.add(true);
    _ticker ??= Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_playing) _positions.add(currentPositionMs);
    });
  }

  @override
  Future<void> pause() async {
    if (!_playing) return;
    stops.add((kind: 'pause', at: currentPositionMs));
    _mark();
    _playing = false;
    _playingChanges.add(false);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _mark();
    _speed = speed;
  }

  void dispose() => _ticker?.cancel();
}

/// A player whose file ends at [endMs]: there it stops by itself, as a decoder does
/// when the file is a little shorter than the recording's declared duration.
class EndingAudio extends FakeAudio {
  final int endMs;
  EndingAudio(this.endMs);
  @override
  Future<void> play() async {
    await super.play();
    _positions.stream.listen((ms) {
      if (ms >= endMs && _playing) _set(false);
    });
  }
}

/// A player as just_audio is: a seek moves its own position at once and is answered
/// [seekMs] later. With [staleAt] set, a report the player sent before it heard of
/// the next seek arrives 5 ms into it, and stands as its position until the answer.
class SlowSeekAudio extends FakeAudio {
  final int seekMs;
  int? staleAt;
  SlowSeekAudio({this.seekMs = 60});

  @override
  Future<void> seek(int ms) async {
    await super.seek(ms);
    final stale = staleAt;
    staleAt = null;
    if (stale == null) {
      await Future<void>.delayed(Duration(milliseconds: seekMs));
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
    _position = stale;
    _positions.add(stale);
    await Future<void>.delayed(Duration(milliseconds: seekMs - 5));
    if (seeks.last == ms) _position = ms; // the player has arrived, unless it was sent elsewhere since
  }
}

final windows = PlaybackWindows(
  cues: Int32List.fromList([-1, 1000, 2000, 3000, 4000, 5000]),
  durationMs: 6000,
  titleAtFirstVerse: const {4: 3800},
);

void main() {
  test('plays a scope through with one seek', () {
    fakeAsync((async) {
      final audio = FakeAudio();
      final engine = PlaybackEngine(audio, PlaybackPlan(windows, const PlaybackScope(1, 5), const PlaybackSettings()));
      engine.play();
      async.elapse(const Duration(seconds: 6));
      expect(audio.seeks, [950]); // everything after the first jump is continuous
      expect(engine.state.finished, isTrue);
      audio.dispose();
    });
  });

  group('the end of the file (F-40)', () {
    test('a player that stops 150 ms before the declared end still finishes', () {
      fakeAsync((async) {
        final audio = EndingAudio(windows.durationMs - 150);
        final engine = PlaybackEngine(audio, PlaybackPlan(windows, const PlaybackScope(5, 5), const PlaybackSettings()));
        engine.play();
        async.elapse(const Duration(seconds: 3));
        expect(engine.state.finished, isTrue);
        expect(engine.state.playing, isFalse);
        audio.dispose();
      });
    });

    test('a stop well before the end is still a pause, not the end', () {
      fakeAsync((async) {
        final audio = EndingAudio(windows.durationMs - 400);
        final engine = PlaybackEngine(audio, PlaybackPlan(windows, const PlaybackScope(5, 5), const PlaybackSettings()));
        engine.play();
        async.elapse(const Duration(seconds: 3));
        expect(engine.state.finished, isFalse);
        audio.dispose();
      });
    });

    test('the last verse ends at the decoded duration when the player reports one', () {
      fakeAsync((async) {
        final audio = FakeAudio(); // plays on past the decoded end: only the engine can stop
        final engine = PlaybackEngine(audio, PlaybackPlan(windows, const PlaybackScope(5, 5), const PlaybackSettings()))
          ..decodedDurationMs = windows.durationMs - 300;
        engine.play();
        async.elapse(const Duration(milliseconds: 1500));
        expect(engine.state.finished, isTrue);
        expect(audio.currentPositionMs, lessThan(windows.durationMs - 200));
        audio.dispose();
      });
    });
  });

  test('the gap is a pause, then playback resumes in place', () {
    fakeAsync((async) {
      final audio = FakeAudio();
      final engine = PlaybackEngine(
          audio, PlaybackPlan(windows, const PlaybackScope(1, 2), const PlaybackSettings(gapMs: 500)));
      engine.play();
      async.elapse(const Duration(milliseconds: 1060)); // 950 → 2000 plus a little
      expect(engine.state.inGap, isTrue);
      expect(audio.playing, isFalse);
      expect(engine.state.playing, isTrue); // the student is still listening through the gap
      final pausedAt = audio.currentPositionMs;
      async.elapse(const Duration(milliseconds: 520));
      expect(engine.state.inGap, isFalse);
      expect(engine.state.verse, 2);
      expect(audio.playing, isTrue);
      expect(audio.seeks, [950]); // resumed where it paused, no seek
      expect(audio.currentPositionMs, greaterThanOrEqualTo(pausedAt));
      audio.dispose();
    });
  });

  test('quick next/next/next lands on the last target and never jumps back', () {
    fakeAsync((async) {
      final audio = FakeAudio();
      final verses = <int>[];
      final engine = PlaybackEngine(audio, PlaybackPlan(windows, const PlaybackScope(1, 5), const PlaybackSettings()));
      engine.states.listen((s) => verses.add(s.verse));
      engine.play();
      async.elapse(const Duration(milliseconds: 60));
      engine.next();
      engine.next();
      engine.next();
      async.elapse(const Duration(milliseconds: 300));
      expect(engine.state.verse, 4);
      final after = verses.sublist(verses.lastIndexOf(4));
      expect(after.every((v) => v >= 4), isTrue, reason: '$verses');
      expect(audio.currentPositionMs, greaterThanOrEqualTo(4000));
      audio.dispose();
    });
  });

  group('a position the player reported before a jump, arriving after it', () {
    // Verse 4 is being recited when the jump is asked for: the late report is from there.
    (SlowSeekAudio, PlaybackEngine, List<int>) reciting4(FakeAsync async) {
      final audio = SlowSeekAudio();
      final engine = PlaybackEngine(audio, PlaybackPlan(windows, const PlaybackScope(1, 5), const PlaybackSettings()));
      engine.play();
      async.elapse(const Duration(milliseconds: 3500));
      expect(engine.state.verse, 4);
      final verses = <int>[];
      engine.states.listen((s) => verses.add(s.verse));
      audio.staleAt = audio.currentPositionMs;
      return (audio, engine, verses);
    }

    for (final target in [3, 2]) {
      test('back to verse $target: the engine stays on it, then plays on', () {
        fakeAsync((async) {
          final (audio, engine, verses) = reciting4(async);
          engine.jumpTo(target);
          async.elapse(const Duration(milliseconds: 300));
          // Past the end of the verse asked for, the report is not that verse's end.
          expect(verses.toSet(), {target}, reason: '$verses');
          expect(audio.seeks.last, windows.cue(target) - 50);
          // Once the player has answered, its reports count again: the verse ends in its place.
          async.elapse(const Duration(seconds: 1));
          expect(engine.state.verse, target + 1);
          expect(audio.seeks.last, windows.cue(target) - 50); // continuous: no second seek
          audio.dispose();
        });
      });
    }

    test('a second jump before the player has answered the first: the last verse asked for stands', () {
      fakeAsync((async) {
        final (audio, engine, verses) = reciting4(async);
        engine.jumpTo(2);
        async.elapse(const Duration(milliseconds: 20));
        engine.jumpTo(1);
        async.elapse(const Duration(milliseconds: 300));
        expect(verses.toSet(), {1}, reason: '$verses');
        expect(audio.currentPositionMs, inInclusiveRange(950, 2000));
        audio.dispose();
      });
    });

    test('a new speed before the player has answered does not end the verse from the old place', () {
      fakeAsync((async) {
        final (audio, engine, verses) = reciting4(async);
        engine.jumpTo(3);
        async.elapse(const Duration(milliseconds: 10)); // the late report stands as the player's position
        engine.setSpeed(1.5);
        async.elapse(const Duration(milliseconds: 300));
        expect(verses.toSet(), {3}, reason: '$verses');
        audio.dispose();
      });
    });
  });

  test('verse repeat is visible in the state counters', () {
    fakeAsync((async) {
      final audio = FakeAudio();
      final engine = PlaybackEngine(
          audio, PlaybackPlan(windows, const PlaybackScope(1, 2), const PlaybackSettings(verseRepeats: 3)));
      engine.play();
      async.elapse(const Duration(milliseconds: 1300)); // first play done
      expect(engine.state.verse, 1);
      expect(engine.state.verseRepetition, 2);
      audio.dispose();
    });
  });

  group('the player changed from outside (lock screen, a call, headphones)', () {
    PlaybackEngine engineOn(FakeAudio audio, {int gapMs = 0}) =>
        PlaybackEngine(audio, PlaybackPlan(windows, const PlaybackScope(1, 5), PlaybackSettings(gapMs: gapMs)));

    test('an outside pause is a pause: the state says so and nothing advances', () {
      fakeAsync((async) {
        final audio = FakeAudio();
        final engine = engineOn(audio);
        final states = <EngineState>[];
        engine.states.listen(states.add);
        engine.play();
        async.elapse(const Duration(milliseconds: 600)); // in verse 1
        audio.outsidePause();
        async.flushMicrotasks();
        expect(engine.state.playing, isFalse);
        expect(states.last.playing, isFalse); // the UI heard about it
        final at = audio.currentPositionMs;
        async.elapse(const Duration(seconds: 3));
        expect(audio.currentPositionMs, at);
        expect(engine.state.verse, 1);
        audio.dispose();
      });
    });

    test('an outside play resumes where it stood and plays on', () {
      fakeAsync((async) {
        final audio = FakeAudio();
        final engine = PlaybackEngine(
            audio, PlaybackPlan(windows, const PlaybackScope(1, 5), const PlaybackSettings()));
        engine.play();
        async.elapse(const Duration(milliseconds: 600));
        audio.outsidePause();
        async.elapse(const Duration(seconds: 1));
        audio.outsidePlay();
        async.elapse(const Duration(seconds: 6));
        expect(engine.state.playing, isFalse);
        expect(engine.state.finished, isTrue);
          expect(audio.seeks, [950]); // no jump back
        audio.dispose();
      });
    });

    test('an outside pause during the gap keeps it paused; an outside play skips the gap', () {
      fakeAsync((async) {
        final audio = FakeAudio();
        final engine = engineOn(audio, gapMs: 1000);
        engine.play();
        async.elapse(const Duration(milliseconds: 1260)); // verse 1 done, in the gap
        expect(engine.state.inGap, isTrue);
        audio.outsidePlay();
        async.flushMicrotasks();
        expect(engine.state.inGap, isFalse);
        expect(engine.state.verse, 2);
        expect(engine.state.playing, isTrue);
        audio.dispose();
      });
    });

    test('an outside play after the end starts the scope again', () {
      fakeAsync((async) {
        final audio = FakeAudio();
        final engine = engineOn(audio);
        engine.play();
        async.elapse(const Duration(seconds: 6));
        expect(engine.state.finished, isTrue);
        audio.outsidePlay();
        async.elapse(const Duration(milliseconds: 100));
        expect(engine.state.finished, isFalse);
        expect(engine.state.verse, 1);
        expect(engine.state.playing, isTrue);
        audio.dispose();
      });
    });
  });

  group('an interruption that ends (ADR 0035)', () {
    PlaybackEngine engineOn(AudioPort audio, {int gapMs = 0, int verseRepeats = 1, PlaybackScope? scope}) => PlaybackEngine(
        audio,
        PlaybackPlan(windows, scope ?? const PlaybackScope(1, 5),
            PlaybackSettings(gapMs: gapMs, verseRepeats: verseRepeats)));

    test('it pauses; when it is over the verse is recited again from its start', () {
      fakeAsync((async) {
        final audio = FakeAudio();
        final engine = engineOn(audio);
        final states = <EngineState>[];
        engine.states.listen(states.add);
        engine.play(2);
        async.elapse(const Duration(milliseconds: 600)); // in verse 2
        engine.interrupt();
        async.flushMicrotasks();
        expect((engine.state.playing, states.last.playing, audio.playing), (false, false, false));
        async.elapse(const Duration(minutes: 5)); // the call
        expect(engine.state.verse, 2);
        engine.endInterruption(playOn: true);
        async.flushMicrotasks();
        expect((engine.state.playing, states.last.playing, audio.playing), (true, true, true));
        expect(audio.seeks, [1950, 1950]); // where the jump to it started
        async.elapse(const Duration(milliseconds: 1200));
        expect(engine.state.verse, 3); // and on from there
        expect(audio.seeks, hasLength(2));
        audio.dispose();
      });
    });

    test('a verse reached by playing on starts again at its cue, and counts no repetition', () {
      fakeAsync((async) {
        final audio = FakeAudio();
        final engine = engineOn(audio, verseRepeats: 2);
        engine.play();
        async.elapse(const Duration(milliseconds: 2400)); // verse 1 twice, then into verse 2
        expect((engine.state.verse, engine.state.verseRepetition), (2, 1));
        engine.interrupt();
        async.elapse(const Duration(seconds: 30));
        engine.endInterruption(playOn: true);
        async.flushMicrotasks();
        expect(audio.seeks.last, 2000);
        expect((engine.state.verse, engine.state.verseRepetition), (2, 1));
        audio.dispose();
      });
    });

    test('cut in the verse after its chapter\'s spoken title: the verse alone is recited again', () {
      fakeAsync((async) {
        final audio = FakeAudio();
        final engine = engineOn(audio, scope: const PlaybackScope(4, 5, fromChapterTitle: true));
        engine.play();
        async.elapse(const Duration(milliseconds: 100));
        expect(engine.state.inTitle, isTrue);
        engine.interrupt();
        engine.endInterruption(playOn: true);
        async.flushMicrotasks();
        expect(audio.seeks, [3800, 3800]); // cut in the title: the title again
        async.elapse(const Duration(milliseconds: 500)); // into the verse
        expect(engine.state.inTitle, isFalse);
        engine.interrupt();
        engine.endInterruption(playOn: true);
        async.flushMicrotasks();
        expect(audio.seeks.last, 4000);
        audio.dispose();
      });
    });

    test('one that does not allow it (another app took the sound for good) stays paused', () {
      fakeAsync((async) {
        final audio = FakeAudio();
        final engine = engineOn(audio);
        engine.play();
        async.elapse(const Duration(milliseconds: 600));
        engine.interrupt();
        engine.endInterruption(playOn: false);
        async.elapse(const Duration(seconds: 1));
        expect((engine.state.playing, audio.playing), (false, false));
        engine.endInterruption(playOn: true); // a later end is not this interruption's
        async.elapse(const Duration(seconds: 1));
        expect((engine.state.playing, audio.playing), (false, false));
        audio.dispose();
      });
    });

    test('a command from the student during it stands: nothing resumes by itself', () {
      for (final command in <(String, Future<void> Function(PlaybackEngine))>[
        ('pause', (e) => e.pause()),
        ('play then pause', (e) async {
          await e.resume();
          await e.pause();
        }),
        ('next then pause', (e) async {
          await e.next();
          await e.pause();
        }),
      ]) {
        fakeAsync((async) {
          final audio = FakeAudio();
          final engine = engineOn(audio);
          engine.play();
          async.elapse(const Duration(milliseconds: 600));
          engine.interrupt();
          async.flushMicrotasks();
          command.$2(engine);
          async.flushMicrotasks();
          final seeks = audio.seeks.length;
          engine.endInterruption(playOn: true);
          async.elapse(const Duration(seconds: 1));
          expect((engine.state.playing, audio.playing, audio.seeks.length), (false, false, seeks), reason: command.$1);
          audio.dispose();
        });
      }
    });

    test('the student played on during it: its end does not send the verse back to its start', () {
      for (final command in <(String, Future<void> Function(PlaybackEngine))>[
        ('play', (e) => e.resume()),
        ('next', (e) => e.next()),
        ('the lock screen\'s play', (e) async => (e.audio as FakeAudio).outsidePlay()),
      ]) {
        fakeAsync((async) {
          final audio = FakeAudio();
          final engine = engineOn(audio);
          engine.play();
          async.elapse(const Duration(milliseconds: 600));
          engine.interrupt();
          async.flushMicrotasks();
          command.$2(engine);
          async.elapse(const Duration(milliseconds: 300));
          final seeks = audio.seeks.length, at = audio.currentPositionMs;
          engine.endInterruption(playOn: true);
          async.flushMicrotasks();
          expect((engine.state.playing, audio.seeks.length, audio.currentPositionMs), (true, seeks, at),
              reason: command.$1);
          audio.dispose();
        });
      }
    });

    test('one that comes while paused resumes nothing', () {
      fakeAsync((async) {
        final audio = FakeAudio();
        final engine = engineOn(audio);
        engine.play();
        async.elapse(const Duration(milliseconds: 600));
        engine.pause();
        engine.interrupt();
        engine.endInterruption(playOn: true);
        async.elapse(const Duration(seconds: 1));
        expect((engine.state.playing, audio.playing), (false, false));
        audio.dispose();
      });
    });

    test('cut in the gap between two verses: the recitation goes on as «play» does', () {
      fakeAsync((async) {
        final audio = FakeAudio();
        final engine = engineOn(audio, gapMs: 1000);
        engine.play();
        async.elapse(const Duration(milliseconds: 1260)); // verse 1 done, in the gap
        expect(engine.state.inGap, isTrue);
        engine.interrupt();
        async.elapse(const Duration(seconds: 5));
        expect(engine.state.playing, isFalse);
        engine.endInterruption(playOn: true);
        async.elapse(const Duration(milliseconds: 100));
        expect((engine.state.playing, engine.state.inGap, audio.playing), (true, false, true));
        audio.dispose();
      });
    });
  });

  // ADR 0005: wherever playback stops or jumps, it ends within 40 ms of the
  // window's end at every speed. The player reports its position only every
  // 200 ms, so the end is scheduled from the position and the speed.
  group('stops within 40 ms of the verse\'s end (ADR 0005)', () {
    for (final speed in [0.25, 1.0, 2.0]) {
      test('$speed×: a repeat seeks back, the gap pauses and the end pauses on time', () {
        fakeAsync((async) {
          // With no gap, a verse played twice seeks back at its end.
          final audio = ClockAudio(async);
          final engine =
              PlaybackEngine(audio, PlaybackPlan(windows, const PlaybackScope(2, 3), const PlaybackSettings(verseRepeats: 2)));
          engine.setSpeed(speed);
          engine.play();
          async.elapse(Duration(milliseconds: (30000 / speed).round()));
          expect(audio.seeks, [1950, 1950, 2950]); // verse 3 the first time follows on with no seek
          expect(audio.stops.map((s) => s.kind), ['seek', 'seek', 'pause']);
          final ends = [3000, 3800, 3800]; // verse 3 ends where the title before verse 4 begins
          for (final (i, stop) in audio.stops.indexed) {
            expect((stop.at - ends[i]).abs(), lessThanOrEqualTo(40), reason: '${stop.kind} at ${stop.at}, the window ends at ${ends[i]}');
          }
          expect(engine.state.finished, isTrue);
          audio.dispose();

          // With a gap, each verse ends in a pause.
          final gapped = ClockAudio(async);
          final withGap =
              PlaybackEngine(gapped, PlaybackPlan(windows, const PlaybackScope(2, 3), const PlaybackSettings(gapMs: 1000)));
          withGap.setSpeed(speed);
          withGap.play();
          async.elapse(Duration(milliseconds: (30000 / speed).round()));
          expect(gapped.stops.map((s) => s.kind), ['pause', 'pause']);
          for (final (i, stop) in gapped.stops.indexed) {
            expect((stop.at - [3000, 3800][i]).abs(), lessThanOrEqualTo(40), reason: 'pause at ${stop.at}');
          }
          expect(withGap.state.finished, isTrue);
          gapped.dispose();
        });
      });
    }

    test('a change of speed keeps the counters (ADR 0004)', () {
      fakeAsync((async) {
        final audio = ClockAudio(async);
        final engine = PlaybackEngine(audio, PlaybackPlan(windows, const PlaybackScope(2, 2), const PlaybackSettings(verseRepeats: 3)));
        engine.play();
        async.elapse(const Duration(milliseconds: 1500)); // into the second play of verse 2
        expect(engine.state.verseRepetition, 2);
        engine.setSpeed(1.5);
        async.elapse(const Duration(milliseconds: 100));
        expect(engine.state.verseRepetition, 2);
        audio.dispose();
      });
    });

    test('a change of speed in the middle of a verse moves the stop with it', () {
      fakeAsync((async) {
        final audio = ClockAudio(async);
        final engine = PlaybackEngine(audio, PlaybackPlan(windows, const PlaybackScope(2, 2), const PlaybackSettings()));
        engine.play();
        async.elapse(const Duration(milliseconds: 300));
        engine.setSpeed(2);
        async.elapse(const Duration(seconds: 3));
        expect(audio.stops.single.kind, 'pause');
        expect((audio.stops.single.at - 3000).abs(), lessThanOrEqualTo(40));
        audio.dispose();
      });
    });

    test('a pause in the middle of a verse cancels the scheduled stop; resuming sets it again', () {
      fakeAsync((async) {
        final audio = ClockAudio(async);
        final engine = PlaybackEngine(audio, PlaybackPlan(windows, const PlaybackScope(2, 2), const PlaybackSettings()));
        engine.play();
        async.elapse(const Duration(milliseconds: 500));
        engine.pause();
        async.elapse(const Duration(seconds: 5)); // long past where the stop was due
        expect(engine.state.finished, isFalse);
        expect(audio.stops, hasLength(1)); // the student's own pause
        engine.resume();
        async.elapse(const Duration(seconds: 2));
        expect(engine.state.finished, isTrue);
        expect((audio.stops.last.at - 3000).abs(), lessThanOrEqualTo(40));
        audio.dispose();
      });
    });
  });
}
