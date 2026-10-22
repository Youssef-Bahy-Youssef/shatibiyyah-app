// lib/ui/design/components/matn_strip.dart — the verse a commentary explains,
// shown above it when the verse is hidden behind the sheet (item 3.3, ADR 0022;
// v2.js matnStrip(), v2.css .mstrip, .vchip, .ms-v).
//
// matnBg with 16 px corners and gilt hairlines (50 %) 5 px inside its top and
// bottom. One verse gets a caption; a group gets «يشرح الأبيات …» and a 32 px
// chip per verse, the current one in the action fill. Then the 24 px khatam and
// the two hemistichs at 0.92 × the verse size, line height 1.85, 94 % wide. The
// chips' 48 px targets reach 8 px into the strip's padding above and the verse
// below, so the strip keeps the prototype's height.
import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';
import 'khatam.dart';
import 'rubric.dart';
import 'tap_reach.dart';
import 'verse_unit.dart';
import 'tz_motion.dart';

class MatnStrip extends StatelessWidget {
  final String number; // «٢٢٦»
  final (String, String) hemistichs;
  final List<Rubric> rubrics;

  /// «البيت ٢٢٦ · المتن», or for a group «يشرح الأبيات ٢٣٠–٢٣٣».
  final String caption;

  /// A group's verse numbers, one chip each, and which is [current].
  final List<String> verses;
  final int current;
  final ValueChanged<int>? onVerse;

  /// A phrase of the verse washed in gilt (the matn quote being read), and the
  /// hemistich it is in (1 or 2; either when null).
  final String? highlight;
  final int? highlightHemistich;
  final double verseSize;

  const MatnStrip({
    super.key,
    required this.number,
    required this.hemistichs,
    required this.caption,
    this.rubrics = const [],
    this.verses = const [],
    this.current = 0,
    this.onVerse,
    this.highlight,
    this.highlightHemistich,
    this.verseSize = kVerseSize,
  });

  static const surfaceKey = ValueKey('matn-strip');
  static const topRuleKey = ValueKey('matn-strip-top-rule');

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final group = verses.length > 1;
    final style = TzType.verse.copyWith(fontSize: verseSize * 0.92, height: 1.85, color: c.verseInk);
    Widget rule(Key? key) => Container(
      key: key,
      height: 1,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.gilt.withValues(alpha: 0.5))),
      ),
    );
    final captionText = Text(caption, style: TzType.caption.copyWith(color: c.ink3));
    final verse = Semantics(
      label: 'البيت $number: ${hemistichs.$1}، ${hemistichs.$2}',
      excludeSemantics: true,
      child: IgnorePointer(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Khatam(number, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Hemistich(
                    text: hemistichs.$1,
                    rubrics: rubricsOf(rubrics, 1),
                    style: style,
                    widthFactor: 0.94,
                    highlight: highlightHemistich == 2 ? null : highlight,
                  ),
                  Hemistich(
                    text: hemistichs.$2,
                    rubrics: rubricsOf(rubrics, 2),
                    style: style,
                    widthFactor: 0.94,
                    atEnd: true,
                    highlight: highlightHemistich == 1 ? null : highlight,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Container(
      key: surfaceKey,
      decoration: BoxDecoration(color: c.matnBg, borderRadius: BorderRadius.circular(16)),
      child: Stack(
        children: [
          Positioned(top: 5, left: 18, right: 18, child: rule(topRuleKey)),
          Positioned(bottom: 5, left: 18, right: 18, child: rule(null)),
          Padding(
            // v2.css padding 10/12/12; a group's chip targets take 8 px of the top.
            padding: EdgeInsets.fromLTRB(12, group ? 2 : 10, 12, group ? 6 : 12),
            child: group
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          Padding(padding: const EdgeInsetsDirectional.only(end: 4), child: captionText),
                          for (final (i, v) in verses.indexed) _chip(c, i, v),
                        ],
                      ),
                      // The chips' targets end 8 px under them; the verse starts 2 px under them.
                      Transform.translate(offset: const Offset(0, -6), child: verse),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [captionText, const SizedBox(height: 2), verse],
                  ),
          ),
        ],
      ),
    );
  }

  /// How far a verse chip's target overhangs its pill on each side: a three-digit
  /// pill is 37 px wide, its target 48.
  static const double _chipReach = 5.5;

  Widget _chip(TzColors c, int i, String label) {
    final on = i == current;
    // The pills stand 6 px apart as drawn; each target overhangs its pill to 48 px.
    return TapReach(
      reach: _chipReach,
      child: MergeSemantics(
        child: Semantics(
          button: true,
          selected: on,
          label: 'البيت $label',
          child: TzPressable(sink: true,
            onTap: onVerse == null ? null : () => onVerse!(i),
            borderRadius: BorderRadius.circular(TzRadius.pill),
            // A 48 px target around the 32 px pill.
            child: Container(
              constraints: const BoxConstraints(minWidth: TzSize.touchTarget, minHeight: TzSize.touchTarget),
              padding: const EdgeInsets.symmetric(horizontal: _chipReach),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Container(
                  key: ValueKey('matn-chip-$i'),
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: on ? c.action : c.surface, borderRadius: BorderRadius.circular(TzRadius.pill)),
                  child: ExcludeSemantics(
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        label,
                        style: TzType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1,
                          color: on ? c.onAction : c.ink2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
