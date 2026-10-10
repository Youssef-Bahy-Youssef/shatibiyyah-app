// lib/ui/design/components/share_controls.dart — the share sheet's own controls
// (item 3.11; v2.css .share-prev, .fmts, .chips2): the framed preview of the
// card, the three export sizes, and the book chips of the excerpt.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';
import 'share_card.dart';

/// The card in the sheet (v2.css .share-prev .frame): scaled to fit 330 × 300,
/// with rounded corners, a soft shadow and a hairline around it.
class SharePreviewFrame extends StatelessWidget {
  final CardFormat format;
  final Widget child;
  const SharePreviewFrame({super.key, required this.format, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final size = format.size;
    final k = math.min(300 / size.height, 330 / size.width);
    return Container(
      width: (size.width * k).roundToDouble(),
      height: (size.height * k).roundToDouble(),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          const BoxShadow(color: Color(0x2E000000), offset: Offset(0, 8), blurRadius: 24),
          BoxShadow(color: c.lineSoft, spreadRadius: 1),
        ],
      ),
      child: FittedBox(fit: BoxFit.fill, child: child),
    );
  }
}

/// One export size (v2.css .fmts button): its outline, its name and its ratio.
class ShareFormatButton extends StatelessWidget {
  final CardFormat format;
  final bool selected, enabled;
  final VoidCallback onTap;
  const ShareFormatButton({super.key, required this.format, required this.selected, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final ink = enabled ? c.ink : c.ink3;
    final radius = BorderRadius.circular(TzRadius.control);
    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        enabled: enabled,
        child: Material(
          color: enabled ? c.surface : c.tonal,
          borderRadius: radius,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: radius,
            child: Container(
              height: 80,
              foregroundDecoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: selected ? c.ink : c.lineSoft, width: 1.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 16,
                    height: ((26 * format.height / format.width).round() * 0.62).roundToDouble(),
                    decoration: BoxDecoration(border: Border.all(color: ink, width: 2), borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(height: 4),
                  Text(format.ar, style: TzType.label.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: ink)),
                  Text(format.ratio,
                      style: TzType.caption.copyWith(fontSize: 11, color: c.ink3, fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A book to quote from (v2.css .chips2 b): 36 px drawn, in a 48 px target.
class ShareBookChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const ShareBookChip({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: TzSize.touchTarget,
            child: Center(
              heightFactor: 1,
              widthFactor: 1,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: selected ? c.action : c.tonal, borderRadius: BorderRadius.circular(TzRadius.pill)),
                child: Text(label,
                    style: TzType.label.copyWith(fontSize: 13, color: selected ? c.onAction : c.ink2)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
