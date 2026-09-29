// lib/services/audio_focus.dart — what an interruption does to recitation
// (features-v3 audio-interruptions).
//
// - A call, an alarm, another app taking the audio: pause, and stay paused when it
//   ends. A student who was reciting along should pick up deliberately.
// - A short sound that only asks to duck (a notification, navigation): lower the
//   volume, restore it after.
// - Headphones unplugged: pause.
// The session is configured as spoken audio, so on Android the app is told about
// ducks instead of being ducked silently. just_audio's own handling is off (it
// resumes after a call); the engine then learns about the pause through its port.
import 'dart:async';

import 'package:audio_session/audio_session.dart';

/// Volume while another app's short sound plays over the recitation.
const double kDuckVolume = 0.3;

class AudioFocus {
  final bool Function() isPlaying;
  final Future<void> Function() pause;
  final Future<void> Function(double volume) setVolume;
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _ducked = false;

  AudioFocus({
    required Stream<AudioInterruptionEvent> interruptions,
    required Stream<void> becomingNoisy,
    required this.isPlaying,
    required this.pause,
    required this.setVolume,
  }) {
    _subs
      ..add(interruptions.listen(_onInterruption))
      ..add(becomingNoisy.listen((_) {
        if (isPlaying()) pause();
      }));
  }

  /// Configures the app's audio session and follows its events.
  static Future<AudioFocus> attach({
    required bool Function() isPlaying,
    required Future<void> Function() pause,
    required Future<void> Function(double volume) setVolume,
  }) async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    return AudioFocus(
      interruptions: session.interruptionEventStream,
      becomingNoisy: session.becomingNoisyEventStream,
      isPlaying: isPlaying,
      pause: pause,
      setVolume: setVolume,
    );
  }

  void _onInterruption(AudioInterruptionEvent e) {
    if (e.type == AudioInterruptionType.duck) {
      if (e.begin && !_ducked) {
        _ducked = true;
        setVolume(kDuckVolume);
      } else if (!e.begin && _ducked) {
        _ducked = false;
        setVolume(1);
      }
      return;
    }
    // pause / unknown: pause at the start; never resume at the end.
    if (e.begin && isPlaying()) pause();
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
  }
}
