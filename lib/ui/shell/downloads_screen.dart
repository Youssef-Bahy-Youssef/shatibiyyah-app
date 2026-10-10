// lib/ui/shell/downloads_screen.dart — «التنزيلات» and the «القارئ» sheet
// (features-v3 audio-downloads, reciter-catalog).
//
// The recordings are the only downloads (the three books are bundled). Each card
// shows the reciter, duration and size, and its state: not downloaded; downloading
// with % and MB; verifying; waiting for Wi-Fi; on the device; failed with the
// reason and «إعادة المحاولة»; not enough storage (needed vs available). Next to
// numbers the separator is «،» (in Reem Kufi a «·» there reads as «٠»).
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/audio_library.dart';
import '../../data/recording_repository.dart';
import '../../services/device_storage.dart';
import '../../services/download_manager.dart';
import '../../theme.dart' show kufi;
import '../../utils/arabic.dart';
import '../design/taysir_colors.dart';
import 'shell_page.dart';

class DownloadsScreen extends StatelessWidget {
  final AudioLibrary library;
  const DownloadsScreen({super.key, required this.library});

  static Future<void> open(BuildContext context, AudioLibrary library) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => DownloadsScreen(library: library)));

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return ShellPage(
      title: 'التنزيلات',
      body: AnimatedBuilder(
        animation: library,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _storage(t),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: library.wifiOnly,
              onChanged: (on) => library.wifiOnly = on,
              activeThumbColor: t.onGold,
              activeTrackColor: t.gold,
              title: Text('التنزيل عبر Wi-Fi فقط', style: kufi(size: 15, weight: 400, color: t.text)),
              subtitle: Text('لا تُستهلك بيانات الجوال', style: kufi(size: 12, weight: 400, color: t.muted)),
            ),
            const SizedBox(height: 8),
            for (final r in library.recordings) ...[
              _RecordingCard(library: library, recording: r),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            Text('التنزيل يُستأنف إن انقطع، ويُتحقق من كل ملف قبل تفعيله.',
                textAlign: TextAlign.center, style: kufi(size: 12.5, weight: 400, color: t.muted)),
          ],
        ),
      ),
    );
  }

  Widget _storage(TaysirColors t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text('التلاوات على الجهاز: ${megabytes(library.bytesOnDevice)}',
                  style: kufi(size: 13.5, weight: 400, color: t.text)),
            ),
            FutureBuilder<int?>(
              future: deviceFreeBytes(),
              builder: (_, snap) => snap.data == null
                  ? const SizedBox.shrink()
                  : Text('المتاح ${gigabytes(snap.data!)}', style: kufi(size: 12.5, weight: 400, color: t.muted)),
            ),
          ],
        ),
      );
}

class _RecordingCard extends StatelessWidget {
  final AudioLibrary library;
  final Recording recording;
  const _RecordingCard({required this.library, required this.recording});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final r = recording;
    final chosen = library.current.id == r.id;
    final onDevice = library.isOnDevice(r);
    final p = library.progressOf(r);
    final downloading = library.isDownloading(r);

    final String state;
    Color stateColor = t.muted;
    String? action;
    VoidCallback? onAction;
    if (!library.content.isUsable(r)) {
      // A recording whose cues are incomplete is not played (F-41).
      state = 'غير صالحة: ينقصها توقيت بعض الأبيات';
      stateColor = t.warn;
      action = onDevice ? 'حذف' : 'غير متاحة';
      onAction = onDevice ? () => _confirmDelete(context, t) : null;
    } else if (onDevice) {
      state = 'على الجهاز · مُتحقَّق منه';
      stateColor = t.teal;
      action = 'حذف';
      onAction = () => _confirmDelete(context, t);
    } else if (downloading) {
      state = switch (p?.phase) {
        DownloadPhase.verifying => 'يُتحقَّق من الملف…',
        DownloadPhase.waitingForWifi => 'بانتظار شبكة Wi-Fi',
        _ => p == null
            ? 'يبدأ التنزيل…'
            : 'يُنزَّل ${ar((p.fraction * 100).floor())}٪، ${megabytes(p.received)} من ${megabytes(p.total)}',
      };
      stateColor = t.goldText;
      action = 'إيقاف';
      onAction = () => library.cancel(r);
    } else if (p?.phase == DownloadPhase.failed) {
      state = switch (p!.error) {
        DownloadError.noUrls => 'التنزيل غير متاح بعد',
        DownloadError.noSpace => 'المساحة غير كافية: يلزم ${megabytes(r.localBytes + kFreeSpaceMargin)}',
        DownloadError.verification => 'لم يطابق الملف التحقق؛ أعد المحاولة',
        _ => 'تعذّر الاتصال؛ يُستأنف من حيث توقف',
      };
      stateColor = t.warn;
      action = 'إعادة المحاولة';
      onAction = () => library.download(r);
    } else if (p?.phase == DownloadPhase.cancelled && p!.received > 0) {
      state = 'متوقف عند ${ar((p.fraction * 100).floor())}٪';
      action = 'متابعة';
      onAction = () => library.download(r);
    } else {
      state = 'غير منزّل';
      action = 'تنزيل';
      onAction = () => library.download(r);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: chosen ? t.gold.withValues(alpha: 0.10) : t.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: chosen ? t.goldDeep : t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A Wrap: with large text «المختار» moves under the name.
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(r.reciterName, style: kufi(size: 15.5, weight: 600, color: t.text)),
                        if (chosen) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: t.gold, borderRadius: BorderRadius.circular(999)),
                            child: Text('المختار', style: kufi(size: 11, weight: 600, color: t.onGold)),
                          ),
                        ],
                      ],
                    ),
                    Text('${durationHms(r.durationMs)}، ${megabytes(r.localBytes)}',
                        style: kufi(size: 12, weight: 400, color: t.muted)),
                    const SizedBox(height: 2),
                    Text(state, style: kufi(size: 12.5, weight: 500, color: stateColor)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Flexible: with large text the button shrinks (ellipsis) instead of overflowing.
              Flexible(
                child: OutlinedButton(
                  onPressed: onAction,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    side: BorderSide(color: t.line),
                    shape: const StadiumBorder(),
                  ),
                  child: Text(action,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kufi(size: 13.5, weight: 500, color: t.text)),
                ),
              ),
            ],
          ),
          if (downloading && p != null && p.phase == DownloadPhase.downloading) ...[
            const SizedBox(height: 10),
            Directionality(
              textDirection: TextDirection.ltr,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: p.fraction, minHeight: 6, color: t.gold, backgroundColor: t.line),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, TaysirColors t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: t.panel,
          title: Text('حذف التلاوة؟', style: kufi(size: 17, weight: 600, color: t.text)),
          content: Text(
            'تُحذف تلاوة ${recording.reciterName} من الجهاز (${megabytes(recording.localBytes)})، ويمكن تنزيلها متى شئت.',
            style: kufi(size: 14, weight: 400, color: t.dim),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialog).pop(false),
                child: Text('إلغاء', style: kufi(size: 14, weight: 500, color: t.text))),
            TextButton(
                onPressed: () => Navigator.of(dialog).pop(true),
                child: Text('حذف', style: kufi(size: 14, weight: 600, color: t.warn))),
          ],
        ),
      ),
    );
    if (ok == true) await library.delete(recording);
  }
}

/// «القارئ»: choose the recording; the current verse stays. One that is not on the
/// device leads to «التنزيلات».
Future<void> showReciterSheet(BuildContext context, AudioLibrary library) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheet) {
        final t = TaysirColors.of(sheet);
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            decoration: BoxDecoration(
              color: t.panel,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              border: Border(top: BorderSide(color: t.line)),
            ),
            padding: EdgeInsets.fromLTRB(16, 10, 16, 20 + MediaQuery.of(sheet).padding.bottom),
            child: AnimatedBuilder(
              animation: library,
              builder: (_, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(color: t.line, borderRadius: BorderRadius.circular(999)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('القارئ', style: kufi(size: 18, weight: 600, color: t.text)),
                  Text('يبقى البيت الحالي عند التبديل', style: kufi(size: 12.5, weight: 400, color: t.muted)),
                  const SizedBox(height: 12),
                  for (final r in library.recordings) ...[
                    ReciterOption(
                      library: library,
                      recording: r,
                      onPick: () async {
                        final navigator = Navigator.of(sheet);
                        await library.choose(r);
                        navigator.pop();
                        if (!library.isOnDevice(r)) {
                          navigator.push(MaterialPageRoute<void>(builder: (_) => DownloadsScreen(library: library)));
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: () {
                      final navigator = Navigator.of(sheet);
                      navigator.pop();
                      navigator.push(MaterialPageRoute<void>(builder: (_) => DownloadsScreen(library: library)));
                    },
                    icon: Icon(LucideIcons.download, size: 17, color: t.goldText),
                    label: Text('إدارة التنزيلات', style: kufi(size: 14, weight: 500, color: t.text)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      side: BorderSide(color: t.line),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

class ReciterOption extends StatelessWidget {
  final AudioLibrary library;
  final Recording recording;
  final VoidCallback onPick;
  const ReciterOption({super.key, required this.library, required this.recording, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final r = recording;
    final chosen = library.current.id == r.id;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: chosen,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPick,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: chosen ? t.gold.withValues(alpha: 0.10) : t.panel2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: chosen ? t.goldDeep : t.line),
          ),
          child: Row(
            children: [
              Icon(chosen ? LucideIcons.circleDot : LucideIcons.circle, size: 20, color: chosen ? t.gold : t.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.reciterName, style: kufi(size: 15, weight: 600, color: t.text)),
                    Text(
                      '${durationHms(r.durationMs)}، ${megabytes(r.localBytes)}، '
                      '${library.isOnDevice(r) ? 'على الجهاز' : 'غير منزّل'}',
                      style: kufi(size: 12, weight: 400, color: t.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
