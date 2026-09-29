// Interruptions (features-v3 audio-interruptions): a call pauses and does not resume;
// a duck lowers the volume and restores it; unplugged headphones pause.
import 'dart:async';

import 'package:audio_session/audio_session.dart';
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
}
