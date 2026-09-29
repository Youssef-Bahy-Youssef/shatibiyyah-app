// «البحث»: vowel- and hamza-blind search over verses, chapters and the books; the
// mapped normalizer behind the snippets; book passages a page at a time, numbers,
// notes and recent queries (search v2); the search and quick-jump screens.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/app/recent_searches.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/data/user_store.dart' show Note;
import 'package:shatibiyyah/domain/normalizer.dart';
import 'package:shatibiyyah/domain/search.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/design/taysir_colors.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/search/search_screen.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:shatibiyyah/utils/arabic.dart';
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
    expect(c.results.commentary, hasLength(kCommentaryPageSize));
    expect(c.results.commentary.first.snippet, contains('ورش'));

    expect((await searcher.search('ب')).results.isEmpty, isTrue); // too short
  });

  test('book passages page through every matching block once, in the count', () async {
    final searcher = Searcher(content);
    final first = await searcher.search('النقل');
    final q = first.results.query;
    final all = [...first.results.commentary];
    while (all.length < first.commentaryTotal) {
      final page = await searcher.commentaryPage(q, all.length);
      expect(page, isNotEmpty);
      all.addAll(page);
    }
    expect(all, hasLength(first.commentaryTotal));
    expect(await searcher.commentaryPage(q, all.length), isEmpty);
    final keys = {for (final h in all) '${h.bookId}|${h.fromVerse}|${h.snippet}'};
    expect(keys.length, greaterThan(all.length * 0.9)); // pages do not repeat
    expect([for (final h in all) h.fromVerse], orderedEquals([...all.map((h) => h.fromVerse)]..sort()));
  });

  test('the pipeline\'s hits for 20 sample queries are all found (spd search parity)', () async {
    // test/fixtures/search_parity.json is written by tool/search_parity.py from
    // `spd search`: FTS5 whole tokens, so each is also a substring hit here.
    final fixture = jsonDecode(File('test/fixtures/search_parity.json').readAsStringSync()) as Map<String, dynamic>;
    final searcher = Searcher(content);
    final times = <int>[];
    for (final c in (fixture['cases'] as List).cast<Map<String, dynamic>>()) {
      final watch = Stopwatch()..start();
      final r = await searcher.search(c['query'] as String);
      times.add(watch.elapsedMilliseconds);
      expect(r.results.verses.toSet().containsAll((c['verses'] as List).cast<int>()), isTrue, reason: '${c['query']}');
      expect(r.commentaryTotal, greaterThanOrEqualTo(c['commentary_blocks'] as int), reason: '${c['query']}');
    }
    times.sort();
    expect(times[(times.length * 0.95).ceil() - 1], lessThan(300)); // p95 (on the device: plan P6)
  });

  test('a number alone is a verse or page number, in any digits', () {
    expect(queryNumber('٢٢٩'), 229);
    expect(queryNumber(' 12 '), 12);
    expect(queryNumber('۳۴'), 34);
    expect(queryNumber('٢٢٩ب'), isNull);
    expect(queryNumber('ورش'), isNull);
    expect(queryNumber(''), isNull);
    expect(queryNumber('12345'), isNull);
  });

  test('notes match vowel-blind, in verse order', () {
    final now = DateTime(2026);
    final notes = [Note('a', 300, 'قارن بالوافي', now), Note('b', 12, 'راجع الوَافِي هنا', now), Note('c', 5, 'غيره', now)];
    expect(notesMatching(notes, normalizeMatching('الوافي')).map((n) => n.verse), [12, 300]);
  });

  test('recent queries: newest first, one per normalized form, at most eight, cleared', () async {
    SharedPreferences.setMockInitialValues({});
    final recent = RecentSearches(await Prefs.create());
    expect(recent.all, isEmpty);
    recent
      ..add('ورش')
      ..add('بدأت')
      ..add(' بدات ')
      ..add('  ');
    expect(recent.all, ['بدات', 'ورش']);
    for (var i = 0; i < 10; i++) {
      recent.add('كلمة$i');
    }
    expect(recent.all, hasLength(kMaxRecentSearches));
    expect(recent.all.first, 'كلمة9');
    recent.clear();
    expect(recent.all, isEmpty);
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

  testWidgets('a number offers its verse; opening it remembers the query', (tester) async {
    final r = await reader(tester);
    await host(tester, Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => SearchScreen(reader: r))));
    await tester.pump();
    expect(find.text('بحثت مؤخرًا'), findsNothing);
    await tester.enterText(find.byType(TextField), '٢٢٩');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.text('البيت ٢٢٩'), findsOneWidget);
    await tester.tap(find.text('البيت ٢٢٩'));
    await tester.pump();
    expect(r.verse, 229);
    expect(RecentSearches(r.viewer.prefs).all, ['٢٢٩']);

    await tester.pumpWidget(const SizedBox()); // a fresh search screen
    await host(tester, Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => SearchScreen(reader: r))));
    await tester.pump();
    expect(find.text('بحثت مؤخرًا'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '٢٢٩'), findsOneWidget);
  });

  testWidgets('«عرض المزيد» loads the next page of book passages', (tester) async {
    final r = await reader(tester);
    await host(tester, Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => SearchScreen(reader: r))));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'ورش');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    final total = (await tester.runAsync(() => Searcher(content).search('ورش')))!.commentaryTotal;
    final more = find.text('عرض المزيد (بقي ${ar(total - kCommentaryPageSize)})');
    await tester.scrollUntilVisible(more, 600, scrollable: find.byType(Scrollable).last);
    await tester.tap(more);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(more, findsNothing);
    await tester.scrollUntilVisible(find.text('عرض المزيد (بقي ${ar(total - 2 * kCommentaryPageSize)})'), 600,
        scrollable: find.byType(Scrollable).last);
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
