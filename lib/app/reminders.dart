// lib/app/reminders.dart — «التنبيهات» (features-v3 reminders, plan P7 step 2;
// ADR 0008).
//
// One reminder, off until the user turns it on (the notification permission is
// asked for then, never on first run): «تذكير الباب», three days after the app
// was last left, the chapter and verse the reader was on. Every time the app is
// left the reminder moves forward, so it only comes after three days away. The
// plan is redone at each launch and each time the app is left.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/app_content.dart';
import '../services/notifications.dart';
import '../services/preferences_service.dart';
import '../utils/arabic.dart';
import 'retired_features.dart';

const String kChapterReminderPref = 'v2.reminders.chapter';

const Duration kChapterReminderAfter = Duration(days: 3);

/// Hours a chapter reminder may come in: a time outside them moves to [kQuietEnd].
const int kQuietEnd = 9;
const int kQuietStart = 21;

const int _chapterId = 2000;

/// A tap on a reminder: `verse:N` opens the reader on verse N.
class ReminderTarget {
  final int verse;
  const ReminderTarget(this.verse);
  static ReminderTarget? parse(String payload) {
    final parts = payload.split(':');
    final verse = parts.length == 2 && parts[0] == 'verse' ? int.tryParse(parts[1]) : null;
    return verse == null ? null : ReminderTarget(verse);
  }
}

/// What to schedule at [now]. Pure, for tests.
List<PlannedNotification> planReminders({
  required DateTime now,
  required bool chapterOn,
  required AppContent content,
  required int verse,
}) {
  if (!chapterOn) return const [];
  var when = now.add(kChapterReminderAfter);
  if (when.hour < kQuietEnd) {
    when = DateTime(when.year, when.month, when.day, kQuietEnd);
  } else if (when.hour >= kQuietStart) {
    when = DateTime(when.year, when.month, when.day + 1, kQuietEnd);
  }
  final chapter = content.matn.chapterOfVerse(verse);
  return [
    PlannedNotification(
      _chapterId,
      when,
      'تذكير الباب',
      'تابع «${chapter.shortLabel}» من البيت ${ar(verse)}',
      'verse:$verse',
    ),
  ];
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

  /// Sets up the notifications, clears what removed features left behind, and
  /// schedules the plan for now.
  Future<void> start() async {
    await port.init((payload) {
      if (ReminderTarget.parse(payload) case final target?) _taps.add(target);
    });
    await clearRetiredFeatures(prefs, port);
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

  bool get chapterOn => prefs.getString(kChapterReminderPref) == '1';

  /// Turns «تذكير الباب» on or off. Turning on asks for the permission first and
  /// stays off if it is refused; returns whether the reminder is now as asked.
  Future<bool> setChapter(bool on) async {
    if (on && !await port.requestPermission()) return false;
    prefs.setString(kChapterReminderPref, on ? '1' : '0');
    notifyListeners();
    await reschedule();
    return true;
  }

  /// The reminder as it would come now, whatever the switch (the screen's
  /// preview and the debug build's test tools).
  PlannedNotification sample() =>
      planReminders(now: clock(), chapterOn: true, content: content, verse: verse()).single;

  /// Shows the sample at once (debug test tools).
  Future<void> sendNow() => port.showNow(sample());

  /// A test notification from [scheduleSoon], kept across reschedules until its time.
  PlannedNotification? _soon;

  /// Schedules the sample [after] from now through the real scheduler (debug test
  /// tools). Inexact: it may come a few minutes late. Leaving the app keeps it
  /// (reschedule puts it back), so it can be tested with the app closed.
  Future<void> scheduleSoon(Duration after) async {
    final s = sample();
    _soon = PlannedNotification(3000, clock().add(after), s.title, s.body, s.payload);
    await port.schedule(_soon!);
  }

  /// Replaces whatever was scheduled with the plan for now.
  Future<void> reschedule() async {
    await port.cancelScheduled();
    for (final n in planReminders(now: clock(), chapterOn: chapterOn, content: content, verse: verse())) {
      await port.schedule(n);
    }
    if (_soon case final soon? when soon.when.isAfter(clock())) {
      await port.schedule(soon);
    } else {
      _soon = null;
    }
  }
}
