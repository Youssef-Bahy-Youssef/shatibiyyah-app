// lib/app/reminders.dart — «التنبيهات» (features-v3 reminders, plan P7 step 2).
//
// Two reminders, both off until the user turns them on (the notification
// permission is asked for then, never on first run):
// - «فائدة اليوم»: every day at the chosen time (default 07:00), a verse and the
//   Al-Wafi summary or benefit on it (G-19, lib/data/benefits_repository.dart);
// - «تذكير الباب»: three days after the app was last left, the chapter and verse
//   the reader was on. Every time the app is left the reminder moves forward, so
//   it only comes after three days away.
// The benefit changes every day, so the next [kBenefitDaysAhead] days are
// scheduled one by one, and the plan is redone at each launch and each time the
// app is left (a month away needs no daily benefit).
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/app_content.dart';
import '../data/benefits_repository.dart';
import '../services/notifications.dart';
import '../services/preferences_service.dart';
import '../utils/arabic.dart';

const String kBenefitReminderPref = 'v2.reminders.benefit';
const String kChapterReminderPref = 'v2.reminders.chapter';
const String kBenefitTimePref = 'v2.reminders.benefit_time'; // "HH:MM"

const int kBenefitDaysAhead = 14;
const Duration kChapterReminderAfter = Duration(days: 3);

/// Hours a chapter reminder may come in: a time outside them moves to [kQuietEnd].
const int kQuietEnd = 9;
const int kQuietStart = 21;

const int _benefitId = 1000;
const int _chapterId = 2000;

/// Bodies are cut to this length; the expanded notification shows up to [_longLength].
const int _shortLength = 110;
const int _longLength = 700;

/// A tap on a reminder: `benefit:N` opens Al-Wafi at verse N, `verse:N` the reader.
sealed class ReminderTarget {
  final int verse;
  const ReminderTarget(this.verse);
  static ReminderTarget? parse(String payload) {
    final parts = payload.split(':');
    final verse = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (verse == null) return null;
    return switch (parts[0]) {
      'benefit' => BenefitTarget(verse),
      'verse' => VerseTarget(verse),
      _ => null,
    };
  }
}

class BenefitTarget extends ReminderTarget {
  const BenefitTarget(super.verse);
}

class VerseTarget extends ReminderTarget {
  const VerseTarget(super.verse);
}

/// «فائدة اليوم، البيت ١٠٢» (or the range of verses).
String benefitTitle(DailyBenefit b) =>
    'فائدة اليوم، ${b.fromVerse == b.toVerse ? 'البيت ${ar(b.fromVerse)}' : 'الأبيات ${isolatedRange(b.fromVerse, b.toVerse)}'}';

/// The summary reads «أن …» in the book, after its heading «الخلاصة».
String benefitText(DailyBenefit b) => b.kind == BenefitKind.summary ? 'الخلاصة: ${b.text}' : b.text;

/// [text] cut at a word boundary to about [max] characters, with «…».
String clip(String text, int max) {
  if (text.length <= max) return text;
  final cut = text.lastIndexOf(' ', max);
  return '${text.substring(0, cut > max ~/ 2 ? cut : max).trimRight()}…';
}

/// What to schedule at [now]. Pure, for tests.
List<PlannedNotification> planReminders({
  required DateTime now,
  required bool benefitOn,
  required bool chapterOn,
  required (int, int) benefitTime,
  required AppContent content,
  required int verse,
}) {
  final plan = <PlannedNotification>[];
  if (benefitOn) {
    for (var i = 0; i <= kBenefitDaysAhead; i++) {
      final day = DateTime(now.year, now.month, now.day + i, benefitTime.$1, benefitTime.$2);
      if (!day.isAfter(now) || plan.length == kBenefitDaysAhead) continue;
      final b = content.benefits.forDay(day);
      if (b == null) break;
      final text = benefitText(b);
      plan.add(
        PlannedNotification(
          _benefitId + plan.length,
          day,
          benefitTitle(b),
          clip(text, _shortLength),
          'benefit:${b.fromVerse}',
          longBody: text.length > _shortLength ? clip(text, _longLength) : null,
        ),
      );
    }
  }
  if (chapterOn) {
    var when = now.add(kChapterReminderAfter);
    if (when.hour < kQuietEnd) {
      when = DateTime(when.year, when.month, when.day, kQuietEnd);
    } else if (when.hour >= kQuietStart) {
      when = DateTime(when.year, when.month, when.day + 1, kQuietEnd);
    }
    final chapter = content.matn.chapterOfVerse(verse);
    plan.add(
      PlannedNotification(
        _chapterId,
        when,
        'تذكير الباب',
        'تابع «${chapter.shortLabel}» من البيت ${ar(verse)}',
        'verse:$verse',
      ),
    );
  }
  return plan;
}

class Reminders extends ChangeNotifier {
  final Prefs prefs;
  final NotificationPort port;
  final AppContent content;
  final int Function() verse; // the reader's verse now
  final DateTime Function() clock;

  Reminders({
    required this.prefs,
    required this.port,
    required this.content,
    required this.verse,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final _taps = StreamController<ReminderTarget>.broadcast();

  /// Reminders tapped while the app runs.
  Stream<ReminderTarget> get taps => _taps.stream;

  /// Sets up the notifications and schedules the plan for now.
  Future<void> start() async {
    await port.init((payload) {
      if (ReminderTarget.parse(payload) case final target?) _taps.add(target);
    });
    await reschedule();
  }

  /// The reminder that launched the app, if one did.
  Future<ReminderTarget?> launchTarget() async {
    final payload = await port.launchPayload();
    return payload == null ? null : ReminderTarget.parse(payload);
  }

  @override
  void dispose() {
    _taps.close();
    super.dispose();
  }

  bool get benefitOn => prefs.getString(kBenefitReminderPref) == '1';
  bool get chapterOn => prefs.getString(kChapterReminderPref) == '1';

  (int, int) get benefitTime {
    final parts = (prefs.getString(kBenefitTimePref) ?? '').split(':');
    final h = parts.length == 2 ? int.tryParse(parts[0]) : null;
    final m = parts.length == 2 ? int.tryParse(parts[1]) : null;
    return h != null && m != null && h >= 0 && h < 24 && m >= 0 && m < 60 ? (h, m) : (7, 0);
  }

  /// Today's benefit, for the preview.
  DailyBenefit? get today => content.benefits.forDay(clock());

  /// Turns «فائدة اليوم» on or off. Turning on asks for the permission first and
  /// stays off if it is refused; returns whether the reminder is now as asked.
  Future<bool> setBenefit(bool on) => _set(kBenefitReminderPref, on);
  Future<bool> setChapter(bool on) => _set(kChapterReminderPref, on);

  Future<bool> _set(String key, bool on) async {
    if (on && !await port.requestPermission()) return false;
    prefs.setString(key, on ? '1' : '0');
    notifyListeners();
    await reschedule();
    return true;
  }

  Future<void> setBenefitTime(int hour, int minute) async {
    prefs.setString(kBenefitTimePref, '${'$hour'.padLeft(2, '0')}:${'$minute'.padLeft(2, '0')}');
    notifyListeners();
    await reschedule();
  }

  /// Replaces whatever was scheduled with the plan for now.
  Future<void> reschedule() async {
    await port.cancelScheduled();
    for (final n in planReminders(
      now: clock(),
      benefitOn: benefitOn,
      chapterOn: chapterOn,
      benefitTime: benefitTime,
      content: content,
      verse: verse(),
    )) {
      await port.schedule(n);
    }
  }
}
