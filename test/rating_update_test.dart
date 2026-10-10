// The rating request and the update banner (P7 steps 5–6). Rating (ADR 0008):
// asked once after the 5th distinct day with audio played or a commentary opened,
// at most once per 90 days, and not within 24 h of a recorded error (fake clock);
// only a day count and the last day are stored. Update: the banner follows Play's
// answer, hides until the next launch, and never turns a failure into an error.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/app/app_update.dart';
import 'package:shatibiyyah/app/rating.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/design/taysir_colors.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/shell/home_screen.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeReview implements ReviewPort {
  int requests = 0;
  bool available = true;
  @override
  Future<bool> request() async {
    if (!available) return false;
    requests++;
    return true;
  }
}

class FakeUpdate implements UpdatePort {
  Object? result = true; // bool, or an error to throw
  int updates = 0;
  @override
  Future<bool> available() async => result is bool ? result as bool : throw result!;
  @override
  Future<void> update() async => updates++;
}

void main() {
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('rating_test');
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

  group('rating', () {
    late DateTime now;
    late FakeReview review;
    late Prefs prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await Prefs.create();
      now = DateTime(2026, 9, 30, 10);
      review = FakeReview();
    });

    RatingPrompt session() => RatingPrompt(prefs: prefs, port: review, clock: () => now);

    /// Uses the app on [days] more days, one day apart, from today.
    Future<List<bool>> useOn(RatingPrompt r, int days) async {
      final asked = <bool>[];
      for (var i = 0; i < days; i++) {
        if (i > 0) now = now.add(const Duration(days: 1));
        asked.add(await r.used());
      }
      return asked;
    }

    test('day 5 prompts once; day 6 does not; 90 days later prompts again', () async {
      final r = session();
      expect(await useOn(r, 4), [false, false, false, false]);
      expect(await r.used(), isFalse); // a second use on day 4 is the same day
      now = now.add(const Duration(days: 1));
      expect(await r.used(), isTrue); // day 5
      expect(await r.used(), isFalse); // again on day 5
      expect(review.requests, 1);
      now = now.add(const Duration(days: 1));
      expect(await r.used(), isFalse); // day 6
      now = now.add(const Duration(days: 88)); // 89 days after the prompt
      expect(await session().used(), isFalse);
      now = now.add(const Duration(days: 1)); // 90 days after
      expect(await session().used(), isTrue);
      expect(review.requests, 2);
    });

    test('distinct days, not uses: five uses in one day are one day', () async {
      final r = session();
      for (var i = 0; i < 5; i++) {
        now = now.add(const Duration(minutes: 30));
        expect(await r.used(), isFalse);
      }
      expect(review.requests, 0);
    });

    test('an error today suppresses it; 24 h later it is asked', () async {
      final r = session();
      await useOn(r, 4);
      now = now.add(const Duration(days: 1)); // day 5, 10:00
      r.noteError();
      now = now.add(const Duration(hours: 2));
      expect(await r.used(), isFalse);
      expect(await session().used(), isFalse); // a new launch does not forget it
      now = now.add(const Duration(hours: 21)); // day 6, 09:00: 23 h after the error
      expect(await r.used(), isFalse);
      now = now.add(const Duration(hours: 1)); // 24 h after
      expect(await r.used(), isTrue);
      expect(review.requests, 1);
    });

    test('only the day count and the last day are stored', () async {
      final r = session();
      await useOn(r, 3);
      expect(prefs.keys, {kReviewDaysUsedPref});
      expect(prefs.getString(kReviewDaysUsedPref), '3 2026-10-02');
    });

    test('no review sheet on the platform: nothing recorded, asked next time', () async {
      final r = session();
      await useOn(r, 4);
      now = now.add(const Duration(days: 1));
      review.available = false;
      expect(await r.used(), isFalse);
      expect(prefs.getString(kReviewLastPromptPref), isNull);
      review.available = true;
      expect(await r.used(), isTrue);
    });
  });

  group('update', () {
    test('the banner follows the store; «إخفاء» hides it; a failure is no banner', () async {
      final port = FakeUpdate();
      final u = AppUpdate(port);
      expect(u.showBanner, isFalse);
      await u.check();
      expect(u.showBanner, isTrue);
      await u.update();
      expect(port.updates, 1);
      u.dismiss();
      expect(u.showBanner, isFalse);

      port.result = StateError('not installed from Play');
      final other = AppUpdate(port);
      await other.check();
      expect(other.showBanner, isFalse);
      port.result = false;
      await other.check();
      expect(other.showBanner, isFalse);
    });

    testWidgets('the home screen shows the banner and hides it', (tester) async {
      SharedPreferences.setMockInitialValues({});
      late ReaderController r;
      await tester.runAsync(() async {
        final prefs = await Prefs.create();
        final recording = content.recordings.defaultRecording;
        final windows = await content.windowsFor(recording);
        r = ReaderController(
          content: content,
          recording: recording,
          viewer: PageViewerController(legacyData(content, windows), prefs),
          initialVerse: 226,
        );
      });
      final port = FakeUpdate();
      r.update = AppUpdate(port);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [TaysirColors.dark]),
          home: HomeScreen(reader: r),
        ),
      );
      expect(find.text('إصدار جديد من التطبيق متاح'), findsNothing);
      await r.update!.check();
      await tester.pump();
      expect(find.text('إصدار جديد من التطبيق متاح'), findsOneWidget);
      await tester.tap(find.text('تحديث'));
      expect(port.updates, 1);
      await tester.tap(find.byTooltip('إخفاء'));
      await tester.pump();
      expect(find.text('إصدار جديد من التطبيق متاح'), findsNothing);
    });
  });
}
