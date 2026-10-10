// lib/ui/design/components/chapter_head.dart — a chapter's opening in text mode
// (item 3.3, ADR 0021; v2.js chapterHead(), v2.css .ch-head, .ch-title): centred,
// the 36 px khatam with the chapter's number, the caption (ordinal, verses,
// count), the Naskh title at 1.05 × the verse size, and the centred gilt rule.
import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';
import 'khatam.dart';
import 'ornament.dart';
import 'verse_unit.dart' show kVerseSize;

class ChapterHead extends StatelessWidget {
  final String order; // «١١»
  final String caption; // «الباب الحادي عشر · الأبيات ٢٢٦–٢٣٤ · ٩ أبيات»
  final String title;
  final double verseSize;

  const ChapterHead({super.key, required this.order, required this.caption, required this.title, this.verseSize = kVerseSize});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return Semantics(
      header: true,
      label: '$title\n$caption',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 30, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Khatam(order, size: 36),
            const SizedBox(height: 4),
            Text(caption,
                textAlign: TextAlign.center,
                style: TzType.caption.copyWith(color: c.ink3, fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(title,
                  textAlign: TextAlign.center,
                  textWidthBasis: TextWidthBasis.longestLine,
                  style: TzType.title.copyWith(fontSize: verseSize * 1.05, height: 1.7, color: c.ink)),
            ),
            const SizedBox(height: 4),
            const Padding(padding: EdgeInsets.only(top: 8, bottom: 6), child: GiltRule(centered: true)),
          ],
        ),
      ),
    );
  }
}
