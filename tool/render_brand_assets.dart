// tool/render_brand_assets.dart — draws the app icons and the Android launch logo
// from TaysirLogoPainter, so the platform assets match the in-app logo exactly.
//
//   flutter test tool/render_brand_assets.dart
//
// Writes (and overwrites):
//   android  mipmap-*/ic_launcher.png             legacy icon: the logo on a rounded espresso tile
//            mipmap-*/ic_launcher_foreground.png  adaptive foreground: the logo, 54 of 108 dp
//            mipmap-*/ic_launcher_background.png  adaptive background: the espresso gradient
//            drawable-xxhdpi/splash_logo.png      pre-Android-12 launch logo (128 dp)
//   ios      LaunchImage.imageset/*.png           the launch-screen logo (128 pt)
//   ios      AppIcon.appiconset/*.png             full-bleed square tiles (iOS rounds them);
//                                                 tool/flatten_ios_icons.py then drops the alpha
//                                                 channel, which App Store icons may not carry
// It lives in tool/, so `flutter test` without a path does not run it.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/taysir_logo.dart';

const _android = 'android/app/src/main/res';
const _ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
const _launch = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
const _densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};

/// The tile behind the logo: the prototype's `radial-gradient(120% 100% at 50% 20%, #3F2F15, #1B1307 70%)`.
void _tile(Canvas c, double s, {double radius = 0}) {
  final rect = Rect.fromLTWH(0, 0, s, s);
  final paint = Paint()
    ..shader = ui.Gradient.radial(
      Offset(s / 2, s * 0.2),
      s * 1.1,
      const [Color(0xFF3F2F15), Color(0xFF1B1307)],
      const [0, 0.7],
    );
  c.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)), paint);
}

void _logo(Canvas c, double size, Offset at) {
  c.save();
  c.translate(at.dx, at.dy);
  const TaysirLogoPainter().paint(c, Size.square(size));
  c.restore();
}

Future<void> _png(String path, int px, void Function(Canvas c, double s) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder), px.toDouble());
  final image = await recorder.endRecording().toImage(px, px);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
  stdout.writeln('wrote $path ($px px)');
}

void main() {
  testWidgets('render brand assets', (tester) async {
    await tester.runAsync(() async {
      for (final MapEntry(key: name, value: d) in _densities.entries) {
        final dir = '$_android/mipmap-$name';
        // Legacy launcher icon (48 dp): the prototype's `icon` variant.
        await _png('$dir/ic_launcher.png', (48 * d).round(), (c, s) {
          _tile(c, s, radius: s * 0.23);
          _logo(c, s * 0.74, Offset(s * 0.13, s * 0.13));
        });
        // Adaptive icon layers (108 dp; the launcher masks the middle 72 dp).
        await _png('$dir/ic_launcher_foreground.png', (108 * d).round(), (c, s) {
          _logo(c, s * 0.5, Offset(s * 0.25, s * 0.25));
        });
        await _png('$dir/ic_launcher_background.png', (108 * d).round(), (c, s) => _tile(c, s));
      }
      await _png('$_android/drawable-xxhdpi/splash_logo.png', 128 * 3, (c, s) => _logo(c, s, Offset.zero));
      for (final (suffix, scale) in [('', 1), ('@2x', 2), ('@3x', 3)]) {
        await _png('$_launch/LaunchImage$suffix.png', 128 * scale, (c, s) => _logo(c, s, Offset.zero));
      }

      final contents = jsonDecode(File('$_ios/Contents.json').readAsStringSync()) as Map<String, dynamic>;
      for (final icon in (contents['images'] as List).cast<Map<String, dynamic>>()) {
        final points = double.parse((icon['size'] as String).split('x').first);
        final scale = int.parse((icon['scale'] as String).replaceAll('x', ''));
        await _png('$_ios/${icon['filename']}', (points * scale).round(), (c, s) {
          _tile(c, s);
          _logo(c, s * 0.74, Offset(s * 0.13, s * 0.13));
        });
      }
    });
  });
}
