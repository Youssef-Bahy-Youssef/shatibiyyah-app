// lib/ui/shell/settings_screen.dart — «الإعدادات» (features-v3 settings-screen).
//
// The theme (داكنة · ورقية) and the text-mode size (١٠٠٪ · ١٥٠٪ · ٢٠٠٪), both
// kept by the settings store; then the way to the downloads, reminders, backup,
// reader codes and about. When Google Play has a newer version, a banner at the
// top offers it (lib/app/app_update.dart; the only screen that shows it, since
// the home screen went in item 3.4).
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/app_update.dart';
import '../../app/routes.dart';
import '../../data/settings_store.dart';
import '../design/tokens.g.dart';
import '../../utils/arabic.dart';
import '../design/app_theme.dart';
import '../design/pill_tabs.dart';
import '../design/taysir_colors.dart';
import '../reader/reader_controller.dart';
import 'backup_screen.dart';
import 'shell_page.dart';

/// The text-mode sizes offered here; the ± in text mode steps between others too.
const List<double> kSettingsTextScales = [1, 1.5, 2];

class SettingsScreen extends StatelessWidget {
  final ReaderController reader;
  const SettingsScreen({super.key, required this.reader});

  void _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(s, style: TzType.caption.copyWith(color: t.muted)),
        );
    return ListenableBuilder(
      listenable: Listenable.merge([reader, appTheme, ?reader.update]),
      builder: (context, _) {
        final scale = kSettingsTextScales.where((s) => (s - reader.textScale).abs() < 0.01).firstOrNull;
        return ShellPage.topLevel(
          title: 'الإعدادات',
          body: ListView(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 32 + ShellInset.of(context)),
            children: [
              if (reader.update case final update? when update.showBanner) _updateBanner(t, update),
              label('السمة'),
              PillTabs<ReaderTheme>(
                options: const {ReaderTheme.dark: 'داكنة', ReaderTheme.paper: 'ورقية'},
                selected: appTheme.value,
                onSelect: reader.setTheme,
              ),
              label('حجم النص في العرض النصي'),
              PillTabs<double>(
                options: {for (final s in kSettingsTextScales) s: '${ar((s * 100).round())}٪'},
                selected: scale,
                onSelect: reader.setTextScale,
              ),
              label('التلاوة والعرض'),
              _Group(rows: [
                _Row(
                  icon: LucideIcons.download,
                  title: 'التنزيلات',
                  subtitle: 'التلاوات على الجهاز',
                  onTap: () => _push(context, AppRoute.downloads.build(reader)),
                ),
                _Row(
                  icon: LucideIcons.bell,
                  title: 'التنبيهات',
                  subtitle: 'تذكير الباب',
                  onTap: () => _push(context, AppRoute.reminders.build(reader)),
                ),
              ]),
              label('البيانات'),
              _Group(rows: [
                _Row(
                  icon: LucideIcons.archive,
                  title: 'نسخ احتياطي واستعادة',
                  subtitle: 'ملف على الجهاز',
                  onTap: () => _push(context, BackupScreen(reader: reader)),
                ),
              ]),
              const SizedBox(height: 18),
              _Group(rows: [
                _Row(
                  icon: LucideIcons.scrollText,
                  title: 'رموز القراء',
                  onTap: () => _push(context, AppRoute.rumuz.build(reader)),
                ),
                _Row(
                  icon: LucideIcons.info,
                  title: 'حول التطبيق',
                  onTap: () => _push(context, AppRoute.about.build(reader)),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }
}

Widget _updateBanner(TaysirColors t, AppUpdate update) => Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: t.panel2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.goldDeep),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.download, size: 18, color: t.goldText),
          const SizedBox(width: 10),
          Expanded(child: Text('إصدار جديد من التطبيق متاح', style: TzType.label.copyWith(color: t.text))),
          TextButton(
            onPressed: update.update,
            child: Text('تحديث', style: TzType.label.copyWith(color: t.goldText)),
          ),
          IconButton(
            tooltip: 'إخفاء',
            onPressed: update.dismiss,
            icon: Icon(LucideIcons.x, size: 18, color: t.muted),
          ),
        ],
      ),
    );

class _Group extends StatelessWidget {
  final List<Widget> rows;
  const _Group({required this.rows});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return Material(
      color: t.panel,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: t.line)),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 62, color: t.line),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _Row({required this.icon, required this.title, this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: t.panel2, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: t.goldText),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: TzType.body.copyWith(color: t.text)),
                    if (subtitle != null) Text(subtitle!, style: TzType.caption.copyWith(color: t.muted)),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronLeft, size: 18, color: t.muted),
            ],
          ),
        ),
      ),
    );
  }
}
