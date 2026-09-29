// Paragraph layout of commentary segments: sentence-end cuts, verse-echo stripping,
// footnote markers split out at their anchors, no text lost.
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/data/commentary_repository.dart';
import 'package:shatibiyyah/domain/commentary_text.dart';

Footnote note(String marker, int? anchor) => Footnote('f$marker', 's', 0, marker, anchor, 'حاشية $marker');

void main() {
  test('short text is one paragraph', () {
    final ps = layoutSegment('قال الناظم كذا. ثم قال.', const []);
    expect(ps, hasLength(1));
    expect(ps.single.plainText, 'قال الناظم كذا. ثم قال.');
  });

  test('long text breaks only at sentence ends, and loses nothing but the break spaces', () {
    final sentence = '${'كلمة ' * 30}انتهت.';
    final text = List.filled(6, sentence).join(' ');
    final ps = layoutSegment(text, const [], target: 300);
    expect(ps.length, greaterThan(1));
    for (final p in ps) {
      expect(p.plainText.trimRight(), endsWith('.'));
    }
    expect(ps.map((p) => p.plainText).join(' '), text);
  });

  test('a verse echo at the start is dropped and anchors follow the shift', () {
    const text = '٢٢٩ - وشىء وشيئا لم يزد....... اختلف الرواة عن حمزة (١) في الوقف.';
    final anchor = text.indexOf('(١)') + 1;
    final ps = layoutSegment(text, [note('١', anchor)]);
    expect(ps.single.plainText, startsWith('اختلف الرواة'));
    final marker = ps.single.runs.singleWhere((r) => r.isMarker);
    expect(marker.text, '١');
  });

  test('bare markers become their own runs', () {
    const text = 'قال تعالى: {وَالْأَرْضِ} ١. أي: كذا بورش٢ وغيره.';
    final ps = layoutSegment(text, [note('١', text.indexOf('١')), note('٢', text.indexOf('٢'))]);
    final runs = ps.single.runs;
    expect(runs.where((r) => r.isMarker).map((r) => r.text), ['١', '٢']);
    expect(runs.map((r) => r.text).join(), text);
  });

  test('an anchor that does not sit on its marker is ignored, not misplaced', () {
    const text = 'نص بلا علامة هنا.';
    final ps = layoutSegment(text, [note('٣', 2)]);
    expect(ps.single.runs.any((r) => r.isMarker), isFalse);
  });
}
