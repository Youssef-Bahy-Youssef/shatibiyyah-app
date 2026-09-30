// lib/app/rating.dart — asking for a rating (features-v3 app-update-and-review,
// plan P7 step 5).
//
// Only after an achievement: when a chapter becomes finished (its last unheard
// verse is played through, lib/data/user_store.dart verse_listens), the native
// in-app review is requested — if the last request was 90 days ago or more
// (v2.review.last_prompt_at) and no error was shown in this session or in the
// last few minutes (v2.last_error_at). The platform decides whether the sheet
// actually appears; the request counts either way.
import 'package:in_app_review/in_app_review.dart';

import '../data/matn_repository.dart';
import '../data/user_store.dart';
import '../services/preferences_service.dart';

const String kReviewLastPromptPref = 'v2.review.last_prompt_at';
const String kLastErrorPref = 'v2.last_error_at';
const Duration kReviewInterval = Duration(days: 90);
const Duration kErrorQuiet = Duration(minutes: 5);

/// The platform's review request; faked in tests.
abstract class ReviewPort {
  /// Requests the review sheet; false when the platform offers none.
  Future<bool> request();
}

class InAppReviewPort implements ReviewPort {
  @override
  Future<bool> request() async {
    final review = InAppReview.instance;
    if (!await review.isAvailable()) return false;
    await review.requestReview();
    return true;
  }
}

class RatingPrompt {
  final Prefs prefs;
  final ReviewPort port;
  final DateTime Function() clock;
  bool _errorThisSession = false;

  RatingPrompt({required this.prefs, required this.port, DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  DateTime? _at(String key) {
    final ms = int.tryParse(prefs.getString(key) ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// An error was shown to the user (a failed download, a refused backup file…).
  void noteError() {
    _errorThisSession = true;
    prefs.setString(kLastErrorPref, '${clock().millisecondsSinceEpoch}');
  }

  bool get mayAsk {
    final now = clock();
    final last = _at(kReviewLastPromptPref);
    final error = _at(kLastErrorPref);
    return !_errorThisSession &&
        (last == null || now.difference(last) >= kReviewInterval) &&
        (error == null || now.difference(error) >= kErrorQuiet);
  }

  /// A chapter has just become finished: ask, if the rules allow. True when asked.
  Future<bool> chapterFinished() async {
    if (!mayAsk) return false;
    if (!await port.request()) return false;
    prefs.setString(kReviewLastPromptPref, '${clock().millisecondsSinceEpoch}');
    return true;
  }
}

/// Records that [verse] was played through and calls [onFinished] when it was the
/// last unheard verse of its chapter (so a chapter finishes once, and seeking to
/// its end, which records nothing, finishes nothing).
Future<void> recordListened(
  UserStore user,
  MatnRepository matn,
  String recordingId,
  int verse,
  void Function(MatnChapter chapter) onFinished,
) async {
  final before = await user.listenedVerses();
  await user.recordVerseListened(recordingId, verse);
  if (before.contains(verse)) return;
  final chapter = matn.chapterOfVerse(verse);
  for (var v = chapter.fromVerse; v <= chapter.toVerse; v++) {
    if (v != verse && !before.contains(v)) return;
  }
  onFinished(chapter);
}
