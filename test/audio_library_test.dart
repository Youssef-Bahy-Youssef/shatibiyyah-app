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
import 'package:shatibiyyah/domain/playback_engine.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/services/download_manager.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/shell/downloads_screen.dart';
import 'package:shatibiyyah/ui/shell/tour_screen.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
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
    await sideLoad(dm, content.recordings.defaultRecording); // Atiq on the device
    await library.refresh();
    final windows = await content.windowsFor(library.current);
    final reader = ReaderController(
      content: content,
      recording: library.current,
      viewer: PageViewerController(legacyData(content, windows), prefs),
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
    expect(opened, ['muhammad-atiq-1']);
    expect(reader.library, library);
  });

  test('choosing a reciter not on the device keeps the verse and drops the audio', () async {
    final (library, reader, _, _) = await setUpLibrary();
    final other = library.recordings.firstWhere((r) => !r.isDefault);
    await library.choose(other);
    expect(library.current.id, other.id);
    expect(reader.recording.id, other.id);
    expect(reader.audioAvailable, isFalse);
    expect(reader.verse, 229);

    await library.choose(content.recordings.defaultRecording); // back: audio again
    expect(reader.audioAvailable, isTrue);
    expect(reader.verse, 229);
  });

  // (A part file that verifies is taken in: download_manager_test.)
  test('a background download that does not verify is discarded, not played', () async {
    final (library, reader, dm, _) = await setUpLibrary();
    final other = library.recordings.firstWhere((r) => !r.isDefault);
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
    expect(find.text('محمد بن عتيق الصنوي'), findsOneWidget);
    expect(find.text('\u2066٢:٣٠:٣٧\u2069، ١٤٥ م.ب'), findsOneWidget);
    expect(find.text('على الجهاز · مُتحقَّق منه'), findsOneWidget);
    expect(find.text('المختار'), findsOneWidget);
    expect(find.text('\u2066٢:٥٣:٤٧\u2069، ١٢٥ م.ب'), findsOneWidget);
    expect(find.text('غير منزّل'), findsOneWidget);
    expect(find.text('التلاوات على الجهاز: ١٤٥ م.ب'), findsOneWidget);

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
      // A snapshot whose default recording (Atiq) has no cue for verse 500.
      final dir = await Directory.systemTemp.createTemp('missing_cue');
      addTearDown(() => dir.delete(recursive: true));
      final copy = await File('assets/content/content.sqlite').copy('${dir.path}/content.sqlite');
      final db = await databaseFactoryFfi.openDatabase(copy.path);
      await db.rawDelete("DELETE FROM verse_timings WHERE recording_id = 'recording:shatibiyyah:muhammad-atiq-1' "
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
      final atiq = broken.recordings.defaultRecording;
      expect(broken.isUsable(atiq), isFalse);
      expect(broken.isUsable(library.recordings.firstWhere((r) => !r.isDefault)), isTrue);
      await sideLoad(dm, atiq); // even on the device, it is not played
      await library.refresh();
      // What reader_boot does: windows only for a usable recording, then the engine.
      final windows = await broken.windowsOrNull(atiq);
      expect(windows, isNull);
      final other = await broken.windowsFor(library.recordings.firstWhere((r) => !r.isDefault));
      expect(await library.openCurrent(PlaybackPlan(other, const PlaybackScope(1, 1), const PlaybackSettings())), isNull);
      ReaderController(
        content: broken,
        recording: atiq,
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
    expect(find.text('حذف'), findsNWidgets(2)); // Atiq on the device, and the paused one

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
    expect(find.text('يبقى البيت الحالي عند التبديل'), findsOneWidget);
    await tester.tap(find.text('عبدالحميد بن عبدالله القريو الليبي'));
    await settle(tester);
    expect(reader.recording.slug, 'abdulhamid-alqaryu-1');
    expect(reader.verse, 229);
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
      expect(find.text('المخطوط أولًا'), findsOneWidget);
      expect(find.text('تخطَّ'), findsOneWidget);
      await tester.tap(find.text('التالي'));
      await tester.pump();
      expect(find.text('الشرح والمراجعة حول البيت'), findsOneWidget);
      await tester.tap(find.text('التالي'));
      await tester.pump();
      expect(find.text('الشروح الثلاثة على جهازك'), findsOneWidget);
      expect(find.textContaining('اختبار'), findsNothing);
      await tester.tap(find.text('اختر القارئ'));
      await tester.pump();
      expect(find.text('اختر القارئ'), findsOneWidget); // the pick screen's title
      expect(find.text('ابدأ التلاوة'), findsOneWidget); // Atiq is on the device
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
      await tester.tap(find.text('عبدالحميد بن عبدالله القريو الليبي'));
      await settle(tester);
      expect(find.text('تنزيل ١٢٥ م.ب والبدء'), findsOneWidget);
      await tester.tap(find.text('لاحقًا، ابدأ بالقراءة'));
      await tester.pumpAndSettle();
      expect(tourDone(prefs), isTrue);
      expect(library.current.slug, 'abdulhamid-alqaryu-1');
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
