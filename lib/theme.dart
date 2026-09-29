// lib/theme.dart — design tokens ported verbatim from css/style.css :root.
// CSS px → Flutter logical px is 1:1 (a mobile browser at initial-scale=1 maps
// 1 CSS px to 1 device-independent px, which is exactly Flutter's logical px).
// 1rem = 16 CSS px = 16 logical px.
import 'package:flutter/material.dart';

/// Colour palette — every value is the exact hex/rgba from style.css :root.
class C {
  // provided palette
  static const colorDarker = Color(0xFF965F0D);
  static const colorBase = Color(0xFFFFAB2E);
  static const colorLighter = Color(0xFFFADBAE);
  static const colorAccent = Color(0xFF4314FF);
  static const colorDark = Color(0xFF4E3613);
  static const colorLight = Color(0xFFF4F1EB);

  // warm-dark surfaces (espresso → brown)
  static const ink = Color(0xFF1B1307);
  static const ink2 = Color(0xFF241A0C);
  static const panel = Color(0xFF2A1E0E);
  static const panel2 = Color(0xFF33260F);
  static const raised = Color(0xFF3F2F15);
  static const line = Color(0xFF4A3719);
  static const lineSoft = Color(0xFF382912);

  // amber / gold accents
  static const gold = Color(0xFFFFAB2E);
  static const goldBright = Color(0xFFFADBAE);
  static const goldDeep = Color(0xFF965F0D);
  static final goldFaint = const Color(0xFFFFAB2E).withValues(alpha: .16);

  // warm cream text
  static const parch = Color(0xFFF4F1EB);
  static const parchDim = Color(0xFFD6CCB8);
  static const muted = Color(0xFFB39A6B);
  static const muted2 = Color(0xFF8D7850);

  // status + interaction accent
  static const teal = Color(0xFF86B07A);
  static const danger = Color(0xFFE08A5A);
  static const accent = Color(0xFF4314FF);

  // text colour used on gold-filled surfaces (style.css uses #1a1304 throughout)
  static const onGold = Color(0xFF1A1304);

  // page-viewer highlight colours (page-viewer.js COLORS / CHAPTER_COLORS)
  static const hiliteDayFill = Color(0x52FFAB2E); // rgba(255,171,46,0.32)
  static const hiliteDayStroke = Color(0xF2FFAB2E); // rgba(255,171,46,0.95)
  static const hiliteDayGhost = Color(0x2EFFAB2E); // rgba(255,171,46,0.18)
  static const hiliteNightFill = Color(0x4D788CFA); // rgba(120,140,250,0.30)
  static const hiliteNightStroke = Color(0xF2AABAFF); // rgba(170,186,255,0.95)
  static const hiliteNightGhost = Color(0x2E96A8FF); // rgba(150,168,255,0.18)
  static const chapterSelFill = Color(0x33FFAB2E); // rgba(255,171,46,0.20)
  static const chapterSelStroke = Color(0xF2FFAB2E); // rgba(255,171,46,0.95)
  static const chapterHoverFill = Color(0x1AFFAB2E); // rgba(255,171,46,0.10)
  static const chapterHoverStroke = Color(0xA6FFAB2E); // rgba(255,171,46,0.65)
}

/// Border radii (style.css: --r-lg/md/sm) and the --tap target size.
class R {
  static const lg = 22.0;
  static const md = 16.0;
  static const sm = 12.0;
  static const tap = 52.0;
}

/// Font families (style.css --ff-kufi / --ff-naskh / --ff-ui).
const String kFontNaskh = 'ScheherazadeNew';
const String kFontKufi = 'ReemKufi';

/// Global fallback so Arabic-Indic digits and letters always render in
/// "ui" (system) styles too.
const List<String> kFontFallback = ['ScheherazadeNew', 'ReemKufi'];

/// --ff-naskh: "Scheherazade New"
TextStyle naskh({
  double size = 16,
  FontWeight weight = FontWeight.w400,
  Color color = C.parch,
  double? height,
  double? letterSpacing,
}) =>
    TextStyle(
      fontFamily: kFontNaskh,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );

/// --ff-kufi: "Reem Kufi" (variable font — drive the weight via the wght axis).
TextStyle kufi({
  double size = 16,
  int weight = 600,
  Color color = C.parch,
  double? height,
  double? letterSpacing,
}) =>
    TextStyle(
      fontFamily: kFontKufi,
      // Reem Kufi has no «٪» (U+066A) among others: the Naskh face, not a system
      // font or a box, stands in for what it lacks.
      fontFamilyFallback: const [kFontNaskh],
      fontSize: size,
      fontWeight: FontWeight.values[(weight ~/ 100) - 1],
      fontVariations: [FontVariation('wght', weight.toDouble())],
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );

/// --ff-ui: system sans (numbers / meta). Tabular numerals where the CSS asks.
TextStyle ui({
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color color = C.parch,
  double? height,
  bool tabular = false,
  double? letterSpacing,
}) =>
    TextStyle(
      fontFamilyFallback: kFontFallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );
