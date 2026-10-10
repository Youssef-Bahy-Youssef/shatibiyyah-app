// Interruptions (features-v3 audio-interruptions): a call pauses and does not resume;
// a duck lowers the volume and restores it; unplugged headphones pause.
import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/services/audio_focus.dart';

void main() {
  late StreamController<AudioInterruptionEvent> interruptions;
  late StreamController<void> noisy;
  late bool playing;
  late List<String> log;
  late AudioFocus focus;

  setUp(() {
    interruptions = StreamController(sync: true);
    noisy = StreamController(sync: true);
    playing = true;
    log = [];
    focus = AudioFocus(
      interruptions: interruptions.stream,
      becomingNoisy: noisy.stream,
      isPlaying: () => playing,
      pause: () async {
        playing = false;
        log.add('pause');
      },
      setVolume: (v) async => log.add('volume $v'),
    );
  });

  tearDown(() => focus.dispose());

  test('a call pauses, and its end does not resume', () {
    interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
    interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.pause));
    expect(log, ['pause']);
    expect(playing, isFalse);
  });

  test('an unknown interruption pauses too; nothing happens when already paused', () {
    playing = false;
    interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.unknown));
    expect(log, isEmpty);
    playing = true;
    interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.unknown));
    expect(log, ['pause']);
  });

  test('a duck lowers the volume and its end restores it, without pausing', () {
    interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.duck));
    interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.duck));
    expect(log, ['volume $kDuckVolume', 'volume 1.0']);
    expect(playing, isTrue);
  });

  test('unplugged headphones pause', () {
    noisy.add(null);
    expect(log, ['pause']);
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

    Future<AudioFocus> attach() =>
        AudioFocus.attach(isPlaying: () => false, pause: () async {}, setVolume: (_) async {});

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
