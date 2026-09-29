// lib/ui/shell/shell_page.dart — the frame of every screen reached from the drawer:
// a 56 px header with «رجوع» and the title (the prototype's secondary screens),
// then the content on the theme background.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme.dart' show kufi;
import '../design/taysir_colors.dart';

class ShellPage extends StatelessWidget {
  final String title;
  final Widget body;
  const ShellPage({super.key, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'رجوع',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(LucideIcons.chevronRight, size: 21, color: t.text),
                      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kufi(size: 20, weight: 600, color: t.text),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

/// A destination that lands in a later update: its name and a short note.
class ComingSoonScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  const ComingSoonScreen({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return ShellPage(
      title: title,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: t.goldText),
              const SizedBox(height: 16),
              Text(
                'قريبًا في تحديث قادم',
                textAlign: TextAlign.center,
                style: kufi(size: 16, weight: 600, color: t.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
