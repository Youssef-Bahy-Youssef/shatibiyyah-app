// TzSheet (item 3.3; v2.css .psheet and .picker): a grab and rounded top
// corners: the full sheet (surface, 28 px) or the picker (raised, 24 px, padded
// 8/16/34). It rises in 320 ms (emphasized) from 60 px down at 40 % opacity,
// instantly under reduced motion.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/tz_sheet.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'harness.dart';

BoxDecoration deco(WidgetTester tester) =>
    tester.widget<Container>(find.byKey(TzSheet.surfaceKey)).decoration! as BoxDecoration;

void main() {
  testWidgets('the sheet: surface, 28 px top corners, float shadow; the grab 38 × 5 in line, 8 px down', (tester) async {
    await pumpTz(tester, const TzSheet(child: SizedBox(height: 200, child: Text('المشغّل'))));
    expect(deco(tester).color, TzColors.paper.surface);
    expect(deco(tester).borderRadius, const BorderRadius.vertical(top: Radius.circular(TzRadius.sheet)));
    expect(deco(tester).boxShadow, TzColors.paper.float);
    final grab = tester.getRect(find.byKey(TzSheet.grabKey));
    expect(grab.size, const Size(38, 5));
    expect(grab.top - tester.getRect(find.byKey(TzSheet.surfaceKey)).top, 8);
    expect(grab.center.dx, closeTo(tester.getRect(find.byKey(TzSheet.surfaceKey)).center.dx, 0.01));
    expect((tester.widget<Container>(find.byKey(TzSheet.grabKey)).decoration! as BoxDecoration).color, TzColors.paper.line);
    await expectAccessible(tester);
  });

  testWidgets('the picker: raised, 24 px, padded 8/16/34, the grab 16 px down', (tester) async {
    await pumpTz(tester, const TzSheet.picker(child: Text('السرعة')), tz: TzTheme.dark);
    expect(deco(tester).color, TzColors.night.raised);
    expect(deco(tester).borderRadius, const BorderRadius.vertical(top: Radius.circular(24)));
    final surface = tester.getRect(find.byKey(TzSheet.surfaceKey));
    expect(tester.getRect(find.byKey(TzSheet.grabKey)).top - surface.top, 16);
    expect(surface.right - tester.getRect(find.text('السرعة')).right, closeTo(16, 0.01)); // RTL: text at the start
  });

  testWidgets('rises in 320 ms; instantly under reduced motion', (tester) async {
    await pumpTz(tester, const TzSheet(child: SizedBox(height: 100)), settle: false);
    await tester.pump(const Duration(milliseconds: 100));
    final rising = tester.widget<FadeTransition>(find.byKey(TzSheet.riseKey));
    expect(rising.opacity.value, inExclusiveRange(0.4, 1));
    await tester.pumpAndSettle();
    expect(tester.widget<FadeTransition>(find.byKey(TzSheet.riseKey)).opacity.value, 1);

    await pumpTz(tester, const SizedBox.shrink());
    await pumpTz(tester, const TzSheet(child: SizedBox(height: 100)), reducedMotion: true, settle: false);
    await expectInstant(tester);
    expect(tester.widget<FadeTransition>(find.byKey(TzSheet.riseKey)).opacity.value, 1);
  });
}
