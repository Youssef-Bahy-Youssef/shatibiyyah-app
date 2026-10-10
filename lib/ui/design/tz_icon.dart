// lib/ui/design/tz_icon.dart — the app's one icon set (item 3.2, ADR 0019).
//
// The glyphs are the prototype's sprite (design/redesign/v2.js), exported to
// assets/icons/NAME.svg by tool/export_icons.py: a 24 grid, a 1.6 stroke, round
// caps and joins, drawn in currentColor. Transport glyphs and the active tab are
// filled (`filled: true`); everything else is stroked. Glyphs that point are
// already drawn for RTL ("next verse" points left), so nothing is mirrored here.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'tokens.g.dart';
import 'tz_theme.dart';

/// Every glyph of the sprite, in its order.
const List<String> kTzIcons = [
  'play', 'pause', 'next', 'prev', 'search', 'aa', 'book', 'book-f', 'list', 'list-f', 'bookmark', 'gear', //
  'gear-f', 'listen', 'pen', 'copy', 'share', 'select', 'back', 'fwd', 'repeat', 'gauge', 'gap', 'mic', 'user',
  'trash', 'down', 'retry', 'theme', 'textsize', 'expand', 'x', 'chev', 'collapse',
];

/// The glyphs drawn filled: transport, and the active-tab forms (`-f`).
const Set<String> kTzFilledIcons = {'play', 'pause', 'next', 'prev', 'book-f', 'list-f', 'gear-f'};

/// [svg] with its root's stroked style turned into a fill (children keep their own attributes).
String filledSvg(String svg) {
  final end = svg.indexOf('>');
  final root = svg.substring(0, end).replaceFirst('fill="none"', 'fill="currentColor"').replaceFirst('stroke="currentColor"', 'stroke="none"');
  return root + svg.substring(end);
}

/// Loads a glyph's asset, filled or stroked; cached per glyph, style and colour.
@immutable
class TzIconLoader extends SvgAssetLoader {
  final bool filled;
  const TzIconLoader(super.assetName, {required this.filled, super.theme});

  @override
  String provideSvg(ByteData? message) {
    final svg = super.provideSvg(message);
    return filled ? filledSvg(svg) : svg;
  }

  @override
  SvgCacheKey cacheKey(BuildContext? context) {
    final base = super.cacheKey(context);
    return SvgCacheKey(keyData: (base.keyData, filled), theme: base.theme, colorMapper: base.colorMapper);
  }

  @override
  bool operator ==(Object other) => other is TzIconLoader && super == other && other.filled == filled;

  @override
  int get hashCode => Object.hash(super.hashCode, filled);
}

class TzIcon extends StatelessWidget {
  final String name;
  final bool filled;

  /// Defaults to the surrounding IconTheme, then 24 (the grid).
  final double? size;

  /// Defaults to the surrounding IconTheme, then the theme's ink.
  final Color? color;

  /// Icons are decorative unless labelled.
  final String? semanticLabel;

  TzIcon(this.name, {super.key, this.filled = false, this.size, this.color, this.semanticLabel})
      : assert(kTzIcons.contains(name), 'no icon "$name" in the sprite');

  @override
  Widget build(BuildContext context) {
    final icons = IconTheme.of(context);
    final size = this.size ?? icons.size ?? TzSize.iconGrid;
    final color = this.color ?? icons.color ?? TzTheme.of(context).colors.ink;
    final picture = SvgPicture(
      TzIconLoader('assets/icons/$name.svg', filled: filled, theme: SvgTheme(currentColor: color)),
      width: size,
      height: size,
      excludeFromSemantics: true,
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: SizedBox.square(dimension: size, child: picture))
        : Semantics(label: semanticLabel, image: true, child: SizedBox.square(dimension: size, child: picture));
  }
}
