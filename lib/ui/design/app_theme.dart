// lib/ui/design/app_theme.dart — the palette and the night ink, app-wide.
//
// Notifiers above MaterialApp, so every route (the reader, the commentary,
// sheets) changes together. «المظهر» is a choice of three: paper, night, or
// with the system; [appTheme] is what that comes to on this device now.
import 'package:flutter/widgets.dart';

import '../../data/settings_store.dart';
import 'tokens.g.dart';
import 'tz_theme.dart';

final ValueNotifier<ThemeChoice> appThemeChoice = ValueNotifier(ThemeChoice.auto);
final ValueNotifier<ReaderTheme> appTheme = ValueNotifier(ReaderTheme.dark);

/// The night ink the reader chose (ADR 0020): the night page, the chosen-verse
/// ring and the rubric at night are drawn in it.
final ValueNotifier<TzNightInk> appNightInk = ValueNotifier(TzNightPage.jade);

ReaderTheme resolveTheme(ThemeChoice choice, Brightness system) => switch (choice) {
      ThemeChoice.paper => ReaderTheme.paper,
      ThemeChoice.night => ReaderTheme.dark,
      ThemeChoice.auto => system == Brightness.dark ? ReaderTheme.dark : ReaderTheme.paper,
    };

/// Sets «المظهر» and what it comes to under the system's brightness now.
void applyThemeChoice(ThemeChoice choice) {
  appThemeChoice.value = choice;
  appTheme.value = resolveTheme(choice, WidgetsBinding.instance.platformDispatcher.platformBrightness);
}

/// The offered ink with [id]; anything else (nothing stored, a retired ink, a
/// damaged value) is the default, jade.
TzNightInk nightInkById(String? id) {
  for (final ink in TzNightPage.inks) {
    if (ink.id == id) return ink;
  }
  return TzNightPage.jade;
}

/// The token theme of [theme]: paper, or night in [ink].
TzTheme tzThemeFor(ReaderTheme theme, {TzNightInk ink = TzNightPage.jade}) =>
    theme == ReaderTheme.paper ? TzTheme.paper : TzTheme(TzColors.night, night: true, nightInk: ink);
