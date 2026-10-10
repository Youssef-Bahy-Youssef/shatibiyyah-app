// lib/app/personal_data.dart — the student's bookmarks and notes, in memory for the
// UI (ribbons on the page, the home screen) and written through to user.sqlite.
import 'package:flutter/foundation.dart';

import '../data/user_store.dart';


const Map<BookmarkTag, String> kBookmarkTagLabels = {
  BookmarkTag.hifz: 'حفظ',
  BookmarkTag.muraja: 'مراجعة',
  BookmarkTag.ishkal: 'إشكال',
};

class PersonalData extends ChangeNotifier {
  final UserStore store;
  List<Bookmark> _bookmarks = const [];
  List<Note> _notes = const [];

  PersonalData(this.store);

  List<Bookmark> get bookmarks => _bookmarks;
  List<Note> get notes => _notes;

  Future<void> load() async {
    _bookmarks = await store.bookmarks();
    _notes = await store.notes();
    notifyListeners();
  }

  /// The bookmark that starts at [from] and ends at [to] (a single verse when null).
  Bookmark? bookmarkAt(int from, {int? to}) {
    final end = to == null || to == from ? null : to;
    for (final b in _bookmarks) {
      if (b.fromVerse == from && b.toVerse == end) return b;
    }
    return null;
  }

  /// The bookmarks whose verses include [verse] (a single verse or a run), the
  /// most recently changed first. The verse menu and the sheet work on these.
  List<Bookmark> bookmarksCovering(int verse) => [for (final b in _bookmarks) if (b.covers(verse)) b];

  /// Ribbons on the page: the colour of the bookmark starting at each verse
  /// (a run is marked on its first verse).
  Map<int, BookmarkColor> get ribbons => {
        for (final b in _bookmarks.reversed) b.fromVerse: b.color,
      };

  Note? noteFor(int verse) {
    for (final n in _notes) {
      if (n.verse == verse) return n;
    }
    return null;
  }

  Future<void> saveBookmark(int from, {int? to, required BookmarkColor color, required BookmarkTag tag}) async {
    await store.saveBookmark(from, to: to, color: color, tag: tag);
    await load();
  }

  Future<void> deleteBookmark(int from, {int? to}) async {
    await store.deleteBookmark(from, to: to);
    await load();
  }

  /// Changes the colour and tag of [b], keeping its verses and uuid.
  Future<void> updateBookmark(Bookmark b, {required BookmarkColor color, required BookmarkTag tag}) async {
    await store.updateBookmark(b.uuid, color: color, tag: tag);
    await load();
  }

  /// Deletes [b]; [restoreBookmark] brings it back as it was.
  Future<void> removeBookmark(Bookmark b) async {
    // Out of the lists and off the page at once (a swiped row must leave the tree now).
    final before = _bookmarks;
    _bookmarks = [for (final x in _bookmarks) if (x.uuid != b.uuid) x];
    notifyListeners();
    try {
      await store.deleteBookmarkById(b.uuid);
    } catch (_) {
      // Not deleted: back on the page, and the caller says so (F-55).
      _bookmarks = before;
      notifyListeners();
      rethrow;
    }
    await load();
  }

  /// «تراجع» after a delete: the same uuid, verses, colour and tag.
  Future<void> restoreBookmark(Bookmark b) async {
    await store.restoreBookmark(b.uuid);
    await load();
  }

  Future<void> saveNote(int verse, String body) async {
    await store.saveNote(verse, body);
    await load();
  }

  /// Deletes [n]; [restoreNote] brings it back as it was.
  Future<void> removeNote(Note n) async {
    // Out of the list at once (a swiped row must leave the tree now).
    final before = _notes;
    _notes = [for (final x in _notes) if (x.uuid != n.uuid) x];
    notifyListeners();
    try {
      await store.deleteNoteById(n.uuid);
    } catch (_) {
      // Not deleted: back in the list, and the caller says so (F-55).
      _notes = before;
      notifyListeners();
      rethrow;
    }
    await load();
  }

  /// «تراجع» after a delete: the same uuid and text. A note written on the verse
  /// since then stays instead.
  Future<void> restoreNote(Note n) async {
    await store.restoreNote(n.uuid);
    await load();
  }
}
