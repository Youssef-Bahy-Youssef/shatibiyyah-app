// lib/ui/shell/about_screen.dart — «حول» (features-v3 about-and-support).
//
// The app's icon, its name and the poem's title over a gilt rule, and one line
// saying what the app is; then what is in it, read from the content (the matn's
// verses and chapters, the books, the reciters), «أعد الجولة», and the version.
// The groups are «الإعدادات»'s rows. «أرسل ملاحظة» waits for a support address.
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

import '../../data/app_content.dart';
import '../../utils/arabic.dart';
import '../design/components/ornament.dart';
import '../design/components/settings_row.dart';
import '../design/tokens.g.dart';
import '../design/taysir_logo.dart';
import '../design/tz_theme.dart';
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
  /// For what is in the app and «أعد الجولة» (null: neither, e.g. in tests).
  final ReaderController? reader;
  const AboutScreen({super.key, this.reader});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final r = reader;
    return ShellPage(
      title: 'حول',
      body: ListView(
        padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          const _Masthead(),
          if (r != null) _Contents(content: r.content),
          if (r?.store case final store?)
            SettingsGroup(title: 'التعريف بالتطبيق', rows: [
              SettingsRow(
                icon: 'retry',
                label: 'أعد الجولة',
                caption: 'بطاقات قصيرة تعرّفك بالتطبيق',
                onTap: () => TourScreen.open(
                  context,
                  content: r!.content,
                  library: r.library,
                  prefs: store.prefs,
                  replay: true,
                ),
              ),
            ]),
          // Debug and profile builds only (Android Studio): the test tools. Never in
          // the release build that goes to the store.
          if (!kReleaseMode && r != null)
            SettingsGroup(title: 'نسخة التطوير', rows: [
              SettingsRow(
                icon: 'gear',
                label: 'أدوات التجربة',
                caption: 'لا تظهر في نسخة المتجر',
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DebugToolsScreen(reader: r))),
              ),
            ]),
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text(
              versionLabel(kAppVersion),
              textAlign: TextAlign.center,
              style: TzType.caption.copyWith(color: c.ink3),
            ),
          ),
        ],
      ),
    );
  }
}

/// The icon, the app's name, the poem's title, the gilt rule and the one line.
class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 6),
      child: Column(
        children: [
          const TaysirLogo(size: 92, variant: LogoVariant.icon),
          const SizedBox(height: 18),
          Semantics(
            header: true,
            child: Text('تيسير الشاطبية', textAlign: TextAlign.center, style: TzType.display.copyWith(color: c.ink)),
          ),
          Text(
            'حِرْزُ الأَمَانِي وَوَجْهُ التَّهَانِي',
            textAlign: TextAlign.center,
            style: TzType.chapter.copyWith(color: c.ink2),
          ),
          const SizedBox(height: 10),
          const GiltRule(centered: true),
          const SizedBox(height: 10),
          Text(
            'رفيقك لدراسة متن الشاطبية وحفظها، بتلاوة صوتية بيتًا بيتًا، وشروح تعينك على فهم كل بيت',
            textAlign: TextAlign.center,
            style: TzType.body.copyWith(color: c.ink2),
          ),
        ],
      ),
    );
  }
}

/// «في التطبيق»: the matn, the books and the reciters, as the content names them.
class _Contents extends StatelessWidget {
  final AppContent content;
  const _Contents({required this.content});

  @override
  Widget build(BuildContext context) {
    final matn = content.matn;
    return SettingsGroup(title: 'في التطبيق', rows: [
      SettingsRow.info(
        icon: 'book',
        label: 'المتن',
        caption: '${versesCount(matn.lastVerse)} في ${chaptersCount(matn.chapters.length)}، بعرض الصفحة أو النص',
      ),
      SettingsRow.info(
        icon: 'pen',
        label: 'الشروح',
        caption: content.books.books.map((b) => b.shortTitle).join(' · '),
      ),
      SettingsRow.info(
        icon: 'listen',
        label: 'التلاوة',
        caption: content.recordings.recordings.map((r) => r.reciterName).join(' · '),
      ),
    ]);
  }
}
