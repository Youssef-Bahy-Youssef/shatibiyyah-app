// Smoke test: today's HomeScreen, booted the way main.dart boots it but on the
// real bundled snapshot, renders without errors and shows the no-audio state
// (nothing is bundled and no recording is on the "device").
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/app_controller.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/data/legacy_prefs.dart';
import 'package:shatibiyyah/services/audio_service.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/services/sync_service.dart';
import 'package:shatibiyyah/ui/home_screen.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('home_smoke_test');
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

  testWidgets('boots on the snapshot and shows «التلاوة قريبًا» without a recording', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    SharedPreferences.setMockInitialValues({});
    late AppController app;
    await tester.runAsync(() async {
      final prefs = await Prefs.create();
      migrateLegacyPrefs(prefs, content.matn);
      final recording = content.recordings.defaultRecording;
      final data = legacyData(content, await content.windowsFor(recording));
      final audio = AudioEngine(AudioPlayer(), data, prefs);
      final viewer = PageViewerController(data, prefs);
      app = AppController(
        content: content,
        recording: recording,
        audioFilePath: null,
        data: data,
        verseText: legacyVerseText(content),
        audio: audio,
        viewer: viewer,
        sync: SyncController(audio, viewer, data),
        prefs: prefs,
      );
    });

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: HomeScreen(app: app),
    ));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(app.audioAvailable, isFalse);
    // The chrome starts hidden on phones; show it and look at the player bar.
    app.showControls();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('التلاوة قريبًا'), findsOneWidget);
    expect(find.text('خطبة الكتاب'), findsWidgets); // chapter 0's short label, from the snapshot
    expect(app.data.chapters, hasLength(78));

    // Pressing play does nothing rather than failing.
    app.togglePlay();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10)); // let auto-hide timers expire
  });
}
