// «رموز القراء» (P6, rumuz-legend): the snapshot's readers and codes, and the
// screen's three tabs; a code's source verse opens the reader there.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/data/rumuz_repository.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/shell/rumuz_screen.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

void main() {
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('rumuz_test');
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

  test('seven imams with two transmitters each; 21 letters, 6 group letters, 8 words', () {
    final z = content.rumuz;
    expect(z.readers.length, 21);
    expect(z.readers.where((r) => r.isImam).length, 7);
    expect(z.ofKind(RamzKind.letter).length, 21);
    expect(z.ofKind(RamzKind.groupLetter).map((r) => r.code).join(), 'ثخذظغش');
    expect(z.ofKind(RamzKind.word).length, 8);
    expect(z.ofKind(RamzKind.letter).every((r) => r.fromVerse == 45 && r.readerIds.length == 1), isTrue);
    for (final r in z.rumuz) {
      expect(r.readerIds.every((id) => z.readers.any((x) => x.id == id)), isTrue, reason: r.code);
    }
  });

  Future<ReaderController> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    late ReaderController r;
    await tester.runAsync(() async {
      final prefs = await Prefs.create();
      final recording = content.recordings.defaultRecording;
      final windows = await content.windowsFor(recording);
      r = ReaderController(
        content: content,
        recording: recording,
        viewer: PageViewerController(legacyData(content, windows), prefs),
        initialVerse: 1,
      );
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: tzThemeData(TzTheme.dark),
      home: Directionality(textDirection: TextDirection.rtl, child: RumuzScreen(reader: r)),
    ));
    await tester.pump();
    return r;
  }

  testWidgets('three tabs: letters by triples, groups and words with their verses', (tester) async {
    final r = await open(tester);
    expect(find.text('رموز القراء'), findsOneWidget);
    expect(find.text('أبج دهز حطي كلم نصع فضق رست، البيت ٤٥'), findsOneWidget);
    expect(find.text('قالون'), findsOneWidget);

    await tester.tap(find.text('الجماعات'));
    await tester.pump();
    expect(find.text('الكوفيون'), findsOneWidget);
    expect(find.textContaining('الأبيات'), findsOneWidget);

    await tester.tap(find.text('الكلمات'));
    await tester.pump();
    expect(find.text('صحبة'), findsOneWidget);
    expect(find.text('حمزة والكسائي وشعبة'), findsOneWidget);

    await tester.ensureVisible(find.text('حصن')); // the rows are taller in the hero role
    await tester.pumpAndSettle();
    await tester.tap(find.text('حصن'));
    await tester.pumpAndSettle();
    expect(r.verse, 55);
  });
}
