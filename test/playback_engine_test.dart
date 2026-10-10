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

  // ADR 0005: wherever playback stops or jumps, it ends within 40 ms of the
  // window's end at every speed. The player reports its position only every
  // 200 ms, so the end is scheduled from the position and the speed.
  group('stops within 40 ms of the verse\'s end (ADR 0005)', () {
    for (final speed in [0.25, 1.0, 2.0]) {
      test('$speed×: a repeat seeks back, the gap pauses and the end pauses on time', () {
        fakeAsync((async) {
          final audio = ClockAudio(async);
          final engine = PlaybackEngine(
              audio, PlaybackPlan(windows, const PlaybackScope(2, 3), const PlaybackSettings(verseRepeats: 2, gapMs: 1000)));
          engine.setSpeed(speed);
          engine.play();
          async.elapse(Duration(milliseconds: (30000 / speed).round()));

          // Verse 2 twice (a seek back at its end), a gap (a pause), verse 3 straight on
          // from where the gap paused, then again (a seek back), and the end (a pause).
          expect(audio.seeks, [1950, 1950, 2950]);
          expect(audio.stops.map((s) => s.kind), ['seek', 'pause', 'seek', 'pause']);
          final ends = [3000, 3000, 3800, 3800]; // verse 3 ends where the title before verse 4 begins
          for (final (i, stop) in audio.stops.indexed) {
            expect((stop.at - ends[i]).abs(), lessThanOrEqualTo(40), reason: '${stop.kind} at ${stop.at}, the window ends at ${ends[i]}');
          }
          expect(engine.state.finished, isTrue);
          audio.dispose();
        });
      });
    }

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
