// lib/ui/design/taysir_colors.dart — the v3 design's two palettes as a ThemeExtension.
//
// Values are the prototype's `D` (dark: espresso and gold) and `L` (paper) token
// maps (Prototype - Full App.dc.html). New screens read colours from here, never
// from constants, so the paper theme works everywhere they are used. The old
// screens still use lib/theme.dart's dark-only `C` constants until P4 redraws them.
import 'package:flutter/material.dart';

@immutable
class TaysirColors extends ThemeExtension<TaysirColors> {
  final Color bg, panel, panel2, raised, line;
  final Color gold, goldBright, goldDeep, goldText;
  final Color text, dim, muted;
  final Color teal, tealBg, warn, quran, glass;

  /// Text on a gold fill (the same in both themes).
  final Color onGold;

  const TaysirColors({
    required this.bg,
    required this.panel,
    required this.panel2,
    required this.raised,
    required this.line,
    required this.gold,
    required this.goldBright,
    required this.goldDeep,
    required this.goldText,
    required this.text,
    required this.dim,
    required this.muted,
    required this.teal,
    required this.tealBg,
    required this.warn,
    required this.quran,
    required this.glass,
    this.onGold = const Color(0xFF1A1304),
  });

  static const dark = TaysirColors(
    bg: Color(0xFF1B1307),
    panel: Color(0xFF2A1E0E),
    panel2: Color(0xFF33260F),
    raised: Color(0xFF3F2F15),
    line: Color(0xFF4A3719),
    gold: Color(0xFFFFAB2E),
    goldBright: Color(0xFFFADBAE),
    goldDeep: Color(0xFF965F0D),
    goldText: Color(0xFFFFAB2E),
    text: Color(0xFFF4F1EB),
    dim: Color(0xFFD6CCB8),
    muted: Color(0xFFB39A6B),
    teal: Color(0xFF86B07A),
    tealBg: Color(0x2986B07A), // rgba(134,176,122,.16)
    warn: Color(0xFFE08A5A),
    quran: Color(0xFF7CCBD8),
    glass: Color(0xF0241A0C), // rgba(36,26,12,.94)
  );

  static const paper = TaysirColors(
    bg: Color(0xFFF3EAD7),
    panel: Color(0xFFFBF7EE),
    panel2: Color(0xFFF4EBD8),
    raised: Color(0xFFE9DABB),
    line: Color(0xFFD9C49C),
    gold: Color(0xFFFFAB2E),
    goldBright: Color(0xFF7A4A06),
    goldDeep: Color(0xFFB87A1C),
    goldText: Color(0xFF825107),
    text: Color(0xFF241A0C),
    dim: Color(0xFF4E3613),
    muted: Color(0xFF735629),
    teal: Color(0xFF3F6A37),
    tealBg: Color(0x1F3F6A37), // rgba(63,106,55,.12)
    warn: Color(0xFF963F10),
    quran: Color(0xFF1C6674),
    glass: Color(0xF2FBF7EE), // rgba(251,247,238,.95)
  );

  static TaysirColors of(BuildContext context) =>
      Theme.of(context).extension<TaysirColors>() ?? TaysirColors.dark;

  @override
  TaysirColors copyWith() => this;

  @override
  TaysirColors lerp(TaysirColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return TaysirColors(
      bg: l(bg, other.bg),
      panel: l(panel, other.panel),
      panel2: l(panel2, other.panel2),
      raised: l(raised, other.raised),
      line: l(line, other.line),
      gold: l(gold, other.gold),
      goldBright: l(goldBright, other.goldBright),
      goldDeep: l(goldDeep, other.goldDeep),
      goldText: l(goldText, other.goldText),
      text: l(text, other.text),
      dim: l(dim, other.dim),
      muted: l(muted, other.muted),
      teal: l(teal, other.teal),
      tealBg: l(tealBg, other.tealBg),
      warn: l(warn, other.warn),
      quran: l(quran, other.quran),
      glass: l(glass, other.glass),
    );
  }
}
