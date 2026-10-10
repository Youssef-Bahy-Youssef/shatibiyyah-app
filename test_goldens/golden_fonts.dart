// The app's real fonts for golden tests (flutter_test draws text in a box font
// otherwise): Scheherazade New, IBM Plex Sans Arabic and the Lucide icon font.
import 'package:flutter/services.dart';

Future<void> loadGoldenFonts() async {
  Future<void> family(String name, List<String> assets) async {
    final loader = FontLoader(name);
    for (final a in assets) {
      loader.addFont(rootBundle.load(a));
    }
    await loader.load();
  }

  await family('ScheherazadeNew', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/ScheherazadeNew-$w.ttf',
  ]);
  await family('IBMPlexSansArabic', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/IBMPlexSansArabic-$w.ttf',
  ]);
  await family('packages/lucide_icons_flutter/Lucide', ['packages/lucide_icons_flutter/assets/lucide.ttf']);
}
