// lib/ui/shell/settings_screen.dart — «الإعدادات» (items 3.6 and 3.10; handoff
// settings-main): four groups of rows under the unwan header.
//   العرض          المظهر (ورقي · ليلي · تلقائي) · العرض عند الفتح · حجم نص المتن
//   الوضع الليلي    لون الحبر الليلي, with the night page in the chosen ink
//   الاستماع        التلاوة · التنزيلات · عناوين الأبواب
//   التطبيق         رموز القراء · نسخ احتياطي واستعادة · حول تيسير الشاطبية
// A row the design does not draw stands last in «التطبيق», so every drawn row
// keeps its measured place: «التنبيهات» (the reminder is a kept feature and this
// is its only way in).
// When Google Play has a newer version, a banner above the groups offers it
// (lib/app/app_update.dart; the only screen that shows it).
import 'package:flutter/material.dart';

import '../../app/app_update.dart';
import '../../app/routes.dart';
import '../../data/settings_store.dart';
import '../../utils/arabic.dart';
import '../design/app_theme.dart';
import '../design/components/min_segmented.dart';
import '../design/components/night_crop.dart';
import '../design/components/settings_row.dart';
import '../design/components/tz_switch.dart';
import '../design/tokens.g.dart';
import '../design/tz_icon.dart';
import '../design/tz_theme.dart';
import '../reader/display_sheet.dart';
import '../reader/reader_controller.dart';
import 'backup_screen.dart';
import 'downloads_screen.dart';
import 'night_ink_sheet.dart';
import 'shell_page.dart';

class SettingsScreen extends StatelessWidget {
  final ReaderController reader;
  const SettingsScreen({super.key, required this.reader});

  void _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final library = reader.library;
    return ListenableBuilder(
      listenable: Listenable.merge([reader, appThemeChoice, appNightInk, ?library, ?reader.update]),
      builder: (context, _) {
        final c = TzTheme.of(context).colors;
        final ink = reader.nightInk;
        return ShellPage.topLevel(
          title: 'الإعدادات',
          body: ListView(
            padding: EdgeInsets.only(bottom: 32 + ShellInset.of(context)),
            children: [
              if (reader.update case final update? when update.showBanner) _UpdateBanner(update: update),
              SettingsGroup(title: 'العرض', rows: [
                SettingsRow.control(
                  icon: 'theme',
                  label: 'المظهر',
                  controlOverhang: 2,
                  control: MinSegmented<ThemeChoice>(
                    semanticLabel: 'المظهر',
                    options: const {ThemeChoice.paper: 'ورقي', ThemeChoice.night: 'ليلي', ThemeChoice.auto: 'تلقائي'},
                    selected: reader.themeChoice,
                    onSelect: reader.setThemeChoice,
                  ),
                ),
                SettingsRow.control(
                  icon: 'book',
                  label: 'العرض عند الفتح',
                  controlOverhang: 2,
                  control: MinSegmented<bool>(
                    semanticLabel: 'العرض عند الفتح',
                    options: const {false: 'الصفحة', true: 'النص'},
                    selected: reader.textMode,
                    onSelect: reader.setTextMode,
                  ),
                ),
                SettingsRow(
                  icon: 'textsize',
                  label: 'حجم نص المتن',
                  value: '${ar((reader.textScale * 100).round())}٪',
                  onTap: () => showDisplaySheet(context, reader),
                ),
              ]),
              SettingsGroup(title: 'الوضع الليلي', rows: [
                SettingsRow(
                  leading: NightCrop(ink: ink, width: 64),
                  label: TzNightPage.pickerTitle,
                  caption: 'أسماء القراء ورموزهم وإطار الصفحة',
                  value: ink.ar,
                  valueStyle: TzType.chapter
                      .copyWith(color: c.ink, fontWeight: FontWeight.w700, height: 20 / TzType.chapter.fontSize!),
                  semanticLabel: '${TzNightPage.pickerTitle}: ${ink.ar}',
                  onTap: () => showNightInkSheet(context, reader),
                ),
              ]),
              SettingsGroup(title: 'الاستماع', rows: [
                SettingsRow(
                  icon: 'user',
                  label: 'التلاوة',
                  value: reader.recording.reciterName,
                  onTap: () => library == null
                      ? _push(context, AppRoute.downloads.build(reader))
                      : showReciterSheet(context, library),
                ),
                SettingsRow(
                  icon: 'down',
                  label: 'التنزيلات',
                  value: library == null ? null : megabytes(library.bytesOnDevice),
                  onTap: () => _push(context, AppRoute.downloads.build(reader)),
                ),
                SettingsRow.control(
                  icon: 'mic',
                  label: 'عناوين الأبواب',
                  controlOverhang: 11,
                  control: TzSwitch(
                    semanticLabel: 'تلاوة عناوين الأبواب',
                    value: reader.settings.playTitles,
                    onWord: 'تُتلى',
                    offWord: 'لا تُتلى',
                    onChanged: reader.setPlayTitles,
                  ),
                ),
              ]),
              SettingsGroup(title: 'التطبيق', rows: [
                SettingsRow(icon: 'list', label: 'رموز القراء', onTap: () => _push(context, AppRoute.rumuz.build(reader))),
                SettingsRow(icon: 'copy', label: 'نسخ احتياطي واستعادة', onTap: () => _push(context, BackupScreen(reader: reader))),
                SettingsRow(icon: 'book', label: 'حول تيسير الشاطبية', onTap: () => _push(context, AppRoute.about.build(reader))),
                SettingsRow(icon: 'gap', label: 'التنبيهات', onTap: () => _push(context, AppRoute.reminders.build(reader))),
              ]),
            ],
          ),
        );
      },
    );
  }
}

/// «إصدار جديد من التطبيق متاح»: update, or put it away.
class _UpdateBanner extends StatelessWidget {
  final AppUpdate update;
  const _UpdateBanner({required this.update});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: c.tonal,
        borderRadius: BorderRadius.circular(TzRadius.card),
        border: Border.all(color: c.gilt),
      ),
      child: Row(
        children: [
          TzIcon('down', size: 20, color: c.lapis),
          const SizedBox(width: 10),
          Expanded(child: Text('إصدار جديد من التطبيق متاح', style: TzType.label.copyWith(color: c.ink))),
          TextButton(
            onPressed: update.update,
            child: Text('تحديث', style: TzType.label.copyWith(color: c.lapis)),
          ),
          IconButton(
            tooltip: 'إخفاء',
            onPressed: update.dismiss,
            icon: TzIcon('x', size: 20, color: c.ink3),
          ),
        ],
      ),
    );
  }
}
