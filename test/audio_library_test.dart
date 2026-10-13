// The recordings library: choosing a reciter keeps the verse and swaps the audio;
// one not on the device leaves the reader without audio; deleting the chosen one
// takes its audio away; offline, a download fails cleanly (no test reaches the network).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/app/audio_library.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/data/recording_repository.dart';
import 'package:shatibiyyah/data/settings_store.dart';
import 'package:shatibiyyah/domain/playback_engine.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/services/download_manager.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/shell/downloads_screen.dart';
import 'package:shatibiyyah/ui/shell/tour_screen.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:shatibiyyah/utils/arabic.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

/// No network in unit tests: every mirror fails at once.
class _OfflineTransfer extends Transfer {
  int attempts = 0;
  @override
  Future<void> fetch(Uri url, File part, int total, void Function(int) progress, DownloadCancel? cancel,
      {required bool wifiOnly}) async {
    attempts++;
    throw SocketException('offline (test): $url');
  }
}

class _SilentAudio implements AudioPort {
  bool _playing = false;
  final seeks = <int>[];
  @override
  Stream<int> get positionMs => const Stream.empty();
  @override
  Stream<bool> get playingChanges => const Stream.empty();
  @override
  int get currentPositionMs => 0;
  @override
  bool get playing => _playing;
  @override
  Future<void> seek(int ms) async => seeks.add(ms);
  @override
  Future<void> play() async => _playing = true;
  @override
  Future<void> pause() async => _playing = false;
  @override
  Future<void> setSpeed(double speed) async {}
}

/// The downloads with every recording but the chosen one fixed in one state, to
/// look at how «التنزيلات» words it.
class _FixedLibrary extends AudioLibrary {
  DownloadProgress? progress;
  bool downloading = false;
  int? free;
  int mobileData = 0, downloads_ = 0;
  _FixedLibrary({required super.content, required super.prefs, required super.downloads});

  @override
  DownloadProgress? progressOf(Recording r) => r.isDefault ? null : progress;
  @override
  bool isDownloading(Recording r) => !r.isDefault && downloading;
  @override
  int? get freeBytes => free;
  @override
  void useMobileData(Recording r) => mobileData++;
  @override
  Future<void> download(Recording r) async => downloads_++;
}

void main() {
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('audio_library_test');
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

  /// Waits for [done]: a switch reads the other recording's cues from the database.
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue);
  }

  /// A file of the right size where the downloader keeps [r] (sparse: instant).
  Future<void> sideLoad(DownloadManager dm, Recording r) async {
    final f = dm.fileFor(r);
    await f.parent.create(recursive: true);
    final raf = await f.open(mode: FileMode.write);
    await raf.truncate(r.localBytes);
    await raf.close();
  }

  Future<(AudioLibrary, ReaderController, DownloadManager, List<String>)> setUpLibrary() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.create();
    final dir = await Directory.systemTemp.createTemp('lib');
    addTearDown(() => dir.delete(recursive: true));
    final dm = DownloadManager(
      supportDir: dir,
      freeBytes: () async => null,
      onUnmeteredNetwork: () async => true,
      transfer: _OfflineTransfer(),
      retryDelay: Duration.zero,
    );
    final opened = <String>[];
    final library = AudioLibrary(
      content: content,
      prefs: prefs,
      downloads: dm,
      engineFactory: (r, path, plan) async {
        opened.add(r.slug);
        return (engine: PlaybackEngine(_SilentAudio(), plan), dispose: () async {});
      },
    );
    await sideLoad(dm, content.recordings.defaultRecording); // the preselected one (Qaryu) on the device
    await library.refresh();
    final windows = await content.windowsFor(library.current);
    final reader = ReaderController(
      content: content,
      recording: library.current,
      viewer: PageViewerController(legacyData(content, windows), prefs),
      store: SettingsStore(prefs),
      engine: await library.openCurrent(PlaybackPlan(windows, const PlaybackScope(226, 234), const PlaybackSettings())),
      initialVerse: 229,
    );
    library.attach(reader);
    return (library, reader, dm, opened);
  }

  test('the side-loaded recording is on the device and plays', () async {
    final (library, reader, _, opened) = await setUpLibrary();
    expect(library.isOnDevice(library.current), isTrue);
    expect(reader.audioAvailable, isTrue);
    expect(opened, ['abdulhamid-alqaryu-1']);
    expect(reader.library, library);
  });

  // ADR 0007: a verified file whose hash is no longer in the snapshot.
  test('an older recording\'s file on the device needs an update: not «on the device», never played', () async {
    final (library, reader, dm, opened) = await setUpLibrary();
    final inUse = library.current;
    // An app update brought another file for it: what is on the device has another size.
    final raf = await dm.fileFor(inUse).open(mode: FileMode.write);
    await raf.truncate(inUse.localBytes - 10);
    await raf.close();
    await library.refresh();
    expect((library.needsUpdate(inUse), library.isOnDevice(inUse), library.holdsBytes(inUse)), (true, false, true));
    final windows = await content.windowsFor(inUse);
    opened.clear();
    expect(await library.openCurrent(PlaybackPlan(windows, const PlaybackScope(226, 234), const PlaybackSettings())), isNull);
    expect(opened, isEmpty); // no engine was built on the old file
    expect(reader.verse, 229);

    await library.delete(inUse);
    expect((library.needsUpdate(inUse), library.holdsBytes(inUse), dm.fileFor(inUse).existsSync()), (false, false, false));
  });

  test('a file verified before the markers is adopted at refresh; a later change of its hash is then seen', () async {
    final (library, _, dm, _) = await setUpLibrary();
    final inUse = library.current;
    expect(library.isOnDevice(inUse), isTrue);
    final marker = File(dm.fileFor(inUse).path.replaceAll(RegExp(r'\.mp3$'), '.ok'));
    expect(await marker.readAsString(), inUse.delivery?.sha256 ?? inUse.audioSha256);
  });

  // ADR 0006: switching reciter keeps the verse and keeps playing.
  group('switching reciter (ADR 0006)', () {
    test('while playing: at once from the same verse\'s start, its own speed, the section kept, counters fresh', () async {
      final (library, reader, dm, opened) = await setUpLibrary();
      final other = library.recordings.firstWhere((r) => !r.isDefault);
      await sideLoad(dm, other);
      await library.refresh();
      reader.store!.setSpeedFor(other.id, 1.5);
      reader.setVerseRepeats(3);
      await reader.playScope(const PlaybackScope(228, 232));
      await pumpEventQueue();
      await reader.tapVerse(229);
      await pumpEventQueue();
      reader.engine!.plan.advance(); // the second play of verse 229
      expect((reader.playing, reader.verse, reader.engine!.plan.verseRepetition), (true, 229, 2));

      await library.choose(other);
      await until(() => reader.playing);
      expect((library.current.id, reader.recording.id), (other.id, other.id));
      expect((reader.playing, reader.verse), (true, 229));
      final plan = reader.engine!.plan;
      expect((plan.scope.fromVerse, plan.scope.toVerse, plan.verseRepetition, plan.settings.verseRepeats), (228, 232, 1, 3));
      expect(reader.speed, 1.5);
      final windows = await content.windowsFor(other);
      expect((reader.engine!.audio as _SilentAudio).seeks.last, windows.cue(229) - 50);
      expect(opened.last, other.slug);
    });

    test('while paused: the verse stays, nothing starts', () async {
      final (library, reader, dm, _) = await setUpLibrary();
      final other = library.recordings.firstWhere((r) => !r.isDefault);
      await sideLoad(dm, other);
      await library.refresh();
      await library.choose(other);
      expect((reader.recording.id, reader.playing, reader.verse, reader.audioAvailable), (other.id, false, 229, true));
    });

    test('one not on the device: the current keeps playing; the switch waits for the file, then for the verse\'s end', () async {
      final (library, reader, dm, _) = await setUpLibrary();
      final inUse = library.current;
      final other = library.recordings.firstWhere((r) => !r.isDefault);
      await reader.playScope(const PlaybackScope(228, 232));
      await pumpEventQueue();
      await library.choose(other); // its download starts (offline here: it fails)
      await until(() => (dm.transfer as _OfflineTransfer).attempts > 0 && !library.isDownloading(other));
      expect((library.current.id, library.pending?.id), (inUse.id, other.id));
      expect((reader.recording.id, reader.playing, reader.audioAvailable), (inUse.id, true, true));
      expect((dm.transfer as _OfflineTransfer).attempts, greaterThan(0));

      // The file arrives and verifies while verse 228 is still being recited: no switch yet.
      await sideLoad(dm, other);
      await library.backgroundFinished();
      expect((library.current.id, reader.recording.id, reader.verse), (inUse.id, inUse.id, 228));

      // The next verse begins: now.
      await reader.engine!.next();
      await until(() => reader.recording.id == other.id && reader.playing);
      expect((library.current.id, library.pending), (other.id, null));
      expect((reader.recording.id, reader.playing, reader.verse), (other.id, true, 229));
      final windows = await content.windowsFor(other);
      expect((reader.engine!.audio as _SilentAudio).seeks.last, windows.cue(229) - 50);
    });

    test('one not on the device while nothing can play: it becomes the recording at once', () async {
      final (library, reader, _, _) = await setUpLibrary();
      await library.delete(library.current); // nothing on the device
      final other = library.recordings.firstWhere((r) => !r.isDefault);
      await library.choose(other);
      expect((library.current.id, library.pending, reader.recording.id, reader.audioAvailable), (other.id, null, other.id, false));
      expect(reader.verse, 229);
    });

    test('choosing the playing one again drops a pending switch', () async {
      final (library, reader, dm, _) = await setUpLibrary();
      final inUse = library.current;
      final other = library.recordings.firstWhere((r) => !r.isDefault);
      await reader.playScope(const PlaybackScope(228, 232));
      await pumpEventQueue();
      await library.choose(other);
      await library.choose(inUse);
      expect(library.pending, isNull);
      await until(() => !library.isDownloading(other)); // the attempt it started has ended
      await sideLoad(dm, other);
      await library.backgroundFinished();
      await reader.engine!.next();
      await pumpEventQueue();
      expect(reader.recording.id, inUse.id); // downloaded, not switched to
    });

    test('picked, then downloaded while the app was closed: it is the recording at the next start', () async {
      final (library, reader, dm, _) = await setUpLibrary();
      final other = library.recordings.firstWhere((r) => !r.isDefault);
      await library.choose(other, startDownload: false);
      expect((library.current.isDefault, library.pending?.id), (true, other.id));
      await sideLoad(dm, other);
      await library.refresh(); // what the app does when it starts
      await until(() => reader.recording.id == other.id);
      expect((library.current.id, library.pending, reader.verse, reader.playing), (other.id, null, 229, false));
    });

    test('Qaryu is the default and is preselected (ADR 0034)', () async {
      final (library, _, _, _) = await setUpLibrary();
      expect((library.current.isDefault, library.current.slug), (true, 'abdulhamid-alqaryu-1'));
    });
  });

  // (A part file that verifies is taken in: download_manager_test.)
  test('a background download that does not verify is discarded, not played', () async {
    final (library, reader, dm, _) = await setUpLibrary();
    final other = library.recordings.firstWhere((r) => !r.isDefault);
    await library.delete(library.current); // nothing else to play: the chosen one is the recording
    await library.choose(other);
    final part = dm.partFileFor(other);
    await part.parent.create(recursive: true);
    final raf = await part.open(mode: FileMode.write);
    await raf.truncate(other.localBytes); // full size, wrong bytes (what a bad mirror could leave)
    await raf.close();
    await library.backgroundFinished();
    expect(library.isOnDevice(other), isFalse);
    expect(part.existsSync(), isFalse); // discarded: the next download starts clean
    expect(dm.fileFor(other).existsSync(), isFalse);
    expect(reader.audioAvailable, isFalse);
  });

  test('deleting the chosen recording takes its audio away', () async {
    final (library, reader, dm, _) = await setUpLibrary();
    final r = library.current;
    await library.delete(r);
    expect(reader.audioAvailable, isFalse);
    expect(dm.fileFor(r).existsSync(), isFalse);
    expect(library.isOnDevice(r), isFalse);
    expect(library.bytesOnDevice, 0);
  });

  test('offline, a download tries every mirror, then fails with «network», not a hang', () async {
    final (library, _, dm, _) = await setUpLibrary();
    final other = library.recordings.firstWhere((r) => !r.isDefault);
    await library.download(other);
    expect(library.progressOf(other)!.phase, DownloadPhase.failed);
    expect(library.progressOf(other)!.error, DownloadError.network);
    expect(library.isDownloading(other), isFalse);
    expect((dm.transfer as _OfflineTransfer).attempts, other.delivery!.urls.length * dm.rounds);
  });

  test('Wi-Fi only is on by default and remembered', () async {
    final (library, _, _, _) = await setUpLibrary();
    expect(library.wifiOnly, isTrue);
    library.wifiOnly = false;
    expect(library.wifiOnly, isFalse);
  });

  /// Lets real I/O started by a tap finish: each step continues in the test's fake
  /// zone, so alternate real waits with pumps.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> host(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: tzThemeData(TzTheme.dark), home: home));
    await tester.pump();
  }

  testWidgets('«التنزيلات»: each recording with its size, duration and state', (tester) async {
    late AudioLibrary library;
    await tester.runAsync(() async => (library, _, _, _) = await setUpLibrary());
    await host(tester, DownloadsScreen(library: library));
    expect(find.text('عبدالحميد بن عبدالله القريو الليبي'), findsOneWidget);
    expect(find.text('\u2066٢:٥٣:٤٧\u2069، ١٢٥ م.ب'), findsOneWidget);
    expect(find.text('على الجهاز · مُتحقَّق منه'), findsOneWidget);
    expect(find.text('المختار'), findsOneWidget);
    expect(find.text('\u2066٢:٣٠:٣٧\u2069، ١٤٥ م.ب'), findsOneWidget);
    expect(find.text('غير منزّل'), findsOneWidget);
    expect(find.text('التلاوات على الجهاز: ١٢٥ م.ب'), findsOneWidget);

    await tester.tap(find.text('تنزيل'));
    // Three rounds over both mirrors, each step real file I/O: several settles.
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
    expect(find.text('تعذّر الاتصال؛ يُستأنف من حيث توقف'), findsOneWidget); // offline in the test
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });

  testWidgets('a recording missing a cue: boot goes on, it shows «غير صالحة» (F-41)', (tester) async {
    late AudioLibrary library;
    late AppContent broken;
    await tester.runAsync(() async {
      // A snapshot whose default recording (Qaryu) has no cue for verse 500.
      final dir = await Directory.systemTemp.createTemp('missing_cue');
      addTearDown(() => dir.delete(recursive: true));
      final copy = await File('assets/content/content.sqlite').copy('${dir.path}/content.sqlite');
      final db = await databaseFactoryFfi.openDatabase(copy.path);
      await db.rawDelete("DELETE FROM verse_timings WHERE recording_id = 'recording:shatibiyyah:abdulhamid-alqaryu-1' "
          "AND matn_verse_id = 'verse:shatibiyyah:500'");
      await db.close(); // no VACUUM: the size stays what content.json says
      broken = await AppContent.open(
        loadAsset: (key) async =>
            ByteData.sublistView(await File(key.endsWith('.sqlite') ? copy.path : key).readAsBytes()),
        supportDir: await Directory('${dir.path}/support').create(),
        factory: databaseFactoryFfi,
      );
      addTearDown(broken.store.close);
      SharedPreferences.setMockInitialValues({});
      final prefs = await Prefs.create();
      final dm = DownloadManager(
          supportDir: dir, freeBytes: () async => null, onUnmeteredNetwork: () async => true, transfer: _OfflineTransfer());
      library = AudioLibrary(content: broken, prefs: prefs, downloads: dm, engineFactory: (r, path, plan) async {
        fail('no engine for an unusable recording');
      });
      final preselected = broken.recordings.defaultRecording;
      expect(broken.isUsable(preselected), isFalse);
      expect(broken.isUsable(library.recordings.firstWhere((r) => !r.isDefault)), isTrue);
      await sideLoad(dm, preselected); // even on the device, it is not played
      await library.refresh();
      // What reader_boot does: windows only for a usable recording, then the engine.
      final windows = await broken.windowsOrNull(preselected);
      expect(windows, isNull);
      final other = await broken.windowsFor(library.recordings.firstWhere((r) => !r.isDefault));
      expect(await library.openCurrent(PlaybackPlan(other, const PlaybackScope(1, 1), const PlaybackSettings())), isNull);
      ReaderController(
        content: broken,
        recording: preselected,
        viewer: PageViewerController(legacyData(broken, windows), prefs),
        initialVerse: 500,
      );
    });
    await host(tester, DownloadsScreen(library: library));
    expect(find.textContaining('غير صالحة'), findsOneWidget);
  });

  testWidgets('delete asks first, then the recording is gone', (tester) async {
    late AudioLibrary library;
    late ReaderController reader;
    await tester.runAsync(() async => (library, reader, _, _) = await setUpLibrary());
    await host(tester, DownloadsScreen(library: library));
    await tester.tap(find.text('حذف'));
    await tester.pumpAndSettle();
    expect(find.text('حذف التلاوة؟'), findsOneWidget);
    await tester.tap(find.text('حذف').last);
    await settle(tester);
    expect(library.isOnDevice(library.current), isFalse);
    expect(reader.audioAvailable, isFalse);
    expect(find.text('التلاوات على الجهاز: ٠ م.ب'), findsOneWidget);
  });

  /// What a download stopped part-way leaves (ADR 0007): the part file, and the
  /// sidecar that ties it to its delivery file.
  Future<void> keepPartial(DownloadManager dm, Recording r, int bytes, {required bool paused}) async {
    final part = dm.partFileFor(r);
    await part.parent.create(recursive: true);
    final raf = await part.open(mode: FileMode.write);
    await raf.truncate(bytes);
    await raf.close();
    await File(part.path.replaceFirst(RegExp(r'\.mp3\.part$'), '.part.json')).writeAsString(jsonEncode({
      'delivery_sha256': r.delivery!.sha256,
      'delivery_bytes': r.delivery!.bytes,
      'received': bytes,
      'paused': paused,
    }));
  }

  Future<void> confirmDelete(WidgetTester tester) async {
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    expect(find.text('حذف التلاوة؟'), findsOneWidget);
    await tester.tap(find.text('حذف').last);
  }

  testWidgets('«حذف» for a paused recording: «متوقف عند ٦٠٪», then deleted', (tester) async {
    late AudioLibrary library;
    late DownloadManager dm;
    late Recording other;
    await tester.runAsync(() async {
      (library, _, dm, _) = await setUpLibrary();
      other = library.recordings.firstWhere((r) => !r.isDefault);
      await keepPartial(dm, other, (other.localBytes * 0.6).ceil(), paused: true);
      await library.refresh(); // as after a relaunch
    });
    await host(tester, DownloadsScreen(library: library));
    expect(find.text('متوقف عند ٦٠٪'), findsOneWidget);
    expect(find.text('متابعة'), findsOneWidget);
    expect(find.text('حذف'), findsNWidgets(2)); // the one on the device, and the paused one

    await confirmDelete(tester);
    await settle(tester);
    expect(dm.partFileFor(other).existsSync(), isFalse);
    expect(find.text('غير منزّل'), findsOneWidget);
    expect(find.text('حذف'), findsOneWidget);
  });

  testWidgets('«حذف» for a failed recording that holds bytes', (tester) async {
    late AudioLibrary library;
    late DownloadManager dm;
    late Recording other;
    await tester.runAsync(() async {
      (library, _, dm, _) = await setUpLibrary();
      other = library.recordings.firstWhere((r) => !r.isDefault);
      await keepPartial(dm, other, 4000000, paused: false);
      await library.download(other); // offline in the test: fails, the bytes stay
    });
    await host(tester, DownloadsScreen(library: library));
    expect(find.text('تعذّر الاتصال؛ يُستأنف من حيث توقف'), findsOneWidget);
    expect(find.text('حذف'), findsNWidgets(2));

    await confirmDelete(tester);
    await settle(tester);
    expect(dm.partFileFor(other).existsSync(), isFalse);
    expect(find.text('غير منزّل'), findsOneWidget);
  });

  group('«التنزيلات» words each state of a download (ADR 0007)', () {
    Future<_FixedLibrary> fixed(WidgetTester tester) async {
      late _FixedLibrary library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await Prefs.create();
        final dir = await Directory.systemTemp.createTemp('lib');
        addTearDown(() => dir.delete(recursive: true));
        final dm = DownloadManager(supportDir: dir, freeBytes: () async => null, onUnmeteredNetwork: () async => true);
        library = _FixedLibrary(content: content, prefs: prefs, downloads: dm);
        await sideLoad(dm, content.recordings.defaultRecording);
        await library.refresh();
      });
      return library;
    }

    testWidgets('before a start: the size, and the free space when the device tells it', (tester) async {
      final library = await fixed(tester)..free = 3400 * 1000 * 1000;
      await host(tester, DownloadsScreen(library: library));
      await settle(tester);
      expect(find.text('غير منزّل · المتاح على الجهاز ٣٫٤ غ.ب'), findsOneWidget);
      expect(find.textContaining('١٤٥ م.ب'), findsWidgets); // its size
    });

    testWidgets('waiting for Wi-Fi: «نزّل عبر البيانات» for this one download', (tester) async {
      final library = await fixed(tester);
      final other = library.recordings.firstWhere((r) => !r.isDefault);
      library
        ..downloading = true
        ..progress = DownloadProgress(DownloadPhase.waitingForWifi, 0, other.localBytes);
      await host(tester, DownloadsScreen(library: library));
      await settle(tester);
      expect(find.text('بانتظار شبكة Wi-Fi'), findsOneWidget);
      await tester.tap(find.text('نزّل عبر البيانات'));
      expect(library.mobileData, 1);
      expect(library.wifiOnly, isTrue); // the setting stays
    });

    testWidgets('waiting for a network, a file that does not verify, a full disk', (tester) async {
      final library = await fixed(tester);
      final other = library.recordings.firstWhere((r) => !r.isDefault);
      library
        ..downloading = true
        ..progress = DownloadProgress(DownloadPhase.waitingForNetwork, 40 * 1000 * 1000, other.localBytes);
      await host(tester, DownloadsScreen(library: library));
      await settle(tester);
      expect(find.text('بانتظار الاتصال بالشبكة؛ يُستأنف تلقائيًا'), findsOneWidget);
      expect(find.text('نزّل عبر البيانات'), findsNothing);

      library
        ..downloading = false
        ..progress = DownloadProgress(DownloadPhase.failed, 0, other.localBytes, DownloadError.verification);
      library.wifiOnly = true; // any change: the screen is drawn again
      await settle(tester);
      expect(find.text('تعذّر التحقق من الملف'), findsOneWidget);
      await tester.tap(find.text('إعادة المحاولة'));
      expect(library.downloads_, 1);

      library.progress = DownloadProgress(DownloadPhase.failed, 40 * 1000 * 1000, other.localBytes, DownloadError.noSpace);
      library.wifiOnly = true;
      await settle(tester);
      // What is still needed: the rest of the file and the 50 MB margin.
      final needed = megabytes(other.localBytes - 40 * 1000 * 1000 + kFreeSpaceMargin);
      expect(find.text('المساحة غير كافية: يلزم $needed'), findsOneWidget);
    });

    testWidgets('a file of an older recording: «يلزم تحديث التلاوة», with «تنزيل» and «حذف»', (tester) async {
      late AudioLibrary library;
      late DownloadManager dm;
      await tester.runAsync(() async {
        (library, _, dm, _) = await setUpLibrary();
        final other = library.recordings.firstWhere((r) => !r.isDefault);
        final f = dm.fileFor(other);
        await f.parent.create(recursive: true);
        await f.writeAsBytes(List.filled(64, 1)); // what an older version left
        await library.refresh();
      });
      await host(tester, DownloadsScreen(library: library));
      await settle(tester);
      expect(find.text('يلزم تحديث التلاوة'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'تنزيل'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'حذف'), findsOneWidget);
    });
  });

  testWidgets('«القارئ»: choosing one not on the device keeps the verse and opens «التنزيلات»', (tester) async {
    late AudioLibrary library;
    late ReaderController reader;
    await tester.runAsync(() async => (library, reader, _, _) = await setUpLibrary());
    await host(
      tester,
      Scaffold(body: Builder(builder: (context) => TextButton(onPressed: () => showReciterSheet(context, library), child: const Text('open')))),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('يبقى البيت الحالي عند التبديل، وتستمر التلاوة'), findsOneWidget);
    // Qaryu first, then Atiq, and neither is marked (ADR 0034).
    expect(find.text('الافتراضية'), findsNothing);
    expect(tester.getCenter(find.text('عبدالحميد بن عبدالله القريو الليبي')).dy,
        lessThan(tester.getCenter(find.text('محمد بن عتيق الصنوي')).dy));
    await tester.tap(find.text('محمد بن عتيق الصنوي'));
    await settle(tester);
    // The one in use stays until the other is downloaded and verified (ADR 0006).
    expect((reader.recording.slug, library.pending?.slug), ('abdulhamid-alqaryu-1', 'muhammad-atiq-1'));
    expect(reader.verse, 229);
    expect(reader.audioAvailable, isTrue);
    expect(find.byType(DownloadsScreen), findsOneWidget);
  });

  group('first run', () {
    Future<(AudioLibrary, Prefs)> openTour(WidgetTester tester, {bool replay = false}) async {
      late AudioLibrary library;
      late Prefs prefs;
      await tester.runAsync(() async {
        (library, _, _, _) = await setUpLibrary();
        prefs = library.prefs;
      });
      await host(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => TourScreen.open(context, content: content, library: library, prefs: prefs, replay: replay),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return (library, prefs);
    }

    testWidgets('three cards, «تخطَّ» on each; then the reciter; «ابدأ التلاوة» ends the first run', (tester) async {
      final (_, prefs) = await openTour(tester);
      expect(find.text('المتن بين يديك'), findsOneWidget);
      expect(find.text('تخطَّ'), findsOneWidget);
      await tester.tap(find.text('التالي'));
      await tester.pump();
      expect(find.text('اضغط مطوّلًا على أي بيت'), findsOneWidget);
      await tester.tap(find.text('التالي'));
      await tester.pump();
      expect(find.text('متوفر حاليًا ثلاثة شروح لكل بيت'), findsOneWidget);
      expect(find.textContaining('اختبار'), findsNothing);
      await tester.tap(find.text('اختر التلاوة'));
      await tester.pump();
      expect(find.text('اختر التلاوة'), findsOneWidget); // the pick screen's title
      expect(find.text('المتن والشروح جاهزة الآن دون تنزيل. اختر التلاوة التي تسمعها مع المتن.'), findsOneWidget);
      expect(find.text('ابدأ التلاوة'), findsOneWidget); // the preselected one is on the device
      expect(tourDone(prefs), isFalse);
      await tester.tap(find.text('ابدأ التلاوة'));
      await tester.pumpAndSettle();
      expect(find.byType(TourScreen), findsNothing);
      expect(tourDone(prefs), isTrue);
    });

    testWidgets('a reciter not on the device: «تنزيل … والبدء» or «لاحقًا»', (tester) async {
      final (library, prefs) = await openTour(tester);
      await tester.tap(find.text('تخطَّ'));
      await tester.pump();
      await tester.tap(find.text('محمد بن عتيق الصنوي'));
      await settle(tester);
      expect(find.text('تنزيل ١٤٥ م.ب والبدء'), findsOneWidget);
      await tester.tap(find.text('لاحقًا، ابدأ بالقراءة'));
      await tester.pumpAndSettle();
      expect(tourDone(prefs), isTrue);
      // It is the listener's pick; the one on the device stays in use until it is downloaded.
      expect((library.chosen.slug, library.current.slug), ('muhammad-atiq-1', 'abdulhamid-alqaryu-1'));
      expect(library.isDownloading(library.chosen), isFalse); // «لاحقًا»: nothing started
    });

    testWidgets('replayed from «حول»: the cards only, ending with «تم»', (tester) async {
      await openTour(tester, replay: true);
      await tester.tap(find.text('التالي'));
      await tester.pump();
      await tester.tap(find.text('التالي'));
      await tester.pump();
      await tester.tap(find.text('تم'));
      await tester.pumpAndSettle();
      expect(find.byType(TourScreen), findsNothing);
    });
  });
}
