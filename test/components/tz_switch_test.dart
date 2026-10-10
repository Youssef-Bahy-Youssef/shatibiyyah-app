// TzSwitch (item 3.3; v2.css .toggle and .sw): always shows its state as a word
// («تُتلى», «ظاهر») before a 44 × 26 track, lapis when on and line when off; the
// knob slides to the end (RTL: left) when on, over 200 ms; the whole row is the
// 48 px target.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/tz_switch.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'harness.dart';

void main() {
  Widget toggle(bool Function() get, void Function(bool) set) => StatefulBuilder(
        builder: (context, rebuild) => TzSwitch(
          value: get(),
          onWord: 'تُتلى',
          offWord: 'لا تُتلى',
          semanticLabel: 'تلاوة عناوين الأبواب',
          onChanged: (v) => rebuild(() => set(v)),
        ),
      );

  testWidgets('on: the word, a lapis track, the knob at the end (RTL: left); a tap turns it off', (tester) async {
    var on = true;
    await pumpTz(tester, toggle(() => on, (v) => on = v));
    expect(find.text('تُتلى'), findsOneWidget);
    expect(tester.widget<Text>(find.text('تُتلى')).style!.color, TzColors.paper.ink2);
    expect(tester.widget<Text>(find.text('تُتلى')).style!.fontSize, 13);
    final track = tester.getRect(find.byKey(TzSwitch.trackKey));
    expect(track.size, const Size(44, 26));
    expect(((tester.widget<Container>(find.byKey(TzSwitch.trackKey)).decoration!) as BoxDecoration).color,
        TzColors.paper.lapis);
    expect(tester.getRect(find.byKey(TzSwitch.knobKey)).left - track.left, closeTo(3, 0.01));
    // The word comes first: at the start (right) of the track.
    expect(tester.getRect(find.text('تُتلى')).left, greaterThan(track.right));
    expect(tester.getSize(find.byType(TzSwitch)).height, greaterThanOrEqualTo(48));
    expect(tester.getSemantics(find.byType(TzSwitch)),
        matchesSemantics(label: 'تلاوة عناوين الأبواب', value: 'تُتلى', hasToggledState: true, isToggled: true, hasEnabledState: true, isEnabled: true, hasTapAction: true, hasFocusAction: true, isFocusable: true));
    await expectAccessible(tester);

    await tester.tap(find.byType(TzSwitch));
    await tester.pump();
    expect(on, isFalse);
    expect(find.text('لا تُتلى'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    double knob() => tester.getRect(find.byKey(TzSwitch.knobKey)).left - tester.getRect(find.byKey(TzSwitch.trackKey)).left;
    expect(knob(), inExclusiveRange(3, 21)); // sliding (the longer word moved the track)
    await tester.pumpAndSettle();
    expect(knob(), closeTo(21, 0.01));
    expect(((tester.widget<Container>(find.byKey(TzSwitch.trackKey)).decoration!) as BoxDecoration).color,
        TzColors.paper.line);
  });

  testWidgets('reduced motion: the knob jumps', (tester) async {
    var on = false;
    await pumpTz(tester, toggle(() => on, (v) => on = v), reducedMotion: true, tz: TzTheme.dark);
    await tester.tap(find.byType(TzSwitch));
    await expectInstant(tester);
    final track = tester.getRect(find.byKey(TzSwitch.trackKey));
    expect(tester.getRect(find.byKey(TzSwitch.knobKey)).left - track.left, closeTo(3, 0.01));
  });

  testWidgets('disabled: dimmed to 45 %, no tap', (tester) async {
    await pumpTz(tester, const TzSwitch(value: false, onWord: 'مضاف', offWord: 'بدون', onChanged: null));
    expect(tester.widget<Opacity>(find.descendant(of: find.byType(TzSwitch), matching: find.byType(Opacity))).opacity, 0.45);
    await tester.tap(find.byType(TzSwitch));
    expect(find.text('بدون'), findsOneWidget);
  });
}
