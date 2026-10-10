// lib/ui/design/pill_tabs.dart — the prototype's pill choice (`pillSt`): one
// rounded track, the chosen option filled with gold. For tabs («رموز القراء») and
// settings choices («السمة», «حجم النص»). The pill is 40 pt inside a 4 pt track,
// and each option's tap area takes the track's padding too: 48 pt, the Android
// minimum.
import 'package:flutter/material.dart';

import 'tokens.g.dart';
import 'taysir_colors.dart';

class PillTabs<T> extends StatelessWidget {
  final Map<T, String> options;
  final T? selected;
  final ValueChanged<T> onSelect;
  final Color? track; // the track's colour (default: the panel)
  const PillTabs({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.track,
  });

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: track ?? t.panel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.line),
      ),
      child: Row(
        children: [
          for (final e in options.entries)
            Expanded(
              child: Semantics(
                selected: e.key == selected,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => onSelect(e.key),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: e.key == selected ? t.gold : null,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        e.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TzType.label.copyWith(color: e.key == selected ? t.onGold : t.text),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
