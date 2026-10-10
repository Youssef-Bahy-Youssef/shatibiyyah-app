// lib/ui/shell/shell_page.dart — the frame of every screen reached from the drawer:
// a 56 px header with «رجوع» and the title (the prototype's secondary screens),
// then the content on the theme background.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/tokens.g.dart';
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
                        style: TzType.display.copyWith(color: t.text),
                      ),
                    ),
                  ],
                ),
              ),
              // On a tablet the content keeps a reading width instead of spanning the screen.
              Expanded(child: ReadingWidth(child: body)),
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
                style: TzType.head.copyWith(color: t.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The widest a screen's content grows (tablets, plan P8): centred beyond it.
const double kReadingWidth = 720;

class ReadingWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const ReadingWidth({super.key, required this.child, this.maxWidth = kReadingWidth});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}

/// A list's padding for a [width]-wide area: [side] at each edge, more when that
/// keeps the content within [kReadingWidth] (the list still scrolls edge to edge).
EdgeInsets readingPadding(double width, {double side = 16, double top = 0, double bottom = 0}) {
  final extra = width > kReadingWidth + 2 * side ? (width - kReadingWidth) / 2 - side : 0.0;
  return EdgeInsets.fromLTRB(side + extra, top, side + extra, bottom);
}
