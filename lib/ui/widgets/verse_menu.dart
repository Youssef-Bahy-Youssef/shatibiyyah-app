// lib/ui/widgets/verse_menu.dart — the long-press menu of a verse (features-v3: verse-action-menu).
//
// M1 subset: «الشرح» and «نسخ», plus «تشغيل من هنا» once a recording is on the device.
// Bookmark, note, share and range selection arrive with P4/P6. The rest of the page
// dims; the card sits below the verse when it fits, otherwise above it, and always
// inside the screen.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/app_content.dart';
import '../../theme.dart' show kufi, naskh;
import '../../utils/arabic.dart';
import '../commentary/commentary_screen.dart';
import '../design/taysir_colors.dart';

/// The copy format of features-v3 (share-and-copy): number, chapter, both halves, attribution.
String verseCopyText(AppContent content, int verse) {
  final v = content.matn.verse(verse);
  final chapter = content.matn.chapterOfVerse(verse).shortLabel;
  return 'البيت ${ar(verse)} — $chapter\n${v.firstHemistich}\n${v.secondHemistich}\n— تيسير الشاطبية';
}

/// Hosted by a reader screen: [listenable] notifies when [verse] (the menu's verse,
/// null = closed) changes; [anchor] is where that verse is drawn on screen.
class VerseMenu extends StatelessWidget {
  final Listenable listenable;
  final AppContent content;
  final int? Function() verse;
  final Rect? Function(int verse) anchor;
  final VoidCallback onClose;

  /// «تشغيل من هنا»: shown only when [canPlay] says a recording is on the device.
  final bool Function() canPlay;
  final void Function(int verse) onPlayFrom;

  const VerseMenu({
    super.key,
    required this.listenable,
    required this.content,
    required this.verse,
    required this.anchor,
    required this.onClose,
    required this.canPlay,
    required this.onPlayFrom,
  });

  static const double _estimatedHeight = 220;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final verse = this.verse();
        if (verse == null) return const SizedBox.shrink();
        final t = TaysirColors.of(context);
        final size = MediaQuery.of(context).size;
        final pad = MediaQuery.of(context).padding;
        final rect = anchor(verse);
        double top;
        if (rect == null) {
          top = size.height - pad.bottom - _estimatedHeight - 24;
        } else if (rect.bottom + 16 + _estimatedHeight < size.height - pad.bottom) {
          top = rect.bottom + 16;
        } else {
          top = (rect.top - 16 - _estimatedHeight).clamp(pad.top + 8, size.height);
        }
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
              ),
            ),
            if (rect != null)
              Positioned.fromRect(
                rect: rect.inflate(4),
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: t.gold, width: 2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            Positioned(left: 12, right: 12, top: top, child: _card(context, t, verse)),
          ],
        );
      },
    );
  }

  Widget _card(BuildContext context, TaysirColors t, int verse) {
    final sadr = content.matn.verse(verse).firstHemistich;
    void explain() {
      onClose();
      CommentaryScreen.open(context, content, verse);
    }

    void copy() {
      Clipboard.setData(ClipboardData(text: verseCopyText(content, verse)));
      onClose();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('تم نسخ البيت مع الإسناد', style: kufi(size: 14, weight: 500, color: t.text)),
            backgroundColor: t.raised, duration: const Duration(seconds: 2)),
      );
    }

    void playFromHere() {
      onClose();
      onPlayFrom(verse);
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: t.panel,
        elevation: 12,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: t.line)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('البيت ${ar(verse)}', style: kufi(size: 16, weight: 600, color: t.goldText)),
                        Text('$sadr …',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: naskh(size: 15, color: t.dim)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق',
                    icon: Icon(LucideIcons.x, size: 21, color: t.muted),
                    onPressed: onClose,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _action(t, LucideIcons.bookOpen, 'الشرح', explain, primary: true),
                  if (canPlay()) _action(t, LucideIcons.play, 'تشغيل من هنا', playFromHere),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Divider(height: 1, color: t.line),
              ),
              Wrap(spacing: 8, runSpacing: 8, children: [_chip(t, LucideIcons.copy, 'نسخ', copy)]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(TaysirColors t, IconData icon, String label, VoidCallback onTap, {bool primary = false}) => Expanded(
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primary ? t.gold : t.panel2,
                      border: primary ? null : Border.all(color: t.line),
                    ),
                    child: Icon(icon, size: 22, color: primary ? t.onGold : t.goldText),
                  ),
                  const SizedBox(height: 6),
                  Text(label, style: kufi(size: 12.5, weight: 400, color: t.text)),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _chip(TaysirColors t, IconData icon, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: t.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 17, color: t.goldText),
              const SizedBox(width: 7),
              Text(label, style: kufi(size: 13, weight: 400, color: t.text)),
            ]),
          ),
        ),
      );
}
