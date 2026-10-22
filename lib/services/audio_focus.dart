// lib/services/audio_focus.dart — what an interruption does to recitation
// (features-v3 audio-interruptions).
//
// (ADR 0035).
//
// - A call, an alarm, a voice message: pause. When it ends the verse it cut is
//   recited again from its start, unless the student gave a command meanwhile.
// - Another app taking the sound for good (music, a video): pause, and stay paused.
// - A short sound that only asks to duck (a notification, navigation): lower the
//   volume, restore it after.
// - Headphones unplugged: pause and stay paused, during an interruption too.
// The session is spoken audio, but not one that pauses when ducked: with that
// setting audio_session reports every notification sound as a pause. just_audio's
// own handling is off (it resumes in the middle of the verse, and after the
// student's own pause during a call); the engine decides.
import 'dart:async';

import 'package:audio_session/audio_session.dart';

/// Volume while another app's short sound plays over the recitation.
const double kDuckVolume = 0.3;

/// The recitation's session: spoken audio that plays on, lowered, under a short sound.
final AudioSessionConfiguration kRecitationSession =
    const AudioSessionConfiguration.speech().copyWith(androidWillPauseWhenDucked: false);

class AudioFocus {
  /// PlaybackEngine.interrupt: a pause the student did not ask for.
  final Future<void> Function() interrupt;

  /// PlaybackEngine.endInterruption.
  final Future<void> Function({required bool playOn}) endInterruption;

  /// The student's own pause: nothing resumes after it.
  final Future<void> Function() pause;
  final Future<void> Function(double volume) setVolume;
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _ducked = false;

  AudioFocus({
    required Stream<AudioInterruptionEvent> interruptions,
    required Stream<void> becomingNoisy,
    required this.interrupt,
    required this.endInterruption,
    required this.pause,
    required this.setVolume,
  }) {
    _subs
      ..add(interruptions.listen(_onInterruption))
      // Also while a call holds the recitation: it must not come back on the speaker.
      ..add(becomingNoisy.listen((_) => pause()));
  }

  /// Configures the app's audio session and follows its events.
  static Future<AudioFocus> attach({
    required Future<void> Function() interrupt,
    required Future<void> Function({required bool playOn}) endInterruption,
    required Future<void> Function() pause,
    required Future<void> Function(double volume) setVolume,
  }) async {
    final session = await AudioSession.instance;
    await session.configure(kRecitationSession);
    return AudioFocus(
      interruptions: session.interruptionEventStream,
      becomingNoisy: session.becomingNoisyEventStream,
      interrupt: interrupt,
      endInterruption: endInterruption,
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
    // A short sound that grew into a full interruption sends no end of its own.
    if (_ducked) {
      _ducked = false;
      setVolume(1);
    }
    if (e.begin) {
      interrupt();
    } else {
      // The system says whether to play on: Android gives the sound back only
      // after a loss that was to end; iOS sets «should resume» (both arrive as
      // `pause`). Sound taken for good never comes back, or ends as `unknown`.
      endInterruption(playOn: e.type == AudioInterruptionType.pause);
    }
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
  }
}
