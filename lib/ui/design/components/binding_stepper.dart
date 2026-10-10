// lib/ui/design/components/binding_stepper.dart — previous and next verse on the
// binding (item 3.3, ADR 0022; v2.css .stepper): cover, 60 px, 22 px radius,
// the dock shadow. Previous sits at the start with ›, next at the end with ‹,
// and the step's khatam with «من ٩ في الباب» between them. A missing neighbour
// (a chapter's first or last verse) is dimmed and disabled.
import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_icon.dart';
import '../tz_theme.dart';
import 'khatam.dart';

class BindingStepper extends StatelessWidget {
  final String previous, next;
  final String step; // «١»
  final String caption; // «من ٩ في الباب»
  final VoidCallback? onPrevious, onNext;

  const BindingStepper(
      {super.key,
      required this.previous,
      required this.next,
      required this.step,
      required this.caption,
      required this.onPrevious,
      required this.onNext});

  static const bindingKey = ValueKey('binding-stepper');

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    // A fixed-height binding, like the dock: its text follows the system size up
    // to 1.3×, and each of its three parts shrinks to its share before it overflows.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3)),
      child: Container(
        key: bindingKey,
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(color: c.cover, borderRadius: BorderRadius.circular(22), boxShadow: c.dock),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: _button(c, previous, onPrevious, leading: 'back')),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Khatam(step, size: 30, onCover: true),
                  const SizedBox(width: 8),
                  Text(caption, style: TzType.caption.copyWith(fontWeight: FontWeight.w400, color: c.coverMute)),
                ]),
              ),
            ),
            Flexible(child: _button(c, next, onNext, trailing: 'fwd')),
          ],
        ),
      ),
    );
  }

  Widget _button(TzColors c, String label, VoidCallback? onTap, {String? leading, String? trailing}) => MergeSemantics(
        child: Semantics(
          button: true,
          enabled: onTap != null,
          child: Opacity(
            opacity: onTap == null ? 0.45 : 1,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(TzRadius.control),
              child: Container(
                height: TzSize.touchTarget,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (leading != null) TzIcon(leading, size: 22, color: c.onCover),
                    if (leading != null) const SizedBox(width: 2),
                    Text(label, style: TzType.label.copyWith(fontSize: 13.5, color: c.onCover)),
                    if (trailing != null) const SizedBox(width: 2),
                    if (trailing != null) TzIcon(trailing, size: 22, color: c.onCover),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}
