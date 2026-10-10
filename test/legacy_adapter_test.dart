// Today's screens on the snapshot: the legacy data model built by the adapter,
// and the one-time repair of index-keyed preferences.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/data/legacy_prefs.dart';
import 'package:shatibiyyah/models/playback_settings.dart' show K;
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('legacy_adapter_test');
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

  test('the legacy model has the 78 canonical chapters and the reviewed timings', () async {
    final windows = await content.windowsFor(content.recordings.defaultRecording);
    final data = legacyData(content, windows);
    expect(data.chapters, hasLength(78));
    expect(data.lastVerse, 1173);
    expect(data.pageCount, 94);
    // النور is one chapter, 912–919 (the old list stopped it at 912).
    final nur = data.chapters[data.chapterIndexForVerse(913)];
    expect((nur.startVerse, nur.endVerse), (912, 919));
    // Chapter 11 starts at its spoken title, verse 226 at its reviewed cue.
    final ch11 = data.chapters[11];
    expect(ch11.startTime, windows.chapterStart(226) / 1000.0);
    expect(data.verseTimes[226], windows.cue(226) / 1000.0);
    expect(data.getBox(226)!.page, 19);
    expect(data.chaptersOnPage(19), contains(11));
    expect(data.defaultDuration, windows.durationMs / 1000.0);
  });

  test('without a recording the model still lays out the pages', () {
    final data = legacyData(content, null);
    expect(data.verseTimes[226], isNull);
    expect(data.chapters.first.startTime, isNull);
    expect(data.versesOnPage(19), contains(229));
  });

  test('verse text comes from the database, halves intact', () {
    final text = legacyVerseText(content);
    expect(text.list, hasLength(1173));
    expect(text.byId[226]!.sadr, 'وَحَرِّكْ لِوَرْشٍ كُلَّ سَاكِنٍ آخِرٍ');
    expect(text.byId[107]!.ajuz, isNotEmpty);
  });

  group('legacy prefs', () {
    Future<Prefs> prefsWith(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      return Prefs.create();
    }

    test('chapter indices after النور move back by one', () async {
      final prefs = await prefsWith({
        K.chapter: '53', // old «النور» entry list index 53 = سورة 920 → canonical 052
      });
      expect(migrateLegacyPrefs(prefs, content.matn), isTrue);
      expect(prefs.getString(K.chapter), '52');
      expect(migrateLegacyPrefs(prefs, content.matn), isFalse); // once only
    });

    test('fresh installs are left alone apart from the marker', () async {
      final prefs = await prefsWith({});
      migrateLegacyPrefs(prefs, content.matn);
      expect(prefs.getString(K.chapter), isNull);
      expect(prefs.getString(kLegacyPrefsMigrated), '1');
    });
  });
}
