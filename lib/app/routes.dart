// lib/app/routes.dart — where the drawer leads (the prototype's `drawerGo`).
//
// One entry per destination, in drawer order. The reader is the root; each
// destination is pushed over it. Destinations of later phases open a «قريبًا»
// page until they are built: home (P6), downloads (P5), reminders and settings
// (P7), «رموز القراء» (P6).
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../ui/reader/reader_controller.dart';
import '../ui/shell/about_screen.dart';
import '../ui/shell/index_screen.dart';
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
    contents => IndexScreen(reader: reader),
    about => const AboutScreen(),
    _ => ComingSoonScreen(title: label, icon: icon),
  };
}
