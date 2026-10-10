// lib/ui/design/components/min_segmented.dart — a compact segmented control
// (item 3.3; v2.css .minseg): segments of at least 52 × 38 on the tonal fill,
// the chosen one raised (raised fill, ink, 600, a 1 px shadow). The pill is
// drawn 44 px high as in the prototype; each segment's tap area is 48 px.
import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';

class MinSegmented<T> extends StatelessWidget {
  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onSelect;
  final String? semanticLabel;

  const MinSegmented({super.key, required this.options, required this.selected, required this.onSelect, this.semanticLabel});

  static const pillKey = ValueKey('min-segmented-pill');

  /// v2.css .minseg b.on: box-shadow 0 1px 2px rgba(0,0,0,.12).
  static const _raise = [BoxShadow(color: Color(0x1F000000), offset: Offset(0, 1), blurRadius: 2)];

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return Semantics(
      label: semanticLabel,
      container: true,
      child: SizedBox(
        height: TzSize.touchTarget,
        child: Stack(
          children: [
            Positioned.fill(
              top: 2,
              bottom: 2,
              child: Container(
                key: pillKey,
                decoration: BoxDecoration(color: c.tonal, borderRadius: BorderRadius.circular(12)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, MapEntry(:key, :value)) in options.entries.indexed) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Flexible(child: _segment(c, key, value)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(TzColors c, T key, String label) {
    final on = key == selected;
    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: on,
        child: InkWell(
          onTap: () => onSelect(key),
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: TzSize.touchTarget,
            child: Center(
              widthFactor: 1,
              child: Container(
                constraints: const BoxConstraints(minWidth: 52),
                height: 38,
                decoration: on
                    ? BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(10), boxShadow: _raise)
                    : null,
                // Large text that no longer fits its share of the row is drawn smaller, never cut.
                child: Center(
                  widthFactor: 1, // as wide as its word (at least 52), not its whole share of the row
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label,
                        style: TzType.label.copyWith(
                            fontSize: 13, color: on ? c.ink : c.ink2, fontWeight: on ? FontWeight.w600 : FontWeight.w500)),
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
