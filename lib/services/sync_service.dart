// lib/services/sync_service.dart — SyncController: the only module that touches BOTH the
// audio engine and the page viewer. 100% port of js/sync.js. Keeps the page in step with
// playback, routes verse taps back to the audio, and owns the "detached" browsing state.
import 'dart:async';

import '../ui/widgets/page_viewer.dart';
import 'audio_service.dart';
import 'data_service.dart';

class DetachChange {
  final bool detached;
  final int? verse;
  final String chapterName;
  const DetachChange(this.detached, this.verse, this.chapterName);
}

class SyncController {
  final AudioEngine audio;
  final PageViewerController viewer;
  final ShatibiyyahData data;

  bool detached = false;
  int? playingId;
  String playingChapter;

  final _detachCtrl = StreamController<DetachChange>.broadcast();
  Stream<DetachChange> get onDetachChange => _detachCtrl.stream;

  final List<StreamSubscription> _subs = [];

  SyncController(this.audio, this.viewer, this.data)
      : playingId = audio.currentVerse,
        playingChapter = audio.getChapterName() {
    _subs.add(audio.onVerseChange.listen(_onVerseChange));
    // A fresh Play while detached snaps back to the playing verse (spec S4).
    _subs.add(audio.onPlay.listen((_) {
      if (detached) reattach();
    }));
    _subs.add(viewer.onVerseTap.listen(_onVerseTap));
    _subs.add(viewer.onPageChange.listen((_) => _onManualPage()));
  }

  // ported from sync.js: _onVerseChange(d)
  void _onVerseChange(VerseChange d) {
    playingId = d.verse;
    playingChapter = d.chapterName;
    if (!detached) {
      viewer.setActiveVerse(d.verse);
    } else {
      _emitDetach();
    }
  }

  // A verse tap navigates to that verse inside باب (chapter) mode: it highlights/positions the
  // tapped verse and silently seeds the نطاق range (from = to = id) for whenever the user opens
  // the نطاق panel later. The active mode is always left as باب — if we were in نطاق/full mode
  // (or a different chapter), we switch to the chapter that owns the verse — so pressing play
  // plays the whole باب from the tapped verse to its end. It never activates نطاق mode.
  void _onVerseTap(int id) {
    final keepPlaying = !audio.isPaused;
    detached = false;
    final idx = data.chapterIndexForVerse(id);
    if (idx >= 0 && (audio.mode != 'chapter' || audio.chapterIdx != idx)) {
      audio.setChapter(idx);
    }
    audio.seekToVerse(id, keepPlaying);
    audio.presetRange(id);
    _emitDetach();
  }

  // ported from sync.js: _onManualPage()
  void _onManualPage() {
    if (detached) return;
    detached = true;
    _emitDetach();
  }

  // ported from sync.js: reattach()
  void reattach() {
    detached = false;
    if (playingId != null) viewer.setActiveVerse(playingId!);
    _emitDetach();
  }

  // ported from sync.js: jumpToVerse(id, {play})
  void jumpToVerse(int id, {bool play = false}) {
    final a = audio;
    detached = false;
    final inRange = id >= a.rangeStartVerse && id <= a.rangeEndVerse;
    if (!inRange) {
      final idx = data.chapterIndexForVerse(id);
      if (idx >= 0) a.setChapter(idx);
    }
    a.seekToVerse(id, play);
    if (!play) a.setPlaying(false);
    viewer.pulseVerse(id);
    _emitDetach();
  }

  // ported from sync.js: playChapter(idx)
  void playChapter(int idx) {
    if (idx < 0 || idx >= data.chapters.length) return;
    final c = data.chapters[idx];
    detached = false;
    audio.setChapter(idx);
    if (c.startTime != null) audio.seekToTime(c.startTime!);
    playingId = audio.currentVerse;
    playingChapter = audio.getChapterName();
    viewer.setActiveVerse(audio.currentVerse);
    audio.setPlaying(true);
    _emitDetach();
  }

  void _emitDetach() {
    _detachCtrl.add(DetachChange(detached, playingId, playingChapter));
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _detachCtrl.close();
  }
}
