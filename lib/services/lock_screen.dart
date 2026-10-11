// lib/services/lock_screen.dart — the lock screen, notification and headset buttons
// (features-v3 background-audio), through audio_service.
//
// Shows the playing verse: «البيت N» with its chapter and the reciter, updated as
// playback moves on. The buttons act on the reader, not on the player: play/pause,
// and previous/next move one verse — the same as the in-app transport. The handler
// only publishes when what it shows changes, not on every position tick.
//
// The bar is the verse being recited (F-43), not the whole file: the session
// publishes that window's length and where the player stands in it, with the
// speed, and the system moves the bar from there by itself. A new verse, a verse
// played again, a pause, a gap and a change of speed each publish again.
//
// The recitation belongs to the app the student sees: swiping the app away from
// the recent apps ends it, and its notification with it (Android keeps a media
// service running after its task is gone unless it is told to stop).
import 'package:audio_service/audio_service.dart';

import '../ui/reader/reader_controller.dart';
import '../utils/arabic.dart';

class LockScreenHandler extends BaseAudioHandler {
  ReaderController? _reader;
  String? _shown; // what was last published, to skip identical updates

  /// Play was asked for before a reader was attached: the session can be started
  /// with no screen (a headset button, the «تابع» widget), and its first play can
  /// arrive while the reader is still being built.
  bool _playWhenAttached = false;

  /// The app was swiped away: the session stays idle until a recitation plays again.
  bool _ended = false;

  /// Starts following [reader] (at boot).
  void attach(ReaderController reader) {
    _reader?.removeListener(_publish);
    _reader = reader;
    reader.addListener(_publish);
    _publish();
    if (_playWhenAttached) {
      _playWhenAttached = false;
      play();
    }
  }

  void _publish() {
    final r = _reader;
    if (r == null) return;
    if (r.playing) _ended = false;
    if (_ended) return;
    final key = '${r.audioAvailable}|${r.recording.id}|${r.verse}|${r.playing}|${r.inTitle}|${r.inGap}|'
        '${r.speed}|${r.verseRepetition}|${r.sectionRepetition}';
    if (key == _shown) return;
    _shown = key;
    if (!r.audioAvailable) {
      playbackState.add(PlaybackState(processingState: AudioProcessingState.idle, playing: false));
      return;
    }
    final chapter = r.chapter;
    // What is being recited: the verse, from its cue to its end; or the chapter's
    // spoken title before it.
    final engine = r.engine!, windows = engine.windows;
    final (from, to) = r.inTitle
        ? (windows.chapterStart(r.verse), windows.cue(r.verse))
        : (windows.cue(r.verse), windows.verseEnd(r.verse));
    final length = to - from;
    // A jump starts a little before the cue (the pre-roll): the bar starts at zero.
    final at = (engine.audio.currentPositionMs - from).clamp(0, length);
    mediaItem.add(MediaItem(
      id: '${r.recording.id}#${r.verse}',
      title: r.inTitle ? chapter.shortLabel : 'البيت ${ar(r.verse)}',
      album: chapter.shortLabel,
      // Android's media card shows the title and this line only: the chapter goes here.
      artist: '${chapter.shortLabel} · ${r.recording.reciterName}',
      duration: Duration(milliseconds: length),
    ));
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (r.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.playPause, MediaAction.skipToNext, MediaAction.skipToPrevious},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: r.playing,
      updatePosition: Duration(milliseconds: at),
      // In the gap between two plays the player is stopped: the bar stands still.
      speed: r.inGap ? 0 : r.speed,
    ));
  }

  @override
  Future<void> play() async {
    final r = _reader;
    if (r == null) {
      _playWhenAttached = true;
    } else if (!r.playing) {
      await r.playPause();
    }
  }

  @override
  Future<void> pause() async {
    final r = _reader;
    if (r == null) {
      _playWhenAttached = false;
    } else if (r.playing) {
      await r.playPause();
    }
  }

  @override
  Future<void> stop() => pause();

  /// The app was swiped away from the recent apps (Android): the recitation stops
  /// and the session goes idle, which takes the notification down and lets the
  /// service end. The next change the reader makes publishes afresh.
  @override
  Future<void> onTaskRemoved() async {
    _playWhenAttached = false;
    await pause();
    _ended = true;
    _shown = null;
    playbackState.add(PlaybackState(processingState: AudioProcessingState.idle, playing: false));
  }

  @override
  Future<void> skipToNext() async => _reader?.next();

  @override
  Future<void> skipToPrevious() async => _reader?.previous();
}
