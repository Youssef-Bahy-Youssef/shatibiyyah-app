// VerseUnit (item 3.3, ADR 0021; v2.js verseUnit(), v2.css .vu/.hm): a verse as
// a unit, its 26 px khatam in the margin. The first hemistich starts at the
// start, the second ends at the end, each 93 % wide and justified only when it
// fills ≥ 84 % of its column on one line. At 600 px or wider they sit side by
// side. Reader names and symbols are rubric; playing is a soft gilt wash with a
// gilt bar; chosen is a 2 px ring and tint (lapis on paper, the night ink at night).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/khatam.dart';
import 'package:shatibiyyah/ui/design/components/rubric.dart';
import 'package:shatibiyyah/ui/design/components/verse_unit.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'harness.dart';

const v226 = ('وَحَرِّكْ لِوَرْشٍ كُلَّ سَاكِنٍ آخِرٍ', 'صَحِيحٍ بِشَكْلِ الْهَمْزِ واحْذِفْهُ مُسْهِلَا');
const v230 = ('وَقُلْ عَادًا الأُوْلَى بِإِسْكَانِ لامِهِ', 'وَتَنْوِينُهُ بِالْكَسْرِ كَاسِيهِ ظَلَّلَا');

VerseUnit unit226({bool playing = false, bool chosen = false, VoidCallback? onTap}) => VerseUnit(
      number: '٢٢٦',
      first: v226.$1,
      second: v226.$2,
      rubrics: const [Rubric.name('لِوَرْشٍ')],
      playing: playing,
      chosen: chosen,
      onTap: onTap,
    );

RichText hemistich(WidgetTester tester, int i) =>
    tester.widget<RichText>(find.descendant(of: find.byKey(VerseUnit.hemistichKeys[i]), matching: find.byType(RichText)));

void main() {
  testWidgets('the khatam at the start; the first hemistich at the start, the second at the end, 93 % wide', (tester) async {
    await pumpTz(tester, SizedBox(width: 366, child: unit226()));
    final unit = tester.getRect(find.byType(VerseUnit));
    final k = tester.getRect(find.byType(Khatam));
    expect((tester.widget<Khatam>(find.byType(Khatam)).size, tester.widget<Khatam>(find.byType(Khatam)).label), (26.0, '٢٢٦'));
    expect(unit.right - k.right, closeTo(4, 0.01)); // RTL: in the start margin
    expect(k.top - unit.top, closeTo(12 + 6.5, 0.01)); // centred on the first line (1.95 × 20)
    final col = 366 - 8 - 26 - 8;
    final h1 = tester.getRect(find.byKey(VerseUnit.hemistichKeys[0]));
    final h2 = tester.getRect(find.byKey(VerseUnit.hemistichKeys[1]));
    expect(h1.width, closeTo(col * 0.93, 0.5));
    expect(k.left - h1.right, closeTo(8, 0.5)); // h1 hugs the start
    expect(h2.left - (unit.left + 4), closeTo(0, 0.5)); // h2 hugs the end
    final style = hemistich(tester, 0).text.style!;
    expect((style.fontFamily, style.fontSize, style.height, style.color), (TzFont.text, 20.0, 1.95, TzColors.paper.verseInk));
    await expectAccessible(tester);
  });

  test('justified only when one line fills 84 % or more of the column', () {
    expect(justifyGap(natural: 290, column: 300, spaces: 4), closeTo(2.5, 1e-9));
    expect(justifyGap(natural: 240, column: 300, spaces: 4), 0); // ragged: 80 %
    expect(justifyGap(natural: 320, column: 300, spaces: 4), 0); // wraps: not one line
    expect(justifyGap(natural: 290, column: 300, spaces: 0), 0);
  });

  testWidgets('reader names in the rubric; a letter symbol coloured and underlined, its word not', (tester) async {
    await pumpTz(
      tester,
      SizedBox(
        width: 366,
        child: VerseUnit(
          number: '٢٣٠',
          first: v230.$1,
          second: v230.$2,
          rubrics: const [Rubric.symbol('كَ', inWord: 'كَاسِيهِ'), Rubric.symbol('ظَ', inWord: 'ظَلَّلَا')],
        ),
      ),
      tz: TzTheme.dark,
    );
    final spans = (hemistich(tester, 1).text as TextSpan).children!.cast<TextSpan>();
    final k = spans.firstWhere((s) => s.text == 'كَ');
    expect((k.style!.color, k.style!.decoration, k.style!.decorationStyle), (TzNightPage.jade.accent, TextDecoration.underline, TextDecorationStyle.dotted));
    expect(spans.any((s) => s.text!.startsWith('اسِيهِ') && s.style == null), isTrue);
  });

  testWidgets('playing: the soft gilt wash and a 3 px gilt bar outside the start edge', (tester) async {
    await pumpTz(tester, SizedBox(width: 366, child: unit226(playing: true)));
    final box = tester.widget<AnimatedContainer>(find.byKey(VerseUnit.surfaceKey)).decoration! as BoxDecoration;
    expect(box.color, TzColors.paper.giltWashSoft);
    final bar = tester.getRect(find.byKey(VerseUnit.barKey));
    final unit = tester.getRect(find.byType(VerseUnit));
    expect(bar.width, 3);
    expect(bar.left - unit.right, closeTo(5, 0.01)); // right: -8px, 3 wide
    expect((tester.widget<Container>(find.byKey(VerseUnit.barKey)).decoration! as BoxDecoration).color, TzColors.paper.gilt);
  });

  testWidgets('chosen: lapis ring and wash on paper; the night ink at night', (tester) async {
    await pumpTz(tester, SizedBox(width: 366, child: unit226(chosen: true)));
    var box = tester.widget<AnimatedContainer>(find.byKey(VerseUnit.surfaceKey)).decoration! as BoxDecoration;
    expect((box.color, (box.border! as Border).top.color, (box.border! as Border).top.width), (TzColors.paper.lapisWash, TzColors.paper.lapis, 2.0));
    await pumpTz(tester, SizedBox(width: 366, child: unit226(chosen: true)), tz: TzTheme.dark.copyWith(nightInk: TzNightPage.wisteria));
    box = tester.widget<AnimatedContainer>(find.byKey(VerseUnit.surfaceKey)).decoration! as BoxDecoration;
    expect((box.color, (box.border! as Border).top.color), (TzNightPage.wisteria.accent.withValues(alpha: 0.16), TzNightPage.wisteria.accent));
  });

  testWidgets('600 px or wider: the hemistichs side by side, both from the start', (tester) async {
    await pumpTz(tester, SizedBox(width: 700, child: unit226()), width: 800);
    final h1 = tester.getRect(find.byKey(VerseUnit.hemistichKeys[0]));
    final h2 = tester.getRect(find.byKey(VerseUnit.hemistichKeys[1]));
    expect(h1.top, closeTo(h2.top, 0.01));
    expect(h1.left - h2.right, closeTo(48, 0.5)); // 2.4em
  });

  testWidgets('one item for TalkBack, tap acts; the wash fades in 320 ms, instantly under reduced motion', (tester) async {
    var taps = 0;
    await pumpTz(tester, SizedBox(width: 366, child: unit226(onTap: () => taps++)));
    expect(tester.getSemantics(find.byType(VerseUnit)).label, 'البيت ٢٢٦: ${v226.$1}، ${v226.$2}');
    await tester.tap(find.byType(VerseUnit));
    expect(taps, 1);
    await pumpTz(tester, SizedBox(width: 366, child: unit226(playing: true)), settle: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    await pumpTz(tester, SizedBox(width: 366, child: unit226()), reducedMotion: true);
    await pumpTz(tester, SizedBox(width: 366, child: unit226(playing: true)), reducedMotion: true, settle: false);
    await expectInstant(tester);
  });
}
