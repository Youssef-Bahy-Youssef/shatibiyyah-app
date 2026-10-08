// «التنبيهات» (P7, ADR 0008): «تذكير الباب» is the only reminder. The plan at a
// given time (fake clock); the controller over a fake port — permission asked
// when the reminder is turned on, refused = stays off, every reschedule replaces
// the last; taps; the screen. The first launch after the update cancels the
// retired daily-benefit notifications (ids 1000–1013) and deletes their settings.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/app/reminders.dart';
import 'package:shatibiyyah/app/retired_features.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/services/notifications.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/design/taysir_colors.dart';
import 'package:shatibiyyah/ui/shell/reminders_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakePort implements NotificationPort {
  bool grant = true;
  int permissionAsks = 0;
  int cancels = 0;
  final cancelled = <int>[];
  final scheduled = <PlannedNotification>[];
  String? launched;

  @override
  Future<void> init(void Function(String payload) onTap) async {}
  @override
  Future<String?> launchPayload() async => launched;
  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return grant;
  }

  @override
  Future<void> cancelScheduled() async {
    cancels++;
    scheduled.clear();
  }

  @override
  Future<void> cancel(int id) async => cancelled.add(id);

  @override
  Future<void> schedule(PlannedNotification n) async => scheduled.add(n);

  final shown = <PlannedNotification>[];
  @override
  Future<void> showNow(PlannedNotification n) async => shown.add(n);
}

void main() {
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('reminders_test');
    content = await AppContent.open(
      loadAsset: (key) async => ByteData.sublistView(await File(key).readAsBytes()),
      supportDir: support,
      factory: databaseFactoryFfi,
    );
  });

  tearDownAll(() async {
    await content.store.close();
    await support.delete(recursive: true);
  });

  test('the plan: the chapter in 3 days, moved out of the night', () {
    final now = DateTime(2026, 9, 30, 8, 15);
    final chapter = planReminders(now: now, chapterOn: true, content: content, verse: 229).single;
    expect(chapter.payload, 'verse:229');
    expect(chapter.when, DateTime(2026, 10, 3, 9)); // 08:15 is before 09:00: moved to 09:00
    expect(chapter.title, 'تذكير الباب');
    expect(chapter.body, contains(content.matn.chapterOfVerse(229).shortLabel));

    final late = planReminders(now: DateTime(2026, 9, 30, 22, 30), chapterOn: true, content: content, verse: 1);
    expect(late.single.when, DateTime(2026, 10, 4, 9)); // after 21:00: the next morning
    expect(planReminders(now: now, chapterOn: false, content: content, verse: 1), isEmpty);
  });

  test('taps: verse:N opens the verse; anything else is ignored', () {
    expect(ReminderTarget.parse('verse:229')?.verse, 229);
    expect(ReminderTarget.parse('benefit:102'), isNull); // a retired notification still on screen
    expect(ReminderTarget.parse('other:1'), isNull);
    expect(ReminderTarget.parse('verse:x'), isNull);
  });

  Future<(Reminders, FakePort, Prefs)> reminders({DateTime? now, Map<String, Object> values = const {}}) async {
    SharedPreferences.setMockInitialValues(values);
    final port = FakePort();
    final prefs = await Prefs.create();
    final r = Reminders(
      prefs: prefs,
      port: port,
      content: content,
      verse: () => 229,
      clock: () => now ?? DateTime(2026, 9, 30, 8, 15),
    );
    return (r, port, prefs);
  }

  test('the upgrade cancels the daily benefit (ids 1000–1013) and deletes its settings, once', () async {
    final (r, port, prefs) = await reminders(values: {
      'flutter.v2.reminders.benefit': '1',
      'flutter.v2.reminders.benefit_time': '07:30',
      'flutter.shatibiyyah_chap_prog': '{"3":0.5}',
      'flutter.v2.reminders.chapter': '1',
    });
    await r.start();
    expect(port.cancelled, [for (var id = 1000; id <= 1013; id++) id]);
    expect(prefs.has('v2.reminders.benefit'), isFalse);
    expect(prefs.has('v2.reminders.benefit_time'), isFalse);
    expect(prefs.has('shatibiyyah_chap_prog'), isFalse);
    expect(r.chapterOn, isTrue); // «تذكير الباب» is kept
    expect(port.scheduled.single.payload, 'verse:229');
    expect(prefs.getString(kRetiredFeaturesDone), '1');

    port.cancelled.clear();
    await r.start(); // the next launch: nothing to clean up
    expect(port.cancelled, isEmpty);
  });

  test('off by default; on asks for the permission; refused stays off', () async {
    final (r, port, _) = await reminders();
    await r.start();
    expect((r.chapterOn, port.permissionAsks), (false, 0));
    expect(port.scheduled, isEmpty);

    port.grant = false;
    expect(await r.setChapter(true), isFalse);
    expect(r.chapterOn, isFalse);
    expect(port.scheduled, isEmpty);

    port.grant = true;
    expect(await r.setChapter(true), isTrue);
    expect(port.scheduled.single.payload, 'verse:229');
    final cancels = port.cancels;
    await r.reschedule();
    expect(port.cancels, cancels + 1); // each plan replaces the last
    expect(port.scheduled, hasLength(1));

    expect(await r.setChapter(false), isTrue);
    expect(port.scheduled, isEmpty);
    expect(port.permissionAsks, 2); // only when turning on
  });

  test('debug tools: the reminder at once, and one through the scheduler in 2 minutes', () async {
    final (r, port, _) = await reminders();
    await r.sendNow();
    expect(port.shown.single.payload, 'verse:229');
    await r.scheduleSoon(const Duration(minutes: 2));
    expect(port.scheduled.single.when, DateTime(2026, 9, 30, 8, 17));
    await r.reschedule(); // leaving the app keeps the test one
    expect(port.scheduled.single.when, DateTime(2026, 9, 30, 8, 17));
    expect(r.chapterOn, isFalse); // the switch is untouched
  });

  test('the launching reminder is read once from the port', () async {
    final (r, port, _) = await reminders();
    port.launched = 'verse:63';
    expect((await r.launchTarget())!.verse, 63);
    port.launched = null;
    expect(await r.launchTarget(), isNull);
  });

  testWidgets('the screen: one switch, a refusal message and the preview', (tester) async {
    late Reminders r;
    late FakePort port;
    await tester.runAsync(() async => (r, port, _) = await reminders());
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [TaysirColors.dark]),
        home: RemindersScreen(reminders: r),
      ),
    );
    expect(find.text('تذكير الباب'), findsNWidgets(2)); // the switch and the preview's title
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('معاينة'), findsOneWidget);

    port.grant = false;
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('لم يُسمح بالإشعارات'), findsOneWidget);
    expect(r.chapterOn, isFalse);

    port.grant = true;
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(r.chapterOn, isTrue);
    expect(find.textContaining('لم يُسمح بالإشعارات'), findsNothing);
  });
}
