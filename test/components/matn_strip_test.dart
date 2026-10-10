// MatnStrip (item 3.3, ADR 0022; v2.js matnStrip(), v2.css .mstrip): the verse
// a commentary explains, shown above it when the verse is hidden behind the
// sheet. matnBg, 16 px radius, gilt hairlines inside top and bottom; a caption
// (one verse) or «يشرح الأبيات …» with a chip per verse (a group); then the
// 24 px khatam and the two hemistichs at 0.92 × the verse size, 94 % wide.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/khatam.dart';
import 'package:shatibiyyah/ui/design/components/matn_strip.dart';
import 'package:shatibiyyah/ui/design/components/phrase_wash.dart';
import 'package:shatibiyyah/ui/design/components/rubric.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'harness.dart';

const h226 = ('وَحَرِّكْ لِوَرْشٍ كُلَّ سَاكِنٍ آخِرٍ', 'صَحِيحٍ بِشَكْلِ الْهَمْزِ واحْذِفْهُ مُسْهِلَا');
const h231 = ('وَأَدْغَمَ بَاقِيهِمْ وَبِالنَّقْلِ وَصْلُهُمْ', 'وَبَدْؤُهُمُ وَالْبَدْءُ بِالأَصْلِ فُضِّلاَ');

void main() {
  testWidgets('one verse: matnBg, 16 px, the caption, the 24 px khatam; hemistichs at 18.4, 94 % wide', (tester) async {
    await pumpTz(
      tester,
      const SizedBox(
        width: 362,
        child: MatnStrip(number: '٢٢٦', hemistichs: h226, caption: 'البيت ٢٢٦ · المتن', rubrics: [Rubric.name('لِوَرْشٍ')]),
      ),
    );
    final d = tester.widget<Container>(find.byKey(MatnStrip.surfaceKey)).decoration! as BoxDecoration;
    expect((d.color, d.borderRadius), (TzColors.paper.matnBg, BorderRadius.circular(16)));
    expect(tester.widget<Text>(find.text('البيت ٢٢٦ · المتن')).style!.color, TzColors.paper.ink3);
    expect(tester.widget<Khatam>(find.byType(Khatam)).size, 24);
    final rule = tester.widget<Container>(find.byKey(MatnStrip.topRuleKey)).decoration! as BoxDecoration;
    expect((rule.border! as Border).top.color, TzColors.paper.gilt.withValues(alpha: 0.5));
    final strip = tester.getRect(find.byKey(MatnStrip.surfaceKey));
    final top = tester.getRect(find.byKey(MatnStrip.topRuleKey));
    expect((top.top - strip.top, top.left - strip.left, strip.right - top.right), (5.0, 18.0, 18.0));
    final rich = tester.widgetList<RichText>(find.descendant(of: find.byType(MatnStrip), matching: find.byType(RichText)))
        .firstWhere((r) => r.text.toPlainText() == h226.$1);
    expect(rich.text.style!.fontSize, closeTo(18.4, 1e-9));
    expect(rich.text.style!.height, 1.85);
    expect(find.bySemanticsLabel('البيت ٢٢٦: ${h226.$1}، ${h226.$2}'), findsOneWidget);
    await expectAccessible(tester);
  });

  testWidgets('a group: «يشرح الأبيات …» and a chip per verse; the current one in the action fill; 48 px targets', (tester) async {
    int? picked;
    await pumpTz(
      tester,
      SizedBox(
        width: 362,
        child: MatnStrip(
          number: '٢٣١',
          hemistichs: h231,
          caption: 'يشرح الأبيات ٢٣٠–٢٣٣',
          verses: const ['٢٣٠', '٢٣١', '٢٣٢', '٢٣٣'],
          current: 1,
          onVerse: (i) => picked = i,
        ),
      ),
      tz: TzTheme.dark,
    );
    final on = tester.widget<Container>(find.byKey(const ValueKey('matn-chip-1'))).decoration! as BoxDecoration;
    final off = tester.widget<Container>(find.byKey(const ValueKey('matn-chip-0'))).decoration! as BoxDecoration;
    expect((on.color, off.color), (TzColors.night.action, TzColors.night.surface));
    expect(tester.getSize(find.byKey(const ValueKey('matn-chip-0'))).height, 32);
    // RTL: the caption first, then the chips from the start.
    expect(tester.getCenter(find.text('٢٣٠')).dx, greaterThan(tester.getCenter(find.text('٢٣٣')).dx));
    await tester.tap(find.text('٢٣٢'));
    expect(picked, 2);
    expect(tester.getSemantics(find.text('٢٣١')), matchesSemantics(label: 'البيت ٢٣١', isButton: true, hasSelectedState: true, isSelected: true, hasTapAction: true, hasFocusAction: true, isFocusable: true));
    await expectAccessible(tester);
  });

  testWidgets('a quoted phrase is washed in gilt; nothing animates under reduced motion', (tester) async {
    await pumpTz(
      tester,
      const SizedBox(width: 362, child: MatnStrip(number: '٢٢٦', hemistichs: h226, caption: 'البيت ٢٢٦', highlight: 'صَحِيحٍ')),
      reducedMotion: true,
    );
    // The second hemistich has the phrase: a rounded wash behind its words, 2 px wider all round.
    final washes = tester.widgetList<PhraseWash>(find.descendant(of: find.byType(MatnStrip), matching: find.byType(PhraseWash))).toList();
    final at = h226.$2.indexOf('صَحِيحٍ');
    expect([for (final w in washes) w.washes], [
      const <Wash>[],
      [(start: at, end: at + 'صَحِيحٍ'.length, color: TzColors.paper.giltWash, spread: 2.0, radius: 6.0)],
    ]);
    final wash = tester.renderObject<RenderPhraseWash>(find.byWidget(washes[1])).painted.single.$1;
    final words = tester.renderObject<RenderParagraph>(find.descendant(of: find.byWidget(washes[1]), matching: find.byType(RichText)));
    final glyphs = words.getBoxesForSelection(TextSelection(baseOffset: at, extentOffset: at + 'صَحِيحٍ'.length)).first.toRect();
    expect(wash.left, closeTo(glyphs.left - 2, 0.01));
    expect(wash.right, closeTo(glyphs.right + 2, 0.01));
    expect(wash.tlRadiusX, 6.0);
    await expectInstant(tester);
  });
}
