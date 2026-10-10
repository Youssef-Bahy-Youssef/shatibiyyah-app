// lib/ui/shell/reminders_screen.dart — «التنبيهات» (features-v3 reminders).
//
// «تذكير الباب» as a switch, and a preview of the real notification. Turning it
// on asks for the notification permission; if it is refused the switch stays off
// and says where to allow it.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/reminders.dart';
import '../../theme.dart' show kufi, naskh;
import '../design/taysir_colors.dart';
import 'shell_page.dart';

class RemindersScreen extends StatefulWidget {
  final Reminders reminders;
  const RemindersScreen({super.key, required this.reminders});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  bool _refused = false;

  Reminders get _r => widget.reminders;

  Future<void> _toggle(bool on) async {
    final ok = await _r.setChapter(on);
    if (mounted) setState(() => _refused = on && !ok);
  }

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return ListenableBuilder(
      listenable: _r,
      builder: (context, _) {
        final sample = _r.sample();
        return ShellPage(
          title: 'التنبيهات',
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Material(
                color: t.panel,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: BorderSide(color: t.line),
                ),
                child: Column(
                  children: [
                    _SwitchRow(
                      icon: LucideIcons.bellRing,
                      title: 'تذكير الباب',
                      subtitle: 'بعد انقطاع ثلاثة أيام',
                      on: _r.chapterOn,
                      onChanged: _toggle,
                    ),
                  ],
                ),
              ),
              if (_refused)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'لم يُسمح بالإشعارات. اسمح بها للتطبيق من إعدادات الجهاز ثم فعّل التنبيه.',
                    style: kufi(size: 13, weight: 500, color: t.warn, height: 1.7),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 22, bottom: 8),
                child: Text('معاينة', style: kufi(size: 12.5, weight: 400, color: t.muted)),
              ),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.panel2,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: t.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.bellRing, size: 15, color: t.goldText),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text('تيسير الشاطبية', style: kufi(size: 11.5, weight: 400, color: t.muted)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(sample.title, style: kufi(size: 14.5, weight: 600, color: t.text)),
                    const SizedBox(height: 2),
                    Text(sample.body, style: naskh(size: 16, color: t.text, height: 1.7)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool on;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.on,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!on),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 18, color: t.goldText),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: kufi(size: 15, weight: 500, color: t.text)),
                      Text(subtitle, style: kufi(size: 12, weight: 400, color: t.muted)),
                    ],
                  ),
                ),
                Switch(value: on, onChanged: onChanged, activeThumbColor: t.onGold, activeTrackColor: t.gold),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
