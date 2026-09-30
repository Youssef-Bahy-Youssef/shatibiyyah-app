// lib/ui/shell/home_screen.dart — «الرئيسية والمكتبة» (features-v3 home-screen).
//
// «تابع من حيث توقفت» (the reader's verse, chapter and page), then three tabs:
// «المراجع», «الملاحظات», «السجل» (reading-history: listening sessions and
// commentary passages read). Each entry opens its verse in the reader, or its
// passage in its book. When Google Play has a newer version, a banner above them
// offers it (lib/app/app_update.dart; the only screen that shows it). The
// prototype's plans tab left with study plans; the rating is asked for natively
// after a finished chapter (lib/app/rating.dart), not by a card.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/app_update.dart';
import '../../app/personal_data.dart';
import '../../data/user_store.dart';
import '../../theme.dart' show kufi, naskh;
import '../../utils/arabic.dart';
import '../commentary/commentary_screen.dart';
import '../design/taysir_colors.dart';
import '../reader/reader_controller.dart';
import '../reader/shamsa.dart';
import '../search/search_screen.dart';

class HomeScreen extends StatefulWidget {
  final ReaderController reader;
  const HomeScreen({super.key, required this.reader});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  ReaderController get reader => widget.reader;

  void _openVerse(int verse) {
    reader.tapVerse(verse);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final personal = reader.personal;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          bottom: false,
          child: AnimatedBuilder(
            animation: Listenable.merge([reader, ?personal, ?reader.update]),
            builder: (context, _) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _header(t),
                if (reader.update case final update? when update.showBanner) _updateBanner(t, update),
                const SizedBox(height: 8),
                _continueCard(t),
                const SizedBox(height: 16),
                _tabs(t, personal),
                const SizedBox(height: 8),
                if (personal == null)
                  const SizedBox.shrink()
                else
                  switch (_tab) {
                    0 => _bookmarks(t, personal),
                    1 => _notes(t, personal),
                    _ => _history(t, personal),
                  },
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(TaysirColors t) {
    Widget icon(IconData i, String label, VoidCallback onTap) => IconButton(
          tooltip: label,
          onPressed: onTap,
          icon: Icon(i, size: 21, color: t.text),
        );
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(child: Text('تيسير الشاطبية', style: kufi(size: 20, weight: 600, color: t.text))),
          icon(LucideIcons.bookOpen, 'القارئ', () => Navigator.of(context).popUntil((r) => r.isFirst)),
          icon(LucideIcons.search, 'بحث', () => SearchScreen.open(context, reader)),
        ],
      ),
    );
  }

  Widget _updateBanner(TaysirColors t, AppUpdate update) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
        decoration: BoxDecoration(
          color: t.panel2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.goldDeep),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.download, size: 18, color: t.goldText),
            const SizedBox(width: 10),
            Expanded(child: Text('إصدار جديد من التطبيق متاح', style: kufi(size: 13.5, weight: 500, color: t.text))),
            TextButton(
              onPressed: update.update,
              child: Text('تحديث', style: kufi(size: 14, weight: 600, color: t.goldText)),
            ),
            IconButton(
              tooltip: 'إخفاء',
              onPressed: update.dismiss,
              icon: Icon(LucideIcons.x, size: 18, color: t.muted),
            ),
          ],
        ),
      );

  Widget _continueCard(TaysirColors t) {
    final v = reader.verse;
    return Material(
      color: t.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: t.goldDeep)),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Shamsa(size: 60, verse: v, playing: reader.playing),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('تابع من حيث توقفت', style: kufi(size: 12.5, weight: 400, color: t.muted)),
                    Text(reader.chapter.shortLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: naskh(size: 18, weight: FontWeight.w700, color: t.text, height: 1.6)),
                    Text('البيت ${ar(v)}، ص ${ar(reader.content.layout.pageOfVerse(v))}',
                        style: kufi(size: 12.5, weight: 400, color: t.dim)),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronLeft, size: 20, color: t.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabs(TaysirColors t, PersonalData? personal) {
    // The counts in parentheses: next to a number a «·» reads as «٠».
    final labels = [
      'المراجع (${ar(personal?.bookmarks.length ?? 0)})',
      'الملاحظات (${ar(personal?.notes.length ?? 0)})',
      'السجل',
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.line),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                selected: i == _tab,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => setState(() => _tab = i),
                  child: Container(
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == _tab ? t.gold : null,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kufi(size: 13.5, weight: i == _tab ? 600 : 400, color: i == _tab ? t.onGold : t.text)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty(TaysirColors t, IconData icon, String title, String how) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, size: 32, color: t.goldText),
            const SizedBox(height: 10),
            Text(title, style: kufi(size: 15, weight: 600, color: t.text)),
            const SizedBox(height: 4),
            Text(how, textAlign: TextAlign.center, style: kufi(size: 13, weight: 400, color: t.muted)),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              icon: Icon(LucideIcons.bookOpen, size: 17, color: t.goldText),
              label: Text('افتح القارئ', style: kufi(size: 14, weight: 500, color: t.text)),
              style: OutlinedButton.styleFrom(side: BorderSide(color: t.line), shape: const StadiumBorder()),
            ),
          ],
        ),
      );

  Widget _entry(TaysirColors t, {Widget? leading, required String title, String? chip, String? body, required String meta, required VoidCallback onTap}) =>
      InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[leading, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(title, style: kufi(size: 14.5, weight: 600, color: t.text))),
                        if (chip != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: t.line),
                            ),
                            child: Text(chip, style: kufi(size: 11.5, weight: 500, color: t.goldText)),
                          ),
                        ],
                      ],
                    ),
                    if (body != null)
                      Text(body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: naskh(size: 17, color: t.text, height: 1.6)),
                    Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: kufi(size: 12, weight: 400, color: t.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  String _what(int from, int to) => from == to ? 'البيت ${ar(from)}' : 'الأبيات ${isolatedRange(from, to)}';

  Widget _bookmarks(TaysirColors t, PersonalData personal) {
    if (personal.bookmarks.isEmpty) {
      return _empty(t, LucideIcons.bookmark, 'لا مراجع بعد', 'اضغط مطوّلًا على بيت في المخطوط ثم اختر «مرجع».');
    }
    final matn = reader.content.matn;
    return Column(children: [
      for (final b in personal.bookmarks)
        _entry(
          t,
          leading: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: CustomPaint(size: const Size(12, 24), painter: _RibbonMark(kBookmarkColors[b.color]!)),
          ),
          title: _what(b.fromVerse, b.lastVerse),
          chip: kBookmarkTagLabels[b.tag],
          body: matn.verse(b.fromVerse).firstHemistich,
          meta: matn.chapterOfVerse(b.fromVerse).shortLabel,
          onTap: () => _openVerse(b.fromVerse),
        ),
    ]);
  }

  Widget _notes(TaysirColors t, PersonalData personal) {
    if (personal.notes.isEmpty) {
      return _empty(t, LucideIcons.stickyNote, 'لا ملاحظات بعد', 'اضغط مطوّلًا على بيت في المخطوط ثم اختر «ملاحظة».');
    }
    final matn = reader.content.matn;
    return Column(children: [
      for (final n in personal.notes)
        _entry(
          t,
          title: 'البيت ${ar(n.verse)}',
          body: n.body,
          meta: matn.verse(n.verse).firstHemistich,
          onTap: () => _openVerse(n.verse),
        ),
    ]);
  }

  Widget _history(TaysirColors t, PersonalData personal) {
    if (personal.history.isEmpty) {
      return _empty(t, LucideIcons.history, 'لا سجل بعد', 'يظهر هنا ما استمعت إليه وما قرأته من الشروح.');
    }
    final titles = {for (final b in reader.content.books.books) b.id: b.shortTitle};
    return Column(children: [
      for (final a in personal.history)
        switch (a.kind) {
          ActivityKind.listen => _entry(
              t,
              leading: Icon(LucideIcons.headphones, size: 20, color: t.goldText),
              title: 'استماع ${_what(a.fromVerse, a.toVerse)}',
              meta: '${dayLabel(a.at)} ${clockTime(a.at)}، ${minutesCount(((a.seconds ?? 0) / 60).ceil())}',
              onTap: () => _openVerse(a.fromVerse),
            ),
          ActivityKind.commentary => _entry(
              t,
              leading: Icon(LucideIcons.bookOpen, size: 20, color: t.goldText),
              title: 'شرح ${_what(a.fromVerse, a.toVerse)}',
              meta: '${dayLabel(a.at)} ${clockTime(a.at)}، ${titles[a.commentaryId] ?? ''}',
              onTap: () => CommentaryScreen.open(context, reader.content, a.fromVerse, bookId: a.commentaryId),
            ),
        },
    ]);
  }
}

class _RibbonMark extends CustomPainter {
  final Color color;
  const _RibbonMark(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(w, 0)
        ..lineTo(w, h)
        ..lineTo(w / 2, h * 0.75)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_RibbonMark old) => old.color != color;
}
