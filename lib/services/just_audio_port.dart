// lib/services/just_audio_port.dart — the PlaybackEngine's AudioPort, on just_audio.
//
// A recording is one local file (downloaded; nothing is bundled). The lock screen
// is lib/services/lock_screen.dart.
import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../domain/playback_engine.dart';

class JustAudioPort implements AudioPort {
  final AudioPlayer player;
  JustAudioPort(this.player);

  /// Loads [filePath] (the lock screen is published by LockScreenHandler, per verse).
  /// Opens [filePath]; the duration the decoder found, when it reports one.
  Future<Duration?> load(String filePath) => player.setFilePath(filePath);

  @override
  Stream<int> get positionMs => player.positionStream.map((d) => d.inMilliseconds);

  @override
  int get currentPositionMs => player.position.inMilliseconds;

  @override
  bool get playing => player.playing;

  @override
  Stream<bool> get playingChanges => player.playingStream;

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

  /// For ducking under a short interruption (1 = full volume).
  Future<void> setVolume(double volume) => player.setVolume(volume);

  Future<void> dispose() => player.dispose();
}
