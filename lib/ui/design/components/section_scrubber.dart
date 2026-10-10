// lib/ui/design/components/section_scrubber.dart — where the recitation is in
// its section (item 3.7; v2.css .scrub, .track, .times): a 4 px track that
// fills from the start in lapis, a tick where each later verse begins, a 16 px
// knob, and under it the time so far, the verse's place and the section's
// length. A tap or a drag asks for that point ([onSeek], 0…1 from the start).
//
// The box is the 48 px target: 14 px above the track, the track and the times
// (28 px, as measured), 6 px below.
import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';

class SectionScrubber extends StatefulWidget {
  /// 0…1 through the section.
  final double progress;

  /// Where each verse after the first begins, 0…1.
  final List<double> ticks;
  final String start, middle, end;
  final ValueChanged<double>? onSeek;

  const SectionScrubber(
      {super.key,
      required this.progress,
      this.ticks = const [],
      required this.start,
      required this.middle,
      required this.end,
      this.onSeek});

  static const trackKey = ValueKey('scrubber-track');
  static const fillKey = ValueKey('scrubber-fill');
  static const knobKey = ValueKey('scrubber-knob');
  static const tickKey = ValueKey('scrubber-tick');

  /// The space above the track that belongs to the target.
  static const double above = 14;

  @override
  State<SectionScrubber> createState() => _SectionScrubberState();
}

class _SectionScrubberState extends State<SectionScrubber> {
  /// Where the finger is while it drags, 0…1.
  double? _drag;

  double _fraction(Offset local, double width) {
    final x = (local.dx / width).clamp(0.0, 1.0);
    return Directionality.of(context) == TextDirection.rtl ? 1 - x : x;
  }

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final p = (_drag ?? widget.progress).clamp(0.0, 1.0);
    final times = TzType.caption.copyWith(color: c.ink3, fontFeatures: const [FontFeature.tabularFigures()]);
    return Semantics(
      container: true,
      label: 'موضع التلاوة في المقطع',
      value: widget.middle,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: widget.onSeek == null ? null : (d) => widget.onSeek!(_fraction(d.localPosition, w)),
              onHorizontalDragStart:
                  widget.onSeek == null ? null : (d) => setState(() => _drag = _fraction(d.localPosition, w)),
              onHorizontalDragUpdate:
                  widget.onSeek == null ? null : (d) => setState(() => _drag = _fraction(d.localPosition, w)),
              onHorizontalDragEnd: widget.onSeek == null
                  ? null
                  : (_) {
                      final f = _drag;
                      setState(() => _drag = null);
                      if (f != null) widget.onSeek!(f);
                    },
              onHorizontalDragCancel: () => setState(() => _drag = null),
              child: SizedBox(
                height: 48,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    PositionedDirectional(
                      top: SectionScrubber.above,
                      start: 0,
                      end: 0,
                      child: Container(
                        key: SectionScrubber.trackKey,
                        height: 4,
                        decoration: BoxDecoration(color: c.lineSoft, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    PositionedDirectional(
                      top: SectionScrubber.above,
                      start: 0,
                      child: Container(
                        key: SectionScrubber.fillKey,
                        width: w * p,
                        height: 4,
                        decoration: BoxDecoration(color: c.lapis, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    for (final t in widget.ticks)
                      PositionedDirectional(
                        top: SectionScrubber.above - 3,
                        start: w * t - 0.75,
                        child: Container(
                          key: SectionScrubber.tickKey,
                          width: 1.5,
                          height: 10,
                          decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(1)),
                        ),
                      ),
                    PositionedDirectional(
                      top: SectionScrubber.above - 6,
                      start: w * p - 8,
                      child: Container(
                        key: SectionScrubber.knobKey,
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: c.lapis,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: c.surface, spreadRadius: 4)],
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      top: SectionScrubber.above + 12,
                      start: 0,
                      end: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(widget.start, style: times),
                          Flexible(child: Text(widget.middle, maxLines: 1, overflow: TextOverflow.ellipsis, style: times)),
                          Text(widget.end, style: times),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
