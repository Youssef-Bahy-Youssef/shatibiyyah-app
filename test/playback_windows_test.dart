// PlaybackWindows against V2's SQL oracle (Q4 verse windows, Q6 chapter starts),
// run on the bundled snapshot for every verse and chapter of every recording.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/data/content_store.dart';
import 'package:shatibiyyah/data/matn_repository.dart';
import 'package:shatibiyyah/data/recording_repository.dart';
import 'package:shatibiyyah/domain/playback_windows.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _q4 = '''
SELECT v.verse_number, t.start_ms,
  (SELECT min(t2.start_ms) FROM verse_timings t2 WHERE t2.recording_id = t.recording_id AND t2.start_ms > t.start_ms) AS next_cue_ms,
  (SELECT a.start_ms FROM chapter_announcements a JOIN chapters c ON c.id = a.chapter_id
    WHERE a.recording_id = t.recording_id AND c.from_verse = v.verse_number + 1
      AND a.status <> 'disputed' AND a.start_ms > t.start_ms) AS next_announcement_ms,
  r.duration_ms
FROM verse_timings t JOIN matn_verses v ON v.id = t.matn_verse_id JOIN recordings r ON r.id = t.recording_id
WHERE t.recording_id = ? ORDER BY v.verse_number''';

const _q6 = '''
SELECT c.id, c.from_verse, coalesce(
  (SELECT a.start_ms FROM chapter_announcements a WHERE a.recording_id = ? AND a.chapter_id = c.id
     AND a.status <> 'disputed' AND a.start_ms <= f.start_ms), f.start_ms) AS range_start_ms
FROM chapters c JOIN matn_verses fv ON fv.verse_number = c.from_verse
JOIN verse_timings f ON f.matn_verse_id = fv.id AND f.recording_id = ?
ORDER BY c.order_index''';

Future<PlaybackWindows> windowsFor(RecordingRepository recs, MatnRepository matn, Recording r) async {
  final announcements = await recs.announcements(r.id);
  return PlaybackWindows(
    cues: await recs.cues(r.id, matn.lastVerse),
    durationMs: r.durationMs,
    titleAtFirstVerse: {
      for (final e in announcements.entries)
        if (!e.value.disputed) matn.chapter(e.key).fromVerse: e.value.startMs,
    },
  );
}

void main() {
  sqfliteFfiInit();
  late Directory support;
  late ContentStore store;
  late MatnRepository matn;
  late RecordingRepository recs;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('windows_test');
    store = await ContentStore.open(
      loadAsset: (key) async => ByteData.sublistView(await File(key).readAsBytes()),
      supportDir: support,
      factory: databaseFactoryFfi,
    );
    matn = await MatnRepository.load(store.db);
    recs = await RecordingRepository.load(store.db);
  });

  tearDownAll(() async {
    await store.close();
    await support.delete(recursive: true);
  });

  test('every verse window equals the Q4 oracle, for every recording', () async {
    for (final r in recs.recordings) {
      final w = await windowsFor(recs, matn, r);
      final rows = await store.db.rawQuery(_q4, [r.id]);
      expect(rows, hasLength(1173));
      for (final row in rows) {
        final v = row['verse_number'] as int;
        final nextCue = row['next_cue_ms'] as int?;
        final title = row['next_announcement_ms'] as int?;
        final oracleEnd = (title != null && nextCue != null && title < nextCue) ? title : nextCue ?? row['duration_ms'] as int;
        expect(w.cue(v), row['start_ms'], reason: '${r.slug} verse $v start');
        expect(w.verseEnd(v), oracleEnd, reason: '${r.slug} verse $v end');
      }
    }
  });

  test('every chapter start equals the Q6 oracle, for every recording', () async {
    for (final r in recs.recordings) {
      final w = await windowsFor(recs, matn, r);
      final rows = await store.db.rawQuery(_q6, [r.id, r.id]);
      expect(rows, hasLength(78));
      for (final row in rows) {
        expect(w.chapterStart(row['from_verse'] as int), row['range_start_ms'], reason: '${r.slug} ${row['id']}');
      }
    }
  });

  test('titles off: a chapter starts at its first verse', () async {
    final w = await windowsFor(recs, matn, recs.defaultRecording);
    expect(w.chapterStart(226, withTitle: false), w.cue(226));
    expect(w.chapterStart(226), lessThan(w.cue(226)));
  });

  test('seek pre-roll: early by the pre-roll, but not into a spoken title', () async {
    final w = await windowsFor(recs, matn, recs.defaultRecording);
    expect(w.seekStart(229, preRollMs: 250), w.cue(229) - 250); // mid-chapter
    expect(w.titleFollows(225), isTrue); // chapter 11 starts at 226 with a title
    expect(w.seekStart(226, preRollMs: 250), w.cue(226));
    expect(w.seekStart(1, preRollMs: 250), w.cue(1) - 250);
  });

  test('what is playing at a position (V2 Q5)', () async {
    final w = await windowsFor(recs, matn, recs.defaultRecording);
    expect(w.at(w.cue(229) + 100), const PlayingAt(229));
    expect(w.at(w.verseEnd(225) + 10), const PlayingAt(226, inTitle: true));
    expect(w.at(w.cue(226)), const PlayingAt(226));
    expect(w.at(w.durationMs - 1), const PlayingAt(1173));
  });
}
