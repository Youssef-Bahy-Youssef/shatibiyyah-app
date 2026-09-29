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
  @override
  Stream<int> get positionMs => const Stream.empty();
  @override
  Stream<bool> get playingChanges => const Stream.empty();
  @override
  int get currentPositionMs => 0;
  @override
  bool get playing => _playing;
  @override
  Future<void> seek(int ms) async {}
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
}
