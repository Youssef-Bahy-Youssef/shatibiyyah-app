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
      expect(audio.seeks, [750]); // everything after the first jump is continuous
      expect(engine.state.finished, isTrue);
      audio.dispose();
    });
  });

  test('the gap is a pause, then playback resumes in place', () {
    fakeAsync((async) {
      final audio = FakeAudio();
      final engine = PlaybackEngine(
          audio, PlaybackPlan(windows, const PlaybackScope(1, 2), const PlaybackSettings(gapMs: 500)));
      engine.play();
      async.elapse(const Duration(milliseconds: 1260)); // 750 → 2000 plus a little
      expect(engine.state.inGap, isTrue);
      expect(audio.playing, isFalse);
      expect(engine.state.playing, isTrue); // the student is still listening through the gap
      final pausedAt = audio.currentPositionMs;
      async.elapse(const Duration(milliseconds: 520));
      expect(engine.state.inGap, isFalse);
      expect(engine.state.verse, 2);
      expect(audio.playing, isTrue);
      expect(audio.seeks, [750]); // resumed where it paused, no seek
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
          expect(audio.seeks, [750]); // no jump back
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
}
