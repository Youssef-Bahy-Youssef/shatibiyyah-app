// lib/app/routes.dart — the pushed destinations, reached from «الإعدادات»
// (item 3.4: the drawer is gone; the dock's tabs are the top level).
//
// Each destination is pushed over the shell. A destination whose service did not start (the
// downloads or the reminders, in tests) opens a «قريبًا» page.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../ui/reader/reader_controller.dart';
import '../ui/shell/about_screen.dart';
import '../ui/shell/downloads_screen.dart';
import '../ui/shell/reminders_screen.dart';
import '../ui/shell/rumuz_screen.dart';
import '../ui/shell/shell_page.dart';

enum AppRoute {
  downloads('التنزيلات', LucideIcons.download),
  reminders('التنبيهات', LucideIcons.bell),
  rumuz('رموز القراء', LucideIcons.scrollText),
  about('حول', LucideIcons.info);

  final String label;
  final IconData icon;
  const AppRoute(this.label, this.icon);

  Widget build(ReaderController reader) => switch (this) {
    rumuz => RumuzScreen(reader: reader),
    downloads when reader.library != null => DownloadsScreen(library: reader.library!),
    reminders when reader.reminders != null => RemindersScreen(reminders: reader.reminders!),
    about => AboutScreen(reader: reader),
    _ => ComingSoonScreen(title: label, icon: icon),
  };
}
