// The handoff's sample state, from the real content snapshot: the reader on
// verse 226 (page 19), a recording playing the section 226–234, and the three
// bookmarks the prototype shows (229 مراجعة, 120–123 حفظ, 683 إشكال).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/app/audio_library.dart';
import 'package:shatibiyyah/app/personal_data.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/data/settings_store.dart';
import 'package:shatibiyyah/data/user_store.dart';
import 'package:shatibiyyah/domain/playback_engine.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/services/download_manager.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// An audio port that plays nothing: enough for the reader to offer playback.
class SilentAudio implements AudioPort {
  bool _playing = false;
  @override
  Stream<int> get positionMs => const Stream.empty();
  @override
  int get currentPositionMs => 0;
  @override
  bool get playing => _playing;
  @override
  Stream<bool> get playingChanges => const Stream.empty();
  @override
  Future<void> seek(int ms) async {}
  @override
  Future<void> play() async => _playing = true;
  @override
  Future<void> pause() async => _playing = false;
  @override
  Future<void> setSpeed(double speed) async {}
}

class HandoffContent {
  late final Directory _support;
  late final AppContent content;

  Future<void> open() async {
    sqfliteFfiInit();
    _support = await Directory.systemTemp.createTemp('handoff_test');
    content = await AppContent.open(
      loadAsset: (key) async => ByteData.sublistView(await File(key).readAsBytes()),
      supportDir: _support,
      factory: databaseFactoryFfi,
    );
  }

  Future<void> close() async {
    await content.store.close();
    await _support.delete(recursive: true);
  }

  /// The reader on verse 226. With [audio], a recording is on the device and the
  /// section is the chapter (226–234). With [bookmarks], the prototype's three.
  /// With [library], the downloads are there, nothing downloaded yet.
  Future<ReaderController> reader(WidgetTester tester,
      {bool audio = false, bool bookmarks = true, bool note = false, bool library = false}) async {
    SharedPreferences.setMockInitialValues({});
    late ReaderController r;
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('handoff_user');
      addTearDown(() => dir.delete(recursive: true));
      final user = await UserStore.open(directory: dir.path, factory: databaseFactoryFfi);
      addTearDown(user.close);
      final personal = PersonalData(user);
      await personal.load();
      if (bookmarks) {
        await personal.saveBookmark(683, color: BookmarkColor.values[3], tag: BookmarkTag.ishkal);
        await personal.saveBookmark(120, to: 123, color: BookmarkColor.values[2], tag: BookmarkTag.hifz);
        await personal.saveBookmark(229, color: BookmarkColor.values[0], tag: BookmarkTag.muraja);
      }
      if (note) await personal.saveNote(230, 'قارن بالوافي');
      final prefs = await Prefs.create();
      final recording = content.recordings.defaultRecording;
      final windows = await content.windowsFor(recording);
      r = ReaderController(
        content: content,
        recording: recording,
        viewer: PageViewerController(legacyData(content, windows), prefs),
        store: SettingsStore(prefs),
        user: user,
        engine: audio
            ? PlaybackEngine(SilentAudio(), PlaybackPlan(windows, const PlaybackScope(226, 234), const PlaybackSettings()))
            : null,
        initialVerse: 226,
      )..personal = personal;
      if (bookmarks) r.viewer.setRibbons({for (final e in personal.ribbons.entries) e.key: e.value.index});
      if (library) {
        final lib = AudioLibrary(
          content: content,
          prefs: prefs,
          downloads: DownloadManager(supportDir: dir, freeBytes: () async => null, onUnmeteredNetwork: () async => true),
        );
        await lib.refresh();
        lib.attach(r);
      }
    });
    return r;
  }
}
