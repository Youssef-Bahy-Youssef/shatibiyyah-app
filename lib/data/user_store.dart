// lib/data/user_store.dart — the student's own data, in user.sqlite (read-write).
//
// Kept apart from content.sqlite so content updates never touch it. Every row is
// keyed by the content's stable IDs (verse:shatibiyyah:226, recording:…), and
// synced-style fields (uuid, updated_at, deleted_at tombstones) are there from the
// start so backup/restore can merge rather than overwrite (migration plan U-03).
// Schema changes are numbered migrations applied in order by PRAGMA user_version.
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Migration n is at index n-1: its statements, each run on its own, so a «;» inside
/// a literal or a trigger body is never cut (F-58). Never edit one that has shipped;
/// add a new one.
const List<List<String>> kUserMigrations = [
  // 1 — bookmarks, notes, history, played-through verses, downloads (plan 02 §5.2, rev 3)
  [
    '''
    CREATE TABLE bookmarks (
      uuid TEXT PRIMARY KEY,
      from_verse_id TEXT NOT NULL,
      to_verse_id TEXT,
      color TEXT NOT NULL CHECK (color IN ('gold','green','orange','blue','rose','sand')),
      tag TEXT NOT NULL CHECK (tag IN ('hifz','muraja','ishkal')),
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER
    )
    ''',
    '''
    CREATE UNIQUE INDEX ux_bookmark_live ON bookmarks (from_verse_id, ifnull(to_verse_id, '')) WHERE deleted_at IS NULL
    ''',
    '''
    CREATE TABLE notes (
      uuid TEXT PRIMARY KEY, matn_verse_id TEXT NOT NULL, commentary_block_id TEXT,
      body TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER
    )
    ''',
    '''
    CREATE INDEX ix_notes_verse ON notes (matn_verse_id) WHERE deleted_at IS NULL
    ''',
    '''
    CREATE TABLE activity_log (
      uuid TEXT PRIMARY KEY, at INTEGER NOT NULL,
      kind TEXT NOT NULL CHECK (kind IN ('listen','commentary')),
      from_verse_id TEXT, to_verse_id TEXT, recording_id TEXT, commentary_id TEXT,
      seconds INTEGER
    )
    ''',
    '''
    CREATE INDEX ix_activity_at ON activity_log (at)
    ''',
    '''
    CREATE TABLE verse_listens (
      recording_id TEXT NOT NULL, matn_verse_id TEXT NOT NULL,
      first_completed_at INTEGER NOT NULL, completions INTEGER NOT NULL DEFAULT 1,
      PRIMARY KEY (recording_id, matn_verse_id)
    )
    ''',
    '''
    CREATE TABLE downloads (
      item_id TEXT PRIMARY KEY,
      state TEXT NOT NULL CHECK (state IN ('none','queued','downloading','paused','verifying','ready','failed','update_available')),
      bytes_done INTEGER NOT NULL DEFAULT 0, sha256 TEXT, local_path TEXT, error TEXT, updated_at INTEGER NOT NULL
    )
    ''',
  ],
  // 2 — the history, listening progress and the never-used downloads table go (ADR 0008)
  [
    'DROP TABLE activity_log',
    'DROP TABLE verse_listens',
    'DROP TABLE downloads',
  ],
];

/// The six bookmark colours (features-v3 bookmarks), in the schema's words.
enum BookmarkColor { gold, green, orange, blue, rose, sand }

/// The three bookmark tags: «حفظ», «مراجعة», «إشكال».
enum BookmarkTag { hifz, muraja, ishkal }

class Bookmark {
  final String uuid;
  final int fromVerse;
  final int? toVerse; // null: a single verse
  final BookmarkColor color;
  final BookmarkTag tag;
  final DateTime updatedAt;
  const Bookmark(this.uuid, this.fromVerse, this.toVerse, this.color, this.tag, this.updatedAt);

  int get lastVerse => toVerse ?? fromVerse;
  bool covers(int verse) => fromVerse <= verse && verse <= lastVerse;
}

class Note {
  final String uuid;
  final int verse;
  final String body;
  final DateTime updatedAt;
  const Note(this.uuid, this.verse, this.body, this.updatedAt);
}

String _verseId(int verse) => 'verse:shatibiyyah:$verse';
int _verseNumber(String id) => int.parse(id.split(':').last);

final Random _random = Random.secure();

/// A random (version 4) UUID, so rows merge across devices on restore.
String newUuid() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class UserStore {
  final Database db;
  UserStore._(this.db);

  /// [migrations] is [kUserMigrations] except in tests.
  static Future<UserStore> open({
    required String directory,
    DatabaseFactory? factory,
    String name = 'user.sqlite',
    @visibleForTesting List<List<String>> migrations = kUserMigrations,
  }) async {
    Future<void> migrate(Database db, int from, int to) async {
      for (var v = from; v < to; v++) {
        final batch = db.batch();
        for (final statement in migrations[v]) {
          batch.execute(statement);
        }
        await batch.commit(noResult: true);
      }
    }

    final db = await (factory ?? databaseFactory).openDatabase(
      p.join(directory, name),
      options: OpenDatabaseOptions(
        version: migrations.length,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => migrate(db, 0, version),
        onUpgrade: migrate,
      ),
    );
    return UserStore._(db);
  }


  // ── bookmarks (features-v3 bookmarks) ──
  // One live bookmark per verse or range; deleting sets deleted_at (a tombstone).

  /// Live bookmarks, the most recently changed first; within one millisecond, the
  /// last created first (rowid), not the order of whichever index SQLite scans.
  Future<List<Bookmark>> bookmarks() async => [
        for (final r in await db.rawQuery(
            'SELECT uuid, from_verse_id, to_verse_id, color, tag, updated_at FROM bookmarks '
            'WHERE deleted_at IS NULL ORDER BY updated_at DESC, rowid DESC'))
          Bookmark(
            r['uuid'] as String,
            _verseNumber(r['from_verse_id'] as String),
            r['to_verse_id'] == null ? null : _verseNumber(r['to_verse_id'] as String),
            BookmarkColor.values.byName(r['color'] as String),
            BookmarkTag.values.byName(r['tag'] as String),
            DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
          ),
      ];

  /// Creates or updates the bookmark on [from] (…[to] for a run of verses).
  Future<void> saveBookmark(int from, {int? to, required BookmarkColor color, required BookmarkTag tag, DateTime? at}) async {
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final toId = to == null || to == from ? null : _verseId(to);
    final updated = await db.rawUpdate(
      "UPDATE bookmarks SET color = ?, tag = ?, updated_at = ? "
      "WHERE from_verse_id = ? AND ifnull(to_verse_id, '') = ifnull(?, '') AND deleted_at IS NULL",
      [color.name, tag.name, now, _verseId(from), toId],
    );
    if (updated == 0) {
      await db.insert('bookmarks', {
        'uuid': newUuid(),
        'from_verse_id': _verseId(from),
        'to_verse_id': toId,
        'color': color.name,
        'tag': tag.name,
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  Future<void> deleteBookmark(int from, {int? to, DateTime? at}) {
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    return db.rawUpdate(
      "UPDATE bookmarks SET deleted_at = ?, updated_at = ? "
      "WHERE from_verse_id = ? AND ifnull(to_verse_id, '') = ifnull(?, '') AND deleted_at IS NULL",
      [now, now, _verseId(from), to == null || to == from ? null : _verseId(to)],
    );
  }

  /// Changes the colour and tag of the bookmark [uuid] (its verses stay).
  Future<void> updateBookmark(String uuid, {required BookmarkColor color, required BookmarkTag tag, DateTime? at}) =>
      db.rawUpdate(
        'UPDATE bookmarks SET color = ?, tag = ?, updated_at = ? WHERE uuid = ? AND deleted_at IS NULL',
        [color.name, tag.name, (at ?? DateTime.now()).millisecondsSinceEpoch, uuid],
      );

  /// Deletes the bookmark [uuid]: a tombstone, so «تراجع» can bring it back.
  Future<void> deleteBookmarkById(String uuid, {DateTime? at}) {
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    return db.rawUpdate(
      'UPDATE bookmarks SET deleted_at = ?, updated_at = ? WHERE uuid = ? AND deleted_at IS NULL',
      [now, now, uuid],
    );
  }

  /// «تراجع»: the deleted bookmark [uuid] is live again, with its uuid, verses,
  /// colour and tag. False when another live bookmark has taken its verses since.
  Future<bool> restoreBookmark(String uuid, {DateTime? at}) async =>
      await db.rawUpdate(
        'UPDATE bookmarks SET deleted_at = NULL, updated_at = ? '
        'WHERE uuid = ? AND deleted_at IS NOT NULL AND NOT EXISTS ('
        "SELECT 1 FROM bookmarks live WHERE live.deleted_at IS NULL AND live.from_verse_id = bookmarks.from_verse_id "
        "AND ifnull(live.to_verse_id, '') = ifnull(bookmarks.to_verse_id, ''))",
        [(at ?? DateTime.now()).millisecondsSinceEpoch, uuid],
      ) ==
      1;

  // ── notes (features-v3 verse-notes): one per verse; saving an empty one deletes it ──

  /// Live notes, the most recently changed first (the last created, within one millisecond).
  Future<List<Note>> notes() async => [
        for (final r in await db.rawQuery(
            'SELECT uuid, matn_verse_id, body, updated_at FROM notes WHERE deleted_at IS NULL ORDER BY updated_at DESC, rowid DESC'))
          Note(r['uuid'] as String, _verseNumber(r['matn_verse_id'] as String), r['body'] as String,
              DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int)),
      ];

  Future<void> saveNote(int verse, String body, {DateTime? at}) async {
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final text = body.trim();
    if (text.isEmpty) {
      await db.rawUpdate(
        'UPDATE notes SET deleted_at = ?, updated_at = ? WHERE matn_verse_id = ? AND deleted_at IS NULL',
        [now, now, _verseId(verse)],
      );
      return;
    }
    final updated = await db.rawUpdate(
      'UPDATE notes SET body = ?, updated_at = ? WHERE matn_verse_id = ? AND deleted_at IS NULL',
      [text, now, _verseId(verse)],
    );
    if (updated == 0) {
      await db.insert('notes', {
        'uuid': newUuid(),
        'matn_verse_id': _verseId(verse),
        'body': text,
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  /// Deletes the note [uuid]: a tombstone, so «تراجع» can bring it back.
  Future<void> deleteNoteById(String uuid, {DateTime? at}) {
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    return db.rawUpdate(
      'UPDATE notes SET deleted_at = ?, updated_at = ? WHERE uuid = ? AND deleted_at IS NULL',
      [now, now, uuid],
    );
  }

  /// «تراجع»: the deleted note [uuid] is live again, with its uuid and text. False
  /// when its verse has a live note since: that one stays, this one stays deleted.
  Future<bool> restoreNote(String uuid, {DateTime? at}) async =>
      await db.rawUpdate(
        'UPDATE notes SET deleted_at = NULL, updated_at = ? '
        'WHERE uuid = ? AND deleted_at IS NOT NULL AND NOT EXISTS ('
        'SELECT 1 FROM notes live WHERE live.deleted_at IS NULL AND live.matn_verse_id = notes.matn_verse_id)',
        [(at ?? DateTime.now()).millisecondsSinceEpoch, uuid],
      ) ==
      1;

  Future<void> close() => db.close();
}
