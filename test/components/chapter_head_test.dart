// ChapterHead (item 3.3, ADR 0021; v2.js chapterHead(), v2.css .ch-head): a
// chapter's opening in text mode, centred: the 36 px khatam with its number, the
// caption «الباب الحادي عشر · الأبيات ٢٢٦–٢٣٤ · ٩ أبيات», the Naskh title at
// 1.05 × the verse size, and the centred gilt rule.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/chapter_head.dart';
import 'package:shatibiyyah/ui/design/components/khatam.dart';
import 'package:shatibiyyah/ui/design/components/ornament.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'harness.dart';

const title = 'بَابُ نَقْلِ حَرَكَةِ الْهَمْزَةِ إِلَى السَّاكِنِ قَبْلَهَا';
const caption = 'الباب الحادي عشر · الأبيات ٢٢٦–٢٣٤ · ٩ أبيات';

void main() {
  testWidgets('centred: khatam, caption, title, rule; 30 px above, 10 below; a heading for TalkBack', (tester) async {
    await pumpTz(tester, const SizedBox(width: 366, child: ChapterHead(order: '١١', caption: caption, title: title)));
    final head = tester.getRect(find.byType(ChapterHead));
    final k = tester.getRect(find.byType(Khatam));
    expect((tester.widget<Khatam>(find.byType(Khatam)).label, k.width), ('١١', 36.0));
    expect(k.top - head.top, 30);
    expect(k.center.dx, closeTo(head.center.dx, 0.01));
    final cap = tester.widget<Text>(find.text(caption)).style!;
    expect((cap.fontSize, cap.fontWeight, cap.color), (12.0, FontWeight.w500, TzColors.paper.ink3));
    final t = tester.widget<Text>(find.text(title));
    expect((t.style!.fontFamily, t.style!.fontSize, t.style!.height, t.style!.fontWeight, t.style!.color),
        (TzFont.text, 21.0, 1.7, FontWeight.w700, TzColors.paper.ink));
    expect(t.textAlign, TextAlign.center);
    expect(tester.widget<GiltRule>(find.byType(GiltRule)).centered, isTrue);
    expect(tester.getRect(find.byType(GiltRule)).top - tester.getRect(find.text(title)).bottom, closeTo(4 + 8, 0.01));
    expect(head.bottom - tester.getRect(find.byType(GiltRule)).bottom, closeTo(6 + 10, 0.01));
    expect(tester.getSemantics(find.byType(ChapterHead)), matchesSemantics(label: '$title\n$caption', isHeader: true));
    await expectAccessible(tester);
  });

  testWidgets('the title follows the reader\'s verse size; nothing animates', (tester) async {
    await pumpTz(tester, const SizedBox(width: 366, child: ChapterHead(order: '١١', caption: caption, title: title, verseSize: 24)),
        tz: TzTheme.dark, reducedMotion: true);
    expect(tester.widget<Text>(find.text(title)).style!.fontSize, closeTo(25.2, 1e-9));
    expect(tester.widget<Text>(find.text(title)).style!.color, TzColors.night.ink);
    await expectInstant(tester);
  });
}
