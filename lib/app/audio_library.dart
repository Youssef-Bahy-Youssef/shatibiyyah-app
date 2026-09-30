// lib/app/audio_library.dart — the recordings: which is chosen, which are on the
// device, and their downloads (features-v3 reciter-catalog, audio-downloads).
//
// The reader plays whatever this hands it. Choosing a reciter keeps the verse and
// swaps the engine; one that is not on the device leaves the reader without audio
// and points the student to «التنزيلات». When a download finishes for the chosen
// recording, playback becomes available at once.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/app_content.dart';
import '../data/matn_repository.dart';
import '../data/recording_repository.dart';
import '../data/user_store.dart';
import '../domain/playback_engine.dart';
import '../domain/playback_plan.dart';
import '../services/audio_focus.dart';
import '../services/download_manager.dart';
import '../services/just_audio_port.dart';
import '../services/preferences_service.dart';
import '../ui/reader/reader_controller.dart';

const String kRecordingPref = 'v2.recording';
const String kWifiOnlyPref = 'v2.downloads.wifi_only';

/// Builds the engine that plays [recording] from [filePath] (replaceable in tests).
typedef EngineFactory = Future<({PlaybackEngine engine, Future<void> Function() dispose})> Function(
    Recording recording, String filePath, PlaybackPlan plan);

class AudioLibrary extends ChangeNotifier {
  final AppContent content;
  final Prefs prefs;
  final UserStore? user;
  final DownloadManager downloads;
  final EngineFactory? _engineFactory;

  /// The app's engine unless one was given: it tells the reader's rating prompt
  /// when a chapter becomes finished.
  EngineFactory get engineFactory =>
      _engineFactory ??
      justAudioEngine(user, matn: content.matn, onChapterFinished: (_) => _reader?.rating?.chapterFinished());

  final Map<String, DownloadProgress> _progress = {};
  final Map<String, DownloadCancel> _cancels = {};
  final Set<String> _onDevice = {};
  ReaderController? _reader;
  Future<void> Function()? _disposeEngine;

  AudioLibrary({
    required this.content,
    required this.prefs,
    required this.downloads,
    this.user,
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

  bool get wifiOnly => prefs.getString(kWifiOnlyPref) != '0';
  set wifiOnly(bool on) {
    prefs.setString(kWifiOnlyPref, on ? '1' : '0');
    notifyListeners();
  }

  /// Bytes of recordings on the device.
  int get bytesOnDevice => [for (final r in recordings) if (isOnDevice(r)) r.localBytes].fold(0, (a, b) => a + b);

  /// Looks at the files on the device; a download that finished while the app was
  /// closed is verified and moved into place first.
  Future<void> refresh() async {
    for (final r in recordings) {
      if (await downloads.isDownloaded(r) || (!isDownloading(r) && await downloads.recover(r))) {
        _onDevice.add(r.id);
      } else {
        _onDevice.remove(r.id);
      }
    }
    notifyListeners();
  }

  /// The engine for the chosen recording, or null when it is not on the device.
  Future<PlaybackEngine?> openCurrent(PlaybackPlan plan) async {
    await _disposeEngine?.call();
    _disposeEngine = null;
    final r = current;
    if (!isOnDevice(r)) return null;
    final built = await engineFactory(r, downloads.fileFor(r).path, plan);
    _disposeEngine = built.dispose;
    return built.engine;
  }

  /// Connects the reader; from now on choices and downloads reach it.
  void attach(ReaderController reader) {
    _reader = reader;
    reader.library = this;
  }

  /// «القارئ»: choose [r]; the reader keeps its verse and gets the new audio (or none).
  Future<void> choose(Recording r) async {
    prefs.setString(kRecordingPref, r.id);
    await _reconnect();
  }

  Future<void> _reconnect() async {
    final reader = _reader;
    if (reader == null) return;
    final chapter = content.matn.chapterOfVerse(reader.verse);
    final windows = await content.windowsFor(current);
    final engine = await openCurrent(PlaybackPlan(windows, PlaybackScope(chapter.fromVerse, chapter.toVerse), reader.settings));
    await reader.setAudio(current, engine);
    notifyListeners();
  }

  /// Starts (or resumes) downloading [r]; errors land in [progressOf].
  Future<void> download(Recording r) async {
    if (isDownloading(r)) return;
    final cancel = DownloadCancel();
    _cancels[r.id] = cancel;
    notifyListeners();
    try {
      await downloads.download(r, wifiOnly: wifiOnly, cancel: cancel, onProgress: (p) {
        _progress[r.id] = p;
        notifyListeners();
      });
      _onDevice.add(r.id);
      if (r.id == current.id) await _reconnect(); // playable now
    } on DownloadException catch (e) {
      if (e.error != DownloadError.cancelled) _reader?.rating?.noteError(); // shown in «التنزيلات»
      final p = _progress[r.id];
      _progress[r.id] = DownloadProgress(
          e.error == DownloadError.cancelled ? DownloadPhase.cancelled : DownloadPhase.failed,
          p?.received ?? 0,
          r.localBytes,
          e.error);
    } finally {
      _cancels.remove(r.id);
      notifyListeners();
    }
  }

  void cancel(Recording r) => _cancels[r.id]?.cancel();

  /// A background download finished with the app not waiting for it: take it in,
  /// and play it at once if it is the chosen recording.
  Future<void> backgroundFinished() async {
    final wasCurrent = isOnDevice(current);
    await refresh();
    if (!wasCurrent && isOnDevice(current)) await _reconnect();
  }

  /// Removes [r] from the device; the reader loses its audio if it was the chosen one.
  Future<void> delete(Recording r) async {
    cancel(r);
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

/// The app's engine: just_audio (own interruption policy), listening progress
/// recorded per verse.
EngineFactory justAudioEngine(UserStore? user, {MatnRepository? matn, void Function(MatnChapter)? onChapterFinished}) =>
    (recording, filePath, plan) async {
      // Interruptions follow our own policy (AudioFocus): just_audio's would resume after a call.
      final port = JustAudioPort(AudioPlayer(handleInterruptions: false));
      await port.load(filePath);
      final engine = PlaybackEngine(port, plan, onVerseCompleted: ReaderController.listenRecorder(user, recording, matn: matn, onChapterFinished: onChapterFinished));
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
    };
