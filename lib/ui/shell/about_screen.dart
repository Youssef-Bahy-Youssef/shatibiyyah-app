// lib/ui/shell/about_screen.dart — «حول» (features-v3 about-and-support): the app
// icon, name, the poem's title, version, a one-line description and «أعد الجولة».
// «أرسل ملاحظة» waits for a support address.
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

import '../../theme.dart' show kufi, naskh;
import '../design/taysir_colors.dart';
import '../design/taysir_logo.dart';
import '../reader/reader_controller.dart';
import 'debug_tools_screen.dart';
import 'shell_page.dart';
import 'tour_screen.dart';

/// The app version shown to users; test/app_version_test.dart keeps it equal to pubspec's.
const String kAppVersion = '1.0.0';

/// «الإصدار ١٫٠٫٠».
String versionLabel(String version) {
  const digits = '٠١٢٣٤٥٦٧٨٩';
  final arabic = version.split('').map((c) {
    final d = int.tryParse(c);
    return d != null ? digits[d] : (c == '.' ? '٫' : c);
  }).join();
  return 'الإصدار $arabic';
}

class AboutScreen extends StatelessWidget {
  /// For «أعد الجولة» (null: no replay, e.g. in tests).
  final ReaderController? reader;
  const AboutScreen({super.key, this.reader});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return ShellPage(
      title: 'حول',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          const Center(child: TaysirLogo(size: 104, variant: LogoVariant.icon)),
          const SizedBox(height: 18),
          Text(
            'تيسير الشاطبية',
            textAlign: TextAlign.center,
            style: kufi(size: 24, weight: 600, color: t.text),
          ),
          Text(
            'حِرْزُ الأَمَانِي وَوَجْهُ التَّهَانِي',
            textAlign: TextAlign.center,
            style: naskh(size: 18, color: t.goldText, height: 1.8),
          ),
          Text(
            versionLabel(kAppVersion),
            textAlign: TextAlign.center,
            style: kufi(size: 13, weight: 400, color: t.muted),
          ),
          const SizedBox(height: 18),
          Text(
            'رفيق لدراسة متن الشاطبية وحفظه: المخطوط، والتلاوة بيتًا بيتًا، والشروح الثلاثة. يعمل دون اتصال.',
            textAlign: TextAlign.center,
            style: kufi(size: 15, weight: 400, color: t.dim, height: 1.7),
          ),
          if (reader?.store != null) ...[
            const SizedBox(height: 24),
            Center(
              child: OutlinedButton(
                onPressed: () => TourScreen.open(
                  context,
                  content: reader!.content,
                  library: reader!.library,
                  prefs: reader!.store!.prefs,
                  replay: true,
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  side: BorderSide(color: t.line),
                  shape: const StadiumBorder(),
                ),
                child: Text('أعد الجولة', style: kufi(size: 14.5, weight: 500, color: t.text)),
              ),
            ),
          ],
          // Debug and profile builds only (Android Studio): the test tools. Never in
          // the release build that goes to the store.
          if (!kReleaseMode && reader != null) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => DebugToolsScreen(reader: reader!))),
                child: Text('أدوات التجربة', style: kufi(size: 13.5, weight: 500, color: t.goldText)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
