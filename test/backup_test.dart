// Backup and restore (P7, U-03): backup → wipe → restore reproduces the data;
// restoring into data already there merges (newest wins, one live row per verse,
// tombstones travel); a second restore changes nothing; a file that is not a
// backup is refused before anything is written. Format v2 (ADR 0008) has no
// history or listened verses; a v1 file still imports, and those parts are ignored.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/data/backup.dart';
import 'package:shatibiyyah/data/user_store.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final t0 = DateTime(2026, 9, 1, 10);
  DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

  Future<UserStore> store() async {
    final dir = await Directory.systemTemp.createTemp('backup_test');
    addTearDown(() => dir.delete(recursive: true));
    final s = await UserStore.open(directory: dir.path, factory: databaseFactoryFfi);
    addTearDown(s.close);
    return s;
  }

  Future<Prefs> prefs(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return Prefs.create();
  }

  /// The device's data as a backup would carry it, minus the export time.
  Future<Map<String, Object?>> snapshot(UserStore s, Prefs p) async =>
      (await exportBackup(s, p))..remove('exported_at');

  Future<UserStore> filled() async {
    final a = await store();
    await a.saveBookmark(229, color: BookmarkColor.rose, tag: BookmarkTag.ishkal, at: at(1));
    await a.saveBookmark(120, to: 123, color: BookmarkColor.green, tag: BookmarkTag.hifz, at: at(2));
    await a.saveBookmark(300, color: BookmarkColor.gold, tag: BookmarkTag.muraja, at: at(3));
    await a.deleteBookmark(300, at: at(4)); // a tombstone
    await a.saveNote(230, 'قارن بالوافي', at: at(5));
    return a;
  }

  test('backup → wipe → restore reproduces the data and the settings', () async {
    final a = await filled();
    final pa = await prefs({'flutter.v2.theme': 'paper', 'flutter.v2.speed.recording:atiq': '1.25', 'flutter.v2.tour.done': '1'});
    final before = await snapshot(a, pa);
    final text = encodeBackup(await exportBackup(a, pa));
    expect((before['settings'] as Map).keys, ['v2.speed.recording:atiq', 'v2.theme']); // device state stays behind

    final b = await store();
    final pb = await prefs({});
    final report = await mergeBackup(b, pb, decodeBackup(text));
    expect((report.bookmarks, report.notes), (3, 1));
    expect(before.keys, isNot(contains('activity')));
    expect(before.keys, isNot(contains('verse_listens')));
    expect(before['version'], 2);
    expect(await snapshot(b, pb), before);
    expect((await b.bookmarks()).map((x) => x.fromVerse).toSet(), {229, 120});
    expect(pb.getString('v2.tour.done'), isNull);

    final again = await mergeBackup(b, pb, decodeBackup(text));
    expect(again.total, 0); // restoring twice changes nothing
    expect(await snapshot(b, pb), before);
  });

  test('restore into data already there merges: the newest wins per verse', () async {
    final a = await filled();
    final pa = await prefs({'flutter.v2.theme': 'paper'});
    final backup = decodeBackup(encodeBackup(await exportBackup(a, pa)));

    final b = await store();
    await b.saveBookmark(229, color: BookmarkColor.blue, tag: BookmarkTag.hifz, at: at(30)); // newer than the backup's
    await b.saveNote(230, 'ملاحظة أقدم', at: at(0)); // older than the backup's
    await b.saveBookmark(500, color: BookmarkColor.sand, tag: BookmarkTag.muraja, at: at(1)); // only here
    final pb = await prefs({'flutter.v2.theme': 'dark'});

    await mergeBackup(b, pb, backup);
    final bookmarks = {for (final x in await b.bookmarks()) x.fromVerse: x};
    expect(bookmarks.keys.toSet(), {229, 120, 500});
    expect(bookmarks[229]!.color, BookmarkColor.blue); // this device's newer one
    expect((await b.notes()).single.body, 'قارن بالوافي'); // the backup's newer one
    final tombstones = await b.db.rawQuery(
        "SELECT count(*) AS n FROM bookmarks WHERE from_verse_id = 'verse:shatibiyyah:229' AND deleted_at IS NOT NULL");
    expect(tombstones.first['n'], 1); // the backup's 229 came in as a tombstone
    expect(pb.getString('v2.theme'), 'dark'); // this device's own setting stays
  });

  test('a later delete travels: the tombstone wins over the older live row', () async {
    final a = await store();
    await a.saveNote(12, 'مؤقت', at: at(1));
    final b = await store();
    final pb = await prefs({});
    await mergeBackup(b, pb, decodeBackup(encodeBackup(await exportBackup(a, await prefs({})))));
    expect((await b.notes()).single.verse, 12);
    await a.saveNote(12, '', at: at(2)); // deleted on the first device
    await mergeBackup(b, pb, decodeBackup(encodeBackup(await exportBackup(a, await prefs({})))));
    expect(await b.notes(), isEmpty);
  });

  test('not a backup, a newer version or a damaged row: refused, nothing written', () async {
    expect(() => decodeBackup('not json'), throwsA(isA<BackupError>()));
    expect(() => decodeBackup('{"format":"other","version":1}'), throwsA(isA<BackupError>()));
    expect(() => decodeBackup('{"format":"shatibiyyah-backup","version":3}'), throwsA(isA<BackupError>()));
    final b = await store();
    final bad = decodeBackup('{"format":"shatibiyyah-backup","version":1,'
        '"notes":[{"uuid":"n1","matn_verse_id":"verse:shatibiyyah:5","body":"x","created_at":1,"updated_at":1}],'
        '"bookmarks":[{"uuid":"b1","from_verse_id":"verse:x","color":"gold","tag":"hifz","created_at":1,"updated_at":1}]}');
    await expectLater(mergeBackup(b, await prefs({}), bad), throwsA(isA<BackupError>()));
    expect(await b.notes(), isEmpty);
  });

  test('a v1 file imports: bookmarks, notes and settings; history and listened verses are ignored', () async {
    const v1 = '''{
 "format": "shatibiyyah-backup", "version": 1, "exported_at": "2026-09-01T10:00:00.000Z",
 "settings": {"v2.theme": "paper"},
 "bookmarks": [{"uuid": "b1", "from_verse_id": "verse:shatibiyyah:229", "to_verse_id": null, "color": "rose",
   "tag": "ishkal", "created_at": 1, "updated_at": 1, "deleted_at": null}],
 "notes": [{"uuid": "n1", "matn_verse_id": "verse:shatibiyyah:230", "commentary_block_id": null,
   "body": "قارن بالوافي", "created_at": 2, "updated_at": 2, "deleted_at": null}],
 "activity": [{"uuid": "a1", "at": 3, "kind": "listen", "from_verse_id": "verse:shatibiyyah:226",
   "to_verse_id": "verse:shatibiyyah:229", "recording_id": "recording:atiq", "commentary_id": null, "seconds": 720}],
 "verse_listens": [{"recording_id": "recording:atiq", "matn_verse_id": "verse:shatibiyyah:95",
   "first_completed_at": 4, "completions": 2}]
}''';
    final b = await store();
    final pb = await prefs({});
    final report = await mergeBackup(b, pb, decodeBackup(v1));
    expect((report.bookmarks, report.notes), (1, 1));
    expect(report.settings, {'v2.theme'});
    expect(report.total, 3);
    expect((await b.bookmarks()).single.fromVerse, 229);
    expect((await b.notes()).single.body, 'قارن بالوافي');
    expect(pb.getString('v2.theme'), 'paper');
  });
}
