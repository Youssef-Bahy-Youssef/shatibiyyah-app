// lib/ui/shell/backup_screen.dart — «نسخ احتياطي» (features-v3 backup-and-sync).
//
// «إنشاء نسخة الآن» writes the backup (lib/data/backup.dart) to a file where the
// user chooses; «استعادة من ملف» merges one back — it never wipes. The last backup's
// time and size are shown. Restored reader settings (theme, text) apply at once.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/backup.dart';
import '../../data/settings_store.dart';
import '../../services/device_storage.dart' as device;
import '../../theme.dart' show kufi;
import '../../utils/arabic.dart';
import '../design/taysir_colors.dart';
import '../reader/reader_controller.dart';
import 'shell_page.dart';

const String kBackupLastAtPref = 'v2.backup.last_at';
const String kBackupLastBytesPref = 'v2.backup.last_bytes';

typedef SaveDocument = Future<String?> Function(String name, String text);
typedef OpenDocument = Future<String?> Function();

class BackupScreen extends StatefulWidget {
  final ReaderController reader;
  final SaveDocument save;
  final OpenDocument open;
  const BackupScreen({
    super.key,
    required this.reader,
    this.save = device.saveDocument,
    this.open = device.openDocument,
  });

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String? _message;
  bool _failed = false;

  ReaderController get _reader => widget.reader;

  static String _deviceError(device.DocumentError e) => switch (e.code) {
        'unsupported' => 'غير متاح على هذا الجهاز بعد',
        'too_large' => 'الملف أكبر من أن يكون نسخة احتياطية',
        _ => 'تعذّر الوصول إلى الملف',
      };

  Future<void> _run(Future<String?> Function() task) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    String? message;
    var failed = false;
    try {
      message = await task();
    } on BackupError catch (e) {
      (message, failed) = (e.message, true);
    } on device.DocumentError catch (e) {
      (message, failed) = (_deviceError(e), true);
    }
    if (failed) _reader.rating?.noteError();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
      _failed = failed;
    });
  }

  Future<String?> _backup() async {
    final user = _reader.user;
    if (user == null) return null;
    final prefs = _reader.viewer.prefs;
    final now = DateTime.now();
    final text = encodeBackup(await exportBackup(user, prefs, now: now));
    final d = '${now.year}-${'${now.month}'.padLeft(2, '0')}-${'${now.day}'.padLeft(2, '0')}';
    final saved = await widget.save('shatibiyyah-backup-$d.json', text);
    if (saved == null) return null; // cancelled
    prefs.setString(kBackupLastAtPref, '${now.millisecondsSinceEpoch}');
    prefs.setString(kBackupLastBytesPref, '${utf8.encode(text).length}');
    return 'حُفظت النسخة';
  }

  Future<String?> _restore() async {
    final user = _reader.user;
    if (user == null) return null;
    final text = await widget.open();
    if (text == null) return null; // cancelled
    final prefs = _reader.viewer.prefs;
    final report = await mergeBackup(user, prefs, decodeBackup(text));
    await _reader.personal?.load();
    final settings = SettingsStore(prefs);
    if (report.settings.contains('v2.theme')) _reader.setTheme(settings.theme);
    if (report.settings.contains('v2.text.scale')) _reader.setTextScale(settings.textScale);
    if (report.settings.contains('v2.reader.view')) _reader.setTextMode(settings.textMode);
    return report.total == 0 ? 'لا جديد في هذه النسخة' : 'تمت الاستعادة ودُمجت مع ما على الجهاز';
  }

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final prefs = _reader.viewer.prefs;
    final lastAt = int.tryParse(prefs.getString(kBackupLastAtPref) ?? '');
    final lastBytes = int.tryParse(prefs.getString(kBackupLastBytesPref) ?? '');
    final last = lastAt == null ? null : DateTime.fromMillisecondsSinceEpoch(lastAt);
    return ShellPage(
      title: 'نسخ احتياطي',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: t.panel2, borderRadius: BorderRadius.circular(12)),
                  child: Icon(LucideIcons.archive, size: 20, color: t.goldText),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(last == null ? 'لم تُنشأ نسخة بعد' : 'آخر نسخة: ${dayLabel(last)} ${clockTime(last)}',
                          style: kufi(size: 15, weight: 500, color: t.text)),
                      Text(
                        lastBytes == null
                            ? 'ملف على الجهاز'
                            : 'ملف على الجهاز، ${ar((lastBytes / 1024).ceil())} ك.ب',
                        style: kufi(size: 12.5, weight: 400, color: t.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'يشمل: المراجع والملاحظات والسجل والأبيات المسموعة وإعدادات القراءة. '
            'لا يشمل الصوت ولا الشروح.',
            style: kufi(size: 13, weight: 400, color: t.muted, height: 1.7),
          ),
          const SizedBox(height: 6),
          Text('الاستعادة تدمج مع ما على الجهاز ولا تمحو شيئًا.',
              style: kufi(size: 13, weight: 400, color: t.muted, height: 1.7)),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : () => _run(_backup),
            style: FilledButton.styleFrom(
              backgroundColor: t.gold,
              foregroundColor: t.onGold,
              minimumSize: const Size.fromHeight(52),
              shape: const StadiumBorder(),
            ),
            child: Text('إنشاء نسخة الآن', style: kufi(size: 15, weight: 600, color: t.onGold)),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _run(_restore),
            icon: Icon(LucideIcons.upload, size: 18, color: t.goldText),
            label: Text('استعادة من ملف', style: kufi(size: 15, weight: 500, color: t.text)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              side: BorderSide(color: t.line),
              shape: const StadiumBorder(),
            ),
          ),
          if (_busy)
            const Padding(padding: EdgeInsets.only(top: 18), child: Center(child: CircularProgressIndicator()))
          else if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Text(_message!,
                  textAlign: TextAlign.center,
                  style: kufi(size: 14, weight: 500, color: _failed ? t.warn : t.goldText)),
            ),
        ],
      ),
    );
  }
}
