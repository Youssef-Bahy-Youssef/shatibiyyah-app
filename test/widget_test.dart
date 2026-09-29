// Unit tests for the trickiest pure-logic ports (no platform / no timers).
import 'package:flutter_test/flutter_test.dart';

import 'package:shatibiyyah/utils/arabic.dart';
import 'package:shatibiyyah/services/verse_text.dart';
import 'package:shatibiyyah/models/playback_settings.dart';

void main() {
  group('ar() — Arabic-Indic numerals (app.js AR)', () {
    test('integers', () {
      expect(ar(1), '١');
      expect(ar(1173), '١١٧٣');
      expect(ar(0), '٠');
    });
    test('speeds use the Arabic decimal separator, ≤2 frac digits', () {
      expect(ar(0.5), '٠٫٥');
      expect(ar(0.75), '٠٫٧٥');
      expect(ar(1.25), '١٫٢٥');
      expect(ar(2), '٢');
    });
  });

  group('fmtTime() (app.js)', () {
    test('m:ss with padded Arabic seconds', () {
      expect(fmtTime(0), '٠:٠٠');
      expect(fmtTime(65), '١:٠٥');
      expect(fmtTime(8916), '١٤٨:٣٦');
    });
  });

  group('normalize() — diacritic/alef/tatweel-insensitive (verse-text.js)', () {
    test('drops tashkeel', () {
      expect(normalize('بَدَأْتُ'), 'بدات');
    });
    test('folds alef variants to bare alef (but not alef-maqsura ى)', () {
      expect(normalize('أسماء'), normalize('اسماء'));
      expect(normalize('إلى'), 'الى'); // verse-text.js foldAlef leaves ى unchanged
    });
    test('collapses whitespace', () {
      expect(normalize('  ا   ب  '), 'ا ب');
    });
  });

  group('normalizeWithMap() position mapping (app.js appendHighlighted)', () {
    test('map points back to original indices', () {
      final nm = normalizeWithMap('بَدَأْتُ');
      expect(nm.norm, 'بدات');
      // first kept char (ب) is at original index 0
      expect(nm.map.first, 0);
      expect(nm.map.length, nm.norm.length);
    });
  });

  group('repToStore / repFromStore (audio.js)', () {
    test('infinity round-trips as "inf"', () {
      expect(repToStore(double.infinity), 'inf');
      expect(repFromStore('inf', 1), double.infinity);
    });
    test('finite values', () {
      expect(repToStore(5), '5');
      expect(repFromStore('5', 1), 5);
      expect(repFromStore(null, 3), 3);
    });
  });

  group('parseShatibiyyah (verse-text.js)', () {
    test('parses an Arabic-numbered verse line into sadr/ajuz', () {
      const line = '٣٤٧ - صدر البيت ... عجز البيت';
      final out = parseShatibiyyah(line);
      expect(out.length, 1);
      expect(out.first.id, 347);
      expect(out.first.sadr, 'صدر البيت');
      expect(out.first.ajuz, 'عجز البيت');
    });
  });
}
