// The rating request and the update banner (P7 steps 5–6). Rating: asked exactly
// once on the first finished chapter, not again within 90 days, not after an error
// in this session or in the last minutes (fake clock). A chapter finishes when its
// last unheard verse is played through, once. Update: the banner follows Play's
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
import 'package:shatibiyyah/data/matn_repository.dart';
import 'package:shatibiyyah/data/user_store.dart';
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

    test('asked on the first finished chapter, then not within 90 days', () async {
      final r = session();
      expect(await r.chapterFinished(), isTrue);
      expect(review.requests, 1);
      now = now.add(const Duration(days: 1));
      expect(await r.chapterFinished(), isFalse); // a second chapter the next day
      now = now.add(const Duration(days: 88)); // 89 days after
      expect(await session().chapterFinished(), isFalse);
      now = now.add(const Duration(days: 1)); // 90 days after
      expect(await session().chapterFinished(), isTrue);
      expect(review.requests, 2);
    });

    test('not after an error in this session, nor within minutes of one', () async {
      final r = session()..noteError();
      now = now.add(const Duration(hours: 2));
      expect(await r.chapterFinished(), isFalse); // same session: never
      final next = session(); // a new launch, 2 h after the error
      expect(next.mayAsk, isTrue);
      next.noteError();
      final soon = session(); // and a launch 3 minutes after an error
      now = now.add(const Duration(minutes: 3));
      expect(await soon.chapterFinished(), isFalse);
      now = now.add(const Duration(minutes: 3));
      expect(await soon.chapterFinished(), isTrue);
      expect(review.requests, 1);
    });

    test('no review sheet on the platform: nothing recorded, asked next time', () async {
      review.available = false;
      expect(await session().chapterFinished(), isFalse);
      expect(prefs.getString(kReviewLastPromptPref), isNull);
      review.available = true;
      expect(await session().chapterFinished(), isTrue);
    });

    test('a chapter finishes once, on its last unheard verse', () async {
      final dir = await Directory.systemTemp.createTemp('rating_user');
      addTearDown(() => dir.delete(recursive: true));
      final user = await UserStore.open(directory: dir.path, factory: databaseFactoryFfi);
      addTearDown(user.close);
      final chapter = content.matn.chapters.first;
      final finished = <MatnChapter>[];
      for (var v = chapter.toVerse; v >= chapter.fromVerse; v--) {
        expect(finished, isEmpty, reason: 'before verse $v');
        await recordListened(user, content.matn, 'recording:a', v, finished.add);
      }
      expect(finished.single.id, chapter.id);
      await recordListened(user, content.matn, 'recording:a', chapter.fromVerse, finished.add); // heard again
      await recordListened(user, content.matn, 'recording:b', chapter.toVerse, finished.add); // another reciter
      expect(finished, hasLength(1));
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
