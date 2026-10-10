// lib/domain/daily_verse.dart — «بيت اليوم»: which verse a day shows (ADRs 0017, 0025).
//
// The poem is walked in order, one verse a day, from verse 1 on the day the widget
// is added; the day after the last verse shows the first again. A day is a local
// calendar date: only the dates count, not the hours between them, so a day of 23
// or 25 hours and a change of timezone are each one step per date.
//
// Plain Dart. The Android widget does the same arithmetic itself, since it changes
// at midnight with the app closed (android/…/widgets/DailyVerse.kt); both are held
// to test/fixtures/daily_verse.json.

/// The verse (1…[verses]) for [today], for a widget added on [added]. A clock set
/// back before [added] shows the first verse.
int dailyVerse({required DateTime added, required DateTime today, int verses = 1173}) {
  // The two dates as UTC midnights: their difference is a whole number of days.
  final from = DateTime.utc(added.year, added.month, added.day);
  final to = DateTime.utc(today.year, today.month, today.day);
  final days = to.difference(from).inDays;
  return (days < 0 ? 0 : days) % verses + 1;
}
