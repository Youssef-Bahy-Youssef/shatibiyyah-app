// lib/ui/shell/about_screen.dart — «حول» (features-v3 about-and-support).
//
// The app's icon, its name and the poem's title over a gilt rule, and one line
// saying what the app is; then what is in it, read from the content (the matn's
// verses and chapters, the books, the reciters) and ending with the student's
// own bookmarks and notes, which stay on the device (ADR 0033); then «رأيك
// ودعمك», «أعد الجولة», and the version. The groups are «الإعدادات»'s rows.
//
// «رأيك ودعمك» has a row for each place the app can point to (lib/app/app_links.dart):
//   أرسل ملاحظة    a letter to the support address, in the device's mail app
//   شارك التطبيق   the app's line and its store page, through the system's sheet
//   قيّم التطبيق    the store page itself
// A row with nowhere to go is not drawn.
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_links.dart';
import '../../app/rating.dart';
import '../../data/app_content.dart';
import '../../services/device_storage.dart';
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

/// Opens [uri] outside the app; false when nothing on the device takes it.
typedef LinkOpener = Future<bool> Function(Uri uri);

/// Hands the app's line to the system's share sheet.
typedef AppShare = Future<void> Function(ShareParams params);

Future<bool> _openOutside(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on PlatformException {
    return false;
  }
}

Future<void> _systemShare(ShareParams params) async => SharePlus.instance.share(params);

class AboutScreen extends StatelessWidget {
  /// For what is in the app and «أعد الجولة» (null: neither, e.g. in tests).
  final ReaderController? reader;

  /// Where «رأيك ودعمك» points (null: where this platform's build points).
  final AppLinks? links;

  /// The device's hands, replaceable in tests.
  final LinkOpener open;
  final AppShare share;
  final Future<String> Function() system;

  const AboutScreen({
    super.key,
    this.reader,
    this.links,
    this.open = _openOutside,
    this.share = _systemShare,
    this.system = deviceSystem,
  });

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
          _Support(
            links: links ?? AppLinks.ofPlatform(),
            open: open,
            share: share,
            system: system,
            content: r?.content,
            rating: r?.rating,
          ),
          if (r?.store case final store?)
            SettingsGroup(title: 'التعريف بالتطبيق', rows: [
              SettingsRow(
                icon: 'retry',
                label: 'أعد الجولة',
                caption: 'ثلاث بطاقات على صفحة من المتن',
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
            '$kAppLine يعمل دون اتصال.',
            textAlign: TextAlign.center,
            style: TzType.body.copyWith(color: c.ink2),
          ),
        ],
      ),
    );
  }
}

/// «في التطبيق»: the matn, the books and the reciters, as the content names them,
/// and what the student adds to them.
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
        caption: '${versesCount(matn.lastVerse)} في ${chaptersCount(matn.chapters.length)}، بصفحاته وبالنص',
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
      // The one promise on the screen. What keeps it true is listed in ADR 0033 and
      // held by test/privacy_test.dart.
      const SettingsRow.info(icon: 'bookmark', label: 'مراجعك وملاحظاتك', caption: 'تبقى على جهازك'),
    ]);
  }
}

/// «رأيك ودعمك»: a note to the support address, the app's page sent on, and the
/// same page opened to rate it.
class _Support extends StatelessWidget {
  final AppLinks links;
  final LinkOpener open;
  final AppShare share;
  final Future<String> Function() system;
  final AppContent? content;
  final RatingPrompt? rating;

  const _Support({
    required this.links,
    required this.open,
    required this.share,
    required this.system,
    required this.content,
    required this.rating,
  });

  static void _say(ScaffoldMessengerState? messenger, String message) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 5)));

  Future<void> _note(BuildContext context, String address) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final letter = feedbackMail(
      address: address,
      version: kAppVersion,
      content: content?.store.manifest.contentSha256.substring(0, 8),
      system: await system(),
    );
    if (await open(letter)) return;
    // No mail app on the device: the address itself, to write to from wherever they do.
    await Clipboard.setData(ClipboardData(text: address));
    _say(messenger, 'لا تطبيق بريد على الجهاز. نُسخ العنوان: $address');
  }

  Future<void> _share(BuildContext row, Uri listing) {
    final box = row.findRenderObject() as RenderBox?;
    return share(ShareParams(
      text: shareAppText(listing),
      subject: 'تيسير الشاطبية',
      // An iPad hangs its sheet on the row.
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
  }

  Future<void> _rate(BuildContext context, Uri review) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (await open(review)) {
      rating?.openedListing();
    } else {
      _say(messenger, 'تعذّر فتح ${links.storeName ?? 'المتجر'}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    // The sprite draws neither an envelope nor a star: Lucide's, at the weight
    // nearest the sprite's 1.6 stroke.
    Widget glyph(IconData icon) => Icon(icon, size: 20, color: c.ink3);
    final rows = [
      if (links.supportEmail case final address?)
        SettingsRow(
          leading: glyph(LucideIcons.mail300),
          label: 'أرسل ملاحظة',
          caption: 'بالبريد: خطأ وجدته، أو اقتراح',
          onTap: () => _note(context, address),
        ),
      if (links.listing case final listing?)
        Builder(
          builder: (row) => SettingsRow(
            icon: 'share',
            label: 'شارك التطبيق',
            caption: 'أرسل رابطه إلى من ينتفع به',
            onTap: () => _share(row, listing),
          ),
        ),
      if (links.review case final review?)
        SettingsRow(
          leading: glyph(LucideIcons.star300),
          label: 'قيّم التطبيق',
          caption: 'في ${links.storeName ?? 'المتجر'}',
          onTap: () => _rate(context, review),
        ),
    ];
    return rows.isEmpty ? const SizedBox.shrink() : SettingsGroup(title: 'رأيك ودعمك', rows: rows);
  }
}
