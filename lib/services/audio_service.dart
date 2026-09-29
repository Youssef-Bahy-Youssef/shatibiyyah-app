// lib/services/audio_service.dart — AudioEngine: owns the just_audio player and ALL
// playback state. 100% port of js/audio.js. The subtle parts (frame-accurate seeking,
// the eps() boundary lead, verse/section repeat, inter-verse pause, the timeupdate + rAF
// double pump via positionStream + a 16ms Timer) are preserved verbatim.
//
// Knows nothing about pages or boxes. Fires `verseChange` with just a verse id; the
// SyncController resolves the page + box.
//
// Events (broadcast streams, mirroring EventTarget): ready · verseChange · timeUpdate ·
// rangeChange · play · pause · ended · offline · loadError
import 'dart:async';
import 'dart:math' as math;

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/playback_settings.dart';
import 'data_service.dart';
import 'preferences_service.dart';

class VerseChange {
  final int verse;
  final String chapterName;
  final bool pulse;
  const VerseChange(this.verse, this.chapterName, this.pulse);
}

class TimeUpdate {
  final double time;
  final double rangeStart;
  final double rangeEnd;
  const TimeUpdate(this.time, this.rangeStart, this.rangeEnd);
}

class RangeChange {
  final String mode;
  final int rangeStartVerse;
  final int rangeEndVerse;
  const RangeChange(this.mode, this.rangeStartVerse, this.rangeEndVerse);
}

double _clamp(double v, double a, double b) => math.min(b, math.max(a, v));

class AudioEngine {
  final AudioPlayer audio;
  final ShatibiyyahData data;
  final Prefs prefs;

  final int LAST_VERSE; // ignore: non_constant_identifier_names
  double DURATION; // ignore: non_constant_identifier_names

  // persisted config
  late String mode;
  late int chapterIdx;
  late int fromVerse;
  late int toVerse;
  late double verseRepsTotal;
  late double sectionRepsTotal;
  late double speed;
  late int pauseSeconds;

  // runtime
  int rangeStartVerse = 1;
  int rangeEndVerse = 1;
  double rangeStartTime = 0;
  double rangeEndTime = 0;
  String selectedChapterName = '';
  int currentVerse = 1;
  late double verseRepsLeft;
  late double sectionRepsLeft;
  int playToken = 0;
  Timer? pauseTimer;
  Timer? _ticker;
  bool scrubbing = false;
  ({double t, bool play})? pendingSeek;
  bool atEndGuard = false;
  final double _timeBase = 0;
  bool _ready = false;

  // ── event streams ──
  final _verseCtrl = StreamController<VerseChange>.broadcast();
  final _timeCtrl = StreamController<TimeUpdate>.broadcast();
  final _rangeCtrl = StreamController<RangeChange>.broadcast();
  final _playCtrl = StreamController<void>.broadcast();
  final _pauseCtrl = StreamController<void>.broadcast();
  final _endedCtrl = StreamController<void>.broadcast();
  final _readyCtrl = StreamController<void>.broadcast();
  final _loadErrorCtrl = StreamController<void>.broadcast();

  Stream<VerseChange> get onVerseChange => _verseCtrl.stream;
  Stream<TimeUpdate> get onTimeUpdate => _timeCtrl.stream;
  Stream<RangeChange> get onRangeChange => _rangeCtrl.stream;
  Stream<void> get onPlay => _playCtrl.stream;
  Stream<void> get onPause => _pauseCtrl.stream;
  Stream<void> get onEnded => _endedCtrl.stream;
  Stream<void> get onReady => _readyCtrl.stream;
  Stream<void> get onLoadError => _loadErrorCtrl.stream;

  bool _wasPlaying = false;

  AudioEngine(this.audio, this.data, this.prefs)
    : LAST_VERSE = data.lastVerse,
      DURATION = data.defaultDuration {
    // ported from audio.js constructor: persisted config
    mode = prefs.getLS(K.mode, 'chapter');
    chapterIdx = int.tryParse(prefs.getLS(K.chapter, '0')) ?? 0;
    fromVerse = _clampInt(
      int.tryParse(prefs.getLS(K.from, '1')) ?? 1,
      1,
      LAST_VERSE,
    );
    toVerse = _clampInt(
      int.tryParse(prefs.getLS(K.to, '10')) ?? 10,
      1,
      LAST_VERSE,
    );
    verseRepsTotal = repFromStore(prefs.getLS(K.vrep, '1'), 1);
    sectionRepsTotal = repFromStore(prefs.getLS(K.srep, '1'), 1);
    speed = double.tryParse(prefs.getLS(K.speed, '1')) ?? 1;
    if (speed == 0) speed = 1;
    pauseSeconds = int.tryParse(prefs.getLS(K.pause, '0')) ?? 0;
    if (!['chapter', 'range', 'full'].contains(mode)) mode = 'chapter';

    verseRepsLeft = verseRepsTotal;
    sectionRepsLeft = sectionRepsTotal;

    _bindAudio();
  }

  int _clampInt(int v, int a, int b) => math.min(b, math.max(a, v));

  // ── emit helpers (ported from audio.js: _emit / _announceVerse / _emitProgress / _emitRange) ──
  // ported from audio.js: _announceVerse(pulse)
  void _announceVerse(bool pulse) {
    _verseCtrl.add(VerseChange(currentVerse, getChapterName(), pulse));
  }

  void _emitProgress(double t) {
    _timeCtrl.add(TimeUpdate(t, rangeStartTime, rangeEndTime));
  }

  void _emitRange() {
    _rangeCtrl.add(RangeChange(mode, rangeStartVerse, rangeEndVerse));
  }

  // ── time base (CBR, frame-accurate) ──
  double _getTime() => audio.position.inMilliseconds / 1000.0 + _timeBase;

  void _setTime(double t) {
    try {
      audio.seek(Duration(milliseconds: ((t - _timeBase) * 1000).round()));
      _verifySeek(t);
    } catch (_) {}
  }

  // prompt requirement: after every seek verify position within 500ms, retry once if off.
  void _verifySeek(double t) {
    Timer(const Duration(milliseconds: 450), () {
      if (!_ready) return;
      final cur = audio.position.inMilliseconds / 1000.0;
      if ((cur - t).abs() > 0.5 && (t - _timeBase) >= 0) {
        try {
          audio.seek(Duration(milliseconds: ((t - _timeBase) * 1000).round()));
        } catch (_) {}
      }
    });
  }

  // ── range-dependent helpers (ported from audio.js) ──
  double _rangeEndForVerse(int endVerse) {
    final vt = data.verseTimes;
    if (endVerse >= LAST_VERSE) return DURATION;
    double t = vt[endVerse + 1] ?? DURATION;
    final nextCh = data.startAtVerse[endVerse + 1];
    if (nextCh != null && nextCh.startTime != null) {
      t = math.min(t, nextCh.startTime!);
    }
    return t;
  }

  double _verseNaturalEnd(int v) {
    final vt = data.verseTimes;
    return (v + 1 < vt.length ? vt[v + 1] : null) ?? DURATION;
  }

  int _verseFromTime(double t) {
    final vt = data.verseTimes;
    int lo = rangeStartVerse, hi = rangeEndVerse, ans = rangeStartVerse;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if ((vt[mid] ?? double.infinity) <= t) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  // ported from audio.js: getChapterName()
  String getChapterName() {
    if (mode == 'chapter') return selectedChapterName;
    final c = data.getChapterForVerse(currentVerse);
    return c?.name ?? '';
  }

  // ── range setup (ported from audio.js: setupRange) ──
  void setupRange(bool preservePos) {
    final ch = data.chapters;
    final vt = data.verseTimes;
    if (mode == 'chapter') {
      chapterIdx = _clampInt(chapterIdx, 0, ch.length - 1);
      final c = ch[chapterIdx];
      rangeStartVerse = c.startVerse;
      rangeStartTime = c.startTime ?? (vt[c.startVerse] ?? 0);
      final nx = chapterIdx + 1 < ch.length ? ch[chapterIdx + 1] : null;
      rangeEndTime = nx != null ? (nx.startTime ?? DURATION) : DURATION;
      rangeEndVerse = nx != null ? nx.startVerse - 1 : LAST_VERSE;
      selectedChapterName = c.name;
    } else if (mode == 'range') {
      rangeStartVerse = _clampInt(fromVerse, 1, LAST_VERSE);
      rangeEndVerse = _clampInt(toVerse, rangeStartVerse, LAST_VERSE);
      rangeStartTime = vt[rangeStartVerse] ?? 0;
      rangeEndTime = _rangeEndForVerse(rangeEndVerse);
      selectedChapterName = '';
    } else {
      // full
      rangeStartVerse = 1;
      rangeEndVerse = LAST_VERSE;
      rangeStartTime = vt[1] ?? 0;
      rangeEndTime = DURATION;
      selectedChapterName = '';
    }
    if (!preservePos ||
        currentVerse < rangeStartVerse ||
        currentVerse > rangeEndVerse) {
      currentVerse = rangeStartVerse;
      seekTo(rangeStartTime, false);
    }
    verseRepsLeft = verseRepsTotal;
    sectionRepsLeft = sectionRepsTotal;
    atEndGuard = false;
    _emitRange();
    _announceVerse(false);
    final gt = _getTime();
    _emitProgress(gt != 0 ? gt : rangeStartTime);
  }

  // ── playback core (ported from audio.js) ──
  void seekTo(double t, bool play) {
    t = _clamp(t, 0, DURATION > 0 ? DURATION : 1e9);
    if (!_ready) {
      pendingSeek = (t: t, play: play);
      return;
    }
    _setTime(t); // native, frame-accurate (audio is CBR)
    if (play) startPlay();
  }

  /// A recording is loaded. Without one (no download yet) the transport is inert.
  bool get available => _ready;

  void startPlay() {
    if (!_ready) return;
    audio.setSpeed(speed);
    audio.play();
  }

  void setPlaying(bool b) {
    if (b) {
      startPlay();
    } else {
      audio.pause();
    }
  }

  // EPS leads the cut slightly; widen at higher speed to avoid bleeding into the next verse.
  double eps() => math.max(0.14, speed * 0.16);

  // ported from audio.js: tick()
  void tick() {
    if (!audio.playing || scrubbing) return;
    final t = _getTime();
    if (t < rangeEndTime - 1) atEndGuard = false;
    _emitProgress(t);
    final effEnd = math.min(_verseNaturalEnd(currentVerse), rangeEndTime);
    if (t >= effEnd - eps()) onBoundary(t);
  }

  // ported from audio.js: onBoundary(t)
  void onBoundary(double t) {
    if (verseRepsLeft > 1) {
      verseRepsLeft--;
      _announceVerse(true);
      seekTo(data.verseTimes[currentVerse] ?? 0, true);
      return;
    }
    verseRepsLeft = verseRepsTotal;
    if (t >= rangeEndTime - eps() || currentVerse >= rangeEndVerse) {
      reachRangeEnd();
    } else {
      currentVerse++;
      if (pauseSeconds > 0) pauseBetweenVerses();
      _announceVerse(false);
    }
  }

  // ported from audio.js: reachRangeEnd()
  void reachRangeEnd() {
    if (atEndGuard) return;
    atEndGuard = true;
    if (sectionRepsLeft != double.infinity) sectionRepsLeft--;
    if (sectionRepsLeft <= 0) {
      sectionRepsLeft = sectionRepsTotal;
      setPlaying(false);
      currentVerse = rangeStartVerse;
      seekTo(rangeStartTime, false);
      _endedCtrl.add(null);
    } else {
      currentVerse = rangeStartVerse;
      seekTo(rangeStartTime, true);
    }
    _announceVerse(false);
  }

  // ported from audio.js: pauseBetweenVerses()
  void pauseBetweenVerses() {
    audio.pause();
    pauseTimer?.cancel();
    final token = ++playToken;
    pauseTimer = Timer(Duration(milliseconds: pauseSeconds * 1000), () {
      if (token != playToken) return;
      seekTo(data.verseTimes[currentVerse] ?? 0, true);
    });
  }

  // ported from audio.js: refreshDuration()
  void refreshDuration() {
    final d = audio.duration;
    final floor = (data.verseTimes[LAST_VERSE] ?? 0) + 1;
    if (d != null && d.inMicroseconds > 0) {
      DURATION = math.max(d.inMicroseconds / 1e6, floor);
    }
  }

  // ── ticker (rAF analogue) ──
  void _startTicker() {
    _ticker ??= Timer.periodic(const Duration(milliseconds: 16), (_) => tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  // ── bind player events (ported from audio.js: _bindAudio) ──
  void _bindAudio() {
    // timeupdate analogue (reliable in the background): positionStream.
    audio.positionStream.listen((_) => tick());

    audio.playerStateStream.listen((st) {
      final playing = st.playing;
      if (playing && !_wasPlaying) {
        _wasPlaying = true;
        _playCtrl.add(null);
        _startTicker();
      } else if (!playing && _wasPlaying) {
        _wasPlaying = false;
        _pauseCtrl.add(null);
        _stopTicker();
      }
      // 'ended' analogue: natural completion of the whole file → reachRangeEnd().
      if (st.processingState == ProcessingState.completed) {
        reachRangeEnd();
      }
    });

    audio.durationStream.listen((_) => refreshDuration());
  }

  /// ported from audio.js: loadedmetadata handler — called once the asset is loaded.
  void onLoaded() {
    _ready = true;
    refreshDuration();
    if (pendingSeek != null) {
      final pk = pendingSeek!;
      pendingSeek = null;
      seekTo(pk.t, pk.play);
    } else {
      audio.setSpeed(speed);
      setupRange(false);
    }
    _readyCtrl.add(null);
  }

  // ── transport (ported from audio.js) ──
  void togglePlay() {
    if (!_ready) return;
    atEndGuard = false;
    if (!audio.playing) {
      if (_getTime() >= rangeEndTime - eps() ||
          _getTime() < rangeStartTime - 0.5) {
        currentVerse = rangeStartVerse;
        seekTo(rangeStartTime, true);
        _announceVerse(false);
      } else {
        startPlay();
      }
    } else {
      audio.pause();
    }
  }

  // ported from audio.js: stop()
  void stop() {
    playToken++;
    pauseTimer?.cancel();
    atEndGuard = false;
    audio.pause();
    currentVerse = rangeStartVerse;
    verseRepsLeft = verseRepsTotal;
    sectionRepsLeft = sectionRepsTotal;
    seekTo(rangeStartTime, false);
    _announceVerse(false);
  }

  // ported from audio.js: seekToVerse(v, keepPlaying)
  void seekToVerse(int v, bool keepPlaying) {
    playToken++;
    pauseTimer?.cancel();
    atEndGuard = false;
    currentVerse = _clampInt(v, rangeStartVerse, rangeEndVerse);
    verseRepsLeft = verseRepsTotal;
    seekTo(data.verseTimes[currentVerse] ?? 0, keepPlaying);
    _announceVerse(true);
  }

  // ported from audio.js: seekToTime(t)
  void seekToTime(double t) {
    playToken++;
    pauseTimer?.cancel();
    atEndGuard = false;
    t = _clamp(t, rangeStartTime, rangeEndTime);
    currentVerse = _verseFromTime(t);
    verseRepsLeft = verseRepsTotal;
    seekTo(t, audio.playing);
    _announceVerse(false);
    _emitProgress(t);
  }

  void next() => seekToVerse(currentVerse + 1, audio.playing);
  void prev() => seekToVerse(currentVerse - 1, audio.playing);
  bool get isPaused => !audio.playing;

  // ── mode / selection (ported from audio.js) ──
  void setMode(String m) {
    mode = m;
    prefs.setLS(K.mode, m);
    playToken++;
    pauseTimer?.cancel();
    audio.pause();
    setupRange(false);
  }

  void setChapter(int idx) {
    chapterIdx = _clampInt(idx, 0, data.chapters.length - 1);
    prefs.setLS(K.chapter, chapterIdx.toString());
    mode = 'chapter';
    prefs.setLS(K.mode, 'chapter');
    playToken++;
    pauseTimer?.cancel();
    audio.pause();
    setupRange(false);
  }

  void setRange(int from, int to) {
    int f = _clampInt(from, 1, LAST_VERSE);
    int t = _clampInt(to, 1, LAST_VERSE);
    if (t < f) t = f;
    fromVerse = f;
    toVerse = t;
    prefs.setLS(K.from, f.toString());
    prefs.setLS(K.to, t.toString());
    if (mode != 'range') {
      mode = 'range';
      prefs.setLS(K.mode, 'range');
    }
    playToken++;
    pauseTimer?.cancel();
    audio.pause();
    setupRange(false);
  }

  // Silently seed the نطاق range (from = to = verse) for a verse tap: persists the new
  // bounds but does NOT switch mode, reposition playback, or emit any events. The value is
  // simply there the next time the user opens the نطاق panel.
  void presetRange(int verse) {
    final v = _clampInt(verse, 1, LAST_VERSE);
    fromVerse = v;
    toVerse = v;
    prefs.setLS(K.from, v.toString());
    prefs.setLS(K.to, v.toString());
  }

  // ── config (bottom-sheet pickers) (ported from audio.js) ──
  void setSpeed(double v) {
    speed = v;
    prefs.setLS(K.speed, _numStr(v));
    audio.setSpeed(v);
  }

  void setPause(int v) {
    pauseSeconds = v;
    prefs.setLS(K.pause, v.toString());
  }

  void setVerseReps(double v) {
    verseRepsTotal = v;
    verseRepsLeft = v;
    prefs.setLS(K.vrep, repToStore(v));
  }

  void setSectionReps(double v) {
    sectionRepsTotal = v;
    sectionRepsLeft = v;
    prefs.setLS(K.srep, repToStore(v));
  }

  // ── scrubber (ported from audio.js) ──
  double timeAtFraction(double frac) =>
      rangeStartTime + frac * (rangeEndTime - rangeStartTime);

  void setScrubbing(bool b) => scrubbing = b;

  double previewVerseAt(double frac) {
    final t = timeAtFraction(frac);
    final v = _verseFromTime(t);
    if (v != currentVerse) {
      currentVerse = v;
      _announceVerse(false);
    }
    return t;
  }

  void seekToFraction(double frac) {
    playToken++;
    pauseTimer?.cancel();
    atEndGuard = false;
    final t = timeAtFraction(frac);
    currentVerse = _verseFromTime(t);
    verseRepsLeft = verseRepsTotal;
    seekTo(t, audio.playing);
    scrubbing = false;
    _announceVerse(false);
    _emitProgress(t);
  }

  // ── source — no audio is bundled. A recording plays only from a file on the device
  // (written by the download manager in P5; side-loaded in development). With
  // [filePath] null the engine stays unavailable and reports a load error. ──
  Future<void> initSource({
    required String? filePath,
    required String recordingId,
    required String artist,
  }) async {
    if (filePath == null) {
      _loadErrorCtrl.add(null);
      return;
    }
    try {
      await audio.setAudioSource(
        AudioSource.file(
          filePath,
          tag: MediaItem(id: recordingId, album: 'تيسير الشاطبية', title: 'تيسير الشاطبية', artist: artist),
        ),
      );
      onLoaded();
    } catch (_) {
      _loadErrorCtrl.add(null);
    }
  }

  String _numStr(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

  void dispose() {
    _stopTicker();
    pauseTimer?.cancel();
    _verseCtrl.close();
    _timeCtrl.close();
    _rangeCtrl.close();
    _playCtrl.close();
    _pauseCtrl.close();
    _endedCtrl.close();
    _readyCtrl.close();
    _loadErrorCtrl.close();
  }
}
