// «بيت اليوم» (plan 6.2, ADR 0025): one verse a day in order, from verse 1 on the day
// the widget is added. The cases are shared with the widget's own arithmetic on Android.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/domain/daily_verse.dart';

DateTime _day(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

void main() {
  final fixture = json.decode(File('test/fixtures/daily_verse.json').readAsStringSync()) as Map<String, dynamic>;

  for (final c in (fixture['cases'] as List).cast<Map<String, dynamic>>()) {
    test('added ${c['added']}, today ${c['today']}: verse ${c['verse']} (${c['why']})', () {
      expect(dailyVerse(added: _day(c['added'] as String), today: _day(c['today'] as String)), c['verse']);
    });
  }

  test('every day of three rounds is a verse from 1 to 1173, in order', () {
    final added = DateTime(2026, 10, 11);
    for (var d = 0; d < 3 * 1173; d++) {
      final verse = dailyVerse(added: added, today: DateTime(2026, 10, 11 + d));
      expect(verse, d % 1173 + 1, reason: 'day $d');
    }
  });

  test('the hour does not count: one minute before midnight and ten past it are two days', () {
    expect(dailyVerse(added: DateTime(2026, 10, 11, 23, 59), today: DateTime(2026, 10, 12, 0, 10)), 2);
    expect(dailyVerse(added: DateTime(2026, 10, 11, 0, 1), today: DateTime(2026, 10, 11, 23, 59)), 1);
  });

  test('a change of timezone counts the dates the device shows, whatever the hours between', () {
    // Added at 23:30 on the 11th; the traveller's clock then reads 01:00 on the 13th.
    expect(dailyVerse(added: DateTime(2026, 10, 11, 23, 30), today: DateTime(2026, 10, 13, 1)), 3);
    // Flying west, the clock reads the 11th again, earlier in the day than when it was added.
    expect(dailyVerse(added: DateTime(2026, 10, 11, 23, 30), today: DateTime(2026, 10, 11, 9)), 1);
  });

  test('a poem of another length wraps at its own end', () {
    expect(dailyVerse(added: DateTime(2026, 1, 1), today: DateTime(2026, 1, 4), verses: 3), 1);
    expect(dailyVerse(added: DateTime(2026, 1, 1), today: DateTime(2026, 1, 3), verses: 3), 3);
  });
}
