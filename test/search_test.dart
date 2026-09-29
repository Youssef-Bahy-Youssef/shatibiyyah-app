// «البحث»: vowel- and hamza-blind search over verses, chapters and the books; the
// mapped normalizer behind the snippets; the search and quick-jump screens.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/domain/normalizer.dart';
import 'package:shatibiyyah/domain/search.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/design/taysir_colors.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/search/search_screen.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('search_test');
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

  test('the mapped normalizer gives normalizeMatching\'s text, with in-range sources', () {
    final fixture = jsonDecode(File('test/fixtures/normalizer_parity.json').readAsStringSync()) as Map<String, dynamic>;
    for (final c in (fixture['cases'] as List).cast<List<dynamic>>()) {
      final input = c[0] as String;
      final m = normalizeMatchingMapped(input);
      expect(m.text, normalizeMatching(input));
      expect(m.source, hasLength(m.text.length));
      expect(m.source.every((i) => i >= 0 && i < input.length), isTrue);
    }
  });

  test('snippets are cut from the displayed text around the match', () {
    const display = 'قال الناظم رحمه الله: وَبَسْمَلَ بَيْنَ السُّورَتَيْنِ بِسُنَّةٍ، وهذا قول الجمهور.';
    final s = snippetAround(display, normalizeMatching('بسنة'), before: 5, after: 5);
    expect(s, contains('بِسُنَّةٍ'));
    expect(s, startsWith('…'));
    expect(s, endsWith('…'));
  });

  test('vowel and hamza blind: «بدات» finds verse 1; a chapter by its name; the books', () async {
    final searcher = Searcher(content);
    final a = await searcher.search('بدات');
    expect(a.results.verses, contains(1));

    final b = await searcher.search('نقل حركة');
    expect(b.results.chapters.map((c) => c.fromVerse), contains(226));

    final c = await searcher.search('ورش');
    expect(c.results.verses, isNotEmpty);
    expect(c.commentaryTotal, greaterThan(c.results.commentary.length)); // many passages, 30 shown
    expect(c.results.commentary, hasLength(kMaxCommentaryHits));
    expect(c.results.commentary.first.snippet, contains('ورش'));

    expect((await searcher.search('ب')).results.isEmpty, isTrue); // too short
  });

  Future<ReaderController> reader(WidgetTester tester) async {
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
    return r;
  }

  Future<void> host(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: ThemeData(extensions: const [TaysirColors.dark]), home: home));
  }

  testWidgets('typing finds a verse; a tap opens the reader there', (tester) async {
    final r = await reader(tester);
    await host(tester, Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => SearchScreen(reader: r))));
    await tester.pump();
    expect(find.text('الانتقال السريع إلى صفحة أو بيت'), findsOneWidget); // the empty state

    await tester.enterText(find.byType(TextField), 'بدات ببسم');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200))); // the SQL query
    await tester.pump();
    expect(find.text(content.matn.verse(1).firstHemistich), findsOneWidget);
    await tester.tap(find.text(content.matn.verse(1).firstHemistich));
    await tester.pump();
    expect(r.verse, 1);
  });

  testWidgets('quick jump: 2 2 9 on the keypad, then ← opens verse 229', (tester) async {
    final r = await reader(tester);
    await host(tester, Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => JumpScreen(reader: r))));
    await tester.pump();
    expect(find.text('٢٢٦ من ١١٧٣'), findsOneWidget); // starts on the current verse
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.bySemanticsLabel('حذف'));
      await tester.pump();
    }
    for (final k in ['٢', '٢', '٩']) {
      await tester.tap(find.text(k));
      await tester.pump();
    }
    expect(find.text('٢٢٩ من ١١٧٣'), findsOneWidget);
    expect(find.text(content.matn.verse(229).firstHemistich), findsOneWidget); // live preview
    await tester.tap(find.bySemanticsLabel('انتقال'));
    await tester.pump();
    expect(r.verse, 229);
  });
}
