// lib/ui/design/components/verse_sheet_surface.dart — the surface of a sheet tied
// to a verse (item 3.9; v2.css .csheet, .csheet .notch, .hl.spot): 26 px top
// corners, a soft shadow upwards over a hairline, and a notch that points at the
// verse it explains. The verse itself is ringed on the page behind it.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tz_theme.dart';

class VerseSheetSurface extends StatelessWidget {
  /// Where the notch points across the sheet, or null for none (the verse is hidden).
  final double? notchX;
  final Key? surfaceKey, notchKey;
  final Widget child;
  const VerseSheetSurface({super.key, required this.child, this.notchX, this.surfaceKey, this.notchKey});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              boxShadow: [
                const BoxShadow(color: Color(0x24000000), offset: Offset(0, -10), blurRadius: 30),
                BoxShadow(color: c.lineSoft, offset: const Offset(0, -1)),
              ],
            ),
          ),
        ),
        if (notchX case final x?)
          Positioned(
            top: -8,
            left: x - 8,
            child: IgnorePointer(
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  key: notchKey,
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [BoxShadow(color: c.lineSoft, offset: const Offset(-1, -1))],
                  ),
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: ClipRRect(
            key: surfaceKey,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// The ring round the verse a sheet explains (v2.css .hl.spot without its scrim):
/// 2 px outside the verse's box, over an optional [tint] (the night ink's).
class VerseRing extends StatelessWidget {
  final Color color;
  final Color? tint;
  const VerseRing({super.key, required this.color, this.tint});

  /// The ring's own box for a verse at [verse].
  static Rect around(Rect verse) => verse.inflate(2);

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: color, width: 2),
          ),
        ),
      );
}
