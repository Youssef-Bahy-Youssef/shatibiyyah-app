// lib/app/recent_searches.dart — the last queries of «البحث» (search v2), newest
// first, kept in the preferences. A query is remembered when it is submitted or a
// result of it is opened; one differing only in vowel marks or hamza seats
// replaces the older one.
import 'dart:convert';

import '../domain/normalizer.dart';
import '../services/preferences_service.dart';

const String kRecentSearchesPref = 'v2.search.recent';
const int kMaxRecentSearches = 8;

class RecentSearches {
  final Prefs prefs;
  RecentSearches(this.prefs);

  List<String> get all {
    try {
      return (jsonDecode(prefs.getLS(kRecentSearchesPref, '[]')) as List).cast<String>();
    } on Object {
      return const [];
    }
  }

  void add(String query) {
    final q = query.trim();
    final key = normalizeMatching(q);
    if (key.isEmpty) return;
    final list = [q, for (final old in all) if (normalizeMatching(old) != key) old];
    prefs.setLS(kRecentSearchesPref, jsonEncode(list.take(kMaxRecentSearches).toList()));
  }

  void clear() => prefs.setLS(kRecentSearchesPref, '[]');
}
