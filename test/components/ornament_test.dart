// GiltRule and Lozenge (item 3.3, ADR 0019): the rule is a 1 px gilt line at 55 %
// with a 7 px lozenge near its start (22 px in) or, centred, under a chapter
// heading at 72 % width; the lozenge is a 7 px square turned 45°.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/ornament.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'harness.dart';

void main() {
  testWidgets('the lozenge: a 7 px gilt square turned 45°, decorative', (tester) async {
    await pumpTz(tester, const Lozenge());
    final t = tester.widget<Transform>(find.descendant(of: find.byType(Lozenge), matching: find.byType(Transform)));
    expect(t.transform.getRotation().entry(1, 0), closeTo(math.sin(math.pi / 4), 1e-6));
    final box = tester.widget<Container>(find.descendant(of: find.byType(Lozenge), matching: find.byType(Container)));
    expect((box.decoration as BoxDecoration).color, TzColors.paper.gilt);
    expect(box.constraints!.maxWidth, 7);
    expect(find.bySemanticsLabel(RegExp('.')), findsNothing);
  });

  testWidgets('the rule: 12 px high, the line in gilt at 55 %, the lozenge 22 px from the start (RTL: right)', (tester) async {
    await pumpTz(tester, const SizedBox(width: 300, child: GiltRule()), tz: TzTheme.dark);
    expect(tester.getSize(find.byType(GiltRule)), const Size(300, 12));
    final line = tester.widget<Container>(find.byKey(GiltRule.lineKey));
    expect((line.decoration as BoxDecoration).border!.top.color, TzColors.night.gilt.withValues(alpha: 0.55));
    final rule = tester.getRect(find.byType(GiltRule));
    final loz = tester.getCenter(find.byType(Lozenge));
    expect(loz.dx, closeTo(rule.right - 22 - 3.5, 0.01));
    expect(loz.dy, closeTo(rule.center.dy, 0.01));
  });

  testWidgets('centred under a heading: 72 % wide, the lozenge in the middle', (tester) async {
    await pumpTz(tester, const SizedBox(width: 300, child: GiltRule(centered: true)));
    expect(tester.getSize(find.byKey(GiltRule.lineKey)).width, closeTo(216, 0.01));
    expect(tester.getCenter(find.byType(Lozenge)).dx, closeTo(tester.getCenter(find.byType(GiltRule)).dx, 0.01));
    await expectAccessible(tester);
    await expectInstant(tester);
  });
}
