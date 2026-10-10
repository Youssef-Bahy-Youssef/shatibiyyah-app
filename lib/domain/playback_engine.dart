// lib/domain/playback_engine.dart — carries out a PlaybackPlan on an audio player.
//
// The engine owns no rules: it asks the plan what to play, seeks (only when the
// action is not continuous), stops at the action's end, waits out silences, and
// asks again. The player sits behind [AudioPort] so the engine is tested with a
// fake clock (test/playback_engine_test.dart); the just_audio adapter is in
// lib/services/just_audio_port.dart.
//
// Every command bumps a generation token. Anything still pending from an older
// generation — a seek completing late, a silence timer, a boundary reached just
// as the user pressed «next» — is dropped, so quick taps never jump back (AUD-20).
//
// «Playing» is the student's intent, not the player's state: it stays true through
// the silent gap between verses. When the player stops or starts without the engine
// asking (the lock-screen buttons, a call, headphones unplugged), the engine takes
// that as a pause or a resume, so the UI and the gap timers never run on alone.
import 'dart:async';

import 'playback_plan.dart';
import 'playback_windows.dart';

/// The small slice of an audio player the engine needs.
abstract class AudioPort {
  Stream<int> get positionMs; // frequent position updates while playing
  int get currentPositionMs;
  bool get playing;

  /// Every change of [playing], including ones the engine did not ask for (the
  /// lock-screen buttons, an interruption, headphones unplugged).
  Stream<bool> get playingChanges;
  Future<void> seek(int ms);
  Future<void> play();
  Future<void> pause();
  Future<void> setSpeed(double speed);
}

/// What the UI shows; emitted on every change.
class EngineState {
  final int verse;
  final bool inTitle;
  final bool playing;
  final bool inGap;
  final int verseRepetition;
  final int sectionRepetition;
  final bool finished;
  const EngineState({
    required this.verse,
    this.inTitle = false,
    this.playing = false,
    this.inGap = false,
    this.verseRepetition = 1,
    this.sectionRepetition = 1,
    this.finished = false,
  });
}

/// A player that stops by itself this close to the end of the file has reached it:
/// decoders often report a file a little shorter than its declared duration (F-40).
const int kEndOfFileSlackMs = 200;

class PlaybackEngine {
  final AudioPort audio;
  final PlaybackPlan plan;

  /// How close to an action's end counts as reaching it (position updates are periodic).
  final int boundaryLeadMs;

  /// The file's length as the player decoded it, when it reports one. The last
  /// verse ends there if that is before the recording's declared duration (F-40).
  int? decodedDurationMs;

  final _state = StreamController<EngineState>.broadcast();
  StreamSubscription<int>? _positionSub;
  StreamSubscription<bool>? _playingSub;
  bool _active = false; // the student wants playback (true through gaps)
  Timer? _gapTimer;
  PlanAction? _current;
  int _generation = 0;

  PlaybackEngine(this.audio, this.plan, {this.boundaryLeadMs = 40}) {
    _positionSub = audio.positionMs.listen(_onPosition);
    _playingSub = audio.playingChanges.listen((_) => _onPlayerChanged());
  }

  Stream<EngineState> get states => _state.stream;
  PlaybackWindows get windows => plan.windows;
  EngineState get state => _snapshot();

  Future<void> play([int? verse]) => _run(plan.start(verse));

  Future<void> jumpTo(int verse) => _run(plan.jumpTo(verse));

  Future<void> next() => jumpTo((plan.verse + 1).clamp(plan.scope.fromVerse, plan.scope.toVerse));

  Future<void> previous() => jumpTo((plan.verse - 1).clamp(plan.scope.fromVerse, plan.scope.toVerse));

  Future<void> pause() async {
    _generation++;
    _active = false;
    _gapTimer?.cancel();
    await audio.pause();
    _emit();
  }

  /// Resume the current action where the player stands; after the end of the
  /// scope, start it again.
  Future<void> resume() async {
    final current = _current;
    if (current is PlayRange) {
      _generation++;
      _active = true;
      await audio.play();
      _emit();
    } else if (current is Finished) {
      await _run(plan.start());
    } else {
      await _run(plan.jumpTo(plan.verse));
    }
  }

  /// The player changed on its own. It is judged by where it stands now, not by
  /// the event, so a late event about the engine's own pause or play is harmless.
  void _onPlayerChanged() {
    final nowPlaying = audio.playing;
    final current = _current;
    if (!nowPlaying && _active && current is PlayRange && _reachedEndOfFile(current)) {
      _run(plan.advance()); // the file ran out a little early: that is the end of the range
    } else if (!nowPlaying && _active && current is PlayRange) {
      pause(); // stopped from outside: the student is no longer listening
    } else if (nowPlaying && !_active) {
      resume(); // started from outside (the lock screen)
    } else if (nowPlaying && _current is Silence) {
      _run(plan.advance()); // «play» pressed during the gap between verses: skip the gap
    }
  }

  Future<void> _run(PlanAction action) async {
    final generation = ++_generation;
    _gapTimer?.cancel();
    _current = action;
    _active = action is! Finished;
    switch (action) {
      case PlayRange():
        if (!action.continuous) {
          await audio.seek(action.fromMs);
          if (generation != _generation) return; // superseded while seeking
        }
        if (!audio.playing) await audio.play();
      case Silence():
        await audio.pause();
        _gapTimer = Timer(Duration(milliseconds: action.ms), () {
          if (generation == _generation) _run(plan.advance());
        });
      case Finished():
        await audio.pause();
    }
    if (generation == _generation) _emit();
  }

  void _onPosition(int ms) {
    final current = _current;
    if (current is! PlayRange || !audio.playing) return;
    if (ms >= _endOf(current) - boundaryLeadMs) {
      _run(plan.advance());
    } else {
      _emit();
    }
  }

  /// Where [range] really ends: at the decoded end of the file when that comes
  /// before the declared one.
  int _endOf(PlayRange range) {
    final decoded = decodedDurationMs;
    if (decoded == null || range.toMs < windows.durationMs) return range.toMs;
    return decoded < range.toMs ? decoded : range.toMs;
  }

  /// [range] runs to the end of the file, and the player stopped within
  /// [kEndOfFileSlackMs] of it.
  bool _reachedEndOfFile(PlayRange range) =>
      range.toMs >= windows.durationMs && audio.currentPositionMs >= _endOf(range) - kEndOfFileSlackMs;

  EngineState _snapshot() {
    final current = _current;
    final position = audio.currentPositionMs;
    return EngineState(
      verse: plan.verse,
      inTitle: current is PlayRange && current.titleEndMs != null && position < current.titleEndMs!,
      playing: _active,
      inGap: current is Silence,
      verseRepetition: plan.verseRepetition,
      sectionRepetition: plan.sectionRepetition,
      finished: current is Finished,
    );
  }

  void _emit() {
    if (!_state.isClosed) _state.add(_snapshot());
  }

  Future<void> dispose() async {
    _generation++;
    _gapTimer?.cancel();
    await _positionSub?.cancel();
    await _playingSub?.cancel();
    await _state.close();
  }
}
