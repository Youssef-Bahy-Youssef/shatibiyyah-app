// StatTile (item 3.3; v2.css .stat): a value over its caption on the tonal fill,
// 66 px or taller, with an optional counter badge in its top end corner (RTL:
// top left), lapis on the lapis wash.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/stat_tile.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'harness.dart';

void main() {
  testWidgets('value 16/600 tabular in ink, caption 11.5 in ink3, tonal fill, 66 px; one button for TalkBack', (tester) async {
    var taps = 0;
    await pumpTz(tester, SizedBox(width: 90, child: StatTile(value: '١٫٢٥×', label: 'السرعة', onTap: () => taps++)));
    final tile = tester.getRect(find.byType(StatTile));
    expect(tile.height, greaterThanOrEqualTo(66));
    final value = tester.widget<Text>(find.text('١٫٢٥×')).style!;
    expect((value.fontSize, value.fontWeight, value.color), (16.0, FontWeight.w600, TzColors.paper.ink));
    expect(value.fontFeatures, [const FontFeature.tabularFigures()]);
    final label = tester.widget<Text>(find.text('السرعة')).style!;
    expect((label.fontSize, label.color), (11.5, TzColors.paper.ink3));
    final ink = tester.widget<Ink>(find.descendant(of: find.byType(StatTile), matching: find.byType(Ink)));
    expect((ink.decoration! as BoxDecoration).color, TzColors.paper.tonal);
    expect((ink.decoration! as BoxDecoration).borderRadius, BorderRadius.circular(TzRadius.control));
    await tester.tap(find.byType(StatTile));
    expect(taps, 1);
    expect(tester.getSemantics(find.byType(StatTile)), matchesSemantics(label: 'السرعة: ١٫٢٥×', isButton: true, hasTapAction: true, hasFocusAction: true, isFocusable: true));
    await expectAccessible(tester);
  });

  testWidgets('the counter badge: top end corner (RTL: left), lapis on the wash, read after the value', (tester) async {
    await pumpTz(tester, SizedBox(width: 90, child: StatTile(value: '٣', label: 'تكرار البيت', badge: '٢/٣', onTap: () {})),
        tz: TzTheme.dark);
    final tile = tester.getRect(find.byType(StatTile));
    final badge = tester.getRect(find.text('٢/٣'));
    expect(badge.left - tile.left, closeTo(6 + 5, 0.5)); // 6 px in, 5 px padding
    expect(badge.top - tile.top, closeTo(6, 0.5));
    expect(tester.widget<Text>(find.text('٢/٣')).style!.color, TzColors.night.lapis);
    expect(tester.getSemantics(find.byType(StatTile)).label, 'تكرار البيت: ٣، ٢/٣');
  });

  testWidgets('no animation', (tester) async {
    await pumpTz(tester, StatTile(value: '١', label: 'تكرار المقطع', onTap: () {}), reducedMotion: true);
    await expectInstant(tester);
  });
}
