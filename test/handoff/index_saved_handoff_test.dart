// Item 3.10 against the handoff: «الفهرس» and «المحفوظ» (its bookmarks, a row
// swiped, the undo notice, and the empty notes tab), each where its measured
// spec puts it. «الإعدادات» is in settings_handoff_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/data/user_store.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/ui/design/components/chapter_row.dart';
import 'package:shatibiyyah/ui/design/components/dock.dart';
import 'package:shatibiyyah/ui/design/components/khatam.dart';
import 'package:shatibiyyah/ui/design/components/ornament.dart';
import 'package:shatibiyyah/ui/design/components/tz_button.dart';
import 'package:shatibiyyah/ui/design/components/undo_snackbar.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';
import 'package:shatibiyyah/ui/shell/index_screen.dart';
import 'package:shatibiyyah/ui/shell/saved_screen.dart';
import 'package:shatibiyyah/utils/arabic.dart';

import 'fixtures.dart';
import 'handoff.dart';

void main() {
  final data = HandoffContent();
  setUpAll(data.open);
  tearDownAll(data.close);

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6)); // past the undo notice's five seconds
  }

  Rect rect(WidgetTester tester, Finder f) => tester.getRect(f);

  testWidgets('index: the header, the filter, khatam rows; the recited chapter 130 dp down, filled, «يُتلى الآن»', (tester) async {
    final spec = HandoffSpec.load('index-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    final r = await data.reader(tester, audio: true);
    await tester.runAsync(() => r.playScope(const PlaybackScope(226, 234)));
    await pumpPhone(tester, AppShell(reader: r, initialTab: DockTab.contents));
    final c = Conformance(spec);

    c.line('title', rect(tester, find.text('الفهرس').first), spec.cls('t-display').rect);
    final count = rect(tester, find.text('٧٨ بابًا · ١١٧٣ بيتًا'));
    final countSpec = spec.cls('t-cap num').rect;
    c.same('count at the end of the title row', (count.left - countSpec.left).abs() <= 1 && (count.top - countSpec.top).abs() <= 1, true);
    c.box('gilt rule', rect(tester, find.byType(GiltRule)), spec.component('GiltRule').rect);
    c.box('filter', rect(tester, find.byKey(IndexScreen.filterKey)), spec.component('SearchField').rect);
    c.centre('filter glyph', rect(tester, find.byKey(IndexScreen.filterGlyphKey)), spec.id(11).rect);
    expect(find.text('اسم الباب أو رقم البيت'), findsOneWidget);

    // The rows in view: chapters 9 to 12, the eleventh being recited.
    for (final (order, id) in [(9, 57), (10, 62), (11, 67), (12, 74)]) {
      final row = find.byWidgetPredicate((w) => w is ChapterRow && w.order == order);
      final kids = spec.childrenOf(spec.id(id));
      c.box('row $order', rect(tester, row), spec.id(id).rect);
      c.box('khatam $order', rect(tester, find.descendant(of: row, matching: find.byType(Khatam))), kids[0].rect);
      final name = kids.firstWhere((n) => n.cls == 't-chapter nm');
      c.line('name $order', rect(tester, find.descendant(of: row, matching: find.byKey(ChapterRow.nameKey))), name.rect);
      c.line('range $order', rect(tester, find.descendant(of: row, matching: find.byKey(ChapterRow.rangeKey))),
          kids.firstWhere((n) => n.cls == 't-cap num').rect);
      final khatam = tester.widget<Khatam>(find.descendant(of: row, matching: find.byType(Khatam)));
      c.same('khatam $order: number, filled only when current', (khatam.label, khatam.current), (spec.childrenOf(kids[0]).first.text, order == 11));
    }
    final ch = data.content.matn.chapterOfVerse(226);
    expect(tester.widget<Text>(find.descendant(
            of: find.byWidgetPredicate((w) => w is ChapterRow && w.order == 11), matching: find.byKey(ChapterRow.nameKey))).data,
        ch.shortLabel);
    expect(find.text('${isolatedRange(226, 234)} · ٩ أبيات'), findsOneWidget);
    final now = spec.cls('now').rect;
    final nowBox = rect(tester, find.byKey(ChapterRow.nowKey));
    c.same('«يُتلى الآن» at the row\'s end', (nowBox.left - now.left).abs() <= 1 && (nowBox.center.dy - now.center.dy).abs() <= 1, true);
    expect(find.text('يُتلى الآن'), findsOneWidget);
    c.same('equaliser', rect(tester, find.byKey(ChapterRow.eqKey)).size, const Size(11.5, 12));

    // «الفهرس» keeps the now-playing row in the dock.
    c.box('dock', rect(tester, find.byKey(Dock.bindingKey)), spec.component('Dock').rect);
    c.done();
    await unmount(tester);
  });

  testWidgets('saved-bookmarks: the header with search, two tabs, three rows, one swiped to «حذف», the undo notice', (tester) async {
    final spec = HandoffSpec.load('saved-bookmarks-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    final r = await data.reader(tester);
    // The one the notice is about.
    await tester.runAsync(() => r.personal!.saveBookmark(1001, color: BookmarkColor.values[1], tag: BookmarkTag.muraja));
    await pumpPhone(tester, AppShell(reader: r, initialTab: DockTab.saved));
    // Swipe the newest row away: «أُزيل المرجع: البيت ١٠٠١», with «تراجع».
    await tester.drag(find.text('البيت ١٠٠١'), const Offset(-390, 0));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 200));
    }
    final c = Conformance(spec);

    c.line('title', rect(tester, find.text('المحفوظ').first), spec.cls('t-display').rect);
    c.centre('search', rect(tester, find.byTooltip('بحث في المحفوظ')), spec.id(8).rect);
    c.box('gilt rule', rect(tester, find.byType(GiltRule)), spec.component('GiltRule').rect);
    c.box('tabs', rect(tester, find.byKey(SavedScreen.tabsKey)), spec.component('SavedTabs').rect);
    c.centre('«المراجع ٣»', rect(tester, find.text('المراجع ٣')), spec.text('المراجع ٣').rect.deflate(0).translate(0, -1));
    c.centre('«الملاحظات ٠»', rect(tester, find.text('الملاحظات ٠')), spec.text('الملاحظات ٠').rect.translate(0, -1));

    final rows = [for (final n in spec.nodes) if (n.component == 'BookmarkRow') n];
    final labels = ['البيت ٢٢٩', 'الأبيات ${isolatedRange(120, 123)}', 'البيت ٦٨٣'];
    final tags = ['مراجعة', 'حفظ', 'إشكال'];
    for (var i = 0; i < 3; i++) {
      final row = find.byType(SavedRow).at(i);
      c.box('row ${i + 1}', rect(tester, row), rows[i].rect);
      if (i == 0) continue; // the design draws it swiped: below
      final inner = spec.childrenOf(rows[i]).firstWhere((n) => n.cls == 'inner');
      final parts = spec.childrenOf(inner);
      c.box('ribbon ${i + 1}', rect(tester, find.descendant(of: row, matching: find.byKey(SavedRow.ribbonKey))), parts[0].rect);
      final top = spec.childrenOf(parts[1]);
      c.line('title ${i + 1}', rect(tester, find.descendant(of: row, matching: find.text(labels[i], findRichText: true))), top[0].rect);
      c.centre('tag ${i + 1}', rect(tester, find.descendant(of: row, matching: find.byKey(SavedRow.tagKey))), top[1].rect, tol: 1.5);
      expect(find.descendant(of: row, matching: find.text(tags[i])), findsOneWidget);
      c.line('verse ${i + 1}', rect(tester, find.descendant(of: row, matching: find.byKey(SavedRow.verseKey))), parts[2].rect);
      c.line('chapter ${i + 1}', rect(tester, find.descendant(of: row, matching: find.byKey(SavedRow.captionKey))), parts[3].rect);
    }

    // The undo notice, 96 dp above the bottom edge.
    c.box('undo notice', rect(tester, find.byKey(UndoSnackbar.surfaceKey)), spec.component('UndoSnackbar').rect);
    expect(find.text('أُزيل المرجع: البيت ١٠٠١'), findsOneWidget);
    c.centre('«تراجع»', rect(tester, find.widgetWithText(TextButton, 'تراجع')), spec.text('تراجع').rect, tol: 1.5);

    // The first row held 100 dp aside: «حذف» on carmine behind it.
    final gesture = await tester.startGesture(tester.getCenter(find.byType(SavedRow).at(0)));
    await gesture.moveBy(const Offset(-30, 0)); // taken as the start of a drag
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();
    final del = spec.cls('del');
    c.centre('trash glyph', rect(tester, find.byKey(SavedScreen.deleteGlyphKey).hitTestable()), spec.childrenOf(del).first.rect, tol: 1.5);
    expect(find.text('حذف').hitTestable(), findsOneWidget);
    c.same('the row is 100 dp aside', rect(tester, find.byType(SavedRow).at(0)).left.round(), -100);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    c.box('dock', rect(tester, find.byKey(Dock.bindingKey)), spec.component('Dock').rect);
    expect(find.byKey(Dock.rowKey), findsNothing);
    c.done();
    await unmount(tester);
  });

  testWidgets('saved-notes: the empty tab says the gesture and offers the way back', (tester) async {
    final spec = HandoffSpec.load('saved-notes-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    final r = await data.reader(tester);
    await pumpPhone(tester, AppShell(reader: r, initialTab: DockTab.saved));
    await tester.tap(find.text('الملاحظات ٠'));
    await tester.pump(const Duration(milliseconds: 300));
    final c = Conformance(spec);

    final empty = spec.component('EmptyState');
    final kids = spec.childrenOf(empty);
    c.box('khatam', rect(tester, find.descendant(of: find.byType(SavedScreen), matching: find.byType(Khatam))), kids[0].rect);
    c.centre('title', rect(tester, find.text('لم تكتب ملاحظة بعد')), kids[1].rect);
    c.same('title line', rect(tester, find.text('لم تكتب ملاحظة بعد')).height, 32.0);
    final body = rect(tester, find.textContaining('اضغط مطوّلًا على أي بيت'));
    c.same('body: two lines under the title', (body.top - kids[2].rect.top).abs() <= 1 && (body.height - 48).abs() <= 1, true);
    final button = rect(tester, find.widgetWithText(TzButton, 'افتح المتن'));
    c.same('button: 48 high, centred', (button.top - kids[3].rect.top).abs() <= 1 && button.height == 48 && (button.center.dx - 195).abs() <= 1, true);
    c.done();

    await tester.tap(find.text('افتح المتن'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.state<AppShellState>(find.byType(AppShell)).tab, DockTab.matn);
    await unmount(tester);
  });
}
