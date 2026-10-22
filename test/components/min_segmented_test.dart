// MinSegmented (item 3.3; v2.css .minseg): a compact segmented control on the
// tonal fill; the chosen segment is raised in ink, 600. The pill is drawn 44 px
// high as in the prototype; each segment's tap area is 48 px.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/min_segmented.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'harness.dart';

void main() {
  testWidgets('two segments; the chosen one raised in ink; a tap chooses; radio semantics', (tester) async {
    var view = 'text';
    await pumpTz(
      tester,
      StatefulBuilder(
        builder: (context, set) => MinSegmented<String>(
          semanticLabel: 'العرض',
          options: const {'page': 'الصفحة', 'text': 'النص'},
          selected: view,
          onSelect: (v) => set(() => view = v),
        ),
      ),
    );
    Text text(String s) => tester.widget<Text>(find.text(s));
    expect((text('النص').style!.color, text('النص').style!.fontWeight), (TzColors.paper.ink, FontWeight.w600));
    expect((text('الصفحة').style!.color, text('الصفحة').style!.fontWeight), (TzColors.paper.ink2, FontWeight.w500));
    expect(text('النص').style!.fontSize, 13);
    // RTL: the first option at the start (right).
    expect(tester.getCenter(find.text('الصفحة')).dx, greaterThan(tester.getCenter(find.text('النص')).dx));
    expect(tester.getSize(find.byKey(MinSegmented.pillKey)).height, 44);
    expect(tester.getSize(find.byType(MinSegmented<String>)).height, 48);

    await tester.tap(find.text('الصفحة'));
    await tester.pump();
    expect(view, 'page');
    // The ink eases to the new choice (ADR 0037).
    await tester.pump(const Duration(milliseconds: 100));
    expect(text('الصفحة').style!.color, isNot(anyOf(TzColors.paper.ink, TzColors.paper.ink2)));
    await tester.pumpAndSettle();
    expect(text('الصفحة').style!.color, TzColors.paper.ink);
    expect(tester.getSemantics(find.text('الصفحة')),
        matchesSemantics(label: 'الصفحة', isInMutuallyExclusiveGroup: true, hasCheckedState: true, isChecked: true, hasTapAction: true, hasFocusAction: true, isFocusable: true));
    await expectAccessible(tester);
  });

  testWidgets('three segments at night; nothing animates', (tester) async {
    await pumpTz(
      tester,
      MinSegmented<int>(options: const {0: 'ورقي', 1: 'ليلي', 2: 'تلقائي'}, selected: 1, onSelect: (_) {}),
      tz: TzTheme.dark,
      reducedMotion: true,
    );
    expect(tester.widget<Text>(find.text('ليلي')).style!.color, TzColors.night.ink);
    await expectInstant(tester);
    await expectAccessible(tester);
  });
}
