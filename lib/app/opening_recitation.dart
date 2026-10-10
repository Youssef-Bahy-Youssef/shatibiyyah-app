// lib/app/opening_recitation.dart — «بيت الافتتاح» (ADR 0027): one verse recited
// when the app is opened.
//
// Verse 1124, «ومن شغل القرآن عنه لسانه ينل خير أجر الذاكرين مكمّلا», in عبدالحميد
// القريو's voice (8.45 s). It is the one piece of audio the app carries, so it
// sounds on the first launch and with no network. It starts under the launch
// splash, once per launch, and goes on over the reader.
//
// It is not the reader's playback: no highlight, no lock screen, and the current
// verse stays where it was.
//
// It stays silent when «بيت الافتتاح» is off, when the app was started with
// nothing on screen (a headset button can do that), and when the device should
// stay quiet ([OpeningAudio.mayPlay]). A recitation starting, the switch going
// off, or the app leaving the screen ends it. It is a courtesy: no failure in it
// may keep the app from opening.
import 'dart:async';
import 'dart:ui' show AppLifecycleState;

/// The bundled verse.
const String kOpeningAsset = 'assets/opening/verse-1124.mp3';

/// How long the verse waits for the app to come on screen before giving up.
const Duration kOpeningPatience = Duration(seconds: 5);

/// What the opening verse needs from the device (lib/services/opening_audio.dart).
abstract class OpeningAudio {
  /// Whether a sound nobody asked for is welcome now: the phone is not silenced
  /// or in a call, and nothing else is playing.
  Future<bool> get mayPlay;

  /// Plays the verse; completes when it has ended or was stopped.
  Future<void> play();

  /// Ends it and lets the player go. Safe before [play] and more than once.
  Future<void> stop();
}

class OpeningRecitation {
  final OpeningAudio audio;
  final Completer<bool> _onScreen = Completer<bool>();
  final Completer<void> _done = Completer<void>();
  Timer? _patience;
  bool _stopped = false;

  OpeningRecitation(this.audio);

  /// Completes when the verse has ended, was stopped, or was not to be played.
  Future<void> get done => _done.future;

  /// The app's lifecycle as the platform reports it, from launch on: coming on
  /// screen lets the verse start, leaving the screen ends it. A system dialog
  /// over the app (`inactive`) does neither.
  void lifecycle(AppLifecycleState? state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_onScreen.isCompleted) _onScreen.complete(true);
      case AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached:
        // Before it was ever on screen this is only where the platform starts from.
        if (_onScreen.isCompleted) unawaited(stop());
      case AppLifecycleState.inactive || null:
        break;
    }
  }

  /// Recites the verse once if [enabled] and the app comes on screen in time.
  /// Never throws.
  Future<void> start({required Future<bool> enabled}) async {
    if (_stopped) return;
    _patience = Timer(kOpeningPatience, () {
      if (!_onScreen.isCompleted) _onScreen.complete(false);
    });
    try {
      if (!await enabled || !await _onScreen.future || _stopped) return;
      if (!await audio.mayPlay || _stopped) return;
      await audio.play();
    } catch (_) {
      // Silence is the fallback.
    } finally {
      await stop();
    }
  }

  /// Ends it for this launch.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _patience?.cancel();
    if (!_onScreen.isCompleted) _onScreen.complete(false);
    try {
      await audio.stop();
    } catch (_) {}
    _done.complete();
  }
}
