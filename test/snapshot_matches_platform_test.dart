// The bundled snapshot against the data platform it is built from (ADR 0001, F-01).
// For each recording, assets/content/content.sqlite must declare the delivery
// file that shatibiyyah-data/config/recordings/<slug>.yaml declares: the same
// SHA-256, size and mirrors in the same order. Skipped when the platform is not
// checked out beside the app.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The platform's recording configs: `../shatibiyyah-data` in the Taysir
/// workspace, or one level deeper when the workspace repository itself is
/// checked out as `shatibiyyah-data`.
Directory? _recordingsDir() {
  for (final path in const [
    '../shatibiyyah-data/config/recordings',
    '../shatibiyyah-data/shatibiyyah-data/config/recordings',
  ]) {
    final dir = Directory(path);
    if (dir.existsSync()) return dir;
  }
  return null;
}

class _Delivery {
  _Delivery(this.sha256, this.bytes, this.urls);
  final String sha256;
  final int bytes;
  final List<String> urls;
}

/// Reads `recording.slug` and the `delivery:` block of one recording YAML.
/// The files are flat and written by hand, so a line reader is enough.
(String, _Delivery) _readYaml(File file) {
  String? slug;
  String? section;
  String? sha;
  int? bytes;
  final urls = <String>[];
  var inUrls = false;
  for (final raw in file.readAsLinesSync()) {
    final line = raw.replaceFirst(RegExp(r'\s+#.*$'), '');
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    if (!line.startsWith(' ')) {
      section = line.replaceFirst(RegExp(r':.*$'), '');
      inUrls = false;
      continue;
    }
    final trimmed = line.trim();
    if (section == 'recording' && trimmed.startsWith('slug:')) {
      slug = trimmed.substring(5).trim();
    }
    if (section != 'delivery') continue;
    if (trimmed.startsWith('- ') && inUrls) {
      urls.add(trimmed.substring(2).trim());
      continue;
    }
    inUrls = trimmed == 'urls:';
    if (trimmed.startsWith('sha256:')) sha = trimmed.substring(7).trim();
    if (trimmed.startsWith('bytes:')) bytes = int.parse(trimmed.substring(6).trim());
  }
  if (slug == null || sha == null || bytes == null || urls.isEmpty) {
    throw FormatException('no slug or delivery block in ${file.path}');
  }
  return (slug, _Delivery(sha, bytes, urls));
}

void main() {
  final dir = _recordingsDir();

  test('every recording declares the platform\'s delivery file', () async {
    sqfliteFfiInit();
    final yamls = dir!.listSync().whereType<File>().where((f) => f.path.endsWith('.yaml')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final expected = Map.fromEntries(yamls.map((f) {
      final (slug, delivery) = _readYaml(f);
      return MapEntry(slug, delivery);
    }));

    final db = await databaseFactoryFfi.openDatabase(File('assets/content/content.sqlite').absolute.path,
        options: OpenDatabaseOptions(readOnly: true));
    try {
      final rows = await db.rawQuery(
          'SELECT r.slug, f.delivery_sha256, f.delivery_bytes, f.urls_json '
          'FROM recordings r JOIN recording_files f ON f.recording_id = r.id ORDER BY r.slug');
      expect(rows.map((r) => r['slug']), unorderedEquals(expected.keys));
      for (final row in rows) {
        final want = expected[row['slug']]!;
        final reason = '${row['slug']}: run `spd app-snapshot` in shatibiyyah-data';
        expect(row['delivery_sha256'], want.sha256, reason: reason);
        expect(row['delivery_bytes'], want.bytes, reason: reason);
        expect(jsonDecode(row['urls_json']! as String), want.urls, reason: reason);
      }
    } finally {
      await db.close();
    }
  }, skip: dir == null ? 'shatibiyyah-data is not checked out beside the app' : false);
}
