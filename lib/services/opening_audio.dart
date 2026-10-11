// lib/services/opening_audio.dart — the opening verse's OpeningAudio, on just_audio
// (ADR 0027; lib/app/opening_recitation.dart).
//
// The verse has a player of its own, apart from the recitation's. It asks for no
// audio focus and takes no part in the app's audio session: it only sounds when
// nothing else does, and the recitation's player takes the session when it starts.
//
// Android has no silent switch for media, so the ringer is asked: silent, vibrate
// and Do Not Disturb all keep the verse quiet. On iOS the session is put in the
// ambient category, which the silent switch mutes; the recitation's own settings
// are applied when the verse has ended (AudioFocus.sessionHold).
import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../app/opening_recitation.dart';

class JustAudioOpening implements OpeningAudio {
  AudioPlayer? _player;
  Completer<void>? _ended;
  bool _stopped = false;

  /// The verse is 8.45 s: a player that has not finished by then never will.
  static const Duration _limit = Duration(seconds: 20);

  @override
  Future<bool> get mayPlay async {
    if (Platform.isAndroid) {
      final device = AndroidAudioManager();
      return await device.getRingerMode() == AndroidRingerMode.normal &&
          await device.getMode() == AndroidAudioHardwareMode.normal &&
          !await device.isMusicActive();
    }
    if (Platform.isIOS) return !await AVAudioSession().isOtherAudioPlaying;
    return true;
  }

  @override
  Future<void> play() async {
    if (_stopped) return;
    final ended = _ended = Completer<void>();
    if (Platform.isIOS) await AVAudioSession().setCategory(AVAudioSessionCategory.ambient);
    if (_stopped) return;
    final player = _player = AudioPlayer(
      handleInterruptions: false,
      handleAudioSessionActivation: false,
      androidApplyAudioAttributes: false,
    );
    final states = player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && !ended.isCompleted) ended.complete();
    });
    try {
      await player.setAsset(kOpeningAsset);
      if (_stopped) return;
      // play() itself completes only when playback stops: the end is awaited instead.
      unawaited(player.play().catchError((Object _) {
        if (!ended.isCompleted) ended.complete();
      }));
      await ended.future.timeout(_limit, onTimeout: () {});
    } finally {
      await states.cancel();
    }
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    if (_ended case final ended? when !ended.isCompleted) ended.complete();
    final player = _player;
    _player = null;
    await player?.dispose();
  }
}
