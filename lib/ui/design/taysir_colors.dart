// lib/ui/design/taysir_colors.dart — the names the screens written before the
// redesign use for colours, each answered by one design token (plan item 3.1,
// decision D1 option A: one token per legacy role).
//
// No colour value lives here: every getter returns a field of tokens.g.dart.
// Items 3.4–3.11 rebuild the screens from the components, which read the tokens
// directly (`TzTheme.of(context)`); this file goes when the last of them has.
import 'package:flutter/material.dart';

import 'tokens.g.dart';
import 'tz_theme.dart';

@immutable
class TaysirColors {
  final TzColors tokens;

  const TaysirColors(this.tokens);

  static const dark = TaysirColors(TzColors.night);
  static const paper = TaysirColors(TzColors.paper);

  static TaysirColors of(BuildContext context) => TaysirColors(TzTheme.of(context).colors);

  // surfaces
  Color get bg => tokens.bg;
  Color get panel => tokens.surface;
  Color get panel2 => tokens.tonal;
  Color get raised => tokens.raised;
  Color get line => tokens.line;

  // the amber accent family: its fill is the action fill, its text the state colour
  Color get gold => tokens.action;
  Color get onGold => tokens.onAction;
  Color get goldText => tokens.lapis;
  Color get goldDeep => tokens.gilt;
  Color get goldBright => tokens.ink;

  // text
  Color get text => tokens.ink;
  Color get dim => tokens.ink2;
  Color get muted => tokens.ink3;

  // state
  Color get teal => tokens.lapis;
  Color get warn => tokens.carmine;
  Color get quran => tokens.lapis;

  /// The old interaction accent (the selection on the paper page).
  Color get accent => tokens.lapis;

  /// What dims the page behind a menu or a sheet.
  Color get scrim => tokens.scrim;

  /// The shadow under floating elements.
  List<BoxShadow> get float => tokens.float;

  /// The ribbon colour of the bookmark colour at [index] (BookmarkColor's order is the tokens').
  Color bookmark(int index) => tokens.bookmarks[index];

  @override
  bool operator ==(Object other) => other is TaysirColors && identical(other.tokens, tokens);

  @override
  int get hashCode => identityHashCode(tokens);
}
