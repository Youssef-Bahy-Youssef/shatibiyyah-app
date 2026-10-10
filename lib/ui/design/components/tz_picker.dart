// lib/ui/design/components/tz_picker.dart — a focused picker (items 3.6 and 3.7;
// v2.css .picker and .opts): a title in the matn's face, one sentence that
// states the rule, the choices, and «تم». A choice applies at once; «تم» only
// closes. The choices scroll when large text or a short screen leaves no room.
import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';
import 'tz_button.dart';
import 'tz_sheet.dart';

/// Shows a picker over the whole app (the dock too), on the theme's scrim.
Future<void> showTzPicker(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: builder,
    );

class TzPicker extends StatelessWidget {
  final String title;
  final String? help;

  /// A control at the end of the title's line (a [MinSegmented]: 44 px drawn in a 48 px target).
  final Widget? titleTrailing;
  final Widget child;
  const TzPicker({super.key, required this.title, this.help, this.titleTrailing, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return TzSheet.picker(
      child: ConstrainedBox(
        // The sheet's own grab and padding (55 px) stay on screen under the status bar.
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height - statusBarHeight(context) - 55),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The trailing control's target reaches 2 px past its drawing, above and below.
            SizedBox(height: titleTrailing == null ? 10 : 8),
            if (titleTrailing case final trailing?)
              Row(
                children: [
                  Expanded(child: Text(title, style: TzType.title.copyWith(color: c.ink))),
                  const SizedBox(width: 8),
                  trailing,
                ],
              )
            else
              Text(title, style: TzType.title.copyWith(color: c.ink)),
            if (help != null) Text(help!, style: TzType.label.copyWith(color: c.ink3)),
            SizedBox(height: titleTrailing == null ? 14 : 12),
            Flexible(child: SingleChildScrollView(child: child)),
            const SizedBox(height: 12),
            TzButton.primary(label: 'تم', onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}

/// One choice in a grid of values: 56 px high on the tonal fill, the chosen one
/// in the action colour.
class PickerOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Longer values (the speeds) are set a step smaller.
  final bool compact;
  const PickerOption({super.key, required this.label, required this.selected, required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final radius = BorderRadius.circular(TzRadius.control);
    final style = (compact ? TzType.body : TzType.head).copyWith(
        fontWeight: FontWeight.w600,
        color: selected ? c.onAction : c.ink,
        fontFeatures: const [FontFeature.tabularFigures()]);
    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        child: Material(
          color: selected ? c.action : c.tonal,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: style)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The values of one setting, [columns] to a row with 8 px between.
class OptionGrid<T> extends StatelessWidget {
  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onSelect;
  final int columns;
  final bool compact;
  final String? semanticLabel;

  const OptionGrid(
      {super.key,
      required this.options,
      required this.selected,
      required this.onSelect,
      this.columns = 3,
      this.compact = false,
      this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final entries = options.entries.toList();
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: Column(
        children: [
          for (var row = 0; row * columns < entries.length; row++) ...[
            if (row > 0) const SizedBox(height: 8),
            Row(
              children: [
                for (var col = 0; col < columns; col++) ...[
                  if (col > 0) const SizedBox(width: 8),
                  Expanded(
                    child: row * columns + col < entries.length
                        ? PickerOption(
                            label: entries[row * columns + col].value,
                            selected: entries[row * columns + col].key == selected,
                            compact: compact,
                            onTap: () => onSelect(entries[row * columns + col].key),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
