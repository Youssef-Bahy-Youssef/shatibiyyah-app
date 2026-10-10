// lib/ui/design/components/ornament.dart — the ornament primitives (item 3.3,
// ADR 0019): the gilt rule that opens every top-level screen and frames the
// matn, and the lozenge, its mark and the active tab's. As v2.css .gilt-rule.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../tz_theme.dart';

/// A small square turned 45°: the rule's mark (gilt) and the active tab's (gilt on the binding).
class Lozenge extends StatelessWidget {
  final double size;
  final Color? color;
  final double radius;
  const Lozenge({super.key, this.size = 7, this.color, this.radius = 0});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color ?? TzTheme.of(context).colors.gilt,
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
        ),
      );
}

/// 1 px of gilt at 55 % with a lozenge 22 px from the start; [centered] under a
/// chapter heading: 72 % of the width, the lozenge in the middle.
class GiltRule extends StatelessWidget {
  final bool centered;
  const GiltRule({super.key, this.centered = false});

  static const lineKey = ValueKey('gilt-rule-line');

  @override
  Widget build(BuildContext context) {
    final gilt = TzTheme.of(context).colors.gilt;
    final rule = SizedBox(
      height: 12,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            key: lineKey,
            height: 1,
            decoration: BoxDecoration(border: Border(top: BorderSide(color: gilt.withValues(alpha: 0.55)))),
          ),
          if (centered)
            const Lozenge()
          else
            const PositionedDirectional(start: 22, top: 2.5, child: Lozenge()),
        ],
      ),
    );
    return ExcludeSemantics(child: centered ? FractionallySizedBox(widthFactor: 0.72, child: rule) : rule);
  }
}
