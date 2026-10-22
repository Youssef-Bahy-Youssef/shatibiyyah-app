// lib/ui/design/components/text_size_grid.dart — «حجم نص المتن» (v2.css .sizes):
// one «أ» per size, each drawn a step larger, 52 px high on the tonal fill; the
// chosen one is the action colour. A radiogroup: each says its percentage.
import 'package:flutter/material.dart';

import '../../../utils/arabic.dart';
import '../tokens.g.dart';
import '../tz_theme.dart';
import 'tz_motion.dart';

class TextSizeGrid extends StatelessWidget {
  final List<double> scales;
  final double selected;
  final ValueChanged<double> onSelect;
  const TextSizeGrid({super.key, required this.scales, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return Semantics(
      container: true,
      label: 'حجم نص المتن',
      child: Row(
        children: [
          for (final (i, s) in scales.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: _size(c, i, s)),
          ],
        ],
      ),
    );
  }

  Widget _size(TzColors c, int i, double s) {
    final on = (s - selected).abs() < 0.01;
    final radius = BorderRadius.circular(12);
    return MergeSemantics(
      child: Semantics(
        label: '${ar((s * 100).round())}٪',
        inMutuallyExclusiveGroup: true,
        checked: on,
        // The fill and the letter ease to the choice (ADR 0037).
        child: TzColorTween(
          color: on ? c.action : c.tonal,
          builder: (context, fill, child) => Material(color: fill, borderRadius: radius, child: child),
          child: TzPressable(sink: true,
            onTap: () => onSelect(s),
            borderRadius: radius,
            child: SizedBox(
              height: 52,
              child: Center(
                child: ExcludeSemantics(
                  child: TzColorTween(
                    color: on ? c.onAction : c.ink,
                    builder: (context, ink, _) => Text('أ',
                        textScaler: TextScaler.noScaling, // the sizes are the steps themselves
                        style: TextStyle(fontFamily: TzFont.text, fontSize: 15.0 + i * 3, height: 1, color: ink)),
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
