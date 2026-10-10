// lib/ui/design/components/settings_row.dart — «الإعدادات»'s groups and rows
// (items 3.6 and 3.10; v2.css .sgroup, .slist, .srow).
//
// A group is a caption over one bordered surface (18 px corners); its rows are
// at least 56 px high, split by a 1 px line that belongs to the lower row. A
// row is a 20 px glyph (or its own leading), a label (with an optional caption
// under it), and at its end either a value with a chevron, a chevron alone, or a
// control. A control drawn smaller than its 48 px target says by how much it
// overhangs its drawing ([controlOverhang]), so the row keeps the measured height.
import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_icon.dart';
import '../tz_theme.dart';

class SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> rows;
  const SettingsGroup({super.key, required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Semantics(
              header: true,
              child: Text(title, style: TzType.caption.copyWith(color: c.ink3)),
            ),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(TzRadius.card)),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TzRadius.card),
              border: Border.all(color: c.lineSoft),
            ),
            padding: const EdgeInsets.all(1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final (i, row) in rows.indexed) _RowPlace(first: i == 0, child: row)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Where a row stands in its group: the first has no line above it.
class _RowPlace extends InheritedWidget {
  final bool first;
  const _RowPlace({required this.first, required super.child});

  @override
  bool updateShouldNotify(_RowPlace old) => old.first != first;
}

class SettingsRow extends StatelessWidget {
  final String? icon;
  final Widget? leading;
  final String label;
  final String? caption;
  final String? value;
  final TextStyle? valueStyle;
  final Widget? control;
  final double controlOverhang;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// A row that leads on: [value] (if any) and a chevron at its end.
  const SettingsRow({
    super.key,
    this.icon,
    this.leading,
    required this.label,
    this.caption,
    this.value,
    this.valueStyle,
    required VoidCallback this.onTap,
    this.semanticLabel,
  }) : control = null,
       controlOverhang = 0;

  /// A row holding a [control]; the row itself is not a target.
  const SettingsRow.control({super.key, this.icon, required this.label, required Widget this.control, this.controlOverhang = 0})
    : leading = null,
      caption = null,
      value = null,
      valueStyle = null,
      onTap = null,
      semanticLabel = null;

  static const leadingKey = ValueKey('settings-row-leading');

  /// The label and its control at the two ends of one line; when large text
  /// leaves no room for both, the control goes under the label.
  Widget _withControl(Widget glyph, Widget labelText) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    runAlignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          glyph,
          const SizedBox(width: 12),
          Flexible(child: labelText),
        ],
      ),
      control!,
    ],
  );

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final first = context.dependOnInheritedWidgetOfExactType<_RowPlace>()?.first ?? true;
    final labelText = Text(label, style: TzType.label.copyWith(color: c.ink));
    final glyph = KeyedSubtree(
      key: leadingKey,
      child: leading ?? TzIcon(icon!, size: 20, color: c.ink3),
    );
    final row = Container(
      constraints: const BoxConstraints(minHeight: 56),
      decoration: first
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: c.lineSoft)),
            ),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: (8 - controlOverhang).clamp(0, 8).toDouble()),
      child: control != null
          ? _withControl(glyph, labelText)
          : Row(
              children: [
                glyph,
                const SizedBox(width: 12),
                Expanded(
                  child: caption == null
                      ? labelText
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: labelText),
                            const SizedBox(height: 1),
                            Text(caption!, style: TzType.caption.copyWith(color: c.ink3)),
                          ],
                        ),
                ),
                const SizedBox(width: 12),
                if (value != null) ...[
                  // A long value (a reciter's full name) gives way to the label.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: valueStyle ?? TzType.label.copyWith(color: c.ink2, fontWeight: FontWeight.w400),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TzIcon('chev', size: 22, color: c.ink2),
                ] else
                  TzIcon('chev', size: 20, color: c.ink3),
              ],
            ),
    );
    if (onTap == null) return row;
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: semanticLabel,
        excludeSemantics: semanticLabel != null,
        child: InkWell(onTap: onTap, child: row),
      ),
    );
  }
}
