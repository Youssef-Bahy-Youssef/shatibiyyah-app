// lib/ui/design/app_theme.dart — the chosen palette, app-wide.
//
// A notifier above MaterialApp, so every route (the reader, the commentary, sheets)
// switches between the dark and paper themes together.
import 'package:flutter/foundation.dart';

import '../../data/settings_store.dart';
import 'taysir_colors.dart';

final ValueNotifier<ReaderTheme> appTheme = ValueNotifier(ReaderTheme.dark);

TaysirColors colorsFor(ReaderTheme theme) => theme == ReaderTheme.paper ? TaysirColors.paper : TaysirColors.dark;
