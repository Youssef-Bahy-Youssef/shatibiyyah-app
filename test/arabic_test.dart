import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/utils/arabic.dart';

void main() {
  test('versesCount: the noun agrees with the number', () {
    expect(versesCount(1), 'بيت واحد');
    expect(versesCount(2), 'بيتان');
    expect(versesCount(3), '٣ أبيات');
    expect(versesCount(10), '١٠ أبيات');
    expect(versesCount(11), '١١ بيتًا');
    expect(versesCount(94), '٩٤ بيتًا');
    expect(versesCount(100), '١٠٠ بيت');
    expect(versesCount(101), '١٠١ بيت');
    expect(versesCount(103), '١٠٣ أبيات');
    expect(versesCount(1173), '١١٧٣ بيتًا');
  });

  test('chapter ordinals: «الباب الحادي عشر» and the rest, 1…77', () {
    expect(chapterOrdinal(1), 'الباب الأول');
    expect(chapterOrdinal(2), 'الباب الثاني');
    expect(chapterOrdinal(3), 'الباب الثالث');
    expect(chapterOrdinal(10), 'الباب العاشر');
    expect(chapterOrdinal(11), 'الباب الحادي عشر');
    expect(chapterOrdinal(12), 'الباب الثاني عشر');
    expect(chapterOrdinal(19), 'الباب التاسع عشر');
    expect(chapterOrdinal(20), 'الباب العشرون');
    expect(chapterOrdinal(21), 'الباب الحادي والعشرون');
    expect(chapterOrdinal(33), 'الباب الثالث والثلاثون');
    expect(chapterOrdinal(70), 'الباب السبعون');
    expect(chapterOrdinal(77), 'الباب السابع والسبعون');
  });
}
