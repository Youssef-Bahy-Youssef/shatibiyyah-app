// lib/data/recording_repository.dart — reciters, recordings and their timings.
//
// Timings are integer milliseconds on the recording's own timebase. There are no
// stored verse ends: a verse plays until the next cue, or an intervening
// non-disputed chapter announcement, or the end of the file (V2 E8). That rule
// lives in the playback plan, not here.
import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

class Recording {
  final String id;
  final String slug;
  final String reciterId;
  final String reciterName;
  final String title;
  final String? attribution;
  final bool isDefault;
  final int durationMs;
  final int audioBytes;
  final String audioSha256;
  final String timebaseStatus;
  final int? timebaseOffsetMs;
  final String? sampleAssetPath;
  final String? licenseNote;
  final DeliveryFile? delivery;
  const Recording(this.id, this.slug, this.reciterId, this.reciterName, this.title, this.attribution,
      this.isDefault, this.durationMs, this.audioBytes, this.audioSha256, this.timebaseStatus, this.timebaseOffsetMs, this.sampleAssetPath,
      this.licenseNote, this.delivery);
}

class DeliveryFile {
  final String sha256;
  final int bytes;
  final int durationMs;
  final String contentType;
  final List<String> urls;
  const DeliveryFile(this.sha256, this.bytes, this.durationMs, this.contentType, this.urls);
}

class Announcement {
  final int startMs;
  final bool disputed;
  const Announcement(this.startMs, this.disputed);
}

class RecordingRepository {
  final Database db;
  final List<Recording> recordings;
  RecordingRepository._(this.db, this.recordings);

  static Future<RecordingRepository> load(Database db) async {
    final rows = await db.rawQuery(
        'SELECT r.id, r.slug, r.reciter_id, s.name AS reciter_name, r.title, r.attribution, r.is_default, '
        'r.duration_ms, r.audio_bytes, r.audio_sha256, r.timebase_status, r.timebase_offset_ms, r.sample_asset_path, r.license_note, '
        'f.delivery_sha256, f.delivery_bytes, f.duration_ms AS delivery_duration_ms, f.content_type, f.urls_json '
        'FROM recordings r JOIN reciters s ON s.id = r.reciter_id '
        'LEFT JOIN recording_files f ON f.recording_id = r.id ORDER BY r.is_default DESC, r.id');
    return RecordingRepository._(db, [
      for (final r in rows)
        Recording(
          r['id'] as String,
          r['slug'] as String,
          r['reciter_id'] as String,
          r['reciter_name'] as String,
          r['title'] as String,
          r['attribution'] as String?,
          r['is_default'] == 1,
          r['duration_ms'] as int,
          r['audio_bytes'] as int,
          r['audio_sha256'] as String,
          r['timebase_status'] as String,
          r['timebase_offset_ms'] as int?,
          r['sample_asset_path'] as String?,
          r['license_note'] as String?,
          r['delivery_sha256'] == null
              ? null
              : DeliveryFile(
                  r['delivery_sha256'] as String,
                  r['delivery_bytes'] as int,
                  r['delivery_duration_ms'] as int,
                  r['content_type'] as String,
                  (jsonDecode(r['urls_json'] as String) as List).cast<String>(),
                ),
        ),
    ]);
  }

  /// Where a recording's audio lives on the device (the download manager writes here).
  static String localFileName(Recording r) => 'audio/${r.slug}.mp3';

  Recording get defaultRecording => recordings.firstWhere((r) => r.isDefault, orElse: () => recordings.first);

  Recording byId(String id) => recordings.firstWhere((r) => r.id == id);

  /// Start of each verse in ms, indexed by verse number (index 0 unused, -1 = no cue).
  Future<Int32List> cues(String recordingId, int lastVerse) async {
    final cues = Int32List(lastVerse + 1)..fillRange(0, lastVerse + 1, -1);
    for (final r in await db.rawQuery(
        'SELECT v.verse_number, t.start_ms FROM verse_timings t JOIN matn_verses v ON v.id = t.matn_verse_id '
        'WHERE t.recording_id = ?',
        [recordingId])) {
      cues[r['verse_number'] as int] = r['start_ms'] as int;
    }
    return cues;
  }

  /// Spoken chapter titles of a recording, by chapter id.
  Future<Map<String, Announcement>> announcements(String recordingId) async {
    return {
      for (final r in await db.rawQuery(
          'SELECT chapter_id, start_ms, status FROM chapter_announcements WHERE recording_id = ?',
          [recordingId]))
        r['chapter_id'] as String: Announcement(r['start_ms'] as int, r['status'] == 'disputed'),
    };
  }
}
