// lib/ui/share/share_sheet.dart — «مشاركة البيت N» (features-v3 share-and-copy).
//
// Three formats, as in the prototype: «نص» (the copy text), «بطاقة» (a paper card
// with the shamsa, shared as an image) and «من المخطوط» (a strip of the original
// page around the verse, never night-inverted). «مشاركة» hands the text or a PNG to
// the system share sheet.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/app_content.dart';
import '../design/tokens.g.dart';
import '../../utils/arabic.dart';
import '../design/taysir_colors.dart';
import '../reader/shamsa.dart';
import '../widgets/verse_menu.dart' show verseCopyText;
import '../design/tz_theme.dart';

enum ShareFormat { text, card, manuscript }

/// Hands the chosen format to the system; replaceable in tests.
typedef ShareHandler = Future<void> Function(ShareParams params);

Future<void> _systemShare(ShareParams params) async => SharePlus.instance.share(params);

Future<void> showShareSheet(BuildContext context, AppContent content, int verse, {ShareHandler? share}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareSheet(content: content, verse: verse, share: share ?? _systemShare),
    );

class ShareSheet extends StatefulWidget {
  final AppContent content;
  final int verse;
  final ShareHandler share;
  const ShareSheet({super.key, required this.content, required this.verse, required this.share});

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  ShareFormat _format = ShareFormat.card;
  final _card = GlobalKey();
  Future<Uint8List>? _clip;

  Future<Uint8List> get _manuscript => _clip ??= manuscriptClip(widget.content, widget.verse);

  Future<void> _go() async {
    final text = verseCopyText(widget.content, widget.verse);
    final name = 'bayt-${widget.verse}.png';
    final ShareParams params;
    switch (_format) {
      case ShareFormat.text:
        params = ShareParams(text: text);
      case ShareFormat.card:
        final boundary = _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        params = ShareParams(files: [XFile.fromData(png, mimeType: 'image/png', name: name)], text: text);
      case ShareFormat.manuscript:
        params = ShareParams(
          files: [XFile.fromData(await _manuscript, mimeType: 'image/png', name: name)],
          text: text,
        );
    }
    if (mounted) Navigator.of(context).pop();
    await widget.share(params);
  }

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final v = widget.content.matn.verse(widget.verse);
    final chapter = widget.content.matn.chapterOfVerse(widget.verse).shortLabel;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: t.line)),
        ),
        padding: EdgeInsets.fromLTRB(16, 10, 16, 24 + MediaQuery.of(context).padding.bottom),
        child: Column(
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
            Text('مشاركة البيت ${ar(widget.verse)}', style: TzType.title.copyWith(color: t.text)),
            const SizedBox(height: 12),
            _tabs(t),
            const SizedBox(height: 12),
            switch (_format) {
              ShareFormat.text => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: t.panel2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: t.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('البيت ${ar(widget.verse)} — $chapter\n${v.firstHemistich}\n${v.secondHemistich}',
                          style: TzType.verse.copyWith(color: t.text)),
                      Text('— تيسير الشاطبية', style: TzType.caption.copyWith(color: t.muted)),
                    ],
                  ),
                ),
              ShareFormat.card => RepaintBoundary(
                  key: _card,
                  child: VerseCard(verse: widget.verse, first: v.firstHemistich, second: v.secondHemistich, chapter: chapter),
                ),
              ShareFormat.manuscript => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: FutureBuilder<Uint8List>(
                        future: _manuscript,
                        builder: (_, snap) => snap.hasData
                            ? Image.memory(snap.data!, fit: BoxFit.fitWidth)
                            : const SizedBox(height: 110),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('قصاصة من المخطوط الأصلي، ولا يُطبَّق عليها الوضع الليلي',
                        style: TzType.caption.copyWith(color: t.muted)),
                  ],
                ),
            },
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _go,
              style: FilledButton.styleFrom(
                backgroundColor: t.gold,
                foregroundColor: t.onGold,
                minimumSize: const Size.fromHeight(52),
                shape: const StadiumBorder(),
              ),
              child: Text('مشاركة', style: TzType.head.copyWith(color: t.onGold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs(TaysirColors t) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: t.line),
        ),
        child: Row(
          children: [
            for (final (f, label) in [
              (ShareFormat.text, 'نص'),
              (ShareFormat.card, 'بطاقة'),
              (ShareFormat.manuscript, 'من المخطوط'),
            ])
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => setState(() => _format = f),
                  child: Container(
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _format == f ? t.gold : null,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(label,
                        style: TzType.label.copyWith(color: _format == f ? t.onGold : t.text)),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// The shareable paper card: the shamsa with the verse number, both hemistichs,
/// the chapter and the app's name. Always on paper, whatever the theme.
class VerseCard extends StatelessWidget {
  final int verse;
  final String first, second, chapter;
  const VerseCard({super.key, required this.verse, required this.first, required this.second, required this.chapter});

  @override
  Widget build(BuildContext context) {
    final ink = TzColors.paper.ink;
    final line = TzType.verse.copyWith(color: ink);
    return Theme(
      data: Theme.of(context).copyWith(extensions: const [TzTheme.paper]),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
        // The edge keeps the card distinct on the paper theme's sheet, and in the shared image.
        decoration: BoxDecoration(
          color: TzColors.paper.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: TzColors.paper.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Shamsa(size: 44, verse: verse, playing: false),
            const SizedBox(height: 6),
            SizedBox(width: double.infinity, child: Text(first, textAlign: TextAlign.right, style: line)),
            SizedBox(width: double.infinity, child: Text(second, textAlign: TextAlign.left, style: line)),
            const SizedBox(height: 6),
            Text('$chapter · تيسير الشاطبية', style: TzType.caption.copyWith(color: TzColors.paper.ink3)),
          ],
        ),
      ),
    );
  }
}

/// «مشاركة الصفحة»: the scanned page as a PNG, with a line naming it.
Future<void> sharePage(AppContent content, int page, {ShareHandler? share, AssetBundle? bundle}) async {
  final png = await pagePng(page, bundle: bundle);
  final verses = content.layout.versesOnPage(page);
  final chapter = verses.isEmpty ? '' : ' — ${content.matn.chapterOfVerse(verses.first).shortLabel}';
  await (share ?? _systemShare)(ShareParams(
    files: [XFile.fromData(png, mimeType: 'image/png', name: 'page-$page.png')],
    text: 'ص ${ar(page)}$chapter · تيسير الشاطبية',
  ));
}

/// Scanned page [page] (a WebP asset) re-encoded as PNG, which every app accepts.
Future<Uint8List> pagePng(int page, {AssetBundle? bundle}) async {
  final image = await _pageImage(page, bundle);
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

Future<ui.Image> _pageImage(int page, AssetBundle? bundle) async {
  final data = await (bundle ?? rootBundle).load('assets/pages/page${page.toString().padLeft(3, '0')}.webp');
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  return (await codec.getNextFrame()).image;
}

/// A PNG strip of the scanned page around [verse]: the full page width, from a
/// little above the verse's box to a little below it, at the scan's resolution.
Future<Uint8List> manuscriptClip(AppContent content, int verse, {AssetBundle? bundle}) async {
  final region = content.layout.verseRegion(verse);
  final page = await _pageImage(region.page, bundle);
  const margin = 40.0;
  final top = (region.rect.top - margin).clamp(0.0, page.height.toDouble());
  final bottom = (region.rect.bottom + margin).clamp(0.0, page.height.toDouble());
  final src = Rect.fromLTRB(0, top, page.width.toDouble(), bottom);
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(page, src, Rect.fromLTWH(0, 0, src.width, src.height), Paint());
  final clip = await recorder.endRecording().toImage(src.width.round(), src.height.round());
  return (await clip.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}
