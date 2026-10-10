// lib/ui/design/components/symbol_tip.dart — what a reader symbol stands for
// (handoff textmode-symbol; v2.css .symtip): the letter on the lapis wash, the
// reader or readers it names, where the poem defines it, and the way to the
// whole list.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

import '../tokens.g.dart';
import '../tz_theme.dart';
import 'tz_button.dart';

class SymbolTip extends StatelessWidget {
  /// The letter as the verse writes it («كَ»).
  final String code;

  /// Who it stands for («ابن عامر»).
  final String title;

  /// Its kind and the verse that defines it.
  final String caption;

  /// «رموز القراء».
  final VoidCallback onOpenList;

  const SymbolTip({super.key, required this.code, required this.title, required this.caption, required this.onOpenList});

  static const surfaceKey = ValueKey('symbol-tip');
  static const codeKey = ValueKey('symbol-tip-code');

  @override
  Widget build(BuildContext context) {
    final tz = TzTheme.of(context), c = tz.colors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'رمز $code',
      child: Container(
        key: surfaceKey,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(16), boxShadow: c.float),
        child: Row(
          children: [
            Container(
              key: codeKey,
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tz.night ? tz.nightInk.accent.withValues(alpha: 0.16) : c.lapisWash,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExcludeSemantics(
                child: Text(code,
                    textScaler: TextScaler.noScaling,
                    style: TzType.display.copyWith(height: 1, fontWeight: FontWeight.w700, color: tz.rubric)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: TzType.head.copyWith(color: c.ink)),
                  Text(caption, style: TzType.caption.copyWith(color: c.ink3)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // The button's 48 px target stands 1 px past the row's 46 px, above and below.
            SizedBox(
              height: 46,
              child: OverflowBox(
                minHeight: TzSize.touchTarget,
                maxHeight: TzSize.touchTarget,
                fit: OverflowBoxFit.deferToChild,
                child: TzButton.tonal(label: 'رموز القراء', dense: true, onPressed: onOpenList),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
