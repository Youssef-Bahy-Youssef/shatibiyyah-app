// lib/ui/design/app_theme.dart — the chosen palette, app-wide.
//
// A notifier above MaterialApp, so every route (the reader, the commentary, sheets)
// switches between the dark and paper themes together.
import 'package:flutter/foundation.dart';

import '../../data/settings_store.dart';
import 'tz_theme.dart';

final ValueNotifier<ReaderTheme> appTheme = ValueNotifier(ReaderTheme.dark);

/// The token theme of [theme]: paper, or night for the dark choice.
TzTheme tzThemeFor(ReaderTheme theme) => theme == ReaderTheme.paper ? TzTheme.paper : TzTheme.dark;
