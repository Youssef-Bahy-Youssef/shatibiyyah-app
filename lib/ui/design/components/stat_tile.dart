// lib/ui/design/components/stat_tile.dart — a value tile (item 3.3; v2.css .stat):
// the value over its caption on the tonal fill, with an optional counter badge
// (e.g. «٢/٣», the repetition in progress) in its top end corner.
import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';

class StatTile extends StatelessWidget {
  final String value;
  final String label;
  final String? badge;
  final VoidCallback? onTap;

  const StatTile({super.key, required this.value, required this.label, this.badge, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final radius = BorderRadius.circular(TzRadius.control);
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: '$label: $value${badge == null ? '' : '، $badge'}',
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            decoration: BoxDecoration(color: c.tonal, borderRadius: radius),
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: ExcludeSemantics(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 66),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(value,
                                  style: TzType.head.copyWith(
                                      height: 22 / 16, color: c.ink, fontFeatures: const [FontFeature.tabularFigures()])),
                              const SizedBox(height: 2),
                              Text(label, textAlign: TextAlign.center, style: TzType.caption.copyWith(fontSize: 11.5, color: c.ink3)),
                            ],
                          ),
                        ),
                      ),
                      if (badge case final b?)
                        PositionedDirectional(
                          top: 6,
                          end: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            decoration: BoxDecoration(color: c.lapisWash, borderRadius: BorderRadius.circular(6)),
                            child: Text(b,
                                style: TzType.caption.copyWith(fontSize: 10.5, height: 16 / 10.5, fontWeight: FontWeight.w700, color: c.lapis)),
                          ),
                        ),
                    ],
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
