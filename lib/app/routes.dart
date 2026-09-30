// lib/app/routes.dart — where the drawer leads (the prototype's `drawerGo`).
//
// One entry per destination, in drawer order. The reader is the root; each
// destination is pushed over it. A destination whose service did not start (the
// downloads or the reminders, in tests) opens a «قريبًا» page.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../ui/reader/reader_controller.dart';
import '../ui/shell/about_screen.dart';
import '../ui/shell/downloads_screen.dart';
import '../ui/shell/home_screen.dart';
import '../ui/shell/index_screen.dart';
import '../ui/shell/reminders_screen.dart';
import '../ui/shell/rumuz_screen.dart';
import '../ui/shell/settings_screen.dart';
import '../ui/shell/shell_page.dart';

enum AppRoute {
  home('الرئيسية والمكتبة', LucideIcons.house),
  contents('الفهرس', LucideIcons.listTree),
  downloads('التنزيلات', LucideIcons.download),
  reminders('التنبيهات', LucideIcons.bell),
  settings('الإعدادات', LucideIcons.settings),
  rumuz('رموز القراء', LucideIcons.scrollText),
  about('حول', LucideIcons.info);

  final String label;
  final IconData icon;
  const AppRoute(this.label, this.icon);

  Widget build(ReaderController reader) => switch (this) {
    home => HomeScreen(reader: reader),
    contents => IndexScreen(reader: reader),
    rumuz => RumuzScreen(reader: reader),
    downloads when reader.library != null => DownloadsScreen(library: reader.library!),
    reminders when reader.reminders != null => RemindersScreen(reminders: reader.reminders!),
    settings => SettingsScreen(reader: reader),
    about => AboutScreen(reader: reader),
    _ => ComingSoonScreen(title: label, icon: icon),
  };
}
