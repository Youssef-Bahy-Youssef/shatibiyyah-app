// lib/app/personal_data.dart — the student's bookmarks and notes, in memory for the
// UI (ribbons on the page, the home screen) and written through to user.sqlite.
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

import '../data/user_store.dart';

/// The prototype's six bookmark colours.
const Map<BookmarkColor, Color> kBookmarkColors = {
  BookmarkColor.gold: Color(0xFFFFAB2E),
  BookmarkColor.green: Color(0xFF86B07A),
  BookmarkColor.orange: Color(0xFFE08A5A),
  BookmarkColor.blue: Color(0xFFAABAFF),
  BookmarkColor.rose: Color(0xFFD98C9A),
  BookmarkColor.sand: Color(0xFFD6CCB8),
};

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
  Map<int, Color> get ribbons => {
        for (final b in _bookmarks.reversed) b.fromVerse: kBookmarkColors[b.color]!,
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
}
