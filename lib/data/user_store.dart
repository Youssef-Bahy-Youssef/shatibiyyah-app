// lib/data/user_store.dart — the student's own data, in user.sqlite (read-write).
//
// Kept apart from content.sqlite so content updates never touch it. Every row is
// keyed by the content's stable IDs (verse:shatibiyyah:226, recording:…), and
// synced-style fields (uuid, updated_at, deleted_at tombstones) are there from the
// start so backup/restore can merge rather than overwrite (migration plan U-03).
// Schema changes are numbered migrations applied in order by PRAGMA user_version.
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Migration n is at index n-1; never edit one that has shipped, add a new one.
const List<String> kUserMigrations = [
  // 1 — bookmarks, notes, history, played-through verses, downloads (plan 02 §5.2, rev 3)
  '''
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
  ''',
];

class UserStore {
  final Database db;
  UserStore._(this.db);

  static Future<UserStore> open({required String directory, DatabaseFactory? factory, String name = 'user.sqlite'}) async {
    final db = await (factory ?? databaseFactory).openDatabase(
      p.join(directory, name),
      options: OpenDatabaseOptions(
        version: kUserMigrations.length,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _migrate(db, 0, version),
        onUpgrade: _migrate,
      ),
    );
    return UserStore._(db);
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    for (var v = from; v < to; v++) {
      final batch = db.batch();
      for (final statement in kUserMigrations[v].split(';')) {
        if (statement.trim().isNotEmpty) batch.execute(statement);
      }
      await batch.commit(noResult: true);
    }
  }

  /// Records that [verse] of [recordingId] was played through (idempotent per verse).
  Future<void> recordVerseListened(String recordingId, int verse, {DateTime? at}) => db.rawInsert(
        'INSERT INTO verse_listens (recording_id, matn_verse_id, first_completed_at) VALUES (?, ?, ?) '
        'ON CONFLICT (recording_id, matn_verse_id) DO UPDATE SET completions = completions + 1',
        [recordingId, 'verse:shatibiyyah:$verse', (at ?? DateTime.now()).millisecondsSinceEpoch],
      );

  /// Verse numbers played through with any recording.
  Future<Set<int>> listenedVerses() async => {
        for (final r in await db.rawQuery('SELECT DISTINCT matn_verse_id FROM verse_listens'))
          int.parse((r['matn_verse_id'] as String).split(':').last),
      };

  Future<void> close() => db.close();
}
