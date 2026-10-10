// Item 3.11 against the handoff: the share sheet for one verse and for ten,
// each part where its measured spec puts it. The card inside is pinned by its
// own tests and goldens (test/share_card_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/share_card.dart';
import 'package:shatibiyyah/ui/design/components/share_controls.dart';
import 'package:shatibiyyah/ui/design/components/tz_button.dart';
import 'package:shatibiyyah/ui/design/components/tz_sheet.dart';
import 'package:shatibiyyah/ui/design/components/tz_switch.dart';
import 'package:shatibiyyah/ui/share/share_sheet.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';
import 'package:shatibiyyah/utils/arabic.dart';

import 'fixtures.dart';
import 'handoff.dart';

void main() {
  final data = HandoffContent();
  setUpAll(data.open);
  tearDownAll(data.close);

  Rect rect(WidgetTester tester, Finder f) => tester.getRect(f);

  for (final (state, from, to) in [('share-one', 226, 226), ('share-ten', 235, 244)]) {
    testWidgets('$state: the title and size, the framed card, three sizes, the excerpt row, share and save', (tester) async {
      final spec = HandoffSpec.load('$state-paper');
      if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
      final r = await data.reader(tester, audio: true);
      await pumpPhone(tester, AppShell(reader: r));
      showShareSheet(tester.element(find.byType(AppShell)), data.content, from, to: to);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final c = Conformance(spec);
      final sheet = find.byType(ShareSheet);
      Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);

      final surface = rect(tester, inSheet(find.byKey(TzSheet.surfaceKey)));
      c.same('sheet: from 8 dp under the status bar to the bottom', (surface.top, surface.bottom), (52.0, 844.0));
      c.box('grab', rect(tester, inSheet(find.byKey(TzSheet.grabKey))), spec.component('SheetGrab').rect, tol: 1.5);
      final label = from == to ? 'البيت ${ar(from)}' : 'الأبيات ${isolatedRange(from, to)}';
      c.line('title', rect(tester, inSheet(find.text('مشاركة $label'))), spec.cls('t-title').rect, tol: 1.5);
      final size = from == to ? '١٠٨٠×١٣٥٠' : '١٠٨٠×١٩٢٠';
      final caption = rect(tester, inSheet(find.text('صورة بحجم $size')));
      final captionSpec = spec.nodes.firstWhere((n) => n.cls == 't-cap' && (n.text ?? '').startsWith('صورة بحجم')).rect;
      c.same('size caption at the end of the title\'s line', (caption.left - captionSpec.left).abs() <= 1.5 && (caption.center.dy - captionSpec.center.dy).abs() <= 2, true);

      c.box('framed card', rect(tester, find.byKey(ShareSheet.frameKey)), spec.cls('frame').rect, tol: 1.5);
      c.same('the card inside is laid out at its export size', tester.getSize(find.byType(ShareCard)), from == to ? const Size(1080, 1350) : const Size(1080, 1920));

      c.box('sizes', rect(tester, find.byKey(ShareSheet.formatsKey)), spec.component('ShareFormatPicker').rect, tol: 1.5);
      final buttons = spec.childrenOf(spec.component('ShareFormatPicker'));
      for (final (i, name) in ['مربع', 'طولي', 'قصة'].indexed) {
        c.box('«$name»', rect(tester, find.widgetWithText(ShareFormatButton, name)), buttons[i].rect, tol: 1.5);
      }
      if (from != to) {
        c.same('the limits line under the sizes', (rect(tester, find.byKey(ShareSheet.whyKey)).top + 6 - spec.cls('why').rect.top).abs() <= 1.5, true);
      }
      c.line('«مقتطف من الشرح»', rect(tester, inSheet(find.text('مقتطف من الشرح'))),
          spec.nodes.firstWhere((n) => n.cls == 'k t-label').rect.topLeft & Size(spec.nodes.firstWhere((n) => n.cls == 'k t-label').rect.width, 20), tol: 2);
      c.box('excerpt switch', rect(tester, inSheet(find.byKey(TzSwitch.trackKey))), spec.component('TzSwitch').rect, tol: 2);
      c.box('«مشاركة الصورة»', rect(tester, inSheet(find.widgetWithText(TzButton, 'مشاركة الصورة'))), spec.cls('btn primary').rect, tol: 2);
      c.box('«حفظ»', rect(tester, inSheet(find.widgetWithText(TzButton, 'حفظ'))), spec.cls('btn tonal').rect, tol: 2);
      c.done();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  }

  testWidgets('share-excerpt: the books to quote from are three pills in one row', (tester) async {
    final spec = HandoffSpec.load('share-excerpt-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    final r = await data.reader(tester, audio: true);
    await pumpPhone(tester, AppShell(reader: r));
    showShareSheet(tester.element(find.byType(AppShell)), data.content, 226);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(ShareFormatButton, 'قصة'));
    await tester.pump();
    await tester.tap(find.text('بدون'));
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 60));
    }
    final c = Conformance(spec);
    final chips = spec.childrenOf(spec.cls('chips2'));
    expect(chips, hasLength(3));
    for (final chip in chips) {
      final pill = find.descendant(of: find.widgetWithText(ShareBookChip, chip.text!), matching: find.byKey(ShareBookChip.pillKey));
      c.box('«${chip.text}»', rect(tester, pill), chip.rect, tol: 2);
      c.same('«${chip.text}»: a 48 dp target', tester.getSize(find.widgetWithText(ShareBookChip, chip.text!)).height, 48.0);
    }
    c.box('«مشاركة الصورة»', rect(tester, find.widgetWithText(TzButton, 'مشاركة الصورة')), spec.cls('btn primary').rect, tol: 2);
    c.box('«حفظ»', rect(tester, find.widgetWithText(TzButton, 'حفظ')), spec.cls('btn tonal').rect, tol: 2);
    c.done();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
