// UndoSnackbar (item 3.3, ADR 0009; v2.css .snack): after a delete, the message
// and «تراجع» on the snackbar fill, 52 px high, 14 px radius, the float shadow;
// announced as a status; rises in 320 ms, instantly under reduced motion.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/undo_snackbar.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'harness.dart';

void main() {
  testWidgets('message at the start, «تراجع» at the end in snackAct 700; 52 px; a live region; undo acts', (tester) async {
    var undos = 0;
    await pumpTz(tester, SizedBox(width: 366, child: UndoSnackbar(message: 'أُزيل المرجع: البيت ١٠٠١', onUndo: () => undos++)));
    final bar = tester.getRect(find.byType(UndoSnackbar));
    expect(bar.height, 52);
    final d = tester.widget<Container>(find.byKey(UndoSnackbar.surfaceKey)).decoration! as BoxDecoration;
    expect((d.color, d.borderRadius, d.boxShadow), (TzColors.paper.snack, BorderRadius.circular(TzRadius.control), TzColors.paper.float));
    final msg = tester.getRect(find.text('أُزيل المرجع: البيت ١٠٠١'));
    expect(bar.right - msg.right, closeTo(8, 0.01)); // v2.css: padding 0 8px 0 16px (RTL: the start is the right)
    final undo = tester.widget<Text>(find.text('تراجع')).style!;
    expect((undo.color, undo.fontWeight, undo.fontSize), (TzColors.paper.snackAct, FontWeight.w700, 14.0));
    expect(tester.widget<Text>(find.text('أُزيل المرجع: البيت ١٠٠١')).style!.color, TzColors.paper.onSnack);
    expect(tester.getRect(find.text('تراجع')).left - bar.left, closeTo(16 + 12, 0.01));
    await tester.tap(find.text('تراجع'));
    expect(undos, 1);
    expect(tester.getSemantics(find.text('أُزيل المرجع: البيت ١٠٠١')), matchesSemantics(label: 'أُزيل المرجع: البيت ١٠٠١', isLiveRegion: true));
    await expectAccessible(tester);
  });

  testWidgets('rises in 320 ms; instantly under reduced motion', (tester) async {
    await pumpTz(tester, UndoSnackbar(message: 'أُزيلت الملاحظة', onUndo: () {}), settle: false, tz: TzTheme.dark);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<FadeTransition>(find.byKey(UndoSnackbar.riseKey)).opacity.value, inExclusiveRange(0.4, 1));
    await tester.pumpAndSettle();
    await pumpTz(tester, const SizedBox.shrink());
    await pumpTz(tester, UndoSnackbar(message: 'أُزيلت الملاحظة', onUndo: () {}), reducedMotion: true, settle: false);
    await expectInstant(tester);
    expect(tester.widget<FadeTransition>(find.byKey(UndoSnackbar.riseKey)).opacity.value, 1);
  });
}
