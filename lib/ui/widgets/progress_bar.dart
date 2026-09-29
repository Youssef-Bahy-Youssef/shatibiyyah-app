// lib/ui/widgets/progress_bar.dart — the range scrubber (.scrub) + time labels.
// Ported from index.html (#scrubber, #curTime/#totTime) + app.js scrubber wiring:
// input → setScrubbing(true)+previewVerseAt; change → seekToFraction. Track is a gold
// fill up to the played fraction (paintScrubber), thumb is gold-bright.
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../services/audio_service.dart';
import '../../theme.dart';
import '../../utils/arabic.dart';

class ProgressBar extends StatefulWidget {
  final AppController app;
  final bool mini; // mini-scrub (thinner; no time labels)
  const ProgressBar({super.key, required this.app, this.mini = false});

  @override
  State<ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<ProgressBar> {
  double? _dragFrac;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TimeUpdate>(
      valueListenable: widget.app.time,
      builder: (context, d, _) {
        final span = d.rangeEnd - d.rangeStart;
        final frac = _dragFrac ??
            (span > 0
                ? ((d.time - d.rangeStart) / span).clamp(0.0, 1.0)
                : 0.0);
        final slider = SliderTheme(
          data: SliderThemeData(
            trackHeight: widget.mini ? 5 : 7,
            activeTrackColor: C.gold,
            inactiveTrackColor: widget.mini ? const Color(0x38FFAB2E) : C.line,
            thumbColor: widget.mini ? C.gold : C.goldBright,
            overlayShape: SliderComponentShape.noOverlay,
            thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: widget.mini ? 7.5 : 9),
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            min: 0,
            max: 1000,
            value: (frac * 1000).clamp(0, 1000),
            onChangeStart: (_) => widget.app.audio.setScrubbing(true),
            onChanged: (v) {
              setState(() => _dragFrac = v / 1000);
              widget.app.audio.previewVerseAt(v / 1000);
            },
            onChangeEnd: (v) {
              setState(() => _dragFrac = null);
              widget.app.audio.seekToFraction(v / 1000);
            },
          ),
        );

        if (widget.mini) {
          return SizedBox(height: 22, child: slider);
        }

        return Directionality(
          textDirection: TextDirection.ltr, // .scrub{direction:ltr}
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 24, child: slider),
              const SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(fmtTime(d.time - d.rangeStart),
                      style: ui(size: 11.84, color: C.muted, tabular: true)),
                  Text(fmtTime(span),
                      style: ui(size: 11.84, color: C.muted, tabular: true)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
