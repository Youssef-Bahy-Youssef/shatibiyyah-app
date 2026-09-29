// user.sqlite: schema v1 applies, constraints hold, played-through verses are recorded once.
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

  test('schema v1 creates every table', () async {
    final tables = (await store.db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name'])
        .toSet();
    expect(tables, containsAll(['bookmarks', 'notes', 'activity_log', 'verse_listens', 'downloads']));
    expect((await store.db.rawQuery('PRAGMA user_version')).first.values.first, kUserMigrations.length);
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

  test('a verse played through twice is one verse, two completions', () async {
    await store.recordVerseListened('recording:shatibiyyah:muhammad-atiq-1', 226);
    await store.recordVerseListened('recording:shatibiyyah:muhammad-atiq-1', 226);
    await store.recordVerseListened('recording:shatibiyyah:abdulhamid-alqaryu-1', 227);
    expect(await store.listenedVerses(), {226, 227});
    final row = (await store.db.rawQuery(
        "SELECT completions FROM verse_listens WHERE matn_verse_id = 'verse:shatibiyyah:226'")).single;
    expect(row['completions'], 2);
  });

  test('reopening keeps the data (no re-migration)', () async {
    await store.recordVerseListened('recording:shatibiyyah:muhammad-atiq-1', 1);
    await store.close();
    store = await UserStore.open(directory: dir.path, factory: databaseFactoryFfi);
    expect(await store.listenedVerses(), {1});
  });
}
