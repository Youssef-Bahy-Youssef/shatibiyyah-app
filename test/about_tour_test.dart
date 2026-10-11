// «حول», the tour it replays and «أدوات التجربة»: what «حول» says is read from
// the content; «رأيك ودعمك» has a row for each place the app can point to, and
// each row does one thing with the device; each tour card lays its own state on
// the real page 19, in the places the layout gives; a swipe and Back move
// between the cards.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shatibiyyah/app/app_links.dart';
import 'package:shatibiyyah/app/rating.dart';
import 'package:shatibiyyah/app/reminders.dart';
import 'package:shatibiyyah/services/notifications.dart';
import 'package:shatibiyyah/ui/design/components/settings_row.dart';
import 'package:shatibiyyah/ui/design/night_page.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/shell/about_screen.dart';
import 'package:shatibiyyah/ui/shell/debug_tools_screen.dart';
import 'package:shatibiyyah/ui/shell/tour_scene.dart';
import 'package:shatibiyyah/ui/shell/tour_screen.dart';

import 'handoff/fixtures.dart';

/// Notifications that are only counted.
class _CountedNotifications implements NotificationPort {
  final List<PlannedNotification> shown = [], scheduled = [];
  @override
  Future<void> init(void Function(String payload) onTap) async {}
  @override
  Future<String?> launchPayload() async => null;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> cancelScheduled() async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> schedule(PlannedNotification n) async => scheduled.add(n);
  @override
  Future<void> showNow(PlannedNotification n) async => shown.add(n);
}

/// The store's own rating sheet, never asked for here.
class _NoSheet implements ReviewPort {
  @override
  Future<bool> request() async => false;
}

void main() {
  final data = HandoffContent();
  setUpAll(data.open);
  tearDownAll(data.close);

  Future<ReaderController> show(
    WidgetTester tester,
    Widget Function(ReaderController) build, {
    TzTheme theme = TzTheme.paper,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final r = await data.reader(tester, library: true, bookmarks: false);
    await tester.pumpWidget(MaterialApp(
      theme: tzThemeData(theme),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: build(r),
    ));
    await tester.pump();
    return r;
  }

  Widget tour(ReaderController r, {bool replay = true}) =>
      TourScreen(content: r.content, library: r.library, prefs: r.store!.prefs, replay: replay);

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  group('«حول»', () {
    testWidgets('names the app and says what is in it as the content has it; those rows lead nowhere', (tester) async {
      await show(tester, (r) => AboutScreen(reader: r));
      expect(find.text('تيسير الشاطبية'), findsOneWidget);
      expect(find.text('حِرْزُ الأَمَانِي وَوَجْهُ التَّهَانِي'), findsOneWidget);
      expect(find.text('رفيقك لدراسة متن الشاطبية وحفظها، بتلاوة صوتية بيتًا بيتًا، وشروح تعينك على فهم كل بيت'),
          findsOneWidget);
      expect(find.text('١١٧٣ بيتًا في ٧٨ بابًا، بعرض الصفحة أو النص'), findsOneWidget); // under the row «المتن»
      expect(find.text('الوافي · إبراز المعاني · سراج القارئ'), findsOneWidget);
      expect(find.text('محمد بن عتيق الصنوي · عبدالحميد بن عبدالله القريو الليبي'), findsOneWidget);
      for (final label in ['المتن', 'الشروح', 'التلاوة']) {
        expect(find.ancestor(of: find.text(label), matching: find.byType(InkWell)), findsNothing, reason: label);
      }
      await tester.scrollUntilVisible(find.text(versionLabel(kAppVersion)), 200);
      expect(find.text(versionLabel(kAppVersion)), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('«في التطبيق» ends with the student\'s own bookmarks and notes: they stay on the device', (tester) async {
      await show(tester, (r) => AboutScreen(reader: r));
      final row = find.widgetWithText(SettingsRow, 'مراجعك وملاحظاتك');
      expect(find.descendant(of: row, matching: find.text('تبقى على جهازك')), findsOneWidget);
      expect(tester.getSemantics(find.text('مراجعك وملاحظاتك')).label, 'مراجعك وملاحظاتك\nتبقى على جهازك');
      expect(find.ancestor(of: find.text('مراجعك وملاحظاتك'), matching: find.byType(InkWell)), findsNothing);
      // The last row of the group that names the matn, the books and the reciters.
      final group = find.ancestor(of: row, matching: find.byType(SettingsGroup));
      expect(find.descendant(of: group, matching: find.text('في التطبيق')), findsOneWidget);
      expect(tester.getRect(row).top, tester.getRect(find.widgetWithText(SettingsRow, 'التلاوة')).bottom);
      expect(tester.getRect(row).bottom, closeTo(tester.getRect(group).bottom, 1));
      await unmount(tester);
    });

    group('«رأيك ودعمك»', () {
      final page = Uri.parse('https://play.google.com/store/apps/details?id=$kAndroidPackage');
      AppLinks links({String? address = 'taysir@example.org', bool listed = true}) =>
          AppLinks(supportEmail: address, listing: listed ? page : null, storeName: listed ? 'Google Play' : null);

      Future<void> tapRow(WidgetTester tester, String label) async {
        await tester.scrollUntilVisible(find.text(label), 200); // built, perhaps still under the fold
        await tester.ensureVisible(find.text(label));
        await tester.pump();
        await tester.tap(find.text(label));
        await tester.pump();
        await tester.pump();
      }

      // A screen tall enough to hold every group: the list builds only what is near the screen.
      const whole = Size(390, 1600);

      testWidgets('a row for each place there is to go, in the order note, share, rate; none with nowhere to go',
          (tester) async {
        await show(tester, (r) => AboutScreen(reader: r, links: links()), size: whole);
        final tops = [
          for (final label in ['في التطبيق', 'رأيك ودعمك', 'أرسل ملاحظة', 'شارك التطبيق', 'قيّم التطبيق', 'أعد الجولة'])
            tester.getRect(find.text(label)).top,
        ];
        expect(tops, [...tops]..sort());
        final rate = find.widgetWithText(SettingsRow, 'قيّم التطبيق');
        expect(find.descendant(of: rate, matching: find.text('في Google Play')), findsOneWidget);

        await show(tester, (r) => AboutScreen(reader: r, links: links(address: null)), size: whole);
        expect(find.text('أرسل ملاحظة'), findsNothing);
        expect(find.text('شارك التطبيق'), findsOneWidget);
        expect(find.text('قيّم التطبيق'), findsOneWidget);

        await show(tester, (r) => AboutScreen(reader: r, links: links(listed: false)), size: whole);
        expect(find.text('أرسل ملاحظة'), findsOneWidget);
        expect(find.text('شارك التطبيق'), findsNothing);
        expect(find.text('قيّم التطبيق'), findsNothing);

        await show(tester, (r) => AboutScreen(reader: r, links: links(address: null, listed: false)), size: whole);
        expect(find.text('رأيك ودعمك'), findsNothing);
        expect(find.text('أعد الجولة'), findsOneWidget);
        await unmount(tester);
      });

      testWidgets('the build\'s own links: the owner\'s address and this platform\'s store', (tester) async {
        final opened = <Uri>[];
        await show(
          tester,
          (r) => AboutScreen(
            reader: r,
            open: (uri) async {
              opened.add(uri);
              return true;
            },
            system: () async => 'Android',
          ),
          size: whole, // a test runs as Android
        );
        for (final label in ['أرسل ملاحظة', 'شارك التطبيق', 'قيّم التطبيق']) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        await tester.tap(find.text('أرسل ملاحظة'));
        await tester.pump();
        await tester.pump();
        expect(opened.single.path, kSupportEmail);
        await tester.tap(find.text('قيّم التطبيق'));
        await tester.pump();
        await tester.pump();
        expect('${opened.last}', 'https://play.google.com/store/apps/details?id=$kAndroidPackage');
        await unmount(tester);
      });

      testWidgets('«أرسل ملاحظة» opens a letter to the address, saying the version, the content and the device',
          (tester) async {
        final opened = <Uri>[];
        await show(
          tester,
          (r) => AboutScreen(
            reader: r,
            links: links(),
            open: (uri) async {
              opened.add(uri);
              return true;
            },
            system: () async => 'Google Pixel 8 · Android 16',
          ),
        );
        await tapRow(tester, 'أرسل ملاحظة');
        final content = data.content.store.manifest.contentSha256.substring(0, 8);
        expect(opened, [
          feedbackMail(
              address: 'taysir@example.org', version: kAppVersion, content: content, system: 'Google Pixel 8 · Android 16'),
        ]);
        expect(Uri.decodeComponent(opened.single.query), endsWith('الإصدار $kAppVersion · المحتوى $content · Google Pixel 8 · Android 16'));
        expect(find.byType(SnackBar), findsNothing);
        await unmount(tester);
      });

      testWidgets('with no mail app the address is copied, and the student is told', (tester) async {
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
          return null;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
        await show(
          tester,
          (r) => AboutScreen(reader: r, links: links(), open: (_) async => false, system: () async => 'Android'),
        );
        await tapRow(tester, 'أرسل ملاحظة');
        expect(copied, 'taysir@example.org');
        expect(find.text('لا تطبيق بريد على الجهاز. نُسخ العنوان: taysir@example.org'), findsOneWidget);
        await unmount(tester);
      });

      testWidgets('«شارك التطبيق» hands the system the app\'s name, its line and its page, from the row', (tester) async {
        final shared = <ShareParams>[];
        final opened = <Uri>[];
        await show(
          tester,
          (r) => AboutScreen(
            reader: r,
            links: links(),
            share: (params) async => shared.add(params),
            open: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        );
        await tapRow(tester, 'شارك التطبيق');
        expect(shared.single.text, 'تيسير الشاطبية\n$kAppLine\n$page');
        expect(shared.single.files, isNull);
        expect(shared.single.sharePositionOrigin, tester.getRect(find.widgetWithText(SettingsRow, 'شارك التطبيق')));
        expect(opened, isEmpty);
        await unmount(tester);
      });

      testWidgets('«قيّم التطبيق» opens the store\'s page, and the rating sheet then waits its 90 days', (tester) async {
        final opened = <Uri>[];
        var now = DateTime(2026, 10, 11, 9);
        late RatingPrompt rating;
        await show(tester, (r) {
          r.store!.prefs.setString(kReviewDaysUsedPref, '$kReviewAfterDays 2026-10-10');
          rating = r.rating = RatingPrompt(prefs: r.store!.prefs, port: _NoSheet(), clock: () => now);
          return AboutScreen(
            reader: r,
            links: links(),
            open: (uri) async {
              opened.add(uri);
              return true;
            },
          );
        });
        expect(rating.mayAsk, isTrue);
        await tapRow(tester, 'قيّم التطبيق');
        expect(opened, [page]);
        expect(rating.mayAsk, isFalse);
        now = now.add(kReviewInterval - const Duration(minutes: 1));
        expect(rating.mayAsk, isFalse);
        now = now.add(const Duration(minutes: 1));
        expect(rating.mayAsk, isTrue);
        expect(find.byType(SnackBar), findsNothing);
        await unmount(tester);
      });

      testWidgets('a store that does not open says so, and the rating sheet may still ask', (tester) async {
        late RatingPrompt rating;
        await show(tester, (r) {
          r.store!.prefs.setString(kReviewDaysUsedPref, '$kReviewAfterDays 2026-10-10');
          rating = r.rating = RatingPrompt(prefs: r.store!.prefs, port: _NoSheet(), clock: () => DateTime(2026, 10, 11, 9));
          return AboutScreen(reader: r, links: links(), open: (_) async => false);
        });
        await tapRow(tester, 'قيّم التطبيق');
        expect(find.text('تعذّر فتح Google Play'), findsOneWidget);
        expect(rating.mayAsk, isTrue);
        await unmount(tester);
      });
    });

    testWidgets('«أعد الجولة» replays the three cards, and «تم» comes back', (tester) async {
      await show(tester, (r) => AboutScreen(reader: r));
      await tester.scrollUntilVisible(find.text('أعد الجولة'), 200);
      expect(find.text('بطاقات قصيرة تعرّفك بالتطبيق'), findsOneWidget); // under the row
      await tester.tap(find.text('أعد الجولة'));
      await tester.pumpAndSettle();
      expect(find.byType(TourScreen), findsOneWidget);
      expect(find.text('المتن بين يديك'), findsOneWidget);
      expect(find.text('صفحات متن الشاطبية بتحقيق الشيخ محمد تميم الزعبي، والبيت الذي تسمعه مظلَّل أمامك.'), findsOneWidget);
      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();
      expect(find.text('اضغط مطوّلًا على أي بيت'), findsOneWidget);
      expect(find.text('تقرأ شرحه، أو تبدأ الاستماع منه، أو تضع عليه مرجعًا أو ملاحظة تعود إليها.'), findsOneWidget);
      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();
      expect(find.text('متوفر حاليًا ثلاثة شروح لكل بيت'), findsOneWidget);
      expect(
          find.text('الوافي وإبراز المعاني وسراج القارئ: تنقّل بينها والبيت أمامك. '
              'المتن والشروح على جهازك دون اتصال، والتلاوة تُنزَّل مرة واحدة.'),
          findsOneWidget);
      expect(find.text('اختر التلاوة'), findsNothing); // replayed: no reciter step
      await tester.tap(find.text('تم'));
      await tester.pumpAndSettle();
      expect(find.byType(TourScreen), findsNothing);
      expect(find.byType(AboutScreen), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a debug build has «أدوات التجربة» in a group of its own; a tool says what it did', (tester) async {
      final port = _CountedNotifications();
      final r = await show(tester, (r) => AboutScreen(reader: r));
      r.reminders = Reminders(prefs: r.store!.prefs, port: port, content: data.content, verse: () => r.verse);
      await tester.scrollUntilVisible(find.text('أدوات التجربة'), 200);
      expect(find.text('نسخة التطوير'), findsOneWidget);
      await tester.tap(find.text('أدوات التجربة'));
      await tester.pumpAndSettle();
      expect(find.byType(DebugToolsScreen), findsOneWidget);
      await tester.tap(find.text('أرسل'));
      await tester.pump();
      expect(port.shown, hasLength(1));
      expect(find.text('أُرسل «تذكير الباب»'), findsOneWidget);
      await tester.tap(find.text('جدوِل'));
      await tester.pump();
      expect(port.scheduled, hasLength(1));
      // Neither Google Play service is here: their buttons are off.
      await tester.tap(find.text('أظهر'), warnIfMissed: false);
      await tester.pump();
      expect(find.textContaining('يظهر الشريط'), findsNothing);
      await unmount(tester);
    });
  });

  group('the tour', () {
    double opacityOf(WidgetTester tester, Finder of) =>
        tester.widget<AnimatedOpacity>(find.ancestor(of: of, matching: find.byType(AnimatedOpacity)).first).opacity;

    /// [verse]'s box on the scan (1130 px wide), where the scene's page is on screen.
    Rect onPage(WidgetTester tester, int verse) {
      final page = tester.getRect(find.byKey(TourScene.pageKey));
      final k = page.width / 1130;
      final r = data.content.layout.verseRegion(verse).rect;
      return Rect.fromLTRB(page.left + r.left * k, page.top + r.top * k, page.left + r.right * k, page.top + r.bottom * k);
    }

    Future<void> next(WidgetTester tester) async {
      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();
    }

    testWidgets('each card lays its own state on the page: the recited verse, the held verse\'s menu, the books',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await show(tester, tour);
      await tester.pumpAndSettle();
      final page = tester.getRect(find.byKey(TourScene.pageKey));
      final recited = find.byKey(TourScene.recitedKey), menu = find.byKey(TourScene.menuKey);
      final sheet = find.byKey(TourScene.sheetKey);

      // Card 1: the wash lies on verse 226's own box; no menu; the sheet is off the page.
      final wash = tester.getRect(recited), box = onPage(tester, 226);
      for (final (got, want) in [(wash.left, box.left), (wash.top, box.top), (wash.right, box.right), (wash.bottom, box.bottom)]) {
        expect(got, moreOrLessEquals(want, epsilon: 0.5));
      }
      expect(opacityOf(tester, recited), 1);
      expect(opacityOf(tester, menu), 0);
      expect(tester.getRect(sheet).top, greaterThanOrEqualTo(page.bottom));
      expect(find.bySemanticsLabel('١ من ٣'), findsOneWidget);

      // Card 2: the menu, with its four tiles, opens under verse 229; nothing is recited.
      await next(tester);
      expect(opacityOf(tester, menu), 1);
      expect(opacityOf(tester, recited), 0);
      expect(tester.getRect(menu).top, greaterThan(onPage(tester, 229).bottom));
      expect(tester.getRect(menu).bottom, lessThan(page.bottom));
      for (final tile in ['الشرح', 'استمع', 'المرجع', 'ملاحظة']) {
        expect(find.descendant(of: menu, matching: find.text(tile)), findsOneWidget, reason: tile);
      }
      expect(find.bySemanticsLabel('٢ من ٣'), findsOneWidget);

      // Card 3: the sheet stands on the page with the content's three books, the first one's author under them.
      await next(tester);
      expect(opacityOf(tester, menu), 0);
      final up = tester.getRect(sheet);
      expect(up.bottom, moreOrLessEquals(page.bottom, epsilon: 0.5));
      expect(up.top, greaterThan(onPage(tester, 226).bottom)); // the recited verse stays in sight above it
      expect(opacityOf(tester, recited), 1);
      for (final book in data.content.books.books) {
        expect(find.descendant(of: sheet, matching: find.text(book.shortTitle)), findsOneWidget, reason: book.slug);
      }
      expect(find.descendant(of: sheet, matching: find.text('عبد الفتاح القاضي · ت ١٤٠٣هـ')), findsOneWidget);
      expect(find.text('تم'), findsOneWidget);
      await unmount(tester);
      semantics.dispose();
    });

    testWidgets('the page keeps its place from card to card, on a small phone too', (tester) async {
      for (final size in const [Size(390, 844), Size(360, 640)]) {
        await show(tester, tour, size: size);
        await tester.pumpAndSettle();
        final first = tester.getRect(find.byKey(TourScene.pageKey));
        await next(tester);
        expect(tester.getRect(find.byKey(TourScene.pageKey)), first, reason: '$size, card 2');
        await next(tester);
        expect(tester.getRect(find.byKey(TourScene.pageKey)), first, reason: '$size, card 3');
        await unmount(tester);
      }
    });

    testWidgets('at night the page is drawn in the night ink, as the reader draws it; on paper as printed', (tester) async {
      final scan = find.descendant(of: find.byKey(TourScene.pageKey), matching: find.byType(Image));
      final filtered = find.ancestor(of: scan, matching: find.byType(ColorFiltered));
      await show(tester, tour);
      expect(scan, findsOneWidget);
      expect(filtered, findsNothing);
      await unmount(tester);
      const ink = TzNightPage.wisteria;
      await show(tester, tour, theme: const TzTheme(TzColors.night, night: true, nightInk: ink));
      expect(tester.widget<ColorFiltered>(filtered).colorFilter, ColorFilter.matrix(nightInkMatrix(ink)));
      await unmount(tester);
    });

    testWidgets('a swipe turns the card and Back goes one back', (tester) async {
      await show(tester, tour);
      await tester.pumpAndSettle();
      // Arabic pages turn the other way: the next card comes with a swipe to the right.
      await tester.fling(find.byType(TourScreen), const Offset(200, 0), 900);
      await tester.pumpAndSettle();
      expect(find.text('اضغط مطوّلًا على أي بيت'), findsOneWidget);
      await tester.fling(find.byType(TourScreen), const Offset(-200, 0), 900);
      await tester.pumpAndSettle();
      expect(find.text('المتن بين يديك'), findsOneWidget);

      await next(tester);
      await next(tester);
      // The last card: a swipe on does not end the tour; that is the button's.
      await tester.fling(find.byType(TourScreen), const Offset(200, 0), 900);
      await tester.pumpAndSettle();
      expect(find.text('متوفر حاليًا ثلاثة شروح لكل بيت'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('اضغط مطوّلًا على أي بيت'), findsOneWidget);
      expect(find.byType(TourScreen), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('first run: Back from «اختر التلاوة» returns to the card it was reached from', (tester) async {
      await show(tester, (r) => tour(r, replay: false));
      await next(tester);
      await tester.tap(find.text('تخطَّ'));
      await tester.pumpAndSettle();
      expect(find.text('اختر التلاوة'), findsOneWidget);
      expect(find.text('تخطَّ'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('اضغط مطوّلًا على أي بيت'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('nothing overflows at 200 % text on a small phone, on any card or at the reciter', (tester) async {
      await show(tester, (r) => tour(r, replay: false), size: const Size(360, 640), textScale: 2);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 2; i++) {
        await next(tester);
        expect(tester.takeException(), isNull, reason: 'card ${i + 2}');
      }
      await tester.tap(find.text('اختر التلاوة'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  });
}
