// lib/ui/reader/chapter_popover.dart — the chapter popover (item 3.5, ADR 0011;
// index.html heading, v2.css .pop, .hl.spot.gold).
//
// A tap on a printed heading lights it in gilt with the scrim around it and opens
// the popover from its arrow. The title is lit right above, so the popover does
// not repeat it: the chapter number in a khatam, its ordinal, its size, range and
// page, the first words of its first verse, then «تشغيل الباب» (filled) and
// «الشرح» (tonal). Without a recording the filled action reads «نزّل التلاوة»
// (ADR 0011), and is absent where nothing can download. A tap outside, Back, a
// page turn or a zoom closes it.
import 'package:flutter/material.dart';

import '../../data/matn_repository.dart';
import '../../utils/arabic.dart';
import '../design/components/anchored_popover.dart';
import '../design/components/khatam.dart';
import '../design/components/tz_button.dart';
import '../design/tokens.g.dart';
import '../design/tz_theme.dart';
import '../design/tz_type.dart';
import '../widgets/verse_menu.dart' show SpotlightScrim;

class ChapterPopover extends StatelessWidget {
  /// The heading on screen, in the coordinates of the popover's Stack.
  final Rect? anchor;
  final MatnChapter chapter;
  final int page;
  final String firstHemistich;
  final bool audio;
  final double avoidBottom;
  final VoidCallback onPlay, onExplain, onClose;
  final VoidCallback? onDownload;

  const ChapterPopover({
    super.key,
    required this.anchor,
    required this.chapter,
    required this.page,
    required this.firstHemistich,
    required this.audio,
    required this.avoidBottom,
    required this.onPlay,
    required this.onExplain,
    required this.onClose,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final size = MediaQuery.sizeOf(context);
    final intro = chapter.orderIndex == 0;
    final n = chapter.toVerse - chapter.fromVerse + 1;
    return Stack(
      children: [
        Positioned.fill(
          child: Semantics(
            label: 'إغلاق',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: SpotlightScrim(spot: anchor, ring: c.gilt, tint: c.giltWash),
            ),
          ),
        ),
        Positioned.fill(
          child: AnchoredPopover(
            anchor: anchor ?? Rect.fromCenter(center: Offset(size.width / 2, size.height - avoidBottom - 24), width: 0, height: 0),
            avoidBottom: avoidBottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Khatam(intro ? '' : ar(chapter.orderIndex), size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(intro ? chapter.shortLabel : chapterOrdinal(chapter.orderIndex),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TzType.head.copyWith(color: c.ink)),
                          Text('${versesCount(n)} · ${isolatedRange(chapter.fromVerse, chapter.toVerse)} · ص ${ar(page)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TzType.caption.copyWith(color: c.ink3, fontFeatures: const [FontFeature.tabularFigures()])),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('يبدأ بـ', style: TzType.caption.copyWith(color: c.ink3)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(firstHemistich,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TzType.verse.scaled(17 / 19).copyWith(color: c.ink2)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      if (audio)
                        Expanded(flex: 13, child: TzButton.primary(label: 'تشغيل الباب', icon: 'play', iconFilled: true, onPressed: onPlay))
                      else if (onDownload case final download?)
                        Expanded(flex: 13, child: TzButton.primary(label: 'نزّل التلاوة', icon: 'down', onPressed: download)),
                      if (audio || onDownload != null) const SizedBox(width: 8),
                      Expanded(flex: 10, child: TzButton.tonal(label: 'الشرح', icon: 'book', onPressed: onExplain)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
