// lib/data/backup.dart — «نسخ احتياطي واستعادة» (features-v3 backup-and-sync, U-03).
//
// A JSON envelope with the user's bookmarks and notes, and the reader settings:
//   {format: "shatibiyyah-backup", version: 2, exported_at, settings: {…},
//    bookmarks: […], notes: […]}
// Version 1 also carried the history and the listened verses (ADR 0008 removed
// both): a v1 file still restores, and those two lists are ignored.
// Restoring merges, it never wipes:
// - bookmarks and notes: union by uuid, the newest updated_at wins, tombstones
//   (deleted_at) travel both ways. One verse (or range) keeps one live bookmark
//   and one live note: of two live rows on it, the older becomes a tombstone (so
//   restoring the same file twice changes nothing);
// - a setting is restored only where this device has none of its own.
// Audio and the books are not in it: they come with the app or are downloaded.
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../services/preferences_service.dart';
import 'user_store.dart';

const String kBackupFormat = 'shatibiyyah-backup';
const int kBackupVersion = 2;

/// The preferences that travel with a backup: reader settings, not device state
/// (downloads, the chosen recording, the tour).
bool isBackupSetting(String key) =>
    const {
      'v2.theme',
      'v2.reader.view',
      'v2.text.scale',
      'v2.repeat.verse',
      'v2.repeat.section',
      'v2.gap_ms',
      'v2.titles.play',
      'v2.search.recent',
    }.contains(key) ||
    key.startsWith('v2.speed.');

class BackupError implements Exception {
  final String message; // Arabic, shown as is
  const BackupError(this.message);
  @override
  String toString() => 'BackupError: $message';
}

/// What a restore added or changed.
class MergeReport {
  int bookmarks = 0;
  int notes = 0;
  final Set<String> settings = {};
  int get total => bookmarks + notes + settings.length;
}

Future<Map<String, Object?>> exportBackup(UserStore store, Prefs prefs, {DateTime? now}) async {
  final db = store.db;
  return {
    'format': kBackupFormat,
    'version': kBackupVersion,
    'exported_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
    'settings': {
      for (final k in prefs.keys.where(isBackupSetting).toList()..sort()) k: ?prefs.getString(k),
    },
    'bookmarks': await db.query('bookmarks', orderBy: 'created_at'),
    'notes': await db.query('notes', columns: _noteColumns, orderBy: 'created_at'),
  };
}

String encodeBackup(Map<String, Object?> backup) => const JsonEncoder.withIndent(' ').convert(backup);

/// Reads a backup file's text; throws [BackupError] when it is not one this app can restore.
Map<String, Object?> decodeBackup(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    throw const BackupError('الملف ليس نسخة احتياطية صالحة');
  }
  if (json is! Map<String, Object?> || json['format'] != kBackupFormat) {
    throw const BackupError('الملف ليس نسخة احتياطية من تيسير الشاطبية');
  }
  final version = json['version'];
  if (version is! int || version > kBackupVersion) {
    throw const BackupError('النسخة من إصدار أحدث من التطبيق: حدّثه ثم أعد المحاولة');
  }
  return json;
}

Future<MergeReport> mergeBackup(UserStore store, Prefs prefs, Map<String, Object?> backup) async {
  final report = MergeReport();
  final bookmarks = _rows(backup['bookmarks'], _bookmarkValid);
  final notes = _rows(backup['notes'], _noteValid);

  await store.db.transaction((tx) async {
    report.bookmarks = await _mergeLive(tx, 'bookmarks', bookmarks, _bookmarkColumns,
        "from_verse_id = ? AND ifnull(to_verse_id, '') = ifnull(?, '')", (r) => [r['from_verse_id'], r['to_verse_id']]);
    report.notes = await _mergeLive(
        tx, 'notes', notes, _noteColumns, 'matn_verse_id = ?', (r) => [r['matn_verse_id']]);
  });

  final settings = backup['settings'];
  if (settings is Map) {
    for (final MapEntry(:key, :value) in settings.entries) {
      if (key is String && value is String && isBackupSetting(key) && !prefs.has(key)) {
        prefs.setString(key, value);
        report.settings.add(key);
      }
    }
  }
  return report;
}

const _bookmarkColumns = ['uuid', 'from_verse_id', 'to_verse_id', 'color', 'tag', 'created_at', 'updated_at', 'deleted_at'];
const _noteColumns = ['uuid', 'matn_verse_id', 'commentary_block_id', 'body', 'created_at', 'updated_at', 'deleted_at'];

/// Bookmarks or notes: newest updated_at first wins per uuid; one live row per [keyWhere].
Future<int> _mergeLive(Transaction tx, String table, List<Map<String, Object?>> incoming, List<String> columns,
    String keyWhere, List<Object?> Function(Map<String, Object?>) keyArgs) async {
  var changed = 0;
  // Oldest first, so a later change to the same verse wins as it did on its device.
  incoming.sort((a, b) => (a['updated_at'] as int).compareTo(b['updated_at'] as int));
  for (final r in incoming) {
    final row = {for (final c in columns) c: r[c]};
    final local = await tx.query(table, columns: ['updated_at'], where: 'uuid = ?', whereArgs: [row['uuid']]);
    if (local.isNotEmpty && (local.first['updated_at'] as int) >= (row['updated_at'] as int)) continue;

    if (row['deleted_at'] == null) {
      // Another live row on the same verse: the newer one stays live.
      final rivals = await tx.query(table,
          columns: ['uuid', 'updated_at'],
          where: '$keyWhere AND deleted_at IS NULL AND uuid != ?',
          whereArgs: [...keyArgs(row), row['uuid']]);
      for (final rival in rivals) {
        final rivalAt = rival['updated_at'] as int;
        if (rivalAt > (row['updated_at'] as int)) {
          row['deleted_at'] = rivalAt; // the incoming one lost
        } else {
          await tx.update(table, {'deleted_at': row['updated_at'], 'updated_at': row['updated_at']},
              where: 'uuid = ?', whereArgs: [rival['uuid']]);
        }
      }
    }
    if (local.isEmpty) {
      await tx.insert(table, row);
    } else {
      await tx.update(table, row, where: 'uuid = ?', whereArgs: [row['uuid']]);
    }
    changed++;
  }
  return changed;
}

List<Map<String, Object?>> _rows(Object? list, bool Function(Map<String, Object?>) valid) {
  if (list == null) return [];
  if (list is! List) throw const BackupError('الملف تالف: قائمة غير صالحة');
  final rows = <Map<String, Object?>>[];
  for (final r in list) {
    if (r is! Map<String, Object?> || !valid(r)) throw const BackupError('الملف تالف: سجل غير صالح');
    rows.add(r);
  }
  return rows;
}

final RegExp _verseId = RegExp(r'^verse:shatibiyyah:\d+$');
bool _str(Object? v) => v is String && v.isNotEmpty;
bool _verse(Object? v) => v is String && _verseId.hasMatch(v);
bool _optVerse(Object? v) => v == null || _verse(v);
bool _optInt(Object? v) => v == null || v is int;

bool _bookmarkValid(Map<String, Object?> r) =>
    _str(r['uuid']) &&
    _verse(r['from_verse_id']) &&
    _optVerse(r['to_verse_id']) &&
    BookmarkColor.values.any((c) => c.name == r['color']) &&
    BookmarkTag.values.any((t) => t.name == r['tag']) &&
    r['created_at'] is int &&
    r['updated_at'] is int &&
    _optInt(r['deleted_at']);

bool _noteValid(Map<String, Object?> r) =>
    _str(r['uuid']) &&
    _verse(r['matn_verse_id']) &&
    r['body'] is String &&
    (r['commentary_block_id'] == null || r['commentary_block_id'] is String) &&
    r['created_at'] is int &&
    r['updated_at'] is int &&
    _optInt(r['deleted_at']);
