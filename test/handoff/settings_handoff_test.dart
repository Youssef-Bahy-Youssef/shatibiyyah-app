// Items 3.6 and 3.10 (settings) against the handoff: «الإعدادات» and the
// night-ink picker, each where its measured spec puts it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/dock.dart';
import 'package:shatibiyyah/ui/design/components/min_segmented.dart';
import 'package:shatibiyyah/ui/design/components/night_crop.dart';
import 'package:shatibiyyah/ui/design/components/night_ink_option.dart';
import 'package:shatibiyyah/ui/design/components/ornament.dart';
import 'package:shatibiyyah/ui/design/components/settings_row.dart';
import 'package:shatibiyyah/ui/design/components/tz_button.dart';
import 'package:shatibiyyah/ui/design/components/tz_sheet.dart';
import 'package:shatibiyyah/ui/design/components/tz_switch.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';

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

  testWidgets('settings-main: the header, four groups, their rows and controls, the dock alone', (tester) async {
    final spec = HandoffSpec.load('settings-main-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    final r = await data.reader(tester);
    await pumpPhone(tester, AppShell(reader: r, initialTab: DockTab.settings));
    final c = Conformance(spec);

    c.line('title', rect(tester, find.text('الإعدادات').first), spec.text('الإعدادات', cls: 't-display').rect);
    c.box('gilt rule', rect(tester, find.byType(GiltRule)), spec.component('GiltRule').rect);

    // The four groups, by their caption, and every row the spec lists, in order.
    for (final caption in ['العرض', 'الوضع الليلي', 'الاستماع', 'التطبيق']) {
      final node = spec.text(caption, cls: 't-cap');
      final actual = rect(tester, find.text(caption));
      c.same('«$caption» caption', (actual.right - (node.rect.right - 4)).abs() <= 1 && (actual.top - node.rect.top).abs() <= 1, true);
    }
    final groups = [for (final n in spec.nodes) if (n.cls == 'sgroup') n];
    for (var i = 0; i < groups.length; i++) {
      // The last group has one row more than the design (see the screen's header), so only its top is the spec's.
      final outer = rect(tester, find.byType(SettingsGroup).at(i)); // with its margins: 18 above, 16 at the sides
      final actual = Rect.fromLTRB(outer.left + 16, outer.top + 18, outer.right - 16, outer.bottom);
      if (i < groups.length - 1) {
        c.box('group ${i + 1}', actual, groups[i].rect);
      } else {
        c.same('group ${i + 1} top', (actual.top - groups[i].rect.top).abs() <= 1, true);
      }
    }
    final rows = [for (final n in spec.nodes) if (n.component == 'SettingsRow') n];
    expect(rows, hasLength(10));
    for (var i = 0; i < rows.length; i++) {
      c.box('row ${i + 1}', rect(tester, find.byType(SettingsRow).at(i)), rows[i].rect);
    }

    // Row contents: the leading glyph, the label, and what is at the end.
    c.centre('«المظهر» glyph', rect(tester, find.descendant(of: find.byType(SettingsRow).at(0), matching: find.byKey(SettingsRow.leadingKey))), spec.id(14).rect);
    c.line('«المظهر»', rect(tester, find.text('المظهر')), spec.text('المظهر').rect);
    c.box('theme segments', rect(tester, find.byKey(MinSegmented.pillKey).at(0)), spec.id(16).rect);
    for (final label in ['ورقي', 'ليلي', 'تلقائي']) {
      c.centre('segment $label', rect(tester, find.text(label)), spec.text(label).rect);
    }
    c.box('open-in segments', rect(tester, find.byKey(MinSegmented.pillKey).at(1)), spec.id(23).rect);
    c.line('«حجم نص المتن»', rect(tester, find.text('حجم نص المتن')), spec.text('حجم نص المتن').rect);
    c.same('«١٠٠٪» ends 8 dp before its chevron', (rect(tester, find.text('١٠٠٪')).left - (spec.id(30).rect.right + 8)).abs() <= 1.5, true);

    c.box('ink crop', rect(tester, find.byType(NightCrop)), spec.cls('ncrop').rect);
    c.line('«لون الحبر الليلي»', rect(tester, find.text('لون الحبر الليلي')), spec.text('لون الحبر الليلي').rect, tol: 1.5);
    c.line('its caption', rect(tester, find.text('أسماء القراء ورموزهم وإطار الصفحة')), spec.text('أسماء القراء ورموزهم وإطار الصفحة').rect, tol: 1.5);
    c.same('the ink\'s name is the default, jade', find.text('يشم').evaluate().length, 1);

    c.box('titles switch', rect(tester, find.byKey(TzSwitch.trackKey)), spec.component('TzSwitch').rect);
    expect(find.text('تُتلى'), findsOneWidget);
    for (final label in ['التلاوة', 'التنزيلات', 'عناوين الأبواب', 'رموز القراء', 'نسخ احتياطي واستعادة', 'حول تيسير الشاطبية']) {
      c.line('«$label»', rect(tester, find.text(label)), spec.text(label).rect);
    }

    // On «الإعدادات» the dock is the tabs alone.
    c.box('dock', rect(tester, find.byKey(Dock.bindingKey)), spec.component('Dock').rect);
    expect(find.byKey(Dock.rowKey), findsNothing);
    c.done();
    await unmount(tester);
  });

  testWidgets('settings-picker: the sheet, five inks each on its crop of the night page, «تم»', (tester) async {
    final spec = HandoffSpec.load('settings-picker-paper');
    if (spec == null) return markTestSkipped('the workspace (design/redesign/handoff/) is not around the app');
    final r = await data.reader(tester);
    await pumpPhone(tester, AppShell(reader: r, initialTab: DockTab.settings));
    await tester.tap(find.text('لون الحبر الليلي'));
    await tester.pump(); // the sheet's route starts
    await tester.pump(const Duration(milliseconds: 500));
    final c = Conformance(spec);

    c.box('sheet', rect(tester, find.byKey(TzSheet.surfaceKey)), spec.component('TzSheet (picker)').rect, tol: 1.5);
    c.box('grab', rect(tester, find.byKey(TzSheet.grabKey)), spec.component('SheetGrab').rect, tol: 1.5);
    final sheet = find.byKey(TzSheet.surfaceKey);
    Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
    c.line('title', rect(tester, inSheet(find.text(TzNightPage.pickerTitle))), spec.cls('t-title').rect, tol: 1.5);
    final help = rect(tester, inSheet(find.text(TzNightPage.pickerHelp)));
    c.same('help: two lines under the title', (help.top - spec.id(79).rect.top).abs() <= 1.5 && (help.height - 40).abs() <= 1, true);

    final options = [for (final n in spec.nodes) if (n.component == 'NightInkOption') n];
    expect(options, hasLength(5));
    expect([for (final i in TzNightPage.inks) i.ar], ['يشم', 'فيروزج', 'لازورد', 'بنفسج', 'فستقي']);
    for (var i = 0; i < 5; i++) {
      final option = find.byType(NightInkOption).at(i);
      c.box('option ${i + 1}', rect(tester, option), options[i].rect, tol: 1.5);
      final kids = spec.childrenOf(options[i]);
      c.box('crop ${i + 1}', rect(tester, find.descendant(of: option, matching: find.byType(NightCrop))), kids.firstWhere((n) => n.cls == 'ncrop').rect, tol: 1.5);
      c.box('radio ${i + 1}', rect(tester, find.descendant(of: option, matching: find.byKey(NightInkOption.radioKey))), kids.firstWhere((n) => n.cls == 'radio').rect, tol: 1.5);
      final name = kids.firstWhere((n) => n.cls == 'x');
      c.line('name ${i + 1}', rect(tester, find.descendant(of: option, matching: find.text(TzNightPage.inks[i].ar))),
          spec.childrenOf(name).firstWhere((n) => n.cls == 'nm').rect, tol: 2);
      c.line('mood ${i + 1}', rect(tester, find.descendant(of: option, matching: find.text(TzNightPage.inks[i].arMood))),
          spec.childrenOf(name).firstWhere((n) => n.cls == 't-cap').rect, tol: 1.5);
      expect(find.descendant(of: option, matching: find.text(TzNightPage.inks[i].arMood)), findsOneWidget);
    }
    expect(inSheet(find.text(TzNightPage.defaultTag)), findsOneWidget); // on jade only
    c.box('«تم»', rect(tester, find.widgetWithText(TzButton, 'تم')), spec.text('تم').rect, tol: 1.5);
    c.done();

    // A radiogroup: the chosen one is checked, each option at least 72 dp tall.
    expect(tester.getSemantics(find.byType(NightInkOption).at(0)), matchesSemantics(
        label: 'يشم\nالافتراضي\nهادئ · أخضر الحواشي', isInMutuallyExclusiveGroup: true, hasCheckedState: true, isChecked: true,
        hasTapAction: true, hasFocusAction: true, isFocusable: true));
    await unmount(tester);
  });
}
