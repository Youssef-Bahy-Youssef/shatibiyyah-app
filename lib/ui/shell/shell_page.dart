// lib/ui/shell/shell_page.dart — the frame of a screen.
//
// A top-level screen (a dock tab: الفهرس، المحفوظ، الإعدادات) opens with the
// prototype's unwan (item 3.4, v2.css .unwan, .gilt-rule): the title in Naskh
// 30/700 with an optional control or caption beside it, over the gilt rule with
// its lozenge. Its lists end above the dock ([ShellInset]). A pushed screen
// (downloads, reminders, backup, …) keeps a 56 px header with «رجوع».
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/components/ornament.dart';
import '../design/tokens.g.dart';
import '../design/taysir_colors.dart';
import '../design/tz_icon.dart';
import '../design/tz_theme.dart';

class ShellPage extends StatelessWidget {
  final String title;
  final Widget body;

  /// A caption beside a top-level title.
  final Widget? trailing;

  /// A button beside a top-level title (a [ShellIconButton]: 44 px drawn, in a 48 px target).
  final Widget? action;
  final bool topLevel;

  const ShellPage({super.key, required this.title, required this.body})
      : trailing = null,
        action = null,
        topLevel = false;

  /// A dock tab's screen: the unwan header, no «رجوع».
  const ShellPage.topLevel({super.key, required this.title, this.trailing, this.action, required this.body})
      : topLevel = true;

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
              if (topLevel) _unwan(context) else _backHeader(context, t),
              // On a tablet the content keeps a reading width instead of spanning the screen.
              Expanded(child: ReadingWidth(child: body)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _unwan(BuildContext context) {
    final c = TzTheme.of(context).colors;
    // A button's 48 px target reaches 2 px past its 44 px drawing on each side:
    // that much comes off the padding around it, so it is drawn where measured.
    final over = action == null ? 0.0 : 2.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(20, 6 - over, 20 - over, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TzType.display.copyWith(color: c.ink)),
              ),
              // A caption keeps its own width (up to half the row); the title has the rest.
              if (trailing case final w?) ...[
                const SizedBox(width: 8),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 170), child: w),
              ],
              if (action case final w?) ...[SizedBox(width: 8 - over), w],
            ],
          ),
        ),
        Padding(padding: EdgeInsets.fromLTRB(20, 6 - over, 20, 0), child: const GiltRule()),
      ],
    );
  }

  Widget _backHeader(BuildContext context, TaysirColors t) => SizedBox(
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
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TzType.display.copyWith(color: t.text)),
            ),
          ],
        ),
      );
}

/// A 44 px glyph button in a 48 px target beside a title (v2.css .ib).
class ShellIconButton extends StatelessWidget {
  final String icon, label;
  final VoidCallback onPressed;
  const ShellIconButton({super.key, required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: label,
        onPressed: onPressed,
        icon: TzIcon(icon, size: 22, color: TzTheme.of(context).colors.ink2),
        constraints: const BoxConstraints.tightFor(width: TzSize.touchTarget, height: TzSize.touchTarget),
        padding: EdgeInsets.zero,
      );
}

/// What the shell's dock covers at the bottom of a top-level screen: its lists
/// end this far above the edge and scroll under the dock (v2.css .list
/// padding-bottom). Zero for a screen shown on its own.
class ShellInset extends InheritedWidget {
  final double bottom;
  const ShellInset({super.key, required this.bottom, required super.child});

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellInset>()?.bottom ?? 0;

  @override
  bool updateShouldNotify(ShellInset old) => old.bottom != bottom;
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
