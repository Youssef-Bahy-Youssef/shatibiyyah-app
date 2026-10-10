// «رموز القراء» (P6, rumuz-legend; item 3.15): the snapshot's readers and codes, and
// the screen's three tabs: every symbol in its frame (ADR 0024), the letters one
// row per reader, a collective name spelled out; a code's source verse opens the
// reader there, and a symbol's tip opens the screen on that symbol.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/data/rumuz_repository.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/design/components/khatam.dart';
import 'package:shatibiyyah/ui/design/components/symbol_chip.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/shell/rumuz_screen.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

void main() {
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('rumuz_test');
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

  test('seven imams with two transmitters each; 21 letters, 6 group letters, 8 words', () {
    final z = content.rumuz;
    expect(z.readers.length, 21);
    expect(z.readers.where((r) => r.isImam).length, 7);
    expect(z.ofKind(RamzKind.letter).length, 21);
    expect(z.ofKind(RamzKind.groupLetter).map((r) => r.code).join(), 'ثخذظغش');
    expect(z.ofKind(RamzKind.word).length, 8);
    expect(z.ofKind(RamzKind.letter).every((r) => r.fromVerse == 45 && r.readerIds.length == 1), isTrue);
    for (final r in z.rumuz) {
      expect(r.readerIds.every((id) => z.readers.any((x) => x.id == id)), isTrue, reason: r.code);
    }
  });

  Future<ReaderController> open(WidgetTester tester, {String? focus, TzTheme tz = TzTheme.dark}) async {
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
        initialVerse: 1,
      );
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: tzThemeData(tz),
      home: Directionality(textDirection: TextDirection.rtl, child: RumuzScreen(reader: r, focus: focus)),
    ));
    await tester.pump();
    return r;
  }

  List<String> chips(WidgetTester tester) => [for (final c in tester.widgetList<SymbolChip>(find.byType(SymbolChip))) c.code];

  testWidgets('three tabs: letters by triples, groups and words with their verses', (tester) async {
    final r = await open(tester);
    expect(find.text('رموز القراء'), findsOneWidget);
    expect(find.text('أبج دهز حطي كلم نصع فضق رست، البيت ٤٥'), findsOneWidget);
    expect(find.text('قالون'), findsOneWidget);

    await tester.tap(find.text('الجماعات'));
    await tester.pump();
    expect(find.text('الكوفيون'), findsOneWidget);
    expect(find.textContaining('الأبيات'), findsOneWidget);

    await tester.tap(find.text('الكلمات'));
    await tester.pump();
    expect(find.text('صحبة'), findsOneWidget);
    expect(find.text('حمزة والكسائي وشعبة'), findsOneWidget);

    await tester.ensureVisible(find.text('حصن'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حصن'));
    await tester.pumpAndSettle();
    expect(r.verse, 55);
  });

  testWidgets('every symbol is in its frame, in the rubric ink', (tester) async {
    await open(tester, tz: TzTheme.paper);
    expect(chips(tester).join(), 'أبجدهزحطيكلمنصعفضقرست');
    final rubric = TzColors.paper.rubric;
    for (final chip in find.byType(SymbolChip).evaluate().take(3)) {
      final box = tester.widget<Container>(find.descendant(of: find.byWidget(chip.widget), matching: find.byType(Container)).first);
      final d = box.decoration! as BoxDecoration;
      expect((d.color, (d.border! as Border).top.color, (d.border! as Border).top.width),
          (rubric.withValues(alpha: TzSymbolFrame.fill), rubric.withValues(alpha: TzSymbolFrame.line), TzSymbolFrame.lineWidth));
      expect(tester.widget<Text>(find.descendant(of: find.byWidget(chip.widget), matching: find.byType(Text))).style!.color, rubric);
    }
    await tester.tap(find.text('الجماعات'));
    await tester.pump();
    expect(chips(tester).join(), 'ثخذظغش');
    await tester.tap(find.text('الكلمات'));
    await tester.pump();
    expect(chips(tester), ['صحبة', 'صحاب', 'عمّ', 'سما', 'حقّ', 'نفر', 'حرمي', 'حصن']);
  });

  test('a symbol keeps at least 4.5:1 on its frame, on paper and in every night ink', () {
    double lum(Color c) {
      double f(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    }

    double onFrame(Color ink, Color page) {
      final a = lum(ink), b = lum(Color.alphaBlend(ink.withValues(alpha: TzSymbolFrame.fill), page));
      return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
    }

    expect(onFrame(TzColors.paper.rubric, TzColors.paper.bg), closeTo(5.88, 0.05));
    for (final ink in TzNightPage.inks) {
      expect(onFrame(ink.accent, TzColors.night.bg), greaterThanOrEqualTo(6.5), reason: ink.id);
    }
    expect(TzSymbolFrame.minContrast, 4.5);
  });

  testWidgets('the letters: one row per reader, numbered, his letter then his two transmitters\'', (tester) async {
    await open(tester);
    expect([for (final k in tester.widgetList<Khatam>(find.byType(Khatam))) k.label], ['١', '٢', '٣', '٤', '٥', '٦', '٧']);
    expect(find.text('القارئ'), findsOneWidget);
    expect(find.text('راوياه'), findsOneWidget);
    // «كلم»: ابن عامر, then هشام and ابن ذكوان, on one line, right to left.
    final imam = tester.getRect(find.text('ابن عامر')), first = tester.getRect(find.text('هشام')), second = tester.getRect(find.text('ابن ذكوان'));
    expect(imam.center.dy, closeTo(first.center.dy, 1));
    expect(first.center.dy, closeTo(second.center.dy, 1));
    expect(imam.left > first.right && first.left > second.right, isTrue);
    expect(tester.getRect(find.text('القارئ')).right, closeTo(tester.getRect(find.widgetWithText(SymbolChip, 'ك')).right, 1));
    // The reader's name is the heavier one.
    expect(tester.widget<Text>(find.text('ابن عامر')).style!.fontWeight, FontWeight.w700);
    expect(tester.widget<Text>(find.text('هشام')).style!.fontWeight, isNot(FontWeight.w700));
    // The two «الدوري» are told apart by their rows: أبو عمرو's and الكسائي's.
    expect(find.text('الدوري'), findsNWidgets(2));
  });

  testWidgets('a collective name is spelled out: «الكوفيون» are عاصم، حمزة، الكسائي; a plain list is not repeated', (tester) async {
    await open(tester);
    await tester.tap(find.text('الجماعات'));
    await tester.pump();
    expect(find.text('عاصم، حمزة، الكسائي'), findsOneWidget);
    expect(find.text('ابن كثير، أبو عمرو، ابن عامر، عاصم، حمزة، الكسائي'), findsOneWidget); // «السبعة غير نافع»
    expect(find.text('حمزة والكسائي'), findsOneWidget); // «ش»: its name is its list
    expect(find.text('حمزة، الكسائي'), findsNothing);
    final sem = tester.getSemantics(find.widgetWithText(InkWell, 'الكوفيون'));
    expect(sem.label, 'رمز ث: الكوفيون (عاصم، حمزة، الكسائي)، البيت ٤٩');
    await tester.tap(find.text('الكلمات'));
    await tester.pump();
    expect(find.text('نافع، عاصم، حمزة، الكسائي'), findsOneWidget); // «حصن»: الكوفيون ونافع
    expect(find.text('حمزة، الكسائي، شعبة'), findsNothing); // «صحبة» lists them already
  });

  testWidgets('opened from a symbol, its tab is shown with the symbol marked', (tester) async {
    await open(tester, focus: 'ظ', tz: TzTheme.paper);
    await tester.pumpAndSettle();
    expect(chips(tester).join(), 'ثخذظغش');
    expect([for (final c in tester.widgetList<SymbolChip>(find.byType(SymbolChip))) if (c.active) c.code], ['ظ']);
    final d = tester.widget<Container>(find.descendant(of: find.widgetWithText(SymbolChip, 'ظ'), matching: find.byType(Container)).first).decoration!
        as BoxDecoration;
    expect((d.color, (d.border! as Border).top.color, (d.border! as Border).top.width),
        (TzColors.paper.lapisWash, TzColors.paper.lapis, TzSymbolFrame.activeLineWidth));
    await tester.pumpWidget(const SizedBox()); // each visit is a new screen
    await open(tester, focus: 'حصن');
    await tester.pumpAndSettle();
    expect([for (final c in tester.widgetList<SymbolChip>(find.byType(SymbolChip))) if (c.active) c.code], ['حصن']);
    await tester.pumpWidget(const SizedBox());
    await open(tester); // from settings: the letters, none marked
    expect(tester.widgetList<SymbolChip>(find.byType(SymbolChip)).any((c) => c.active), isFalse);
  });

  testWidgets('with large text a reader\'s transmitters go under him, and nothing overflows', (tester) async {
    await open(tester);
    await tester.pumpWidget(MaterialApp(
      theme: tzThemeData(TzTheme.dark),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(390, 844), textScaler: TextScaler.linear(2)),
        child: Directionality(textDirection: TextDirection.rtl, child: tester.widget<RumuzScreen>(find.byType(RumuzScreen))),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final imam = tester.getRect(find.text('نافع')), first = tester.getRect(find.text('قالون'));
    expect(first.top, greaterThan(imam.bottom));
  });
}
