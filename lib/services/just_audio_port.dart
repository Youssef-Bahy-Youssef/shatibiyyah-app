// lib/services/just_audio_port.dart — the PlaybackEngine's AudioPort, on just_audio.
//
// A recording is one local file (downloaded; nothing is bundled). The lock-screen
// metadata is set on load and updated per verse by the reader.
import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../domain/playback_engine.dart';

class JustAudioPort implements AudioPort {
  final AudioPlayer player;
  JustAudioPort(this.player);

  /// Loads [filePath]; the MediaItem is what the lock screen and notification show.
  Future<void> load(String filePath, MediaItem item) => player.setAudioSource(AudioSource.file(filePath, tag: item));

  @override
  Stream<int> get positionMs => player.positionStream.map((d) => d.inMilliseconds);

  @override
  int get currentPositionMs => player.position.inMilliseconds;

  @override
  bool get playing => player.playing;

  @override
  Future<void> seek(int ms) => player.seek(Duration(milliseconds: ms));

  /// just_audio's play() future completes only when playback stops, so it is not
  /// awaited: the engine must keep running while the audio plays.
  @override
  Future<void> play() async {
    unawaited(player.play());
  }

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> setSpeed(double speed) => player.setSpeed(speed);

  Future<void> dispose() => player.dispose();
}
