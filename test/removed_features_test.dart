// The features removed from the app have no entry point left anywhere in lib/:
// - plan rev. 2 (P4): «اختبار» (quiz), «تفكيك البيت», «خلاصة القراءات»;
// - item 2.1 (ADR 0008): «فائدة اليوم», per-chapter listening progress and the
//   history log «السجل». No route, string, preference key or table of them
//   survives. Only two places may still name them: the migrations list in
//   lib/data/user_store.dart (v1 created the tables, v2 drops them), and the
//   one-time clean-up of what they left on a device (lib/app/retired_features.dart).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/app/routes.dart';
import 'package:shatibiyyah/data/user_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Every line of lib/*.dart, minus the places allowed to name a removed feature.
List<(String, int, String)> _libLines() {
  final out = <(String, int, String)>[];
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart') || f.path.endsWith('retired_features.dart')) continue;
    var text = f.readAsStringSync();
    if (f.path.endsWith('user_store.dart')) {
      text = text.replaceFirst(RegExp(r'const List<String> kUserMigrations = \[.*?\n\];', dotAll: true), '');
    }
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      out.add((f.path, i + 1, lines[i]));
    }
  }
  return out;
}

List<String> _hits(RegExp pattern) => [
      for (final (path, line, text) in _libLines())
        if (pattern.hasMatch(text)) '$path:$line: ${text.trim()}',
    ];

void main() {
  test('no «اختبار», «تفكيك البيت» or «خلاصة القراءات» in lib/', () {
    expect(_hits(RegExp('اختبار|تفكيك البيت|خلاصة القراءات')), isEmpty);
  });

  test('no «فائدة اليوم»: no string, repository, preference key or notification', () {
    expect(File('lib/data/benefits_repository.dart').existsSync(), isFalse);
    expect(_hits(RegExp(r'فائدة|الخلاصة|[Bb]enefit|v2\.reminders\.benefit')), isEmpty);
  });

  test('no listening progress: no verse_listens, played-through hook, index bars or ✓', () {
    expect(
      _hits(RegExp(r'verse_listens|onVerseCompleted|listenRecorder|recordListened|listenedVerses|'
          r'recordVerseListened|chapterFinished|chap_prog|chapProg|سماع')),
      isEmpty,
    );
  });

  test('no history «السجل»: no tab, activity_log writer or onRead hook', () {
    expect(_hits(RegExp(r'السجل|activity_log|logListening|logCommentary|ActivityKind|onRead\b')), isEmpty);
  });

  test('no route leads to a removed feature', () {
    for (final r in AppRoute.values) {
      expect(r.label, isNot(matches(RegExp('السجل|فائدة|سماع'))));
    }
  });

  test('a new user database has none of the removed tables', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('removed_features');
    addTearDown(() => dir.delete(recursive: true));
    final store = await UserStore.open(directory: dir.path, factory: databaseFactoryFfi);
    addTearDown(store.close);
    final tables = {
      for (final r in await store.db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'")) r['name'],
    };
    expect(tables, containsAll(['bookmarks', 'notes']));
    expect(tables.intersection({'activity_log', 'verse_listens', 'downloads'}), isEmpty);
  });
}
