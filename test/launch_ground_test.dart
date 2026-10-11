// The native launch ground (ADR 0028). Before Flutter draws its first frame both
// platforms show the logo on one colour, and the in-app splash that follows is the
// night ground in both themes. The native projects cannot read the tokens, so this
// holds their copies of that colour to `TzColors.night.bg`.
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';

List<int> _rgb(Color c) => [for (final v in [c.r, c.g, c.b]) (v * 255).round()];

void main() {
  final ground = _rgb(TzColors.night.bg);
  const res = 'android/app/src/main/res';

  test('Android: the launch colour is the night ground', () {
    final xml = File('$res/values/colors.xml').readAsStringSync();
    final colours = {
      for (final m in RegExp(r'<color name="(\w+)">#([0-9A-Fa-f]{6})</color>').allMatches(xml))
        m.group(1)!: [for (var i = 0; i < 6; i += 2) int.parse(m.group(2)!.substring(i, i + 2), radix: 16)],
    };
    expect(colours, {'launch_ground': ground});
  });

  test('Android: every launch and window background is that colour', () {
    for (final file in ['values/styles.xml', 'values-v31/styles.xml', 'drawable/launch_background.xml']) {
      final xml = File('$res/$file').readAsStringSync();
      final used = {for (final m in RegExp(r'@color/(\w+)').allMatches(xml)) m.group(1)};
      expect(used, {'launch_ground'}, reason: file);
    }
  });

  test('iOS: the launch screen is the night ground', () {
    final xml = File('ios/Runner/Base.lproj/LaunchScreen.storyboard').readAsStringSync();
    final backgrounds = RegExp(
      r'<color key="backgroundColor" red="([0-9.]+)" green="([0-9.]+)" blue="([0-9.]+)" alpha="1" '
      r'colorSpace="custom" customColorSpace="sRGB"/>',
    ).allMatches(xml).toList();
    expect(backgrounds, hasLength(1));
    expect([for (var i = 1; i <= 3; i++) (double.parse(backgrounds.single.group(i)!) * 255).round()], ground);
  });
}
