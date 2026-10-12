// lib/ui/design/components/chapter_head.dart — a chapter's opening in text mode
// (item 3.3, ADR 0021; v2.js chapterHead(), v2.css .ch-head, .ch-title): centred,
// the 36 px khatam with the chapter's number, the caption (ordinal, verses,
// count), the Naskh title at 1.05 × the verse size, and the centred gilt rule.
// While its spoken title is recited the title lies on the playing wash, as a
// recited verse does (verse_unit.dart).
import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';
import 'khatam.dart';
import 'ornament.dart';
import 'tz_motion.dart';
import 'verse_unit.dart' show kVerseSize;

class ChapterHead extends StatelessWidget {
  final String order; // «١١»
  final String caption; // «الباب الحادي عشر · الأبيات ٢٢٦–٢٣٤ · ٩ أبيات»
  final String title;
  final double verseSize;

  /// The chapter's spoken title is being recited.
  final bool playing;

  const ChapterHead({
    super.key,
    required this.order,
    required this.caption,
    required this.title,
    this.verseSize = kVerseSize,
    this.playing = false,
  });

  static const titleKey = ValueKey('chapter-head-title');

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
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // The wash reaches 10 px past the title's words and takes no room of its own.
                  Positioned(
                    left: -10,
                    right: -10,
                    top: 0,
                    bottom: 0,
                    child: AnimatedContainer(
                      key: titleKey,
                      duration: tzDuration(context, TzMotion.long),
                      curve: TzMotion.standard,
                      decoration: BoxDecoration(
                        color: c.giltWashSoft.withValues(alpha: playing ? c.giltWashSoft.a : 0),
                        borderRadius: BorderRadius.circular(TzRadius.control),
                      ),
                    ),
                  ),
                  Text(title,
                      textAlign: TextAlign.center,
                      textWidthBasis: TextWidthBasis.longestLine,
                      style: TzType.title.copyWith(fontSize: verseSize * 1.05, height: 1.7, color: c.ink)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Padding(padding: EdgeInsets.only(top: 8, bottom: 6), child: GiltRule(centered: true)),
          ],
        ),
      ),
    );
  }
}
