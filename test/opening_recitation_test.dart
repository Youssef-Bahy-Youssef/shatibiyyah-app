// «بيت الافتتاح» (ADR 0027): verse 1124 is recited once when the app is opened on
// screen, unless the switch is off or the device should stay quiet; a recitation
// or leaving the app ends it, and nothing it does can stop the app from opening.
import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppLifecycleState;

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/app/opening_recitation.dart';

class _FakeAudio implements OpeningAudio {
  bool quiet = false; // the device should stay quiet
  bool broken = false;
  final List<String> log = [];
  Completer<void>? _ended;

  @override
  Future<bool> get mayPlay async {
    log.add('ask');
    return !quiet;
  }

  @override
  Future<void> play() {
    log.add('play');
    if (broken) throw StateError('no decoder');
    return (_ended = Completer<void>()).future;
  }

  @override
  Future<void> stop() async {
    log.add('stop');
    end();
  }

  /// The verse reaches its end.
  void end() {
    if (_ended case final ended? when !ended.isCompleted) ended.complete();
  }
}

void main() {
  late _FakeAudio audio;
  late OpeningRecitation opening;
  var done = false;

  /// Runs [body] on a fresh launch, with time and microtasks in the test's hands.
  void launch(void Function(FakeAsync async) body) => fakeAsync((async) {
        audio = _FakeAudio();
        opening = OpeningRecitation(audio);
        done = false;
        opening.done.then((_) => done = true);
        body(async);
      });

  void start(FakeAsync async, {bool enabled = true, AppLifecycleState? state = AppLifecycleState.resumed}) {
    opening.lifecycle(state);
    unawaited(opening.start(enabled: Future.value(enabled)));
    async.flushMicrotasks();
  }

  test('opened on screen with the switch on: the verse is recited once, to its end', () {
    launch((async) {
      start(async);
      expect(audio.log, ['ask', 'play']);
      expect(done, isFalse);

      audio.end();
      async.flushMicrotasks();
      expect(audio.log, ['ask', 'play', 'stop']); // the player is let go
      expect(done, isTrue);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('the switch off: nothing is asked of the device and nothing sounds', () {
    launch((async) {
      start(async, enabled: false);
      expect(audio.log, ['stop']);
      expect(done, isTrue);
    });
  });

  test('a device that should stay quiet (silenced, in a call, already playing): nothing sounds', () {
    launch((async) {
      audio.quiet = true;
      start(async);
      expect(audio.log, ['ask', 'stop']);
      expect(done, isTrue);
    });
  });

  test('it waits for the app to be on screen, through a system dialog over it', () {
    launch((async) {
      start(async, state: null); // the platform has not said yet
      opening.lifecycle(AppLifecycleState.inactive);
      async.elapse(const Duration(seconds: 1));
      expect(audio.log, isEmpty);

      opening.lifecycle(AppLifecycleState.resumed);
      async.flushMicrotasks();
      expect(audio.log, ['ask', 'play']);
    });
  });

  test('started with nothing on screen (a headset button): it gives up, and stays quiet when the app is opened later', () {
    launch((async) {
      start(async, state: AppLifecycleState.paused);
      async.elapse(kOpeningPatience);
      expect(audio.log, ['stop']);
      expect(done, isTrue);

      opening.lifecycle(AppLifecycleState.resumed);
      async.flushMicrotasks();
      expect(audio.log, ['stop']);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('a recitation starting ends it at once, and only once', () {
    launch((async) {
      start(async);
      unawaited(opening.stop());
      unawaited(opening.stop());
      async.flushMicrotasks();
      expect(audio.log, ['ask', 'play', 'stop']);
      expect(done, isTrue);
    });
  });

  test('leaving the app ends it; a system dialog over the app does not', () {
    launch((async) {
      start(async);
      opening.lifecycle(AppLifecycleState.inactive);
      async.flushMicrotasks();
      expect(audio.log, ['ask', 'play']);

      opening.lifecycle(AppLifecycleState.hidden);
      async.flushMicrotasks();
      expect(audio.log, ['ask', 'play', 'stop']);
      expect(done, isTrue);
    });
  });

  test('stopped before the device has answered: it never starts', () {
    launch((async) {
      opening.lifecycle(AppLifecycleState.resumed);
      unawaited(opening.start(enabled: Future.value(true)));
      unawaited(opening.stop()); // before a single microtask has run
      async.flushMicrotasks();
      expect(audio.log, ['stop']);
      expect(done, isTrue);
    });
  });

  test('a player that fails is not an error: the app opens the same', () {
    launch((async) {
      audio.broken = true;
      start(async);
      expect(audio.log, ['ask', 'play', 'stop']);
      expect(done, isTrue);
    });
  });

  test('a switch that cannot be read is taken as off', () {
    launch((async) {
      opening.lifecycle(AppLifecycleState.resumed);
      unawaited(opening.start(enabled: Future.error(StateError('no preferences'))));
      async.flushMicrotasks();
      expect(audio.log, ['stop']);
      expect(done, isTrue);
    });
  });

  test('the bundled verse is the owner\'s clip, byte for byte, and the app declares it', () {
    final clip = File(kOpeningAsset);
    expect(clip.lengthSync(), 211752);
    expect(sha256.convert(clip.readAsBytesSync()).toString(),
        '16b08907bf8e6e6d179071e46004f79bd48d134275779d5e36bd181ae5acb146');
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/opening/'));
    // The only audio the app carries.
    final audioFiles = [
      for (final f in Directory('assets').listSync(recursive: true))
        if (RegExp(r'\.(mp3|m4a|aac|ogg|opus|wav|flac)$').hasMatch(f.path)) f.path,
    ];
    expect(audioFiles, [kOpeningAsset]);
  });
}
