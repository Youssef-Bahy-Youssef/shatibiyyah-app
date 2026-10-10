// lib/ui/design/components/night_crop.dart — a piece of a real matn page as it
// looks at night in one ink (item 3.6, ADR 0020; v2.css .ncrop, v2.js
// nightCrop). The picker and its settings row show this instead of a colour
// dot, which would not say what the setting does. The piece is
// TzNightPage.previewCrop of page 19, scaled to [width].
import 'package:flutter/material.dart';

import '../night_page.dart';
import '../tokens.g.dart';

class NightCrop extends StatelessWidget {
  final TzNightInk ink;
  final double width;
  const NightCrop({super.key, required this.ink, required this.width});

  /// The page the crop is cut from, and a scan's size in its own pixels.
  static const String page = 'assets/pages/page019.webp';
  static const Size scan = Size(1130, 1735);

  static double heightFor(double width) => (TzNightPage.previewCrop.height * width / TzNightPage.previewCrop.width).roundToDouble();

  @override
  Widget build(BuildContext context) {
    const crop = TzNightPage.previewCrop;
    final k = width / crop.width;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: width,
          height: heightFor(width),
          color: TzNightPage.pageBg,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: scan.width * k,
            maxWidth: scan.width * k,
            minHeight: scan.height * k,
            maxHeight: scan.height * k,
            child: Transform.translate(
              offset: Offset(-crop.left * k, -crop.top * k),
              child: ColorFiltered(
                colorFilter: ColorFilter.matrix(nightInkMatrix(ink)),
                child: Image.asset(
                  page,
                  fit: BoxFit.fill,
                  // One decoded scan serves every crop on screen; medium filtering keeps
                  // the small ones sharp.
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
