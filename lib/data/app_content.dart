// lib/data/app_content.dart — everything read from the bundled content, opened once at boot.
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/playback_windows.dart';
import 'benefits_repository.dart';
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
  final BenefitsRepository benefits;

  /// Recordings whose cues cannot be played (a verse without a cue, or cues out of
  /// order): offered as «غير صالحة», never played. Found once at open (F-41).
  final Set<String> _unusable = {};

  AppContent._(this.store, this.matn, this.layout, this.books, this.recordings, this.rumuz, this.benefits);

  /// Whether [recording] can be played: every verse has a cue, in order.
  bool isUsable(Recording recording) => !_unusable.contains(recording.id);

  /// [windowsFor] for a usable recording; null for one that is not.
  Future<PlaybackWindows?> windowsOrNull(Recording recording) async =>
      isUsable(recording) ? windowsFor(recording) : null;

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
    final content = AppContent._(
      store,
      await MatnRepository.load(store.db),
      await LayoutRepository.load(store.db),
      await CommentaryRepository.load(store.db),
      await RecordingRepository.load(store.db),
      await RumuzRepository.load(store.db),
      await BenefitsRepository.load(store.db),
    );
    for (final r in content.recordings.recordings) {
      try {
        await content.windowsFor(r);
      } on ArgumentError {
        content._unusable.add(r.id);
      }
    }
    return content;
  }

  /// Verse and chapter windows of [recording] (spoken titles marked disputed are ignored).
  Future<PlaybackWindows> windowsFor(Recording recording) async {
    final announcements = await recordings.announcements(recording.id);
    return PlaybackWindows(
      cues: await recordings.cues(recording.id, matn.lastVerse),
      // The file that is played is the delivery file (F-40).
      durationMs: recording.delivery?.durationMs ?? recording.durationMs,
      titleAtFirstVerse: {
        for (final e in announcements.entries)
          if (!e.value.disputed) matn.chapter(e.key).fromVerse: e.value.startMs,
      },
    );
  }
}
