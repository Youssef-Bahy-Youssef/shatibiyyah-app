// user.sqlite: the schema applies, constraints hold, and a v1 database migrates to
// v2 (ADR 0008): the history, listening and downloads tables go, bookmarks and notes stay.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/data/user_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late UserStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('user_store_test');
    store = await UserStore.open(directory: dir.path, factory: databaseFactoryFfi);
  });

  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  test('the schema creates bookmarks and notes, at the latest version', () async {
    final tables = (await store.db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name'])
        .toSet();
    expect(tables, containsAll(['bookmarks', 'notes']));
    expect((await store.db.rawQuery('PRAGMA user_version')).first.values.first, 2);
  });

  test('v1 → v2 drops activity_log, verse_listens and downloads, and keeps bookmarks and notes', () async {
    await store.close();
    final v1dir = await Directory.systemTemp.createTemp('user_store_v1');
    addTearDown(() => v1dir.delete(recursive: true));
    // A v1 database as the previous release left it, with a row in every table.
    final v1 = await databaseFactoryFfi.openDatabase(
      '${v1dir.path}/user.sqlite',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          for (final s in kUserMigrations.first.split(';')) {
            if (s.trim().isNotEmpty) await db.execute(s);
          }
        },
      ),
    );
    await v1.insert('bookmarks', {
      'uuid': 'b1', 'from_verse_id': 'verse:shatibiyyah:229', 'color': 'rose', 'tag': 'ishkal',
      'created_at': 1, 'updated_at': 1,
    });
    await v1.insert('notes', {
      'uuid': 'n1', 'matn_verse_id': 'verse:shatibiyyah:230', 'body': 'قارن بالوافي', 'created_at': 2, 'updated_at': 2,
    });
    await v1.insert('activity_log', {'uuid': 'a1', 'at': 3, 'kind': 'listen'});
    await v1.insert('verse_listens',
        {'recording_id': 'recording:a', 'matn_verse_id': 'verse:shatibiyyah:1', 'first_completed_at': 4});
    await v1.insert('downloads', {'item_id': 'x', 'state': 'none', 'updated_at': 5});
    await v1.close();

    store = await UserStore.open(directory: v1dir.path, factory: databaseFactoryFfi);
    final tables = {
      for (final r in await store.db.rawQuery("SELECT name FROM sqlite_master WHERE type IN ('table', 'index')")) r['name'],
    };
    expect(tables.intersection({'activity_log', 'verse_listens', 'downloads', 'ix_activity_at'}), isEmpty);
    expect((await store.db.rawQuery('PRAGMA user_version')).first.values.first, 2);
    expect((await store.bookmarks()).single.fromVerse, 229);
    expect((await store.notes()).single.body, 'قارن بالوافي');
  });

  test('a bookmark colour or tag outside the design is refused', () async {
    Future<void> insert(String color, String tag) => store.db.insert('bookmarks', {
          'uuid': '$color$tag', 'from_verse_id': 'verse:shatibiyyah:1', 'color': color, 'tag': tag,
          'created_at': 1, 'updated_at': 1,
        });
    await insert('gold', 'hifz');
    expect(() => insert('purple', 'hifz'), throwsA(isA<DatabaseException>()));
    expect(() => insert('gold', 'plan'), throwsA(isA<DatabaseException>()));
  });

  test('only one live bookmark per verse or range; a deleted one can be re-added', () async {
    Future<void> insert(String uuid, {int? deletedAt}) => store.db.insert('bookmarks', {
          'uuid': uuid, 'from_verse_id': 'verse:shatibiyyah:226', 'to_verse_id': 'verse:shatibiyyah:234',
          'color': 'green', 'tag': 'muraja', 'created_at': 1, 'updated_at': 1, 'deleted_at': deletedAt,
        });
    await insert('a', deletedAt: 5);
    await insert('b');
    expect(() => insert('c'), throwsA(isA<DatabaseException>()));
  });

  test('reopening keeps the data (no re-migration)', () async {
    await store.saveNote(1, 'باقية');
    await store.close();
    store = await UserStore.open(directory: dir.path, factory: databaseFactoryFfi);
    expect((await store.notes()).single.body, 'باقية');
  });

  group('bookmarks', () {
    test('save creates, save again updates, delete leaves a tombstone', () async {
      await store.saveBookmark(229, color: BookmarkColor.gold, tag: BookmarkTag.hifz, at: DateTime(2026, 1, 1));
      await store.saveBookmark(229, color: BookmarkColor.rose, tag: BookmarkTag.ishkal, at: DateTime(2026, 1, 2));
      var all = await store.bookmarks();
      expect(all, hasLength(1));
      expect((all.single.fromVerse, all.single.toVerse, all.single.color, all.single.tag),
          (229, null, BookmarkColor.rose, BookmarkTag.ishkal));

      await store.deleteBookmark(229);
      expect(await store.bookmarks(), isEmpty);
      final rows = await store.db.rawQuery('SELECT deleted_at FROM bookmarks');
      expect(rows.single['deleted_at'], isNotNull); // kept for merging on restore

      await store.saveBookmark(229, color: BookmarkColor.gold, tag: BookmarkTag.hifz);
      all = await store.bookmarks();
      expect(all.single.color, BookmarkColor.gold);
    });

    test('a range is its own bookmark; the newest change comes first', () async {
      await store.saveBookmark(226, to: 234, color: BookmarkColor.blue, tag: BookmarkTag.muraja, at: DateTime(2026, 1, 1));
      await store.saveBookmark(226, color: BookmarkColor.green, tag: BookmarkTag.hifz, at: DateTime(2026, 1, 2));
      final all = await store.bookmarks();
      expect(all.map((b) => (b.fromVerse, b.toVerse)), [(226, null), (226, 234)]);
      expect(all.last.covers(230), isTrue);
      expect(all.first.covers(230), isFalse);
      await store.deleteBookmark(226, to: 234);
      expect((await store.bookmarks()).single.toVerse, isNull);
    });

    test('uuids are random version-4', () {
      final a = newUuid(), b = newUuid();
      expect(a, isNot(b));
      expect(a, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });
  });

  group('notes', () {
    test('one note per verse: save, edit, and an empty save deletes', () async {
      await store.saveNote(229, '  انظر الوافي  ', at: DateTime(2026, 1, 1));
      await store.saveNote(229, 'انظر إبراز المعاني', at: DateTime(2026, 1, 2));
      var all = await store.notes();
      expect(all.single.verse, 229);
      expect(all.single.body, 'انظر إبراز المعاني');
      await store.saveNote(229, '   ');
      expect(await store.notes(), isEmpty);
      expect((await store.db.rawQuery('SELECT deleted_at FROM notes')).single['deleted_at'], isNotNull);
    });
  });
}
