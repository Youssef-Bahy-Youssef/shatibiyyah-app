// lib/app/rating.dart — asking for a rating (features-v3 app-update-and-review,
// plan P7 step 5; re-based by ADR 0008).
//
// The native in-app review is requested once the app has been used on 5 separate
// days, a day of use being one on which audio played or a commentary was opened.
// It is requested at most once every 90 days (v2.review.last_prompt_at) and not
// within 24 hours of an error shown to the user (v2.last_error_at). Only a count
// of days and the last day counted are stored (v2.review.days_used), never what
// was done. The platform decides whether the sheet actually appears; the request
// counts either way. «قيّم التطبيق» on «حول» opens the store's page whenever the
// student wishes; having gone there, they are not asked again for 90 days.
import 'package:in_app_review/in_app_review.dart';

import '../services/preferences_service.dart';

const String kReviewDaysUsedPref = 'v2.review.days_used'; // "<count> <yyyy-mm-dd>"
const String kReviewLastPromptPref = 'v2.review.last_prompt_at';
const String kLastErrorPref = 'v2.last_error_at';
const int kReviewAfterDays = 5;
const Duration kReviewInterval = Duration(days: 90);
const Duration kErrorQuiet = Duration(hours: 24);

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

  RatingPrompt({required this.prefs, required this.port, DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  DateTime? _at(String key) {
    final ms = int.tryParse(prefs.getString(key) ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// An error was shown to the user (a failed download, a refused backup file…).
  void noteError() => prefs.setString(kLastErrorPref, '${clock().millisecondsSinceEpoch}');

  static String _day(DateTime d) => '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}';

  /// Distinct days the app has been used on.
  int get daysUsed => int.tryParse((prefs.getString(kReviewDaysUsedPref) ?? '').split(' ').first) ?? 0;

  bool get mayAsk {
    final now = clock();
    final last = _at(kReviewLastPromptPref);
    final error = _at(kLastErrorPref);
    return daysUsed >= kReviewAfterDays &&
        (last == null || now.difference(last) >= kReviewInterval) &&
        (error == null || now.difference(error) >= kErrorQuiet);
  }

  /// «قيّم التطبيق» took the student to the store's page: they have been asked,
  /// by their own hand, so the sheet waits its interval from now.
  void openedListing() => prefs.setString(kReviewLastPromptPref, '${clock().millisecondsSinceEpoch}');

  /// Audio played or a commentary was opened: counts the day, then asks if the
  /// rules allow. True when asked.
  Future<bool> used() async {
    final stored = (prefs.getString(kReviewDaysUsedPref) ?? '').split(' ');
    final today = _day(clock());
    if (stored.length != 2 || stored[1] != today) {
      prefs.setString(kReviewDaysUsedPref, '${daysUsed + 1} $today');
    }
    if (!mayAsk) return false;
    if (!await port.request()) return false;
    prefs.setString(kReviewLastPromptPref, '${clock().millisecondsSinceEpoch}');
    return true;
  }
}
