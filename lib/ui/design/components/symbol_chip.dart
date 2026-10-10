// lib/ui/design/components/symbol_chip.dart — a reader symbol in its frame, for
// the list of symbols («رموز القراء»; ADR 0024, tokens.json symbolFrame): the
// rubric ink on a tint and a hairline of itself. [active] is the symbol the
// student came from: the chosen-verse tint and a solid ring (lapis on paper,
// the night ink at night). The matn text has no frames (ADR 0021).
import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';

class SymbolChip extends StatelessWidget {
  /// The letter or the word («ك», «صحبة»).
  final String code;

  /// The size of its text; the frame follows it.
  final double size;
  final bool active;

  const SymbolChip(this.code, {super.key, this.size = 22, this.active = false});

  @override
  Widget build(BuildContext context) {
    final tz = TzTheme.of(context), ink = tz.rubric;
    final (fill, line, width) = active
        ? (
            tz.night ? tz.nightInk.accent.withValues(alpha: 0.16) : tz.colors.lapisWash,
            tz.night ? tz.nightInk.accent : tz.colors.lapis,
            TzSymbolFrame.activeLineWidth
          )
        : (ink.withValues(alpha: TzSymbolFrame.fill), ink.withValues(alpha: TzSymbolFrame.line), TzSymbolFrame.lineWidth);
    return Container(
      height: TzSymbolFrame.height * size,
      constraints: BoxConstraints(minWidth: 1.7 * size),
      padding: EdgeInsets.symmetric(horizontal: 0.36 * size),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(TzSymbolFrame.radius * size),
        border: Border.all(color: line, width: width),
      ),
      // The frame is the symbol's size whatever the system's text scale: the names beside it grow.
      child: Center(
        widthFactor: 1,
        child: Text(code, textScaler: TextScaler.noScaling, style: TzType.verse.copyWith(fontSize: size, height: 1.5, color: ink)),
      ),
    );
  }
}
