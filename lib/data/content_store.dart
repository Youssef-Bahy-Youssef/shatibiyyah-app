// lib/data/content_store.dart — the bundled, read-only content database.
//
// content.sqlite is written by `spd app-snapshot` in shatibiyyah-data, next to a
// small content.json manifest (schema version, content hash, size). SQLite cannot
// open a Flutter asset in place, so the database is copied once into the app
// support directory, under a name that carries its content hash; a new app build
// with new content copies again, and older copies are deleted. The app never
// writes to it — personal data lives in user.sqlite.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// The snapshot schema this build of the app understands.
/// 2: readers and rumuz (migration 009).
const int kContentSchemaVersion = 2;

const String kContentAsset = 'assets/content/content.sqlite';
const String kManifestAsset = 'assets/content/content.json';

class ContentError implements Exception {
  final String message;
  const ContentError(this.message);
  @override
  String toString() => 'ContentError: $message';
}

class ContentManifest {
  final int schemaVersion;
  final String contentSha256;
  final int bytes;
  const ContentManifest(this.schemaVersion, this.contentSha256, this.bytes);

  factory ContentManifest.fromJson(Map<String, dynamic> j) => ContentManifest(
        (j['schema_version'] as num).toInt(),
        j['content_sha256'] as String,
        (j['bytes'] as num).toInt(),
      );

  /// File name of the installed copy: changes whenever the content does.
  String get fileName => 'content-${contentSha256.substring(0, 16)}.sqlite';
}

/// Loads an asset's bytes (rootBundle.load in the app; a file read in tests).
typedef AssetLoader = Future<ByteData> Function(String key);

class ContentStore {
  final Database db;
  final ContentManifest manifest;
  ContentStore._(this.db, this.manifest);

  /// Opens the installed copy of the bundled snapshot, installing it first if needed.
  static Future<ContentStore> open({
    required AssetLoader loadAsset,
    required Directory supportDir,
    DatabaseFactory? factory,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final manifestBytes = await loadAsset(kManifestAsset);
    final manifest = ContentManifest.fromJson(
      jsonDecode(utf8.decode(manifestBytes.buffer.asUint8List(
        manifestBytes.offsetInBytes,
        manifestBytes.lengthInBytes,
      ))) as Map<String, dynamic>,
    );
    if (manifest.schemaVersion != kContentSchemaVersion) {
      throw ContentError('bundled content schema ${manifest.schemaVersion}, app expects $kContentSchemaVersion');
    }

    final dir = Directory(p.join(supportDir.path, 'content'));
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, manifest.fileName));
    if (!await target.exists() || await target.length() != manifest.bytes) {
      final data = await loadAsset(kContentAsset);
      final staging = File('${target.path}.part');
      await staging.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await staging.rename(target.path);
    }
    // Remove copies of older content.
    await for (final entry in dir.list()) {
      if (entry is File && p.basename(entry.path) != manifest.fileName) {
        await entry.delete();
      }
    }

    final db = await dbFactory.openDatabase(
      target.path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: true),
    );
    final info = await db.rawQuery('SELECT schema_version, content_sha256 FROM snapshot_info WHERE id = 1');
    if (info.isEmpty ||
        info.first['schema_version'] != kContentSchemaVersion ||
        info.first['content_sha256'] != manifest.contentSha256) {
      await db.close();
      await target.delete();
      throw const ContentError('installed content does not match its manifest; it will be recopied');
    }
    return ContentStore._(db, manifest);
  }

  Future<void> close() => db.close();
}
