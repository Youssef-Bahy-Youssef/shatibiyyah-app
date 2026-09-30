// «التنبيهات» (P7): the daily benefit from Al-Wafi (G-19) in rotation; the plan of
// notifications at a given time (fake clock); the controller over a fake port —
// permission asked when a reminder is turned on, refused = stays off, every
// reschedule replaces the last; taps; the screen.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/app/reminders.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/benefits_repository.dart';
import 'package:shatibiyyah/services/notifications.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/design/taysir_colors.dart';
import 'package:shatibiyyah/ui/shell/reminders_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakePort implements NotificationPort {
  bool grant = true;
  int permissionAsks = 0;
  int cancels = 0;
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
  Future<void> schedule(PlannedNotification n) async => scheduled.add(n);
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

  test('G-19: Al-Wafi summaries and benefits, in the poem\'s order, one a day in turn', () {
    final all = content.benefits.all;
    expect(all.length, 49); // 46 summaries + 3 benefits in the snapshot
    expect(all.where((b) => b.kind == BenefitKind.benefit).length, 3);
    expect([for (final b in all) b.fromVerse], orderedEquals([for (final b in all) b.fromVerse]..sort()));
    expect(all.every((b) => b.text.isNotEmpty && b.fromVerse <= b.toVerse), isTrue);

    final day = DateTime(2026, 9, 30, 23, 59);
    expect(content.benefits.forDay(day), same(content.benefits.forDay(DateTime(2026, 9, 30, 0, 1)))); // by date
    expect(content.benefits.forDay(day.add(const Duration(days: 1))), isNot(same(content.benefits.forDay(day))));
    expect(content.benefits.forDay(day.add(Duration(days: all.length))), same(content.benefits.forDay(day)));
    expect(dayNumber(DateTime(2026)), 0);
  });

  test('the plan: 14 daily benefits from the next one, and the chapter in 3 days by day', () {
    final now = DateTime(2026, 9, 30, 8, 15); // after today's 07:00
    final plan = planReminders(
      now: now,
      benefitOn: true,
      chapterOn: true,
      benefitTime: (7, 0),
      content: content,
      verse: 229,
    );
    final benefits = plan.where((n) => n.payload.startsWith('benefit:')).toList();
    expect(benefits, hasLength(kBenefitDaysAhead));
    expect(benefits.first.when, DateTime(2026, 10, 1, 7));
    expect(benefits.last.when, DateTime(2026, 10, 14, 7));
    expect(benefits.map((n) => n.id).toSet(), hasLength(kBenefitDaysAhead));
    final first = content.benefits.forDay(DateTime(2026, 10, 1))!;
    expect(benefits.first.title, benefitTitle(first));
    expect(benefits.first.payload, 'benefit:${first.fromVerse}');
    expect(benefits.every((n) => n.body.length <= 111), isTrue);

    final chapter = plan.singleWhere((n) => n.payload == 'verse:229');
    expect(chapter.when, DateTime(2026, 10, 3, 9)); // 08:15 is before 09:00: moved to 09:00
    expect(chapter.title, 'تذكير الباب');
    expect(chapter.body, contains(content.matn.chapterOfVerse(229).shortLabel));

    final late = planReminders(
      now: DateTime(2026, 9, 30, 22, 30),
      benefitOn: false,
      chapterOn: true,
      benefitTime: (7, 0),
      content: content,
      verse: 1,
    );
    expect(late.single.when, DateTime(2026, 10, 4, 9)); // after 21:00: the next morning
    final early = planReminders(
      now: DateTime(2026, 9, 30, 6, 0),
      benefitOn: true,
      chapterOn: false,
      benefitTime: (7, 0),
      content: content,
      verse: 1,
    );
    expect(early.first.when, DateTime(2026, 9, 30, 7)); // today's is still ahead
    expect(
      planReminders(now: now, benefitOn: false, chapterOn: false, benefitTime: (7, 0), content: content, verse: 1),
      isEmpty,
    );
  });

  test('summaries read «الخلاصة: أن …»; long ones are cut at a word with the full text expanded', () {
    const s = DailyBenefit(BenefitKind.summary, 102, 102, 'أن الخلاف في البسملة وارد');
    expect(benefitText(s), 'الخلاصة: أن الخلاف في البسملة وارد');
    expect(benefitTitle(const DailyBenefit(BenefitKind.benefit, 171, 175, 'x')), 'فائدة اليوم، الأبيات \u2068١٧١–١٧٥\u2069');
    final long = List.filled(60, 'كلمة').join(' ');
    expect(clip(long, 110), endsWith('…'));
    expect(clip(long, 110).length, lessThanOrEqualTo(111));
    expect(clip('قصير', 110), 'قصير');
  });

  test('taps: benefit:N and verse:N; anything else is ignored', () {
    expect(ReminderTarget.parse('benefit:102'), isA<BenefitTarget>().having((t) => t.verse, 'verse', 102));
    expect(ReminderTarget.parse('verse:229'), isA<VerseTarget>().having((t) => t.verse, 'verse', 229));
    expect(ReminderTarget.parse('other:1'), isNull);
    expect(ReminderTarget.parse('verse:x'), isNull);
  });

  Future<(Reminders, FakePort)> reminders({DateTime? now}) async {
    SharedPreferences.setMockInitialValues({});
    final port = FakePort();
    final r = Reminders(
      prefs: await Prefs.create(),
      port: port,
      content: content,
      verse: () => 229,
      clock: () => now ?? DateTime(2026, 9, 30, 8, 15),
    );
    return (r, port);
  }

  test('off by default; on asks for the permission; refused stays off', () async {
    final (r, port) = await reminders();
    await r.start();
    expect((r.benefitOn, r.chapterOn, port.permissionAsks), (false, false, 0));
    expect(port.scheduled, isEmpty);

    port.grant = false;
    expect(await r.setBenefit(true), isFalse);
    expect(r.benefitOn, isFalse);
    expect(port.scheduled, isEmpty);

    port.grant = true;
    expect(await r.setBenefit(true), isTrue);
    expect(port.scheduled, hasLength(kBenefitDaysAhead));
    expect(await r.setChapter(true), isTrue);
    expect(port.scheduled, hasLength(kBenefitDaysAhead + 1));

    await r.setBenefitTime(20, 5);
    expect(r.benefitTime, (20, 5));
    expect(port.scheduled.first.when, DateTime(2026, 9, 30, 20, 5)); // today's is now ahead
    final cancels = port.cancels;
    await r.reschedule();
    expect(port.cancels, cancels + 1); // each plan replaces the last
    expect(port.scheduled, hasLength(kBenefitDaysAhead + 1));

    expect(await r.setBenefit(false), isTrue);
    expect(port.scheduled.single.payload, 'verse:229');
    expect(port.permissionAsks, 3); // only when turning on
  });

  test('the launching reminder is read once from the port', () async {
    final (r, port) = await reminders();
    port.launched = 'benefit:63';
    expect((await r.launchTarget())!.verse, 63);
    port.launched = null;
    expect(await r.launchTarget(), isNull);
  });

  testWidgets('the screen: switches, the time, a refusal message and the preview', (tester) async {
    late Reminders r;
    late FakePort port;
    await tester.runAsync(() async => (r, port) = await reminders());
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [TaysirColors.dark]),
        home: RemindersScreen(reminders: r),
      ),
    );
    expect(find.text('فائدة اليوم'), findsOneWidget);
    expect(find.text('تذكير الباب'), findsOneWidget);
    expect(find.text('معاينة'), findsOneWidget);
    expect(find.text(benefitTitle(r.today!)), findsOneWidget);
    expect(find.text('الوقت'), findsNothing);

    port.grant = false;
    await tester.tap(find.text('تذكير الباب'));
    await tester.pumpAndSettle();
    expect(find.textContaining('لم يُسمح بالإشعارات'), findsOneWidget);
    expect(r.chapterOn, isFalse);

    port.grant = true;
    await tester.tap(find.text('فائدة اليوم'));
    await tester.pumpAndSettle();
    expect(r.benefitOn, isTrue);
    expect(find.textContaining('لم يُسمح بالإشعارات'), findsNothing);
    expect(find.text('الوقت'), findsOneWidget);
  });
}
