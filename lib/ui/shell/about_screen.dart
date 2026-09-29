// lib/ui/shell/about_screen.dart — «حول» (features-v3 about-and-support): the app
// icon, name, the poem's title, version and a one-line description. «أرسل ملاحظة»
// waits for a support address and «أعد الجولة» for the tour (P5).
import 'package:flutter/material.dart';

import '../../theme.dart' show kufi, naskh;
import '../design/taysir_colors.dart';
import '../design/taysir_logo.dart';
import 'shell_page.dart';

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
  const AboutScreen({super.key});

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
        ],
      ),
    );
  }
}
