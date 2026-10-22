// lib/ui/design/components/tz_switch.dart — a switch that says its state (item
// 3.3; v2.css .toggle and .sw). The word («تُتلى», «ظاهر») comes first, then a
// 44 × 26 track: lapis when on, line when off. The knob sits at the end when on
// (RTL: left, as the prototype draws it) and slides in 200 ms. The whole row is
// the target, at least 48 px high. Disabled is dimmed to 45 %.
import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';
import 'tz_motion.dart';

class TzSwitch extends StatelessWidget {
  final bool value;
  final String onWord, offWord;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  const TzSwitch(
      {super.key, required this.value, required this.onWord, required this.offWord, required this.onChanged, this.semanticLabel});

  static const trackKey = ValueKey('tz-switch-track');
  static const knobKey = ValueKey('tz-switch-knob');

  /// v2.css .sw::after: box-shadow 0 1px 2px rgba(0,0,0,.25).
  static const _knobShadow = [BoxShadow(color: Color(0x40000000), offset: Offset(0, 1), blurRadius: 2)];

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final word = value ? onWord : offWord;
    return MergeSemantics(
      child: Semantics(
        label: semanticLabel,
        value: word,
        toggled: value,
        enabled: onChanged != null,
        child: Opacity(
          opacity: onChanged == null ? 0.45 : 1,
          child: TzPressable(
            onTap: onChanged == null ? null : () => onChanged!(!value),
            borderRadius: BorderRadius.circular(TzRadius.control),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: TzSize.touchTarget),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(child: Text(word, style: TzType.body.copyWith(fontSize: 13, color: c.ink2))),
                  const SizedBox(width: 8),
                  Container(
                    key: trackKey,
                    width: 44,
                    height: 26,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: value ? c.lapis : c.line, borderRadius: BorderRadius.circular(13)),
                    child: AnimatedAlign(
                      alignment: value ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                      duration: tzDuration(context, TzMotion.medium),
                      curve: TzMotion.standard,
                      child: Container(
                        key: knobKey,
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(color: c.raised, shape: BoxShape.circle, boxShadow: _knobShadow),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
