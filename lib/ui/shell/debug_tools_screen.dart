// lib/ui/shell/debug_tools_screen.dart — «أدوات التجربة»: only in debug and
// profile builds (run from Android Studio), never in release; reached from «حول». What cannot be
// waited for or needs Google Play, tried at once: the reminder now, the reminder
// through the real scheduler in two minutes, the update banner, the review call.
// Drawn with «الإعدادات»'s rows: each tool is a row with its one button.
import 'package:flutter/material.dart';

import '../design/components/settings_row.dart';
import '../design/components/tz_button.dart';
import '../design/tokens.g.dart';
import '../design/tz_theme.dart';
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

  /// A tool: what it tries, and the button that tries it (dimmed when its service is absent).
  Widget _tool(String icon, String label, String verb, VoidCallback? onPressed) => SettingsRow.control(
        icon: icon,
        label: label,
        controlOverhang: 2,
        control: TzButton.tonal(label: verb, dense: true, onPressed: onPressed),
      );

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final reminders = r.reminders;
    return ShellPage(
      title: 'أدوات التجربة',
      body: ListView(
        padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              'لنسخ التطوير فقط، ولا تظهر في نسخة المتجر. تجرّب في الحال ما يُنتظر أيامًا أو يحتاج إلى Google Play.',
              style: TzType.body.copyWith(color: c.ink2),
            ),
          ),
          SettingsGroup(title: 'تذكير الباب', rows: [
            _tool(
              'share',
              'أرسله الآن',
              'أرسل',
              reminders == null ? null : () => _run('أُرسل «تذكير الباب»', () => reminders.sendNow()),
            ),
            _tool(
              'gap',
              'جدوِله بعد دقيقتين',
              'جدوِل',
              reminders == null
                  ? null
                  : () => _run(
                      'جُدول «تذكير الباب» بعد دقيقتين (قد يتأخر قليلًا)',
                      () => reminders.scheduleSoon(const Duration(minutes: 2)),
                    ),
            ),
          ]),
          SettingsGroup(title: 'Google Play', rows: [
            _tool(
              'down',
              'شريط التحديث في «الإعدادات»',
              'أظهر',
              r.update == null ? null : () => _run('يظهر الشريط في «الإعدادات»', () async => r.update!.debugShowBanner()),
            ),
            _tool(
              'pen',
              'طلب التقييم',
              'اطلب',
              r.rating == null
                  ? null
                  : () => _run('طُلب التقييم (لا يظهر إلا لنسخة مثبتة من المتجر)', () async => r.rating!.port.request()),
            ),
          ]),
          if (_last case final last?)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Semantics(
                liveRegion: true,
                child: Text(last, style: TzType.label.copyWith(color: c.lapis)),
              ),
            ),
        ],
      ),
    );
  }
}
