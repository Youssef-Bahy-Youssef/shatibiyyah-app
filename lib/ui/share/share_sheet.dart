// lib/ui/share/share_sheet.dart — «مشاركة» (item 3.11, ADRs 0010, 0023; handoff
// share-*): one themed card image of 1–10 verses from one chapter.
//
// The sheet shows the card as it will be exported, the three sizes (a size that
// cannot hold the selection is disabled, with the limits stated), an optional
// quoted opening of a commentary for up to three verses with its book, and
// «مشاركة الصورة» and «حفظ». Only the image is sent, so chat apps do not show
// the verses twice. The card follows the reader's theme; at night its names
// take the chosen ink.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/app_content.dart';
import '../../data/commentary_repository.dart';
import '../../domain/commentary_text.dart';
import '../../services/device_storage.dart';
import '../../utils/arabic.dart';
import '../design/components/share_card.dart';
import '../design/components/share_controls.dart';
import '../design/components/tz_button.dart';
import '../design/components/tz_sheet.dart';
import '../design/components/tz_switch.dart';
import '../design/tokens.g.dart';
import '../design/tz_icon.dart';
import '../design/tz_theme.dart';
import '../reader/verse_rubrics.dart';

/// Hands the image to the system; replaceable in tests.
typedef ShareHandler = Future<void> Function(ShareParams params);

/// Saves the image where the user chooses; false when they cancel.
typedef SaveHandler = Future<bool> Function(String name, Uint8List png);

Future<void> _systemShare(ShareParams params) async => SharePlus.instance.share(params);

/// The most verses one card carries (ADR 0010).
const int kMaxSharedVerses = 10;

/// Why [from]…[to] cannot be shared, or null when it can: 1–10 verses of one chapter.
String? shareLimitReason(AppContent content, int from, int to) {
  final one = content.matn.chapterOfVerse(from).id == content.matn.chapterOfVerse(to).id;
  return one && to - from + 1 <= kMaxSharedVerses ? null : 'المشاركة حتى ${ar(kMaxSharedVerses)} أبيات من باب واحد';
}

/// The card of verses [from]…[to] in [format].
ShareCardData shareCardData(AppContent content, int from, int to, CardFormat format, {CardExcerpt? excerpt}) {
  final chapter = content.matn.chapterOfVerse(from);
  final numbered = chapter.orderIndex > 0; // the introduction has no number
  return ShareCardData(
    format: format,
    firstVerse: from,
    lastVerse: to,
    verses: [
      for (var n = from; n <= to; n++)
        CardVerse(content.matn.verse(n).firstHemistich, content.matn.verse(n).secondHemistich,
            rubrics: verseRubrics(content, n)),
    ],
    chapterTitle: chapter.title,
    chapterOrdinal: numbered ? chapterOrdinal(chapter.orderIndex) : content.matn.partOf(chapter).title,
    chapterNumber: numbered ? ar(chapter.orderIndex) : '',
    excerpt: excerpt,
  );
}

/// The opening of [book]'s explanation of [verse], as written, with its source.
Future<CardExcerpt?> loadExcerpt(AppContent content, Book book, int verse) async {
  final blocks = await content.books.blocksForVerse(book.id, verse);
  for (final block in blocks) {
    for (final segment in await content.books.segments(block.id)) {
      final paragraphs = layoutSegment(segment.text, const []);
      if (paragraphs.isEmpty) continue;
      final text = paragraphs.first.plainText.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;
      return CardExcerpt(text: text, source: [book.title, ?book.author].join(' · '));
    }
  }
  return null;
}

/// The card under [boundary] as an image of exactly its format's pixels.
Future<ui.Image> captureCard(GlobalKey boundary) =>
    (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 1);

Future<void> showShareSheet(BuildContext context, AppContent content, int from,
        {int? to, ShareHandler? share, SaveHandler? save, void Function(String notice)? onNotice}) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (_) => ShareSheet(
          content: content, from: from, to: to ?? from, share: share ?? _systemShare, save: save ?? saveImage, onNotice: onNotice),
    );

class ShareSheet extends StatefulWidget {
  final AppContent content;
  final int from, to;
  final ShareHandler share;
  final SaveHandler save;
  final void Function(String notice)? onNotice;
  const ShareSheet(
      {super.key, required this.content, required this.from, required this.to, required this.share, required this.save, this.onNotice});

  static const frameKey = ValueKey('share-preview-frame');
  static const formatsKey = ValueKey('share-formats');
  static const whyKey = ValueKey('share-why');

  /// The most verses that may carry a commentary's opening.
  static const int excerptVerses = 3;

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  final _card = GlobalKey();
  late CardFormat _format;
  bool _excerptOn = false, _busy = false;
  late Book _book = widget.content.books.defaultBook;
  CardExcerpt? _excerpt;
  String? _failure;

  int get _count => widget.to - widget.from + 1;
  bool get _excerptAllowed => _count <= ShareSheet.excerptVerses;

  @override
  void initState() {
    super.initState();
    // The default is the portrait; a longer selection takes the first size that holds it.
    _format = CardFormat.portrait.maxVerses >= _count ? CardFormat.portrait : CardFormat.story;
  }

  Future<void> _setExcerpt(bool on, [Book? book]) async {
    setState(() {
      _excerptOn = on;
      _book = book ?? _book;
      if (!on) _excerpt = null;
    });
    if (!on) return;
    final wanted = _book;
    final excerpt = await loadExcerpt(widget.content, wanted, widget.from);
    if (mounted && _excerptOn && _book.id == wanted.id) setState(() => _excerpt = excerpt);
  }

  String get _fileName => _count > 1 ? 'taysir-${widget.from}-${widget.to}.png' : 'taysir-${widget.from}.png';

  Future<Uint8List> _png() async {
    final image = await captureCard(_card);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    image.dispose();
    return bytes;
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final png = await _png();
      if (mounted) Navigator.of(context).pop();
      // The image alone: no text beside it (ADR 0010).
      await widget.share(
          ShareParams(files: [XFile.fromData(png, mimeType: 'image/png')], fileNameOverrides: [_fileName]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final saved = await widget.save(_fileName, await _png());
      if (!mounted || !saved) return;
      Navigator.of(context).pop();
      widget.onNotice?.call('حُفظت الصورة');
    } on Object {
      if (mounted) setState(() => _failure = 'تعذّر الحفظ');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tz = TzTheme.of(context), c = tz.colors;
    final media = MediaQuery.of(context);
    final data = shareCardData(widget.content, widget.from, widget.to, _format, excerpt: _excerptOn ? _excerpt : null);
    final size = _format.size;
    return SizedBox(
      height: media.size.height - statusBarHeight(context) - 8,
      child: TzSheet.picker(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(child: Text('مشاركة ${data.label}', style: TzType.title.copyWith(color: c.ink))),
                  const SizedBox(width: 8),
                  Text(_failure ?? 'صورة بحجم ${ar(size.width.toInt())}×${ar(size.height.toInt())}',
                      style: TzType.caption.copyWith(color: _failure == null ? c.ink3 : c.carmine)),
                ],
              ),
              // The card as it will be exported, scaled to the preview.
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Center(
                  child: SharePreviewFrame(
                    key: ShareSheet.frameKey,
                    format: _format,
                    child: RepaintBoundary(
                      key: _card,
                      child: ShareCard(
                          data: data, palette: tz.night ? ShareCardPalette.night(tz.nightInk) : ShareCardPalette.paper),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Semantics(
                container: true,
                explicitChildNodes: true,
                label: 'المقاس',
                // The three stay one height when larger text makes one of them grow.
                child: IntrinsicHeight(
                  key: ShareSheet.formatsKey,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    for (final (i, f) in CardFormat.values.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: ShareFormatButton(
                          format: f,
                          selected: f == _format,
                          enabled: _count <= f.maxVerses,
                          onTap: () => setState(() => _format = f),
                        ),
                      ),
                    ],
                  ],
                  ),
                ),
              ),
              if (_count > CardFormat.square.maxVerses)
                Padding(
                  key: ShareSheet.whyKey,
                  padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TzIcon('chev', size: 22, color: c.ink2),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            'المربع يتسع حتى ${ar(CardFormat.square.maxVerses)} أبيات؛ الطولي حتى ${ar(CardFormat.portrait.maxVerses)}، '
                            'والقصة حتى ${ar(CardFormat.story.maxVerses)}.',
                            style: TzType.caption.copyWith(
                                color: c.ink2, fontWeight: FontWeight.w400, height: 20 / TzType.caption.fontSize!)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(minHeight: 52),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: c.lineSoft))),
                child: Row(
                  children: [
                    TzIcon('book', size: 20, color: c.ink3),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('مقتطف من الشرح', style: TzType.label.copyWith(color: c.ink)),
                          if (!_excerptAllowed)
                            Text('متاح حتى ${ar(ShareSheet.excerptVerses)} أبيات', style: TzType.caption.copyWith(color: c.ink3)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    TzSwitch(
                      semanticLabel: 'مقتطف من الشرح',
                      value: _excerptOn,
                      onWord: 'مضاف',
                      offWord: 'بدون',
                      onChanged: _excerptAllowed ? _setExcerpt : null,
                    ),
                  ],
                ),
              ),
              // v2.css .chips2: 36 px pills, 4 px into the row above, 10 px over the
              // buttons. Each pill keeps a 48 px target, so the pills are drawn 10 px
              // up and the buttons 16 px up (a translation keeps the whole target live).
              if (_excerptOn)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 32),
                  child: Transform.translate(
                    offset: const Offset(0, -10),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final book in widget.content.books.books)
                          ShareBookChip(label: book.shortTitle, selected: book.id == _book.id, onTap: () => _setExcerpt(true, book)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Transform.translate(
                offset: Offset(0, _excerptOn ? -16 : 0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 207,
                      child: TzButton.primary(label: 'مشاركة الصورة', icon: 'share', onPressed: _busy ? null : _share),
                    ),
                    const SizedBox(width: 8),
                    Expanded(flex: 143, child: TzButton.tonal(label: 'حفظ', icon: 'down', onPressed: _busy ? null : _save)),
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
