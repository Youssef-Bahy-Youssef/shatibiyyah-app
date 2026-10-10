// BindingStepper (item 3.3, ADR 0022; v2.css .stepper): previous and next verse
// on the binding (cover, 60 px, 22 px radius, the dock shadow), with the step's
// khatam and «من ٩ في الباب» between them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/binding_stepper.dart';
import 'package:shatibiyyah/ui/design/components/khatam.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_icon.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'harness.dart';

void main() {
  testWidgets('previous at the start (RTL: right) with ›, next at the end with ‹; the step between', (tester) async {
    var prev = 0, next = 0;
    await pumpTz(
      tester,
      SizedBox(
        width: 370,
        child: BindingStepper(
          previous: 'البيت ٢٢٥',
          next: 'البيت ٢٢٧',
          step: '١',
          caption: 'من ٩ في الباب',
          onPrevious: () => prev++,
          onNext: () => next++,
        ),
      ),
    );
    final d = tester.widget<Container>(find.byKey(BindingStepper.bindingKey)).decoration! as BoxDecoration;
    expect((d.color, d.borderRadius, d.boxShadow), (TzColors.paper.cover, BorderRadius.circular(22), TzColors.paper.dock));
    expect(tester.getSize(find.byType(BindingStepper)).height, 60);
    expect(tester.getCenter(find.text('البيت ٢٢٥')).dx, greaterThan(tester.getCenter(find.text('البيت ٢٢٧')).dx));
    final icons = tester.widgetList<TzIcon>(find.byType(TzIcon)).map((i) => i.name).toList();
    expect(icons, ['back', 'fwd']);
    final k = tester.widget<Khatam>(find.byType(Khatam));
    expect((k.label, k.size, k.onCover), ('١', 30.0, true));
    final label = tester.widget<Text>(find.text('البيت ٢٢٥')).style!;
    expect((label.fontSize, label.fontWeight, label.color), (13.5, FontWeight.w500, TzColors.paper.onCover));
    expect(tester.widget<Text>(find.text('من ٩ في الباب')).style!.color, TzColors.paper.coverMute);
    await tester.tap(find.text('البيت ٢٢٥'));
    await tester.tap(find.text('البيت ٢٢٧'));
    expect((prev, next), (1, 1));
    expect(tester.getSemantics(find.text('البيت ٢٢٥')), matchesSemantics(label: 'البيت ٢٢٥', isButton: true, hasEnabledState: true, isEnabled: true, hasTapAction: true, hasFocusAction: true, isFocusable: true));
    await expectAccessible(tester);
  });

  testWidgets('the first verse of a chapter: no previous, dimmed and disabled; nothing animates', (tester) async {
    await pumpTz(
      tester,
      SizedBox(
        width: 370,
        child: BindingStepper(previous: 'البيت ٢٢٥', next: 'البيت ٢٢٧', step: '١', caption: 'من ٩', onPrevious: null, onNext: () {}),
      ),
      tz: TzTheme.dark,
      reducedMotion: true,
    );
    expect(tester.getSemantics(find.text('البيت ٢٢٥')), matchesSemantics(label: 'البيت ٢٢٥', isButton: true, hasEnabledState: true));
    await expectInstant(tester);
  });
}
