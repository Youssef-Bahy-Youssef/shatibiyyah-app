// Items 3.4 and 3.5 against the handoff: the reading screen in its playing
// state, the verse popover and the chapter popover, each where its measured
// spec (design/redesign/handoff/specs/) puts it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/ui/design/components/anchored_popover.dart';
import 'package:shatibiyyah/ui/design/components/dock.dart';
import 'package:shatibiyyah/ui/design/components/khatam.dart';
import 'package:shatibiyyah/ui/design/components/tz_button.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/reader/reader_screen.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';

import 'fixtures.dart';
import 'handoff.dart';

void main() {
  final data = HandoffContent();
  setUpAll(data.open);
  tearDownAll(data.close);

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  Rect rect(WidgetTester tester, Finder f) => tester.getRect(f);
  Rect onPage(WidgetTester tester, Rect inViewer) => inViewer.shift(tester.getTopLeft(find.byType(PageViewer)));

  testWidgets('reader-playing: the top bar, the page, the playing verse, the ribbon and the dock', (tester) async {
    final spec = HandoffSpec.load('reader-playing-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    final ReaderController r = await data.reader(tester, audio: true);
    await pumpPhone(tester, AppShell(reader: r));
    await tester.runAsync(() => r.playScope(const PlaybackScope(226, 234)));
    await tester.pump(const Duration(milliseconds: 400));
    final c = Conformance(spec);

    // Top bar: the chapter in short form (no «باب», no tashkeel: the full title is printed below).
    final title = spec.cls('t-chapter');
    expect(find.text(title.text!), findsOneWidget);
    c.line('title', rect(tester, find.text(title.text!)), title.rect);
    c.same('title colour', tester.widget<Text>(find.text(title.text!)).style!.color, TzColors.paper.ink);
    final folio = spec.component('Folio tag');
    final folioBox = rect(tester, find.byKey(ReaderScreen.folioKey));
    c.line('folio', folioBox, folio.rect);
    final caption = rect(tester, find.text('الأصول · الباب ١١ من ٧٨'));
    c.same('caption starts 6 dp after the folio', (folioBox.left - caption.right).round(), 6);
    c.line('caption line', Rect.fromLTRB(0, caption.top, title.rect.right, caption.bottom), spec.cls('t-cap').rect);
    c.centre('search', rect(tester, find.byTooltip('بحث')), spec.id(10).rect);
    c.centre('display', rect(tester, find.byTooltip('العرض')), spec.id(12).rect);

    // The page sheet over its back sheet, the playing wash and the bookmark's ribbon.
    c.box('page', rect(tester, find.byType(PageViewer)), spec.component('ReadingPage').rect);
    c.box('back sheet', rect(tester, find.byKey(ReaderScreen.backSheetKey)), spec.cls('sheetback').rect);
    c.box('playing wash', onPage(tester, r.viewer.viewRectOfVerse(226)!), spec.component('VerseHighlight').rect, tol: 1.5);
    c.box('ribbon on 229', onPage(tester, r.viewer.ribbonRect(229)!), spec.cls('ribbon').rect, tol: 1.5);

    // The dock.
    c.box('dock', rect(tester, find.byKey(Dock.bindingKey)), spec.component('Dock').rect);
    c.box('now-playing row', rect(tester, find.byKey(Dock.rowKey)), spec.component('Dock now-playing row').rect);
    c.box('tabs', rect(tester, find.byKey(Dock.tabsKey)), spec.component('Dock tabs').rect);
    c.box('dock khatam', rect(tester, find.descendant(of: find.byKey(Dock.rowKey), matching: find.byType(Khatam))), spec.component('Khatam').rect);
    c.box('play disc', rect(tester, find.byKey(Dock.playDiscKey)), spec.cls('dplay').rect);
    // The transport, in the player's order (v2.css .np-ctl).
    final [previous, _, next] = spec.childrenOf(spec.cls('np-ctl'));
    c.centre('previous verse', rect(tester, find.bySemanticsLabel('البيت السابق')), previous.rect);
    c.centre('next verse', rect(tester, find.bySemanticsLabel('البيت التالي')), next.rect);
    c.line('dock title', rect(tester, find.textContaining('البيت ٢٢٦', findRichText: true)), spec.id(23).rect);
    for (final label in ['المتن', 'الفهرس', 'المحفوظ', 'الإعدادات']) {
      c.same('tab $label centre', rect(tester, find.text(label)).center.dx.round(), spec.text(label).rect.center.dx.round());
    }
    c.done();
    await unmount(tester);
  });

  testWidgets('reader-none (night): «استمع إلى المتن» with «تنزيل» in the dock; the same geometry at night', (tester) async {
    final spec = HandoffSpec.load('reader-none-night');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    final r = await data.reader(tester);
    await pumpPhone(tester, AppShell(reader: r), tz: TzTheme.dark);
    final c = Conformance(spec);
    final title = spec.cls('t-chapter');
    c.line('title', rect(tester, find.text(title.text!)), title.rect);
    c.same('title colour', tester.widget<Text>(find.text(title.text!)).style!.color, TzColors.night.ink);
    c.same('folio text is gilt at night', tester.widget<Text>(find.text('ص ١٩')).style!.color, TzColors.night.gilt);
    c.box('page', rect(tester, find.byType(PageViewer)), spec.component('ReadingPage').rect);
    c.box('dock', rect(tester, find.byKey(Dock.bindingKey)), spec.component('Dock').rect);
    c.line('«استمع إلى المتن»', rect(tester, find.text('استمع إلى المتن')), spec.text('استمع إلى المتن').rect);
    final pill = spec.text('تنزيل');
    c.centre('«تنزيل»', rect(tester, find.text('تنزيل')), Rect.fromLTWH(pill.rect.left + 14, pill.rect.top, pill.rect.width - 28 - 28, pill.rect.height), tol: 3);
    c.done();
    await unmount(tester);
  });

  testWidgets('verse: the spotlight on 229 and its popover', (tester) async {
    final spec = HandoffSpec.load('verse-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    final r = await data.reader(tester, audio: true);
    await pumpPhone(tester, AppShell(reader: r));
    r.openMenu(229);
    await tester.pump(const Duration(milliseconds: 300));
    final c = Conformance(spec);
    final body = find.byKey(AnchoredPopover.bodyKey);
    Finder inBody(Finder f) => find.descendant(of: body, matching: f);

    c.box('spotlight', onPage(tester, r.viewer.viewRectOfVerse(229)!), spec.component('VerseHighlight').rect, tol: 1.5);
    c.box('popover', rect(tester, body), spec.component('AnchoredPopover').rect, tol: 1.5);
    c.box('khatam', rect(tester, inBody(find.byType(Khatam))), spec.id(45).rect, tol: 1.5);
    c.line('«البيت ٢٢٩»', rect(tester, inBody(find.text('البيت ٢٢٩'))), spec.text('البيت ٢٢٩').rect, tol: 1.5);
    c.line('where it is', rect(tester, inBody(find.textContaining('· ص ١٩'))), spec.id(49).rect, tol: 1.5);
    final tag = spec.text('مراجعة');
    c.same('tag ends at the body\'s end', rect(tester, inBody(find.text('مراجعة'))).left.round(), tag.rect.left.round());
    c.line('first hemistich', rect(tester, inBody(find.text(data.content.matn.verse(229).firstHemistich))),
        Rect.fromLTWH(26, 369.5, 338, 34), tol: 1.5);
    c.line('second hemistich', rect(tester, inBody(find.text(data.content.matn.verse(229).secondHemistich))),
        Rect.fromLTWH(26, 403.5, 338, 34), tol: 1.5);
    for (final label in ['الشرح', 'استمع', 'المرجع', 'ملاحظة']) {
      c.box('tile $label', rect(tester, find.widgetWithText(InkWell, label)), spec.text(label).rect, tol: 1.5);
    }
    c.same('«الشرح» is the filled tile', tester.widget<Text>(find.text('الشرح')).style!.color, TzColors.paper.onAction);
    // The text buttons: drawn 44 dp high in 48 dp targets, from the body's start, 2 dp apart.
    // (Their label is the `label` role, 14 dp, where the prototype draws 13: the handoff's rule.)
    Rect? previous;
    for (final label in ['نسخ', 'مشاركة', 'تحديد أبيات']) {
      final actual = rect(tester, find.widgetWithText(InkWell, label)), expected = spec.text(label).rect;
      c.same('$label starts', (previous == null ? actual.right - expected.right : previous.left - actual.right - 2).abs() <= 0.5, true);
      c.same('$label centre y', (actual.center.dy - expected.center.dy).abs() <= 1, true);
      c.same('$label is a 48 dp target', actual.height >= 48, true);
      previous = actual;
    }
    c.done();
    await unmount(tester);
  });

  testWidgets('heading: the lit title and the chapter popover', (tester) async {
    final spec = HandoffSpec.load('heading-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    final r = await data.reader(tester, audio: true);
    await pumpPhone(tester, AppShell(reader: r));
    final index = data.content.matn.chapters.indexWhere((ch) => ch.fromVerse == 226);
    r.openHeading(index);
    await tester.pump(const Duration(milliseconds: 300));
    final c = Conformance(spec);
    final body = find.byKey(AnchoredPopover.bodyKey);
    Finder inBody(Finder f) => find.descendant(of: body, matching: f);

    c.box('lit heading', onPage(tester, r.viewer.viewRectOfChapter(index)!), spec.component('VerseHighlight').rect, tol: 1.5);
    c.box('popover', rect(tester, body), spec.component('AnchoredPopover').rect, tol: 1.5);
    c.box('khatam', rect(tester, inBody(find.byType(Khatam))), spec.id(45).rect, tol: 1.5);
    c.line('ordinal', rect(tester, inBody(find.text('الباب الحادي عشر'))), spec.text('الباب الحادي عشر').rect, tol: 1.5);
    c.line('size, range, page', rect(tester, inBody(find.textContaining('· ص ١٩'))), spec.id(49).rect, tol: 1.5);
    expect(inBody(find.text('يبدأ بـ')), findsOneWidget);
    final firstWords = rect(tester, inBody(find.text(data.content.matn.verse(226).firstHemistich)));
    c.same('first words: a 34 dp line at 238', (firstWords.top - spec.id(50).rect.top).abs() <= 1.5 && (firstWords.height - 34).abs() <= 1, true);
    c.box('«تشغيل الباب»', rect(tester, find.widgetWithText(TzButton, 'تشغيل الباب')), spec.text('تشغيل الباب').rect, tol: 1.5);
    c.box('«الشرح»', rect(tester, find.widgetWithText(TzButton, 'الشرح')), spec.text('الشرح').rect, tol: 1.5);
    c.done();
    await unmount(tester);
  });
}
