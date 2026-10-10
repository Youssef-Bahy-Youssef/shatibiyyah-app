// The lock screen shows the playing verse with its chapter and reciter; its buttons
// act on the reader: play/pause, and previous/next move one verse.
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/domain/playback_engine.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/services/lock_screen.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _SilentAudio implements AudioPort {
  bool _playing = false;

  /// Where the player stands (a test sets it; a seek moves it).
  int at = 0;
  @override
  Stream<int> get positionMs => const Stream.empty();
  @override
  Stream<bool> get playingChanges => const Stream.empty();
  @override
  int get currentPositionMs => at;
  @override
  bool get playing => _playing;
  @override
  Future<void> seek(int ms) async => at = ms;
  @override
  Future<void> play() async => _playing = true;
  @override
  Future<void> pause() async => _playing = false;
  @override
  Future<void> setSpeed(double speed) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('lock_screen_test');
    content = await AppContent.open(
      loadAsset: (key) async => ByteData.sublistView(await File(key).readAsBytes()),
      supportDir: support,
      factory: databaseFactoryFfi,
    );
  });

  tearDownAll(() async {
    await content.store.close();
    await support.delete(recursive: true);
  });

  Future<ReaderController> reader({bool audio = true}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.create();
    final recording = content.recordings.defaultRecording;
    final windows = await content.windowsFor(recording);
    return ReaderController(
      content: content,
      recording: recording,
      viewer: PageViewerController(legacyData(content, windows), prefs),
      engine: audio
          ? PlaybackEngine(_SilentAudio(), PlaybackPlan(windows, const PlaybackScope(226, 234), const PlaybackSettings()))
          : null,
      initialVerse: 226,
    );
  }

  test('shows «البيت N» with the chapter and reciter; the buttons drive the reader', () async {
    final r = await reader();
    final handler = LockScreenHandler()..attach(r);
    final chapter = content.matn.chapterOfVerse(226).shortLabel;
    expect(handler.mediaItem.value!.title, 'البيت ٢٢٦');
    expect(handler.mediaItem.value!.album, chapter);
    expect(handler.mediaItem.value!.artist, '$chapter · ${r.recording.reciterName}');
    expect(handler.playbackState.value.playing, isFalse);

    await handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(r.playing, isTrue);
    expect(handler.playbackState.value.playing, isTrue);
    expect(handler.playbackState.value.controls.map((c) => c.action),
        [MediaAction.skipToPrevious, MediaAction.pause, MediaAction.skipToNext]);

    await handler.skipToNext(); // one verse
    await Future<void>.delayed(Duration.zero);
    expect(r.verse, 227);
    expect(handler.mediaItem.value!.title, 'البيت ٢٢٧');

    await handler.skipToPrevious();
    await Future<void>.delayed(Duration.zero);
    expect(r.verse, 226);

    await handler.pause();
    await Future<void>.delayed(Duration.zero);
    expect(r.playing, isFalse);
    expect(handler.playbackState.value.playing, isFalse);
  });

  test('without a recording on the device the session is idle', () async {
    final handler = LockScreenHandler()..attach(await reader(audio: false));
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
  });

  // Plan 4.5 (F-43): the lock screen's bar is the verse being recited, not the
  // 2.5-hour file. The session publishes that window's length and the position in it.
  group('the position and duration are the verse\'s window', () {
    test('the duration is the window\'s length; the position is counted from the verse\'s cue', () async {
      final r = await reader();
      final windows = r.engine!.windows;
      final audio = r.engine!.audio as _SilentAudio;
      final handler = LockScreenHandler()..attach(r);
      expect(handler.mediaItem.value!.duration, Duration(milliseconds: windows.verseEnd(226) - windows.cue(226)));

      await handler.play();
      await Future<void>.delayed(Duration.zero);
      expect(audio.at, windows.cue(226)); // a chapter's first verse starts at its cue, after the title
      expect(handler.playbackState.value.updatePosition, Duration.zero);
      expect(handler.playbackState.value.speed, 1.0);

      // Paused 1.5 s into the verse: the bar stands there.
      audio.at = windows.cue(226) + 1500;
      await handler.pause();
      await Future<void>.delayed(Duration.zero);
      expect(handler.playbackState.value.updatePosition, const Duration(milliseconds: 1500));
      expect(handler.playbackState.value.playing, isFalse);

      // The next verse: its own window.
      await handler.play();
      await Future<void>.delayed(Duration.zero);
      await handler.skipToNext();
      await Future<void>.delayed(Duration.zero);
      expect(handler.mediaItem.value!.duration, Duration(milliseconds: windows.verseEnd(227) - windows.cue(227)));
      // A jump starts 50 ms before the cue: the bar starts at zero, not below it.
      expect(audio.at, windows.cue(227) - 50);
      expect(handler.playbackState.value.updatePosition, Duration.zero);
      await handler.pause();
    });

    test('the speed is published, so the system moves the bar at the same pace', () async {
      final r = await reader();
      final handler = LockScreenHandler()..attach(r);
      await handler.play();
      await Future<void>.delayed(Duration.zero);
      r.setSpeed(1.5);
      await Future<void>.delayed(Duration.zero);
      expect(handler.playbackState.value.speed, 1.5);
      await handler.pause();
    });

    test('a verse played again starts its bar again', () async {
      final r = await reader();
      r.setVerseRepeats(2);
      final windows = r.engine!.windows;
      final audio = r.engine!.audio as _SilentAudio;
      final handler = LockScreenHandler()..attach(r);
      await handler.play();
      await Future<void>.delayed(Duration.zero);
      audio.at = windows.verseEnd(226) - 10; // near the end of the first play
      r.engine!.plan.advance(); // the plan moves to the second play …
      await r.engine!.jumpTo(226); // … and the engine seeks back to the verse's start
      await Future<void>.delayed(Duration.zero);
      expect(handler.playbackState.value.updatePosition, Duration.zero);
      await handler.pause();
    });
  });
}
