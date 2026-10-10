// lib/ui/reader/tools_sheet.dart — «العرض» and «المزيد» (features-v3: console-sheet).
//
// One bottom sheet, two tabs:
//   العرض  — theme (dark / paper; the page follows it), text mode, night brightness 40–100 %
//   المزيد — share the page, downloads, about
// The player has its own sheet (player_sheet.dart, item 3.7); text mode's «العرض»
// sheet replaces the first tab in item 3.8.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/settings_store.dart';
import '../design/tokens.g.dart';
import '../../utils/arabic.dart';
import '../design/pill_tabs.dart';
import '../design/taysir_colors.dart';
import '../share/share_sheet.dart';
import '../shell/about_screen.dart';
import '../shell/downloads_screen.dart';
import '../widgets/page_viewer.dart' show kMinBrightness, kMaxBrightness;
import 'reader_controller.dart';

enum ToolsTab { view, more }

Future<void> showToolsSheet(BuildContext context, ReaderController reader, {ToolsTab tab = ToolsTab.view}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ToolsSheet(reader: reader, initialTab: tab),
    );

class ToolsSheet extends StatefulWidget {
  final ReaderController reader;
  final ToolsTab initialTab;
  const ToolsSheet({super.key, required this.reader, this.initialTab = ToolsTab.view});

  @override
  State<ToolsSheet> createState() => _ToolsSheetState();
}

class _ToolsSheetState extends State<ToolsSheet> {
  late ToolsTab _tab = widget.initialTab;
  ReaderController get r => widget.reader;

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AnimatedBuilder(
        animation: r,
        builder: (context, _) => Container(
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: t.line)),
          ),
          padding: EdgeInsets.fromLTRB(16, 10, 16, 20 + MediaQuery.of(context).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                    width: 36, height: 4, decoration: BoxDecoration(color: t.line, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 12),
              _Pills<ToolsTab>(
                values: ToolsTab.values,
                selected: _tab,
                label: (v) => switch (v) { ToolsTab.view => 'العرض', ToolsTab.more => 'المزيد' },
                onSelect: (v) => setState(() => _tab = v),
              ),
              const SizedBox(height: 14),
              switch (_tab) {
                ToolsTab.view => _viewTab(t),
                ToolsTab.more => _moreTab(t),
              },
            ],
          ),
        ),
      ),
    );
  }

  // ── العرض ──
  Widget _viewTab(TaysirColors t) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('السمة', style: TzType.caption.copyWith(color: t.muted)),
          const SizedBox(height: 6),
          _Pills<ReaderTheme>(
            values: ReaderTheme.values,
            selected: r.theme,
            label: (v) => v == ReaderTheme.dark ? 'داكنة' : 'ورقية',
            onSelect: r.setTheme,
          ),
          const SizedBox(height: 10),
          _SwitchRow(icon: LucideIcons.alignJustify, label: 'العرض النصي', value: r.textMode, onChanged: r.setTextMode),
          Row(
            children: [
              Icon(LucideIcons.sun, size: 20, color: t.goldText),
              const SizedBox(width: 12),
              Expanded(child: Text('سطوع الصفحة ليلًا', style: TzType.label.copyWith(color: t.text))),
              _Round(
                icon: LucideIcons.minus,
                label: 'أخفت',
                onTap: r.brightness > kMinBrightness ? () => r.setBrightness(r.brightness - 10) : null,
              ),
              SizedBox(
                width: 52,
                child: Text('${ar(r.brightness)}٪',
                    textAlign: TextAlign.center, style: TzType.label.copyWith(color: t.text)),
              ),
              _Round(
                icon: LucideIcons.plus,
                label: 'أسطع',
                onTap: r.brightness < kMaxBrightness ? () => r.setBrightness(r.brightness + 10) : null,
              ),
            ],
          ),
        ],
      );

  // ── المزيد ──
  Widget _moreTab(TaysirColors t) {
    Widget row(IconData icon, String label, String sub, VoidCallback? onTap) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: onTap == null ? t.muted : t.goldText),
          title: Text(label, style: TzType.body.copyWith(color: onTap == null ? t.muted : t.text)),
          subtitle: Text(sub, style: TzType.caption.copyWith(color: t.muted)),
          enabled: onTap != null,
          onTap: onTap,
        );
    // A Material of its own: the sheet's coloured box would hide the rows' ink.
    return Material(
      type: MaterialType.transparency,
      child: Column(children: [
        row(LucideIcons.share2, 'مشاركة الصفحة', 'صورة الصفحة ${ar(r.page)} من المخطوط', () {
          Navigator.of(context).pop();
          sharePage(r.content, r.page);
        }),
        row(
          LucideIcons.download,
          'التنزيلات',
          'التلاوات: ${r.library == null ? '—' : megabytes(r.library!.bytesOnDevice)} على الجهاز',
          r.library == null
              ? null
              : () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  navigator.push(MaterialPageRoute<void>(builder: (_) => DownloadsScreen(library: r.library!)));
                },
        ),
        row(LucideIcons.info, 'حول', 'الإصدار والتعريف', () {
          final navigator = Navigator.of(context);
          navigator.pop();
          navigator.push(MaterialPageRoute<void>(builder: (_) => AboutScreen(reader: r)));
        }),
      ]),
    );
  }
}

class _Pills<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelect;
  const _Pills({required this.values, required this.selected, required this.label, required this.onSelect});

  @override
  Widget build(BuildContext context) => PillTabs<T>(
        options: {for (final v in values) v: label(v)},
        selected: selected,
        onSelect: onSelect,
        track: TaysirColors.of(context).bg,
      );
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.icon, required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    // One item for a screen reader (the label with the switch), tappable as a whole.
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        child: SizedBox(
          height: 52,
          child: Row(children: [
            Icon(icon, size: 20, color: t.goldText),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TzType.label.copyWith(color: t.text))),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: t.onGold,
              activeTrackColor: t.gold,
              inactiveThumbColor: t.dim,
              inactiveTrackColor: t.line,
            ),
          ]),
        ),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _Round({required this.icon, required this.label, this.onTap});

  static const double size = 44;

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: t.gold, width: 1.5)),
            child: Icon(icon, size: size * 0.4, color: t.goldText),
          ),
        ),
      ),
    );
  }
}
