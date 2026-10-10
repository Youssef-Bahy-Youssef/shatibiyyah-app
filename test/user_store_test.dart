// user.sqlite: the schema applies, constraints hold, and a v1 database migrates to
// v2 (ADR 0008): the history, listening and downloads tables go, bookmarks and notes stay.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/data/user_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Migration 1 exactly as the release before 2.1 shipped it: one string, which that
/// release ran by splitting on «;». A database made from it is a real v1 database.
const String _shippedV1 = '''
  CREATE TABLE bookmarks (
    uuid TEXT PRIMARY KEY,
    from_verse_id TEXT NOT NULL,
    to_verse_id TEXT,
    color TEXT NOT NULL CHECK (color IN ('gold','green','orange','blue','rose','sand')),
    tag TEXT NOT NULL CHECK (tag IN ('hifz','muraja','ishkal')),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER
  );
  CREATE UNIQUE INDEX ux_bookmark_live ON bookmarks (from_verse_id, ifnull(to_verse_id, '')) WHERE deleted_at IS NULL;
  CREATE TABLE notes (
    uuid TEXT PRIMARY KEY, matn_verse_id TEXT NOT NULL, commentary_block_id TEXT,
    body TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER
  );
  CREATE INDEX ix_notes_verse ON notes (matn_verse_id) WHERE deleted_at IS NULL;
  CREATE TABLE activity_log (
    uuid TEXT PRIMARY KEY, at INTEGER NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('listen','commentary')),
    from_verse_id TEXT, to_verse_id TEXT, recording_id TEXT, commentary_id TEXT,
    seconds INTEGER
  );
  CREATE INDEX ix_activity_at ON activity_log (at);
  CREATE TABLE verse_listens (
    recording_id TEXT NOT NULL, matn_verse_id TEXT NOT NULL,
    first_completed_at INTEGER NOT NULL, completions INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (recording_id, matn_verse_id)
  );
  CREATE TABLE downloads (
    item_id TEXT PRIMARY KEY,
    state TEXT NOT NULL CHECK (state IN ('none','queued','downloading','paused','verifying','ready','failed','update_available')),
    bytes_done INTEGER NOT NULL DEFAULT 0, sha256 TEXT, local_path TEXT, error TEXT, updated_at INTEGER NOT NULL
  );
''';

/// The schema as SQLite records it, with whitespace runs collapsed.
Future<Map<String, String>> _schema(Database db) async => {
      for (final r in await db.rawQuery(
          "SELECT name, sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'android_%' ORDER BY name"))
        r['name'] as String: (r['sql'] as String).replaceAll(RegExp(r'\s+'), ' ').replaceAll('( ', '(').replaceAll(' )', ')').trim(),
    };

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
          for (final s in _shippedV1.split(';')) {
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

    // The upgraded database has the schema a new install gets.
    final fresh = await Directory.systemTemp.createTemp('user_store_fresh');
    addTearDown(() => fresh.delete(recursive: true));
    final installed = await UserStore.open(directory: fresh.path, factory: databaseFactoryFfi);
    addTearDown(installed.close);
    expect(await _schema(store.db), await _schema(installed.db));
  });

  test('migration 2 is three statements, one per dropped table', () {
    expect(kUserMigrations[1], ['DROP TABLE activity_log', 'DROP TABLE verse_listens', 'DROP TABLE downloads']);
  });

  test('a migration is a list of statements: a «;» inside a literal applies (F-58)', () async {
    final other = await Directory.systemTemp.createTemp('user_store_semicolon');
    addTearDown(() => other.delete(recursive: true));
    final s = await UserStore.open(directory: other.path, factory: databaseFactoryFfi, migrations: [
      ...kUserMigrations,
      [
        'CREATE TABLE t (body TEXT NOT NULL)',
        "INSERT INTO t (body) VALUES ('a; b')",
      ],
    ]);
    addTearDown(s.close);
    expect((await s.db.rawQuery('SELECT body FROM t')).single['body'], 'a; b');
    expect((await s.db.rawQuery('PRAGMA user_version')).first.values.first, kUserMigrations.length + 1);
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

    test('delete by uuid, then restore: the same row; refused when its verses were taken', () async {
      await store.saveBookmark(226, to: 234, color: BookmarkColor.blue, tag: BookmarkTag.muraja);
      final b = (await store.bookmarks()).single;
      await store.deleteBookmarkById(b.uuid);
      expect(await store.bookmarks(), isEmpty);
      expect(await store.restoreBookmark(b.uuid), isTrue);
      final back = (await store.bookmarks()).single;
      expect((back.uuid, back.fromVerse, back.toVerse, back.color, back.tag), (b.uuid, 226, 234, b.color, b.tag));

      await store.deleteBookmarkById(b.uuid);
      await store.saveBookmark(226, to: 234, color: BookmarkColor.gold, tag: BookmarkTag.hifz); // a new one
      expect(await store.restoreBookmark(b.uuid), isFalse); // one live bookmark per range
      expect((await store.bookmarks()).single.color, BookmarkColor.gold);
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

    // Plan 5.1, ADR 0009.
    test('an edit keeps the uuid and created_at, and moves updated_at', () async {
      await store.saveNote(229, 'انظر الوافي', at: DateTime(2026, 1, 1));
      final uuid = (await store.notes()).single.uuid;
      await store.saveNote(229, 'انظر إبراز المعاني', at: DateTime(2026, 1, 2));
      final row = (await store.db.query('notes')).single;
      expect(row['uuid'], uuid);
      expect(row['created_at'], DateTime(2026, 1, 1).millisecondsSinceEpoch);
      expect(row['updated_at'], DateTime(2026, 1, 2).millisecondsSinceEpoch);
    });

    test('delete by id, then «تراجع»: the same uuid and text', () async {
      await store.saveNote(229, 'انظر الوافي');
      final n = (await store.notes()).single;
      await store.deleteNoteById(n.uuid);
      expect(await store.notes(), isEmpty);
      expect(await store.restoreNote(n.uuid), isTrue);
      final back = (await store.notes()).single;
      expect((back.uuid, back.verse, back.body), (n.uuid, 229, 'انظر الوافي'));
      expect(await store.db.query('notes'), hasLength(1)); // the same row, not a copy
    });

    test('«تراجع» gives way to a note written on the verse since', () async {
      await store.saveNote(229, 'القديمة');
      final old = (await store.notes()).single;
      await store.deleteNoteById(old.uuid);
      await store.saveNote(229, 'الجديدة');
      expect(await store.restoreNote(old.uuid), isFalse); // one live note per verse
      expect((await store.notes()).single.body, 'الجديدة');
    });
  });
}
