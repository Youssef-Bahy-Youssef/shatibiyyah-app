// lib/ui/design/components/chapter_row.dart — a chapter in the index (item
// 3.10, ADR 0012; v2.css .chr, .now, .eq): its number in a khatam, its name in
// the matn's face over its verse range, at least 64 px high with a hairline
// under it. The reader's chapter has a filled khatam and a word at the row's
// end: «يُتلى الآن» with a live equaliser while it is recited, else «الحالي».
import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';
import 'khatam.dart';

class ChapterRow extends StatelessWidget {
  /// The chapter's number; 0 is the introduction, whose khatam is empty.
  final int order;
  final String number, name, range;
  final bool current;

  /// The word at the row's end, for the current chapter.
  final String? status;

  /// Whether the equaliser moves beside [status].
  final bool playing;
  final String semanticLabel;
  final VoidCallback onTap;

  const ChapterRow(
      {super.key,
      required this.order,
      required this.number,
      required this.name,
      required this.range,
      this.current = false,
      this.status,
      this.playing = false,
      required this.semanticLabel,
      required this.onTap});

  static const nameKey = ValueKey('chapter-row-name');
  static const rangeKey = ValueKey('chapter-row-range');
  static const nowKey = ValueKey('chapter-row-now');
  static const eqKey = ValueKey('chapter-row-eq');

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.lineSoft))),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Khatam(number, size: 38, current: current),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        key: nameKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TzType.chapter.copyWith(color: c.ink)),
                    Text(range,
                        key: rangeKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TzType.caption.copyWith(color: c.ink3, fontFeatures: const [FontFeature.tabularFigures()])),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (status case final word?)
                Row(
                  key: nowKey,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (playing) ...[_Equaliser(color: c.lapis), const SizedBox(width: 6)],
                    Text(word,
                        style: TzType.caption
                            .copyWith(color: c.lapis, fontWeight: FontWeight.w600, height: 19 / TzType.caption.fontSize!)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three bars rising and falling between 3 and 12 px, 900 ms each way, a third
/// of a cycle apart (v2.css .eq). Still under reduced motion.
class _Equaliser extends StatefulWidget {
  final Color color;
  const _Equaliser({required this.color});

  @override
  State<_Equaliser> createState() => _EqualiserState();
}

class _EqualiserState extends State<_Equaliser> with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  /// The bars at rest (reduced motion): the cycle a third of the way in.
  static const double _rest = 1 / 3;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _beat.stop();
      _beat.value = _rest;
    } else if (!_beat.isAnimating) {
      _beat.repeat();
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  /// A bar's height at [t] of the cycle (0…1): up for half of it, down for the other.
  static double _height(double t) {
    final phase = t % 1;
    final up = phase < 0.5 ? phase * 2 : 2 - phase * 2;
    return 3 + 9 * TzMotion.standard.transform(up);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        key: ChapterRow.eqKey,
        width: 11.5,
        height: 12,
        child: AnimatedBuilder(
          animation: _beat,
          builder: (context, _) => Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 2.5,
                  height: _height(_beat.value + i / 3),
                  decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(1)),
                ),
            ],
          ),
        ),
      );
}
