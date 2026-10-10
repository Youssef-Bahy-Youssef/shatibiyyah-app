// lib/ui/design/components/night_ink_option.dart — one ink in the night-ink
// picker (item 3.6, ADR 0020; v2.css .inkopt): the ink on a crop of the real
// page, its name in the matn's face (with «الافتراضي» on the default), a line on
// its character, and a radio. At least 72 px high; the chosen one has an ink
// edge and a filled radio.
import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';
import 'night_crop.dart';

class NightInkOption extends StatelessWidget {
  final TzNightInk ink;
  final bool selected;
  final bool isDefault;
  final VoidCallback onTap;

  const NightInkOption({super.key, required this.ink, required this.selected, this.isDefault = false, required this.onTap});

  static const radioKey = ValueKey('night-ink-radio');

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final radius = BorderRadius.circular(16);
    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        child: Material(
          color: c.surface,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Container(
              constraints: const BoxConstraints(minHeight: 72),
              // The edge is drawn over the box (1.5 px, as v2.css), the content
              // stays where the measured 1 px edge and 8 px padding put it.
              padding: const EdgeInsets.all(9),
              foregroundDecoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: selected ? c.ink : c.lineSoft, width: 1.5),
              ),
              child: Row(
                children: [
                  NightCrop(ink: ink, width: 124),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The tag goes under the name when large text leaves no room beside it.
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(ink.ar, style: TzType.title.copyWith(color: c.ink, height: 26 / TzType.title.fontSize!)),
                            if (isDefault)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                                decoration: BoxDecoration(color: c.tonal, borderRadius: BorderRadius.circular(6)),
                                child: Text(TzNightPage.defaultTag,
                                    style: TzType.caption.copyWith(
                                        color: c.ink2, fontWeight: FontWeight.w600, height: 18 / TzType.caption.fontSize!)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(ink.arMood, style: TzType.caption.copyWith(color: c.ink3, height: 18 / TzType.caption.fontSize!)),
                        const SizedBox(height: 2),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    key: radioKey,
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: selected ? c.ink : c.line, width: 2),
                    ),
                    child: selected
                        ? Container(width: 12, height: 12, decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle))
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
