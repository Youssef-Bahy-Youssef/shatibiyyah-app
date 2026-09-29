// lib/data/legacy_adapter.dart — feeds today's screens from content.sqlite.
//
// The existing reader (AppController, AudioEngine, PageViewer, SyncController)
// was written against the PWA's JSON files. Until P4 replaces those screens, this
// adapter builds the same objects from the repositories, so they now run on the
// canonical data: 78 chapters (the النور duplicate merged, no stretched ranges),
// the snapshot's page regions, the reviewed cues of the selected recording, and
// chapter starts from the V2 window rule (a chapter starts at its spoken title).
import '../domain/playback_windows.dart';
import '../models/chapter.dart';
import '../models/verse.dart';
import '../services/data_service.dart';
import '../services/verse_text.dart';
import 'app_content.dart';

/// The legacy data model, with timings from [windows] (null: no recording available).
ShatibiyyahData legacyData(AppContent content, PlaybackWindows? windows) {
  final layout = content.layout;
  final verses = [
    for (final v in content.matn.verses)
      () {
        final r = layout.verseRegion(v.number);
        return Verse(
          id: v.number,
          page: r.page,
          x: r.rect.left,
          y: r.rect.top,
          width: r.rect.width,
          height: r.rect.height,
        );
      }(),
  ];
  final chapters = [
    for (final c in content.matn.chapters)
      () {
        final header = layout.headerRegion(c.id);
        return Chapter(
          name: c.shortLabel,
          startVerse: c.fromVerse,
          endVerse: c.toVerse,
          verseCount: c.verseCount,
          startTime: windows == null ? null : windows.chapterStart(c.fromVerse) / 1000.0,
          x: header?.rect.left,
          y: header?.rect.top,
          width: header?.rect.width,
          height: header?.rect.height,
        );
      }(),
  ];
  final starts = List<double?>.filled(content.matn.lastVerse + 1, null);
  if (windows != null) {
    for (var v = 1; v <= content.matn.lastVerse; v++) {
      starts[v] = windows.cue(v) / 1000.0;
    }
  }
  return ShatibiyyahData(verses, starts, chapters,
      durationSeconds: windows == null ? 0 : windows.durationMs / 1000.0);
}

/// Verse halves and the legacy search index.
VerseTextData legacyVerseText(AppContent content) => verseTextFromLines([
      for (final v in content.matn.verses)
        VerseLine(v.number, v.firstHemistich, v.secondHemistich, '${v.firstHemistich} ... ${v.secondHemistich}'),
    ]);
