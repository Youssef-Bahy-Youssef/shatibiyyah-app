// lib/ui/design/pill_tabs.dart — the prototype's pill choice (`pillSt`): one
// rounded track, the chosen option filled with gold. For tabs («رموز القراء») and
// settings choices («السمة», «حجم النص»).
import 'package:flutter/material.dart';

import '../../theme.dart' show kufi;
import 'taysir_colors.dart';

class PillTabs<T> extends StatelessWidget {
  final Map<T, String> options;
  final T? selected;
  final ValueChanged<T> onSelect;
  const PillTabs({super.key, required this.options, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.panel,
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
                  child: Container(
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: e.key == selected ? t.gold : null,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(e.value,
                        style: kufi(
                            size: 14, weight: e.key == selected ? 600 : 400, color: e.key == selected ? t.onGold : t.text)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
