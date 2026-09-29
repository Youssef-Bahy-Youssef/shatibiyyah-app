// lib/data/legacy_prefs.dart — one-time repair of preferences written by the JSON-era app.
//
// The old app keyed the selected chapter and per-chapter listening progress by
// the index into its own 79-entry chapter list. The content database has the 78
// canonical chapters (the duplicate «النور» entry at 913 is merged into سورة النور
// 912–919), so every index after it would point one chapter too far. There are no
// published installs; this only keeps development devices consistent.
import 'dart:convert';

import '../models/playback_settings.dart' show K;
import '../services/preferences_service.dart';
import 'matn_repository.dart';

/// First verse of each entry in the old app's chapters.json, frozen (79 entries).
const List<int> kLegacyChapterStarts = [
  1, 95, 100, 108, 116, 132, 158, 168, 183, 202, 214, 226, 235, 255, 259, 262, 266, 270, 274, 277, //
  286, 291, 339, 343, 359, 365, 376, 387, 420, 445, 546, 587, 614, 632, 681, 714, 725, 738, 755, 772,
  787, 797, 802, 808, 816, 830, 860, 871, 887, 893, 903, 912, 913, 920, 927, 932, 945, 952, 958, 975,
  986, 993, 1001, 1005, 1010, 1015, 1018, 1031, 1038, 1052, 1059, 1065, 1078, 1092, 1099, 1115, 1121,
  1134, 1160,
];

const String kLegacyPrefsMigrated = 'v2.legacy_prefs_migrated';

/// Canonical chapter order index for an old list index, or null if out of range.
int? canonicalChapterIndex(MatnRepository matn, int legacyIndex) {
  if (legacyIndex < 0 || legacyIndex >= kLegacyChapterStarts.length) return null;
  return matn.chapterOfVerse(kLegacyChapterStarts[legacyIndex]).orderIndex;
}

/// Rewrites the index-keyed preferences once. Returns true if anything was migrated.
bool migrateLegacyPrefs(Prefs prefs, MatnRepository matn) {
  if (prefs.getString(kLegacyPrefsMigrated) == '1') return false;

  final chapter = int.tryParse(prefs.getString(K.chapter) ?? '');
  if (chapter != null) {
    final canonical = canonicalChapterIndex(matn, chapter) ?? 0;
    prefs.setString(K.chapter, canonical.toString());
  }

  final rawProgress = prefs.getString(K.chapProg);
  if (rawProgress != null) {
    final merged = <int, double>{};
    try {
      final old = json.decode(rawProgress) as Map<String, dynamic>;
      for (final e in old.entries) {
        final canonical = canonicalChapterIndex(matn, int.parse(e.key));
        if (canonical == null) continue;
        final value = (e.value as num).toDouble();
        if (value > (merged[canonical] ?? -1)) merged[canonical] = value; // النور: max of both
      }
    } catch (_) {
      // Unreadable progress is dropped rather than guessed.
    }
    prefs.setString(K.chapProg, json.encode({for (final e in merged.entries) e.key.toString(): e.value}));
  }

  prefs.setString(kLegacyPrefsMigrated, '1');
  return true;
}
