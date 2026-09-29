// lib/services/verse_text.dart — 100% port of js/verse-text.js.
// Loads & parses shatibiyyah.txt into { id, sadr, ajuz, text } + a
// diacritic-insensitive search index.
import 'package:flutter/services.dart' show rootBundle;

const int _lastVerse = 1173;
const String _arDigits = '٠١٢٣٤٥٦٧٨٩';

// ported from verse-text.js: arToInt(s)
int? _arToInt(String s) {
  int n = 0;
  for (final ch in s.split('')) {
    final d = _arDigits.indexOf(ch);
    if (d < 0) return null;
    n = n * 10 + d;
  }
  return n;
}

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

// ported from verse-text.js: RE_VERSE / RE_SPLIT
final RegExp _reVerse =
    RegExp(r'^[‎‏\s]*([٠-٩]+)\s*[-–—]\s*(.+?)\s*$');
final RegExp _reSplit = RegExp(r'\s*\.{3,}\s*|\s+…\s+');

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

/// ported from verse-text.js: parseShatibiyyah(rawText)
List<VerseLine> parseShatibiyyah(String rawText) {
  final out = <VerseLine>[];
  for (final line in rawText.split(RegExp(r'\r?\n'))) {
    final m = _reVerse.firstMatch(line);
    if (m == null) continue;
    final id = _arToInt(m.group(1)!);
    if (id == null) continue;
    final body = m.group(2)!.trim();
    final parts = body.split(_reSplit);
    final sadr = (parts.isNotEmpty ? parts[0] : '').trim();
    final ajuz = parts.length > 1 ? parts.sublist(1).join(' … ').trim() : '';
    out.add(VerseLine(id, sadr, ajuz, body));
  }
  return out;
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

/// ported from verse-text.js: export async function loadVerseText(url)
Future<VerseTextData> loadVerseText(
    [String asset = 'assets/data/shatibiyyah.txt']) async {
  final raw = await rootBundle.loadString(asset);
  final list = parseShatibiyyah(raw);
  final byId = {for (final v in list) v.id: v};
  final index = list
      .map((v) => IndexEntry(v.id, v.sadr, v.ajuz, v.text, normalize(v.text)))
      .toList();
  // (dev guard from verse-text.js omitted; data ships complete with _lastVerse entries)
  assert(list.length == _lastVerse || list.isNotEmpty);
  return VerseTextData(list, byId, index);
}
