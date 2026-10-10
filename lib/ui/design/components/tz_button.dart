// lib/ui/design/components/tz_button.dart — buttons (item 3.3, ADR 0019; v2.css
// .btn). Primary is the one action fill per view (lapis on paper, ivory at
// night); tonal is the quiet one. 48 px high, 14 px radius, a 14/600 label and
// an optional 18 px icon at the start. Disabled is dimmed to 45 %, as the
// prototype dims a disabled switch.
import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_icon.dart';
import '../tz_theme.dart';

enum _Kind { primary, tonal }

class TzButton extends StatelessWidget {
  final String label;
  final String? icon;
  final bool iconFilled;
  final VoidCallback? onPressed;
  final _Kind _kind;

  const TzButton.primary({super.key, required this.label, this.icon, this.iconFilled = false, required this.onPressed})
    : _kind = _Kind.primary;
  const TzButton.tonal({super.key, required this.label, this.icon, this.iconFilled = false, required this.onPressed})
    : _kind = _Kind.tonal;

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final (fill, ink) = _kind == _Kind.primary ? (c.action, c.onAction) : (c.tonal, c.ink);
    final radius = BorderRadius.circular(TzRadius.control);
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        child: Opacity(
          opacity: onPressed == null ? 0.45 : 1,
          child: Material(
            type: MaterialType.transparency,
            child: Ink(
              height: TzSize.touchTarget,
              decoration: BoxDecoration(color: fill, borderRadius: radius),
              child: InkWell(
                onTap: onPressed,
                borderRadius: radius,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon case final name?) ...[
                        TzIcon(name, filled: iconFilled, size: 18, color: ink),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TzType.label.copyWith(fontWeight: FontWeight.w600, color: ink),
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
