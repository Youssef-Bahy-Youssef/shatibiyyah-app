// lib/services/lock_screen.dart — the lock screen, notification and headset buttons
// (features-v3 background-audio), through audio_service.
//
// Shows the playing verse: «البيت N» with its chapter and the reciter, updated as
// playback moves on. The buttons act on the reader, not on the player: play/pause,
// and previous/next move one verse — the same as the in-app transport. The handler
// only publishes when what it shows changes, not on every position tick.
import 'package:audio_service/audio_service.dart';

import '../ui/reader/reader_controller.dart';
import '../utils/arabic.dart';

class LockScreenHandler extends BaseAudioHandler {
  ReaderController? _reader;
  String? _shown; // what was last published, to skip identical updates

  /// Starts following [reader] (at boot).
  void attach(ReaderController reader) {
    _reader?.removeListener(_publish);
    _reader = reader;
    reader.addListener(_publish);
    _publish();
  }

  void _publish() {
    final r = _reader;
    if (r == null) return;
    final key = '${r.audioAvailable}|${r.recording.id}|${r.verse}|${r.playing}|${r.inTitle}';
    if (key == _shown) return;
    _shown = key;
    if (!r.audioAvailable) {
      playbackState.add(PlaybackState(processingState: AudioProcessingState.idle, playing: false));
      return;
    }
    final chapter = r.chapter;
    mediaItem.add(MediaItem(
      id: '${r.recording.id}#${r.verse}',
      title: r.inTitle ? chapter.shortLabel : 'البيت ${ar(r.verse)}',
      album: chapter.shortLabel,
      // Android's media card shows the title and this line only: the chapter goes here.
      artist: '${chapter.shortLabel} · ${r.recording.reciterName}',
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
    ));
  }

  @override
  Future<void> play() async {
    final r = _reader;
    if (r != null && !r.playing) await r.playPause();
  }

  @override
  Future<void> pause() async {
    final r = _reader;
    if (r != null && r.playing) await r.playPause();
  }

  @override
  Future<void> stop() => pause();

  @override
  Future<void> skipToNext() async => _reader?.next();

  @override
  Future<void> skipToPrevious() async => _reader?.previous();
}
