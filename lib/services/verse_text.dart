// lib/services/verse_text.dart — verse text and the legacy search index (port of js/verse-text.js).
//
// The verses now come from content.sqlite (lib/data/legacy_adapter.dart); the
// shatibiyyah.txt parser is retired. The legacy diacritic-insensitive index and
// its highlight mapping stay until search v2 (P6), which uses
// lib/domain/normalizer.dart for parity with the database.

/// ported from verse-text.js: export function isMark(ch)
/// tashkeel (U+0610–061A, U+064B–065F), superscript alef (U+0670), tatweel (U+0640).
bool isMark(String ch) {
  final x = ch.codeUnitAt(0);
  return (x >= 0x610 && x <= 0x61a) ||
      (x >= 0x64b && x <= 0x65f) ||
      x == 0x670 ||
      x == 0x640;
}

// ported from verse-text.js: foldAlef(ch)
String _foldAlef(String ch) =>
    (ch == 'آ' || ch == 'أ' || ch == 'إ' || ch == 'ٱ') ? 'ا' : ch;

class VerseLine {
  final int id;
  final String sadr;
  final String ajuz;
  final String text;
  const VerseLine(this.id, this.sadr, this.ajuz, this.text);
}

class IndexEntry {
  final int id;
  final String sadr;
  final String ajuz;
  final String text;
  final String norm; // _norm
  const IndexEntry(this.id, this.sadr, this.ajuz, this.text, this.norm);
}

/// ported from verse-text.js: export function normalize(str)
String normalize(String str) {
  final out = StringBuffer();
  bool pendingSpace = false;
  bool started = false;
  for (int i = 0; i < str.length; i++) {
    final ch = str[i];
    if (isMark(ch)) continue;
    if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
      if (started) pendingSpace = true;
      continue;
    }
    if (pendingSpace) {
      out.write(' ');
      pendingSpace = false;
    }
    out.write(_foldAlef(ch));
    started = true;
  }
  return out.toString();
}

class NormMap {
  final String norm;
  final List<int> map;
  const NormMap(this.norm, this.map);
}

/// ported from verse-text.js: export function normalizeWithMap(str)
NormMap normalizeWithMap(String str) {
  final norm = StringBuffer();
  final map = <int>[];
  bool pendingSpace = false;
  int pendingSpaceAt = 0;
  bool started = false;
  for (int i = 0; i < str.length; i++) {
    final ch = str[i];
    if (isMark(ch)) continue;
    if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
      if (started && !pendingSpace) {
        pendingSpace = true;
        pendingSpaceAt = i;
      }
      continue;
    }
    if (pendingSpace) {
      norm.write(' ');
      map.add(pendingSpaceAt);
      pendingSpace = false;
    }
    norm.write(_foldAlef(ch));
    map.add(i);
    started = true;
  }
  return NormMap(norm.toString(), map);
}

/// ported from verse-text.js: { list, byId, index }
class VerseTextData {
  final List<VerseLine> list;
  final Map<int, VerseLine> byId;
  final List<IndexEntry> index;
  const VerseTextData(this.list, this.byId, this.index);
  static VerseTextData empty() => const VerseTextData([], {}, []);
}

/// Builds the lines and the legacy search index from verse halves.
VerseTextData verseTextFromLines(List<VerseLine> list) {
  final byId = {for (final v in list) v.id: v};
  final index = list
      .map((v) => IndexEntry(v.id, v.sadr, v.ajuz, v.text, normalize(v.text)))
      .toList(growable: false);
  return VerseTextData(list, byId, index);
}
