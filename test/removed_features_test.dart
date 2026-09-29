// P4 acceptance: the features removed from v2 (plan rev. 2) have no entry point
// anywhere in the app: «اختبار» (quiz), «تفكيك البيت», «خلاصة القراءات».
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no «اختبار», «تفكيك البيت» or «خلاصة القراءات» in lib/', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (RegExp('اختبار|تفكيك البيت|خلاصة القراءات').hasMatch(lines[i])) hits.add('${f.path}:${i + 1}');
      }
    }
    expect(hits, isEmpty);
  });
}
