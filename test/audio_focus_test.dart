// Interruptions (ADR 0035): a call pauses and its end plays on; sound taken for good
// stays paused; a duck lowers the volume and restores it; unplugged headphones pause.
import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/services/audio_focus.dart';

void main() {
  late StreamController<AudioInterruptionEvent> interruptions;
  late StreamController<void> noisy;
  late List<String> log;
  late AudioFocus focus;

  setUp(() {
    interruptions = StreamController(sync: true);
    noisy = StreamController(sync: true);
    log = [];
    focus = AudioFocus(
      interruptions: interruptions.stream,
      becomingNoisy: noisy.stream,
      interrupt: () async => log.add('interrupt'),
      endInterruption: ({required bool playOn}) async => log.add(playOn ? 'play on' : 'stay paused'),
      pause: () async => log.add('pause'),
      setVolume: (v) async => log.add('volume $v'),
    );
  });

  tearDown(() => focus.dispose());

  AudioInterruptionEvent begin(AudioInterruptionType type) => AudioInterruptionEvent(true, type);
  AudioInterruptionEvent end(AudioInterruptionType type) => AudioInterruptionEvent(false, type);

  test('a call interrupts, and its end plays on (Android: the sound is given back)', () {
    interruptions.add(begin(AudioInterruptionType.pause));
    expect(log, ['interrupt']);
    interruptions.add(end(AudioInterruptionType.pause));
    expect(log, ['interrupt', 'play on']);
  });

  test('iOS: every interruption begins as unknown; «should resume» at its end plays on', () {
    interruptions.add(begin(AudioInterruptionType.unknown));
    interruptions.add(end(AudioInterruptionType.pause));
    expect(log, ['interrupt', 'play on']);
  });

  test('sound taken for good stays paused: no end (Android), or an end that does not say resume (iOS)', () {
    interruptions.add(begin(AudioInterruptionType.unknown));
    expect(log, ['interrupt']);
    interruptions.add(end(AudioInterruptionType.unknown));
    expect(log, ['interrupt', 'stay paused']);
  });

  test('a duck lowers the volume and its end restores it, without interrupting', () {
    interruptions.add(begin(AudioInterruptionType.duck));
    interruptions.add(end(AudioInterruptionType.duck));
    expect(log, ['volume $kDuckVolume', 'volume 1.0']);
  });

  test('a duck that grows into a call: the volume is whole again when the recitation comes back', () {
    interruptions.add(begin(AudioInterruptionType.duck));
    interruptions.add(begin(AudioInterruptionType.pause));
    interruptions.add(end(AudioInterruptionType.pause));
    expect(log, ['volume $kDuckVolume', 'volume 1.0', 'interrupt', 'play on']);
  });

  test('unplugged headphones pause, as the student\'s own pause: during a call too', () {
    noisy.add(null);
    expect(log, ['pause']);
  });

  test('the session is spoken audio that is not paused by a sound asking only to duck', () {
    // With «will pause when ducked» audio_session reports a notification sound as a pause.
    expect(kRecitationSession.androidWillPauseWhenDucked, isFalse);
    expect(kRecitationSession.androidAudioAttributes?.contentType, AndroidAudioContentType.speech);
    expect(kRecitationSession.avAudioSessionMode, AVAudioSessionMode.spokenAudio);
  });

  group('the session and the opening verse (ADR 0027)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('com.ryanheise.audio_session');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<String> configured; // each time the session is given the recitation's settings

    setUp(() {
      configured = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setConfiguration') configured.add('speech');
        return null;
      });
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      AudioFocus.sessionHold = null;
    });

    Future<AudioFocus> attach() => AudioFocus.attach(
        interrupt: () async {},
        endInterruption: ({required bool playOn}) async {},
        pause: () async {},
        setVolume: (_) async {});

    test('with nothing holding it, the session is the recitation\'s before attach returns', () async {
      final attached = await attach();
      expect(configured, ['speech']);
      await attached.dispose();
    });

    test('while the opening verse holds it, the session becomes the recitation\'s only when the verse has ended', () async {
      final verse = Completer<void>();
      AudioFocus.sessionHold = verse.future;
      final attached = await attach(); // boot does not wait for the verse
      await pumpEventQueue();
      expect(configured, isEmpty);

      verse.complete();
      await pumpEventQueue();
      expect(configured, ['speech']);
      await attached.dispose();
    });
  });
}
