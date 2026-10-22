// lib/ui/design/tz_theme.dart — the two themes, built only from tokens.g.dart
// (item 3.1, ADRs 0013, 0019, 0020).
//
// Material follows the theme, so its defaults (dialogs, pickers, snackbars,
// selection handles, scrollbars) turn light on paper and dark at night. The
// token colours themselves travel as a ThemeExtension: widgets read them with
// `TzTheme.of(context)`.
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'components/tz_motion.dart';
import 'tokens.g.dart';

/// The token colours of the current theme, and which night ink the page uses.
@immutable
class TzTheme extends ThemeExtension<TzTheme> {
  final TzColors colors;
  final bool night;

  /// The rubric and night-page ink (ADR 0020); only used at night.
  final TzNightInk nightInk;

  const TzTheme(this.colors, {required this.night, this.nightInk = TzNightPage.jade});

  static const paper = TzTheme(TzColors.paper, night: false);
  static const dark = TzTheme(TzColors.night, night: true);

  static TzTheme of(BuildContext context) => Theme.of(context).extension<TzTheme>() ?? paper;

  /// The rubric ink: crimson on paper, the chosen night ink at night (ADR 0021).
  Color get rubric => night ? nightInk.accent : colors.rubric;

  @override
  TzTheme copyWith({TzColors? colors, bool? night, TzNightInk? nightInk}) =>
      TzTheme(colors ?? this.colors, night: night ?? this.night, nightInk: nightInk ?? this.nightInk);

  /// Themes switch at once: token sets are not blended.
  @override
  TzTheme lerp(TzTheme? other, double t) => other == null || t < 0.5 ? this : other;
}

TextTheme _textTheme(Color ink, Color ink2) => TextTheme(
      displayLarge: TzType.display.copyWith(color: ink),
      headlineSmall: TzType.title.copyWith(color: ink),
      titleLarge: TzType.title.copyWith(color: ink),
      titleMedium: TzType.head.copyWith(color: ink),
      titleSmall: TzType.label.copyWith(color: ink),
      bodyLarge: TzType.body.copyWith(color: ink),
      bodyMedium: TzType.body.copyWith(color: ink),
      bodySmall: TzType.caption.copyWith(color: ink2),
      labelLarge: TzType.label.copyWith(color: ink),
      labelMedium: TzType.caption.copyWith(color: ink),
      labelSmall: TzType.caption.copyWith(color: ink2),
    );

/// The app's ThemeData for [tz]: paper or night, from the tokens only.
ThemeData tzThemeData(TzTheme tz) {
  final c = tz.colors;
  final brightness = tz.night ? Brightness.dark : Brightness.light;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: TzFont.ui,
    fontFamilyFallback: const [TzFont.text],
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.surface,
    dividerColor: c.lineSoft,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: c.action,
      onPrimary: c.onAction,
      secondary: c.lapis,
      onSecondary: c.surface,
      secondaryContainer: c.lapisWash,
      onSecondaryContainer: c.lapis,
      tertiary: c.gilt,
      onTertiary: c.surface,
      error: c.carmine,
      onError: c.surface,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.ink2,
      surfaceContainerLowest: c.bg,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.raised,
      surfaceContainerHighest: c.tonal,
      outline: c.line,
      outlineVariant: c.lineSoft,
      scrim: c.scrim,
      shadow: c.float.first.color,
      inverseSurface: c.snack,
      onInverseSurface: c.onSnack,
      inversePrimary: c.snackAct,
    ),
    textTheme: _textTheme(c.ink, c.ink2),
    iconTheme: IconThemeData(color: c.ink, size: TzSize.iconGrid),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.lapis,
      selectionHandleColor: c.lapis,
      selectionColor: c.lapisWash,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.snack,
      contentTextStyle: TzType.body.copyWith(color: c.onSnack),
      actionTextColor: c.snackAct,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TzRadius.control)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      modalBackgroundColor: c.surface,
      modalBarrierColor: c.scrim,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(TzRadius.sheet))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.raised,
      barrierColor: c.scrim,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TzRadius.card)),
      titleTextStyle: TzType.title.copyWith(color: c.ink),
      contentTextStyle: TzType.body.copyWith(color: c.ink2),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.lapis, linearTrackColor: c.line),
    // The app's own tap targets answer with TzPressable (ADR 0037); a bare InkWell
    // stays quiet, and Material's buttons ripple softly inside their own shape.
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    iconButtonTheme: const IconButtonThemeData(style: _ripple),
    textButtonTheme: const TextButtonThemeData(style: _ripple),
    filledButtonTheme: const FilledButtonThemeData(style: _ripple),
    outlinedButtonTheme: const OutlinedButtonThemeData(style: _ripple),
    // Pushed screens move along the reading direction (ADR 0037); iOS keeps its
    // own, which already mirrors in Arabic and follows the back swipe.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: TzPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: TzPageTransitionsBuilder(),
      TargetPlatform.linux: TzPageTransitionsBuilder(),
      TargetPlatform.windows: TzPageTransitionsBuilder(),
      TargetPlatform.fuchsia: TzPageTransitionsBuilder(),
    }),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    extensions: [tz],
  );
}

/// Material's buttons: a ripple from the touch, inside the button's own shape.
const ButtonStyle _ripple = ButtonStyle(splashFactory: InkRipple.splashFactory);
