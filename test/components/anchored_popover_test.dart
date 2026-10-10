// AnchoredPopover (item 3.3, ADRs 0011, 0019; v2.css .pop): one popover for
// verses and chapter headings. 12 px from the screen's sides, raised, 18 px
// radius, with a 14 px arrow at its anchor's centre; placed below the anchor,
// else above; grows from the arrow in 200 ms (standard), instantly under
// reduced motion.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/anchored_popover.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'harness.dart';

Widget stage(Rect anchor, {double avoidBottom = 0}) => SizedBox(
      width: 390,
      height: 700,
      child: Stack(children: [
        Positioned.fill(
          child: AnchoredPopover(
            anchor: anchor,
            avoidBottom: avoidBottom,
            child: SizedBox(height: 120, child: TextButton(onPressed: () {}, child: const Text('الشرح'))),
          ),
        ),
      ]),
    );

Rect body(WidgetTester tester) => tester.getRect(find.byKey(AnchoredPopover.bodyKey));

void main() {
  testWidgets('below the anchor: 12 px under it, 12 px from each side; raised, 18 px radius, float shadow', (tester) async {
    await pumpTz(tester, stage(const Rect.fromLTWH(60, 200, 160, 30)));
    final b = body(tester);
    expect(b.top, closeTo(230 + 12, 0.01));
    expect((b.left, 390 - b.right), (12.0, 12.0));
    final d = tester.widget<Container>(find.byKey(AnchoredPopover.bodyKey)).decoration! as BoxDecoration;
    expect((d.color, d.borderRadius, d.boxShadow), (TzColors.paper.raised, BorderRadius.circular(18), TzColors.paper.float));
    final popover = tester.renderObject<RenderAnchoredPopover>(find.byType(AnchoredPopoverLayout));
    expect(popover.below, isTrue);
    expect(popover.arrowCenterX, closeTo(140, 0.01)); // the anchor's centre
    await expectAccessible(tester);
  });

  testWidgets('no room below: above the anchor, 12 px over it', (tester) async {
    await pumpTz(tester, stage(const Rect.fromLTWH(60, 600, 160, 30)), tz: TzTheme.dark);
    final b = body(tester);
    final popover = tester.renderObject<RenderAnchoredPopover>(find.byType(AnchoredPopoverLayout));
    expect(popover.below, isFalse);
    expect(b.bottom, closeTo(600 - 12, 0.01));
  });

  testWidgets('the dock counts as no room: avoidBottom moves it above', (tester) async {
    await pumpTz(tester, stage(const Rect.fromLTWH(60, 400, 160, 30), avoidBottom: 160));
    expect(tester.renderObject<RenderAnchoredPopover>(find.byType(AnchoredPopoverLayout)).below, isFalse);
  });

  testWidgets('the arrow stays over the body near the sides', (tester) async {
    await pumpTz(tester, stage(const Rect.fromLTWH(0, 200, 20, 30)));
    expect(tester.renderObject<RenderAnchoredPopover>(find.byType(AnchoredPopoverLayout)).arrowCenterX, closeTo(12 + 18, 0.01));
  });

  testWidgets('grows from the arrow over 200 ms; instant under reduced motion', (tester) async {
    await pumpTz(tester, stage(const Rect.fromLTWH(60, 200, 160, 30)), settle: false);
    await tester.pump(const Duration(milliseconds: 100));
    final popover = tester.renderObject<RenderAnchoredPopover>(find.byType(AnchoredPopoverLayout));
    expect(popover.progress, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(popover.progress, 1);

    await pumpTz(tester, const SizedBox.shrink());
    await pumpTz(tester, stage(const Rect.fromLTWH(60, 200, 160, 30)), reducedMotion: true, settle: false);
    await expectInstant(tester);
    expect(tester.renderObject<RenderAnchoredPopover>(find.byType(AnchoredPopoverLayout)).progress, 1);
  });

  testWidgets('taps reach the content; outside the body they pass through', (tester) async {
    var outside = 0;
    await pumpTz(
      tester,
      SizedBox(
        width: 390,
        height: 700,
        child: Stack(children: [
          Positioned.fill(child: GestureDetector(onTap: () => outside++, child: const ColoredBox(color: Color(0x00000000)))),
          const Positioned.fill(child: AnchoredPopover(anchor: Rect.fromLTWH(60, 200, 160, 30), child: SizedBox(height: 80))),
        ]),
      ),
    );
    await tester.tapAt(const Offset(195, 600));
    expect(outside, 1);
    await tester.tapAt(body(tester).center);
    expect(outside, 1);
  });
}
