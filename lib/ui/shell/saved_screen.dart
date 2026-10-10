// lib/ui/shell/saved_screen.dart — «المحفوظ» (item 3.4, ADR 0019; index.html
// saved, v2.css .utabs, .bm, .empty, .snack): the bookmarks and the notes that
// the home screen used to hold.
//
// The same header as every top-level screen, then two underline tabs with their
// counts. A bookmark is a row: its ribbon, the verse with the tag as a dot and a
// word in the ribbon's colour, the first hemistich in Naskh and the chapter.
// Swiping reveals «حذف» in carmine, and «تراجع» undoes it for five seconds; a
// long press offers «تعديل» and «حذف»; a tap opens the verse. A delete that
// fails puts the row back and says «تعذّر الحفظ». The empty states
// say the exact gesture and offer the way back to the matn. A note is a row the
// same way (item 5.1): its verse, its text, the first hemistich; «تعديل» opens its
// sheet, and a delete there is undone here.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/personal_data.dart';
import '../../data/user_store.dart' show Bookmark, Note;
import '../../utils/arabic.dart';
import '../design/components/dock.dart' show DockTab;
import '../design/components/khatam.dart';
import '../design/components/tz_button.dart';
import '../design/components/undo_snackbar.dart';
import '../design/tokens.g.dart';
import '../design/tz_icon.dart';
import '../design/tz_theme.dart';
import '../reader/reader_controller.dart';
import '../search/search_screen.dart';
import '../study/study_sheets.dart';
import 'app_shell.dart';
import 'shell_page.dart';

class SavedScreen extends StatefulWidget {
  final ReaderController reader;
  final bool notes;
  const SavedScreen({super.key, required this.reader, this.notes = false});

  static const tabsKey = ValueKey('saved-tabs');
  static const deleteGlyphKey = ValueKey('saved-delete-glyph');

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

/// What «تراجع» brings back: the bookmark or the note just deleted.
typedef _Deleted = ({String uuid, String message, Future<void> Function() restore});

class _SavedScreenState extends State<SavedScreen> {
  late bool _notes = widget.notes;
  _Deleted? _undo;
  Timer? _undoTimer;
  // Failed deletes so far, part of each row's key: a swiped row that comes back
  // must be a new Dismissible, the old one is spent.
  int _revived = 0;

  ReaderController get reader => widget.reader;

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

  void _openVerse(int verse) => AppShell.openVerse(context, reader, verse);

  /// The app's search; a result that moved the reader shows it.
  Future<void> _search() async {
    final before = reader.verse;
    await SearchScreen.open(context, reader);
    if (mounted && reader.verse != before) AppShell.of(context)?.select(DockTab.matn);
  }

  _Deleted _bookmark(PersonalData personal, Bookmark b) => (
    uuid: b.uuid,
    message: 'أُزيل المرجع: ${bookmarkLabel(b)}',
    restore: () => personal.restoreBookmark(b),
  );

  _Deleted _note(PersonalData personal, Note n) => (
    uuid: n.uuid,
    message: 'حُذفت الملاحظة: البيت ${ar(n.verse)}',
    restore: () => personal.restoreNote(n),
  );

  /// Runs [remove], then offers [deleted] back for five seconds.
  Future<void> _delete(Future<void> Function() remove, _Deleted deleted) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await remove();
    } catch (_) {
      // Not deleted: the row is back in the list, and there is nothing to undo (F-55).
      if (mounted) setState(() => _revived++);
      messenger?.showSnackBar(const SnackBar(content: Text('تعذّر الحفظ'), duration: Duration(seconds: 2)));
      return;
    }
    _offerUndo(deleted);
  }

  void _offerUndo(_Deleted deleted) {
    if (!mounted) return;
    _undoTimer?.cancel();
    setState(() => _undo = deleted);
    _undoTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _undo = null);
    });
  }

  Future<void> _restore() async {
    final deleted = _undo;
    if (deleted == null) return;
    _undoTimer?.cancel();
    setState(() => _undo = null);
    await deleted.restore();
  }

  void _notice(String notice) => ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(notice), duration: const Duration(seconds: 2)));

  void _editBookmark(PersonalData personal, Bookmark b) => showBookmarkSheet(
    context,
    personal: personal,
    content: reader.content,
    from: b.fromVerse,
    to: b.toVerse,
    onDone: _notice,
  );

  void _editNote(PersonalData personal, Note n) => showNoteSheet(
    context,
    personal: personal,
    content: reader.content,
    verse: n.verse,
    onDone: _notice,
    onDeleted: (deleted) => _offerUndo(_note(personal, deleted)),
  );

  @override
  Widget build(BuildContext context) {
    final personal = reader.personal;
    return ListenableBuilder(
      listenable: Listenable.merge([reader, ?personal]),
      builder: (context, _) {
        final c = TzTheme.of(context).colors;
        final bookmarks = personal?.bookmarks ?? const <Bookmark>[];
        final notes = personal?.notes ?? const [];
        return ShellPage.topLevel(
          title: 'المحفوظ',
          action: ShellIconButton(icon: 'search', label: 'بحث في المحفوظ', onPressed: _search),
          body: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  _Tabs(
                    labels: ['المراجع ${ar(bookmarks.length)}', 'الملاحظات ${ar(notes.length)}'],
                    selected: _notes ? 1 : 0,
                    onSelect: (i) => setState(() => _notes = i == 1),
                  ),
                  Expanded(
                    child: personal == null
                        ? const SizedBox.shrink()
                        : _notes
                        ? (notes.isEmpty ? _empty(c, notes: true) : _notesList(c, personal))
                        : (bookmarks.isEmpty ? _empty(c, notes: false) : _bookmarksList(c, personal)),
                  ),
                ],
              ),
              if (_undo case final deleted?)
                PositionedDirectional(
                  start: 12,
                  end: 12,
                  bottom: ShellInset.of(context),
                  child: UndoSnackbar(key: ValueKey('undo-${deleted.uuid}'), message: deleted.message, onUndo: _restore),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _empty(TzColors c, {required bool notes}) => Padding(
    padding: const EdgeInsets.fromLTRB(36, 56, 36, 0),
    child: Column(
      children: [
        const Khatam('', size: 64),
        const SizedBox(height: 16),
        Text(notes ? 'لم تكتب ملاحظة بعد' : 'لا مراجع بعد', style: TzType.title.copyWith(color: c.ink)),
        const SizedBox(height: 10),
        Text(
          notes
              ? 'اضغط مطوّلًا على أي بيت في المتن، ثم اختر «ملاحظة». تظهر ملاحظاتك هنا بترتيب الأبيات.'
              : 'اضغط مطوّلًا على أي بيت في المتن، ثم اختر «المرجع». تظهر مراجعك هنا بترتيب الأبيات.',
          textAlign: TextAlign.center,
          style: TzType.body.copyWith(color: c.ink2),
        ),
        const SizedBox(height: 18),
        TzButton.tonal(label: 'افتح المتن', icon: 'book', onPressed: () => AppShell.of(context)?.select(DockTab.matn)),
      ],
    ),
  );

  Widget _bookmarksList(TzColors c, PersonalData personal) {
    final matn = reader.content.matn;
    return ListView(
      padding: EdgeInsets.only(bottom: ShellInset.of(context)),
      children: [
        for (final b in personal.bookmarks)
          Dismissible(
            key: ValueKey('${b.uuid}/$_revived'),
            direction: DismissDirection.horizontal,
            background: _DeleteBackground(c, AlignmentDirectional.centerStart),
            secondaryBackground: _DeleteBackground(c, AlignmentDirectional.centerEnd),
            onDismissed: (_) => _delete(() => personal.removeBookmark(b), _bookmark(personal, b)),
            child: SavedRow(
              ribbon: c.bookmarks[b.color.index],
              title: bookmarkLabel(b),
              tag: kBookmarkTagLabels[b.tag]!,
              verse: matn.verse(b.fromVerse).firstHemistich,
              caption: plainName(matn.chapterOfVerse(b.fromVerse).shortLabel),
              onTap: () => _openVerse(b.fromVerse),
              onLongPress: () => _rowActions(
                c,
                onEdit: () => _editBookmark(personal, b),
                onDelete: () => _delete(() => personal.removeBookmark(b), _bookmark(personal, b)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _notesList(TzColors c, PersonalData personal) {
    final matn = reader.content.matn;
    return ListView(
      padding: EdgeInsets.only(bottom: ShellInset.of(context)),
      children: [
        for (final n in personal.notes)
          Dismissible(
            key: ValueKey('${n.uuid}/$_revived'),
            direction: DismissDirection.horizontal,
            background: _DeleteBackground(c, AlignmentDirectional.centerStart),
            secondaryBackground: _DeleteBackground(c, AlignmentDirectional.centerEnd),
            onDismissed: (_) => _delete(() => personal.removeNote(n), _note(personal, n)),
            child: SavedRow(
              title: 'البيت ${ar(n.verse)}',
              body: n.body,
              caption: matn.verse(n.verse).firstHemistich,
              onTap: () => _openVerse(n.verse),
              onLongPress: () => _rowActions(
                c,
                onEdit: () => _editNote(personal, n),
                onDelete: () => _delete(() => personal.removeNote(n), _note(personal, n)),
              ),
            ),
          ),
      ],
    );
  }

  /// A long press on a row: «تعديل» and «حذف».
  Future<void> _rowActions(TzColors c, {required VoidCallback onEdit, required VoidCallback onDelete}) =>
      showModalBottomSheet<void>(
        context: context,
        builder: (sheet) => Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: TzIcon('pen', color: c.lapis),
                  title: Text('تعديل', style: TzType.body.copyWith(color: c.ink)),
                  onTap: () {
                    Navigator.of(sheet).pop();
                    onEdit();
                  },
                ),
                ListTile(
                  leading: TzIcon('trash', color: c.carmine),
                  title: Text('حذف', style: TzType.body.copyWith(color: c.carmine)),
                  onTap: () {
                    Navigator.of(sheet).pop();
                    onDelete();
                  },
                ),
              ],
            ),
          ),
        ),
      );
}

/// The two underline tabs (v2.css .utabs): 24 px apart, a 2 px lapis line under
/// the selected one. The prototype draws them 44 px high; here the row is 48, the
/// smallest target.
class _Tabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  const _Tabs({required this.labels, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    // The hairline lies under the row's last pixel; the chosen tab's 2 px line is drawn over it.
    return DecoratedBox(
      key: SavedScreen.tabsKey,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.lineSoft))),
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 24),
            // Flexible: at the largest system text the two labels share the width.
            Flexible(
              child: Semantics(
                button: true,
                selected: i == selected,
                child: InkWell(
                  onTap: () => onSelect(i),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: TzSize.touchTarget),
                    foregroundDecoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: i == selected ? c.lapis : Colors.transparent, width: 2)),
                    ),
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TzType.label.copyWith(
                        color: i == selected ? c.ink : c.ink3,
                        fontWeight: i == selected ? FontWeight.w600 : FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

/// A saved row (v2.css .bm .inner): 14/20 padding, a 12 px gutter for the
/// ribbon, the title with its tag, the verse in Naskh, a caption; a hairline under it.
class SavedRow extends StatelessWidget {
  final Color? ribbon;
  final String title;
  final String? tag, verse, body;
  final String caption;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  static const ribbonKey = ValueKey('saved-row-ribbon');
  static const tagKey = ValueKey('saved-row-tag');
  static const verseKey = ValueKey('saved-row-verse');
  static const captionKey = ValueKey('saved-row-caption');

  const SavedRow({
    super.key,
    this.ribbon,
    required this.title,
    this.tag,
    this.verse,
    this.body,
    required this.caption,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: BoxDecoration(
          color: c.bg,
          border: Border(bottom: BorderSide(color: c.lineSoft)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ribbon case final color?) ...[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SizedBox(
                  width: 12,
                  child: Align(
                    alignment: AlignmentDirectional.topStart,
                    child: CustomPaint(key: ribbonKey, size: const Size(9, 22), painter: _Ribbon(color)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TzType.head.copyWith(color: c.ink),
                        ),
                      ),
                      if (tag case final word?) ...[const SizedBox(width: 10), _Tag(word, ribbon ?? c.ink2, key: tagKey)],
                    ],
                  ),
                  if (verse case final v?) ...[
                    const SizedBox(height: 2),
                    Text(
                      v,
                      key: verseKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TzType.verse.copyWith(color: c.ink),
                    ),
                  ],
                  if (body case final b?) ...[
                    const SizedBox(height: 2),
                    Text(
                      b,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TzType.body.copyWith(color: c.ink),
                    ),
                  ],
                  Text(
                    caption,
                    key: captionKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TzType.caption.copyWith(color: c.ink3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The tag: a 6 px dot and the word, in the ribbon's colour (v2.css .bm .tag).
class _Tag extends StatelessWidget {
  final String word;
  final Color color;
  const _Tag(this.word, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(word, style: TzType.caption.copyWith(color: color)),
    ],
  );
}

/// What a swipe reveals (v2.css .bm .del): carmine, «حذف» with the bin, 26 px from the start.
class _DeleteBackground extends StatelessWidget {
  final TzColors c;
  final AlignmentGeometry alignment;
  const _DeleteBackground(this.c, this.alignment);

  @override
  Widget build(BuildContext context) => Container(
    color: c.carmine,
    alignment: alignment,
    padding: const EdgeInsets.symmetric(horizontal: 26),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TzIcon('trash', key: SavedScreen.deleteGlyphKey, size: 22, color: c.bg),
        const SizedBox(width: 6),
        Text(
          'حذف',
          style: TzType.caption.copyWith(fontWeight: FontWeight.w600, color: c.bg),
        ),
      ],
    ),
  );
}

/// The ribbon: 9 × 22 with a notch at 74 % (v2.css .bm .rib).
class _Ribbon extends CustomPainter {
  final Color color;
  const _Ribbon(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(w, 0)
        ..lineTo(w, h)
        ..lineTo(w / 2, h * 0.74)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_Ribbon old) => old.color != color;
}
