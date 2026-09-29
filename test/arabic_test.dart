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
}
