// lib/data/app_content.dart — everything read from the bundled content, opened once at boot.
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/playback_windows.dart';
import 'commentary_repository.dart';
import 'content_store.dart';
import 'layout_repository.dart';
import 'matn_repository.dart';
import 'recording_repository.dart';
import 'rumuz_repository.dart';

class AppContent {
  final ContentStore store;
  final MatnRepository matn;
  final LayoutRepository layout;
  final CommentaryRepository books;
  final RecordingRepository recordings;
  final RumuzRepository rumuz;

  AppContent._(this.store, this.matn, this.layout, this.books, this.recordings, this.rumuz);

  /// Opens the bundled snapshot (installing it on first run) and loads the repositories.
  static Future<AppContent> open({
    AssetLoader? loadAsset,
    Directory? supportDir,
    DatabaseFactory? factory,
  }) async {
    final store = await ContentStore.open(
      loadAsset: loadAsset ?? rootBundle.load,
      supportDir: supportDir ?? await getApplicationSupportDirectory(),
      factory: factory,
    );
    return AppContent._(
      store,
      await MatnRepository.load(store.db),
      await LayoutRepository.load(store.db),
      await CommentaryRepository.load(store.db),
      await RecordingRepository.load(store.db),
      await RumuzRepository.load(store.db),
    );
  }

  /// Verse and chapter windows of [recording] (spoken titles marked disputed are ignored).
  Future<PlaybackWindows> windowsFor(Recording recording) async {
    final announcements = await recordings.announcements(recording.id);
    return PlaybackWindows(
      cues: await recordings.cues(recording.id, matn.lastVerse),
      durationMs: recording.durationMs,
      titleAtFirstVerse: {
        for (final e in announcements.entries)
          if (!e.value.disputed) matn.chapter(e.key).fromVerse: e.value.startMs,
      },
    );
  }
}
