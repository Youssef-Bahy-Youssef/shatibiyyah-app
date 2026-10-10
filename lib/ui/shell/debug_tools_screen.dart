// lib/ui/shell/debug_tools_screen.dart — «أدوات التجربة»: only in debug and
// profile builds (run from Android Studio), never in release; reached from «حول». What cannot be
// waited for or needs Google Play, tried at once: the reminder now, the reminder
// through the real scheduler in two minutes, the update banner, the review call.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/tokens.g.dart';
import '../design/taysir_colors.dart';
import '../reader/reader_controller.dart';
import 'shell_page.dart';

class DebugToolsScreen extends StatefulWidget {
  final ReaderController reader;
  const DebugToolsScreen({super.key, required this.reader});

  @override
  State<DebugToolsScreen> createState() => _DebugToolsScreenState();
}

class _DebugToolsScreenState extends State<DebugToolsScreen> {
  String? _last;

  ReaderController get r => widget.reader;

  Future<void> _run(String done, Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => _last = done);
    } catch (e) {
      if (mounted) setState(() => _last = 'خطأ: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final reminders = r.reminders;
    Widget action(IconData icon, String label, VoidCallback? onTap) => ListTile(
      leading: Icon(icon, color: onTap == null ? t.muted : t.goldText),
      title: Text(label, style: TzType.label.copyWith(color: onTap == null ? t.muted : t.text)),
      onTap: onTap,
      enabled: onTap != null,
    );
    return ShellPage(
      title: 'أدوات التجربة',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Text(
              'نسخ التطوير فقط؛ لا تظهر في نسخة المتجر.',
              style: TzType.caption.copyWith(color: t.muted),
            ),
          ),
          action(
            LucideIcons.bellRing,
            'أرسل «تذكير الباب» الآن',
            reminders == null ? null : () => _run('أُرسل «تذكير الباب»', () => reminders.sendNow()),
          ),
          action(
            LucideIcons.alarmClock,
            'جدولة «تذكير الباب» بعد دقيقتين',
            reminders == null
                ? null
                : () => _run(
                    'جُدولت بعد دقيقتين (قد تتأخر قليلًا)',
                    () => reminders.scheduleSoon(const Duration(minutes: 2)),
                  ),
          ),
          action(
            LucideIcons.download,
            'أظهر شريط التحديث في الرئيسية',
            r.update == null ? null : () => _run('يظهر الشريط في «الرئيسية»', () async => r.update!.debugShowBanner()),
          ),
          action(
            LucideIcons.star,
            'اطلب التقييم الآن (نسخة من Google Play فقط)',
            r.rating == null
                ? null
                : () => _run('طُلب التقييم (لا يظهر إلا لنسخة مثبتة من المتجر)', () async => r.rating!.port.request()),
          ),
          if (_last != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_last!, style: TzType.label.copyWith(color: t.goldText)),
            ),
        ],
      ),
    );
  }
}
