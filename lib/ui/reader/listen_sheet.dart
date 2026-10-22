// lib/ui/reader/listen_sheet.dart — «الاستماع إلى؟» (features-v3 play-scope-shortcuts).
//
// «تشغيل من هنا» asks how far to play from the verse: the verse only, to the end
// of its chapter, or to the end of the poem. The custom range left v3 with the
// range selector.
import 'package:flutter/material.dart';

import '../../domain/playback_plan.dart';
import '../design/tokens.g.dart';
import '../../utils/arabic.dart';
import '../design/taysir_colors.dart';
import 'reader_controller.dart';
import '../design/components/tz_motion.dart';

/// The scopes offered from [verse], with their labels. On a chapter's last verse
/// «إلى نهاية الباب» would repeat «البيت فقط», so it is left out.
List<({String title, String detail, PlaybackScope scope})> listenOptions(ReaderController reader, int verse) {
  final chapter = reader.content.matn.chapterOfVerse(verse);
  final last = reader.content.matn.lastVerse;
  return [
    (title: 'البيت فقط', detail: 'البيت ${ar(verse)}', scope: PlaybackScope(verse, verse)),
    if (verse < chapter.toVerse)
      (
        title: 'إلى نهاية الباب',
        detail: 'من ${ar(verse)} إلى ${ar(chapter.toVerse)}',
        scope: PlaybackScope(verse, chapter.toVerse),
      ),
    (title: 'إلى نهاية المتن', detail: 'من ${ar(verse)} إلى ${ar(last)}', scope: PlaybackScope(verse, last)),
  ];
}

Future<void> showListenSheet(BuildContext context, ReaderController reader, int verse) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheet) {
        final t = TaysirColors.of(sheet);
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            decoration: BoxDecoration(
              color: t.panel,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: t.line)),
            ),
            padding: EdgeInsets.fromLTRB(16, 10, 16, 20 + MediaQuery.of(sheet).padding.bottom),
            // Scrolls when large text makes the options taller than the sheet.
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(color: t.line, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Text('الاستماع إلى؟', style: TzType.title.copyWith(color: t.text)),
                const SizedBox(height: 12),
                for (final o in listenOptions(reader, verse)) ...[
                  TzPressable(sink: true,
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.of(sheet).pop();
                      reader.playScope(o.scope);
                    },
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: t.panel2,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: t.line),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(o.title, style: TzType.body.copyWith(color: t.text))),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(o.detail,
                                textAlign: TextAlign.end, style: TzType.caption.copyWith(color: t.muted)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
            ),
          ),
        );
      },
    );
