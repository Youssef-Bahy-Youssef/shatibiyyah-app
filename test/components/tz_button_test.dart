// TzButton (item 3.3, ADR 0019; v2.css .btn): primary (the one action fill per
// view) and tonal; 48 px high, 14 px radius, 14/600 label, an optional 18 px
// icon 8 px from it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/tz_button.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_icon.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'harness.dart';

BoxDecoration deco(WidgetTester tester) => tester
    .widget<Ink>(find.descendant(of: find.byType(TzButton), matching: find.byType(Ink)))
    .decoration! as BoxDecoration;

void main() {
  testWidgets('primary: action fill, 48 high, 14 radius; the label and icon in onAction; tap and semantics', (tester) async {
    var taps = 0;
    await pumpTz(tester, TzButton.primary(label: 'تشغيل الباب', icon: 'play', iconFilled: true, onPressed: () => taps++));
    expect(tester.getSize(find.byType(TzButton)).height, 48);
    expect(deco(tester).color, TzColors.paper.action);
    expect(deco(tester).borderRadius, BorderRadius.circular(TzRadius.control));
    final label = tester.widget<Text>(find.text('تشغيل الباب'));
    expect((label.style!.fontFamily, label.style!.fontSize, label.style!.fontWeight, label.style!.color),
        (TzFont.ui, 14, FontWeight.w600, TzColors.paper.onAction));
    final icon = tester.widget<TzIcon>(find.byType(TzIcon));
    expect((icon.name, icon.filled, icon.size, icon.color), ('play', true, 18, TzColors.paper.onAction));
    // RTL: the icon comes first, at the start (right), 8 px before the label.
    expect(tester.getRect(find.byType(TzIcon)).left - tester.getRect(find.text('تشغيل الباب')).right, closeTo(8, 0.01));
    await tester.tap(find.byType(TzButton));
    expect(taps, 1);
    expect(tester.getSemantics(find.byType(TzButton)),
        matchesSemantics(
            label: 'تشغيل الباب', isButton: true, hasTapAction: true, hasFocusAction: true, isEnabled: true, hasEnabledState: true, isFocusable: true));
    await expectAccessible(tester);
  });

  testWidgets('tonal: the quiet fill with ink, at night too', (tester) async {
    await pumpTz(tester, TzButton.tonal(label: 'الشرح', icon: 'book', onPressed: () {}), tz: TzTheme.dark);
    expect(deco(tester).color, TzColors.night.tonal);
    expect(tester.widget<Text>(find.text('الشرح')).style!.color, TzColors.night.ink);
    expect(tester.widget<TzIcon>(find.byType(TzIcon)).color, TzColors.night.ink);
    await expectAccessible(tester);
  });

  testWidgets('disabled: no tap, dimmed, announced as disabled', (tester) async {
    await pumpTz(tester, TzButton.primary(label: 'تم', onPressed: null));
    expect(tester.widget<Opacity>(find.descendant(of: find.byType(TzButton), matching: find.byType(Opacity))).opacity, 0.45);
    expect(tester.getSemantics(find.byType(TzButton)), matchesSemantics(label: 'تم', isButton: true, hasEnabledState: true));
  });

  testWidgets('nothing animates (no ripple), with or without reduced motion', (tester) async {
    await pumpTz(tester, TzButton.primary(label: 'تم', onPressed: () {}), reducedMotion: true);
    await tester.tap(find.byType(TzButton));
    await expectInstant(tester);
  });
}
