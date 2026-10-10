// lib/app/audio_library.dart — the recordings: which is chosen, which are on the
// device, and their downloads (features-v3 reciter-catalog, audio-downloads).
//
// The reader plays whatever this hands it. Choosing a reciter keeps the verse and
// keeps playing (ADR 0006): one on the device takes over at once, from the start
// of the verse in hand. One that is not on the device starts downloading while the
// current one plays on; it takes over once verified, at the next verse boundary.
// When nothing on the device can play, the chosen one is the recording at once,
// and playback becomes available when its download finishes.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/app_content.dart';
import '../data/recording_repository.dart';
import '../domain/playback_engine.dart';
import '../domain/playback_plan.dart';
import '../services/audio_focus.dart';
import '../services/download_manager.dart';
import '../services/just_audio_port.dart';
import '../services/preferences_service.dart';
import '../ui/reader/reader_controller.dart';

const String kRecordingPref = 'v2.recording';

/// A recording chosen while another keeps playing: it takes over once its file is
/// on the device and verified, at the next verse boundary (ADR 0006).
const String kPendingRecordingPref = 'v2.recording.pending';
const String kWifiOnlyPref = 'v2.downloads.wifi_only';

/// Builds the engine that plays [recording] from [filePath] (replaceable in tests).
typedef EngineFactory = Future<({PlaybackEngine engine, Future<void> Function() dispose})> Function(
    Recording recording, String filePath, PlaybackPlan plan);

class AudioLibrary extends ChangeNotifier {
  final AppContent content;
  final Prefs prefs;
  final DownloadManager downloads;
  final EngineFactory? _engineFactory;

  /// The app's engine unless one was given.
  EngineFactory get engineFactory => _engineFactory ?? justAudioEngine;

  final Map<String, DownloadProgress> _progress = {};
  final Map<String, DownloadCancel> _cancels = {};
  final Map<String, Future<void>> _running = {};
  final Set<String> _onDevice = {};
  ReaderController? _reader;
  Future<void> Function()? _disposeEngine;

  AudioLibrary({
    required this.content,
    required this.prefs,
    required this.downloads,
    EngineFactory? engineFactory,
  // A named parameter cannot be private, so no `this._engineFactory`.
  // ignore: prefer_initializing_formals
  }) : _engineFactory = engineFactory;

  List<Recording> get recordings => content.recordings.recordings;

  Recording get current {
    final id = prefs.getString(kRecordingPref);
    return recordings.firstWhere((r) => r.id == id, orElse: () => content.recordings.defaultRecording);
  }

  bool isOnDevice(Recording r) => _onDevice.contains(r.id);
  DownloadProgress? progressOf(Recording r) => _progress[r.id];
  bool isDownloading(Recording r) => _cancels.containsKey(r.id);

  /// Paused with «إيقاف مؤقت» (also after a relaunch): «متابعة» resumes it.
  bool isPaused(Recording r) => !isDownloading(r) && _progress[r.id]?.phase == DownloadPhase.paused;

  /// Whether any bytes of [r] are on the device: «حذف» is offered (ADR 0007).
  bool holdsBytes(Recording r) => isOnDevice(r) || isDownloading(r) || (_progress[r.id]?.received ?? 0) > 0;

  bool get wifiOnly => prefs.getString(kWifiOnlyPref) != '0';
  set wifiOnly(bool on) {
    prefs.setString(kWifiOnlyPref, on ? '1' : '0');
    notifyListeners();
  }

  /// Bytes of recordings on the device.
  int get bytesOnDevice => [for (final r in recordings) if (isOnDevice(r)) r.localBytes].fold(0, (a, b) => a + b);

  /// Looks at the files on the device; a download that finished while the app was
  /// closed is verified and moved into place first. A partial left from before
  /// shows where it stopped: paused, or interrupted.
  Future<void> refresh() async {
    for (final r in recordings) {
      if (await downloads.isDownloaded(r) || (!isDownloading(r) && await downloads.recover(r))) {
        _onDevice.add(r.id);
      } else {
        _onDevice.remove(r.id);
        if (isDownloading(r) || _progress.containsKey(r.id)) continue;
        final kept = await downloads.partialOf(r);
        if (kept != null && kept.received > 0) {
          _progress[r.id] = kept.paused
              ? DownloadProgress(DownloadPhase.paused, kept.received, r.localBytes)
              : DownloadProgress(DownloadPhase.failed, kept.received, r.localBytes, DownloadError.network);
        }
      }
    }
    // A recording picked earlier whose download finished meanwhile (the app was
    // closed, or in the background) takes over: now, or at the verse's end.
    await _switchWhenDue();
    notifyListeners();
  }

  /// The engine for the chosen recording, or null when it is not on the device.
  Future<PlaybackEngine?> openCurrent(PlaybackPlan plan) async {
    await _disposeEngine?.call();
    _disposeEngine = null;
    final r = current;
    if (!isOnDevice(r) || !content.isUsable(r)) return null;
    final built = await engineFactory(r, downloads.fileFor(r).path, plan);
    _disposeEngine = built.dispose;
    return built.engine;
  }

  /// Connects the reader; from now on choices and downloads reach it.
  void attach(ReaderController reader) {
    _reader = reader;
    reader.library = this;
  }

  /// The recording waiting to take over: chosen while another plays, not yet verified.
  Recording? get pending {
    final id = prefs.getString(kPendingRecordingPref);
    for (final r in recordings) {
      if (r.id == id) return r;
    }
    return null;
  }

  void _setPending(Recording? r) {
    _dropBoundaryWatch?.call();
    _dropBoundaryWatch = null;
    r == null ? prefs.remove(kPendingRecordingPref) : prefs.setString(kPendingRecordingPref, r.id);
  }

  VoidCallback? _dropBoundaryWatch;

  /// The recording the listener picked: the one waiting to take over, else the one in use.
  Recording get chosen => pending ?? current;

  /// «القارئ»: choose [r]; the reader keeps its verse and keeps playing. One that
  /// is not on the device starts downloading, unless [startDownload] is false (the
  /// first run asks first).
  Future<void> choose(Recording r, {bool startDownload = true}) async {
    if (r.id == current.id) {
      _setPending(null); // the one playing stays: a switch that was waiting is dropped
      notifyListeners();
      return;
    }
    if (!isOnDevice(r) && isOnDevice(current) && content.isUsable(current)) {
      // The current one plays on while this one downloads and is verified.
      _setPending(r);
      notifyListeners();
      if (startDownload) unawaited(download(r));
      return;
    }
    _setPending(null);
    await _switchTo(r);
  }

  Future<void> _switchTo(Recording r) async {
    final wasPlaying = _reader?.playing ?? false; // read before the old engine is closed
    prefs.setString(kRecordingPref, r.id);
    await _reconnect(resume: wasPlaying);
  }

  /// The pending recording is on the device: it takes over now if nothing plays,
  /// or as soon as the verse being recited ends. Never in the middle of a verse.
  Future<void> _switchWhenDue() async {
    final next = pending, reader = _reader;
    if (next == null || !isOnDevice(next) || !content.isUsable(next)) return;
    if (reader == null || !reader.playing) {
      _setPending(null);
      await _switchTo(next);
      return;
    }
    final verse = reader.verse;
    void onReader() {
      if (reader.verse == verse && reader.playing) return;
      _setPending(null); // drops this watch too
      _switchTo(next);
    }

    _dropBoundaryWatch?.call();
    reader.addListener(onReader);
    _dropBoundaryWatch = () => reader.removeListener(onReader);
  }

  Future<void> _reconnect({bool resume = false}) async {
    final reader = _reader;
    if (reader == null) return;
    final chapter = content.matn.chapterOfVerse(reader.verse);
    // The section in hand goes with the listener to the other recording.
    final section = reader.sectionInHand ?? PlaybackScope(chapter.fromVerse, chapter.toVerse);
    final windows = await content.windowsOrNull(current);
    final engine = windows == null ? null : await openCurrent(PlaybackPlan(windows, section, reader.settings));
    await reader.setAudio(current, engine, resume: resume && engine != null);
    notifyListeners();
  }

  /// Starts (or resumes) downloading [r]; errors land in [progressOf].
  Future<void> download(Recording r) async {
    if (isDownloading(r)) return;
    final cancel = DownloadCancel();
    _cancels[r.id] = cancel;
    final finished = Completer<void>();
    _running[r.id] = finished.future;
    notifyListeners();
    try {
      await downloads.download(r, wifiOnly: wifiOnly, cancel: cancel, onProgress: (p) {
        _progress[r.id] = p;
        notifyListeners();
      });
      _onDevice.add(r.id);
      if (r.id == current.id) {
        await _reconnect(); // playable now
      } else if (r.id == pending?.id) {
        await _switchWhenDue();
      }
    } on DownloadException catch (e) {
      final stopped = e.error == DownloadError.cancelled || e.error == DownloadError.paused;
      if (!stopped) _reader?.rating?.noteError(); // shown in «التنزيلات»
      final p = _progress[r.id];
      _progress[r.id] = DownloadProgress(
          switch (e.error) {
            DownloadError.cancelled => DownloadPhase.cancelled,
            DownloadError.paused => DownloadPhase.paused,
            _ => DownloadPhase.failed,
          },
          p?.received ?? 0,
          r.localBytes,
          e.error);
    } finally {
      _cancels.remove(r.id);
      _running.remove(r.id);
      finished.complete();
      notifyListeners();
    }
  }

  void cancel(Recording r) => _cancels[r.id]?.cancel();

  /// «إيقاف مؤقت»: stops the download and keeps its bytes for «متابعة».
  void pause(Recording r) => _cancels[r.id]?.pause();

  /// A background download finished with the app not waiting for it: take it in,
  /// and play it at once if it is the chosen recording.
  Future<void> backgroundFinished() async {
    final wasCurrent = isOnDevice(current);
    await refresh();
    if (!wasCurrent && isOnDevice(current)) await _reconnect();
  }

  /// Removes [r] from the device in any state (a partial too); the reader loses
  /// its audio if it was the chosen one.
  Future<void> delete(Recording r) async {
    cancel(r);
    if (r.id == pending?.id) _setPending(null);
    await _running[r.id]; // a running download writes its sidecar as it stops
    if (r.id == current.id) {
      await _disposeEngine?.call();
      _disposeEngine = null;
      await _reader?.setAudio(r, null);
    }
    await downloads.delete(r);
    _onDevice.remove(r.id);
    _progress.remove(r.id);
    notifyListeners();
  }
}

/// The app's engine: just_audio, with our own interruption policy.
Future<({PlaybackEngine engine, Future<void> Function() dispose})> justAudioEngine(
    Recording recording, String filePath, PlaybackPlan plan) async {
  // Interruptions follow our own policy (AudioFocus): just_audio's would resume after a call.
  final port = JustAudioPort(AudioPlayer(handleInterruptions: false));
  final decoded = await port.load(filePath);
  final engine = PlaybackEngine(port, plan)..decodedDurationMs = decoded?.inMilliseconds;
  AudioFocus? focus;
  try {
    focus = await AudioFocus.attach(isPlaying: () => engine.state.playing, pause: engine.pause, setVolume: port.setVolume);
  } catch (_) {
    // Without a session the app still plays; it only loses the interruption policy.
  }
  return (
    engine: engine,
    dispose: () async {
      await focus?.dispose();
      await engine.dispose();
      await port.dispose();
    },
  );
}
