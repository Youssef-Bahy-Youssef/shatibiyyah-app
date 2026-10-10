// Item 3.10 (ADR 0012): the index is one list of the 78 chapters. It opens on
// the reader's chapter, filters by a name or a verse number, and a row opens
// its chapter in the reader.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/ui/design/components/chapter_row.dart';
import 'package:shatibiyyah/ui/design/components/dock.dart';
import 'package:shatibiyyah/ui/design/components/khatam.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';
import 'package:shatibiyyah/ui/shell/index_screen.dart';

import 'package:shatibiyyah/utils/arabic.dart';

import 'handoff/fixtures.dart';
import 'handoff/handoff.dart';

void main() {
  final data = HandoffContent();
  setUpAll(data.open);
  tearDownAll(data.close);

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  List<int> shown(WidgetTester tester) => [for (final w in tester.widgetList<ChapterRow>(find.byType(ChapterRow))) w.order];
  Finder row(int order) => find.byWidgetPredicate((w) => w is ChapterRow && w.order == order);

  test('the filter: a name without its marks, or a verse number in either digits', () {
    final chapters = data.content.matn.chapters;
    List<int> orders(String q) => [for (final c in filterChapters(chapters, q)) c.orderIndex];
    expect(orders(''), hasLength(78));
    expect(orders('  '), hasLength(78));
    expect(orders('755'), [data.content.matn.chapterOfVerse(755).orderIndex]);
    expect(orders('٧٥٥'), orders('755'));
    expect(orders('1'), [0]); // the introduction
    expect(orders('1173'), [chapters.last.orderIndex]);
    expect(orders('1174'), isEmpty);
    expect(orders('0'), isEmpty);
    expect(orders('الهمزه'), isNotEmpty); // ة and ه fold, marks are ignored
    expect(orders('الهمزه'), orders('الْهَمْزَةِ'));
    for (final c in filterChapters(chapters, 'هود')) {
      expect(plainName(c.title), contains('هود'));
    }
    expect(orders('لا يوجد باب بهذا'), isEmpty);
  });

  testWidgets('opens on the reader\'s chapter; nothing recited: «الحالي», no equaliser', (tester) async {
    final r = await data.reader(tester, audio: true);
    await pumpPhone(tester, AppShell(reader: r, initialTab: DockTab.contents));
    final current = row(11);
    expect(current, findsOneWidget);
    expect(tester.getTopLeft(current).dy - tester.getBottomLeft(find.byKey(IndexScreen.filterKey)).dy, closeTo(6 + 130, 1));
    expect(tester.widget<Khatam>(find.descendant(of: current, matching: find.byType(Khatam))).current, isTrue);
    expect(find.text('الحالي'), findsOneWidget);
    expect(find.text('يُتلى الآن'), findsNothing);
    expect(find.byKey(ChapterRow.eqKey), findsNothing);
    expect(tester.getSemantics(current), matchesSemantics(
        label: '${data.content.matn.chapterOfVerse(226).shortLabel}، الباب ١١، الأبيات ٢٢٦ إلى ٢٣٤، الباب الحالي',
        isButton: true, hasTapAction: true));

    await tester.runAsync(() => r.playScope(const PlaybackScope(226, 234)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('يُتلى الآن'), findsOneWidget);
    expect(find.text('الحالي'), findsNothing);
    expect(find.byKey(ChapterRow.eqKey), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the first chapters open at the top: the introduction has an empty khatam', (tester) async {
    final r = await data.reader(tester);
    await tester.runAsync(() => r.tapVerse(1));
    await pumpPhone(tester, AppShell(reader: r, initialTab: DockTab.contents));
    expect(shown(tester).first, 0);
    expect(tester.getTopLeft(row(0)).dy - tester.getBottomLeft(find.byKey(IndexScreen.filterKey)).dy, closeTo(6, 1));
    expect(tester.widget<Khatam>(find.descendant(of: row(0), matching: find.byType(Khatam))).label, '');
    expect(tester.widget<Khatam>(find.descendant(of: row(1), matching: find.byType(Khatam))).label, '١');
    await unmount(tester);
  });

  testWidgets('typing filters at once; a row opens its chapter in the reader; no match says how to find one', (tester) async {
    final r = await data.reader(tester);
    await pumpPhone(tester, AppShell(reader: r, initialTab: DockTab.contents));
    await tester.enterText(find.byType(TextField), '٧٥٥');
    await tester.pump();
    final target = data.content.matn.chapterOfVerse(755);
    expect(shown(tester), [target.orderIndex]);

    await tester.enterText(find.byType(TextField), 'لا باب كهذا');
    await tester.pump();
    expect(find.byType(ChapterRow), findsNothing);
    expect(find.text('لا باب بهذا الاسم. جرّب جزءًا من الاسم أو رقم بيت بين ١ و١١٧٣.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '755');
    await tester.pump();
    await tester.tap(row(target.orderIndex));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.state<AppShellState>(find.byType(AppShell)).tab, DockTab.matn);
    expect(r.verse, target.fromVerse);
    await unmount(tester);
  });
}
