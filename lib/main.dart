// lib/main.dart — «تيسير الشاطبية».
//
// Boots the v3 reader (lib/app/reader_boot.dart) under the launch splash. Content
// comes from assets/content/content.sqlite, built by `spd app-snapshot` in
// shatibiyyah-data; the 94 manuscript pages are assets/pages/page001–094.webp.
// No audio is bundled: a recording plays from a file on the device. The theme
// (dark espresso or paper) is app-wide and switched from the tools sheet.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:audio_service/audio_service.dart';

import 'app/reader_boot.dart';
import 'services/lock_screen.dart';
import 'theme.dart';
import 'data/settings_store.dart';
import 'ui/design/app_theme.dart';
import 'ui/reader/reader_controller.dart';
import 'ui/reader/reader_screen.dart';
import 'ui/shell/boot_splash.dart';
import 'ui/shell/tour_screen.dart';

/// The lock-screen handler, when the platform service started.
LockScreenHandler? lockScreen;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock screen, notification and headset buttons. Never let an init failure here
  // blank the whole app — the in-app player works regardless.
  try {
    lockScreen = await AudioService.init(
      builder: LockScreenHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'app.shatibiyyah.hirz.channel.audio',
        androidNotificationChannelName: 'تيسير الشاطبية',
        androidNotificationOngoing: true,
      ),
    );
  } catch (_) {}
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ShatibiyyahApp());
}

class ShatibiyyahApp extends StatelessWidget {
  const ShatibiyyahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReaderTheme>(
      valueListenable: appTheme,
      builder: (context, theme, _) => MaterialApp(
        title: 'تيسير الشاطبية',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: C.ink,
          fontFamily: kFontNaskh,
          colorScheme: const ColorScheme.dark(
            surface: C.ink,
            primary: C.gold,
            secondary: C.goldBright,
            onPrimary: C.onGold,
            error: C.danger,
          ),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          extensions: [colorsFor(theme)],
        ),
        // Status and navigation bar icons follow the theme: light on espresso, dark on paper.
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: theme == ReaderTheme.paper ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
          child: Directionality(textDirection: TextDirection.rtl, child: child!),
        ),
        home: const _Boot(),
      ),
    );
  }
}

/// Boot: open the content and build the reader under the launch splash.
class _Boot extends StatefulWidget {
  const _Boot();
  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  ReaderController? _reader;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final reader = await bootReader();
      lockScreen?.attach(reader);
      if (mounted) setState(() => _reader = reader);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  /// The first time only: the tour, then «اختر القارئ» (features-v3 onboarding-tour).
  void _firstRun() {
    final reader = _reader;
    final prefs = reader?.store?.prefs;
    if (reader == null || prefs == null || tourDone(prefs)) return;
    TourScreen.open(context, content: reader.content, library: reader.library, prefs: prefs);
  }

  @override
  Widget build(BuildContext context) {
    return BootSplash(
      ready: _reader != null || _error,
      onGone: _firstRun,
      child: _reader != null
          ? ReaderScreen(reader: _reader!)
          : (_error ? const _ErrorScreen() : const SizedBox.shrink()),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.ink,
      body: Center(
        child: Text(
          'تعذّر تحميل البيانات',
          style: naskh(size: 20, color: C.parch),
        ),
      ),
    );
  }
}
