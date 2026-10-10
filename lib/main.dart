// lib/main.dart — «تيسير الشاطبية».
//
// Boots the v3 reader (lib/app/reader_boot.dart) under the launch splash. Content
// comes from assets/content/content.sqlite, built by `spd app-snapshot` in
// shatibiyyah-data; the 94 manuscript pages are assets/pages/page001–094.webp.
// No audio is bundled: a recording plays from a file on the device. The theme
// (dark espresso or paper) is app-wide and switched from the tools sheet.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:audio_service/audio_service.dart';

import 'app/reader_boot.dart';
import 'app/reminders.dart';
import 'services/lock_screen.dart';
import 'ui/design/tokens.g.dart';
import 'data/settings_store.dart';
import 'ui/design/app_theme.dart';
import 'ui/design/components/dock.dart' show DockTab;
import 'ui/shell/app_shell.dart';
import 'ui/design/tz_theme.dart';
import 'ui/reader/reader_controller.dart';
import 'ui/shell/boot_splash.dart';
import 'ui/shell/tour_screen.dart';
import 'ui/design/taysir_colors.dart';

/// The lock-screen handler, when the platform service started.
LockScreenHandler? lockScreen;

/// The app's navigator: a tapped reminder opens its verse from outside the tree.
final GlobalKey<NavigatorState> appNavigator = GlobalKey<NavigatorState>();

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
  applyOrientationPolicy();
  runApp(const ShatibiyyahApp());
  // The window's size may be known only once the first frame is laid out.
  WidgetsBinding.instance.addPostFrameCallback((_) => applyOrientationPolicy());
}

/// Phones stay upright; a tablet (shortest side from 600 dp, plan P8) turns freely,
/// so the page and its commentary can stand side by side in landscape.
void applyOrientationPolicy() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return;
  final view = views.first;
  final shortest = view.physicalSize.shortestSide / view.devicePixelRatio;
  SystemChrome.setPreferredOrientations(shortest >= kTabletShortestSide
      ? DeviceOrientation.values
      : const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
}

/// The shortest side (dp) from which the device counts as a tablet.
const double kTabletShortestSide = 600;

class ShatibiyyahApp extends StatelessWidget {
  const ShatibiyyahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReaderTheme>(
      valueListenable: appTheme,
      builder: (context, theme, _) => MaterialApp(
        title: 'تيسير الشاطبية',
        navigatorKey: appNavigator,
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // The one theme source: the tokens (item 3.1).
        theme: tzThemeData(tzThemeFor(theme)),
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

class _BootState extends State<_Boot> with WidgetsBindingObserver {
  ReaderController? _reader;
  bool _error = false;
  StreamSubscription<ReminderTarget>? _taps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _taps?.cancel();
    super.dispose();
  }

  /// Leaving the app moves «تذكير الباب» to three days from now, on the current verse.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _reader?.reminders?.reschedule();
  }

  Future<void> _init() async {
    try {
      final reader = await bootReader();
      lockScreen?.attach(reader);
      _taps = reader.reminders?.taps.listen(_openReminder);
      if (mounted) setState(() => _reader = reader);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  /// A tapped reminder: the reader on its verse.
  void _openReminder(ReminderTarget target) {
    final reader = _reader;
    final navigator = appNavigator.currentState;
    if (reader == null || navigator == null) return;
    navigator.popUntil((r) => r.isFirst);
    reader.tapVerse(target.verse);
    appShell.currentState?.select(DockTab.matn);
  }

  /// After the splash: the tour on the first run, else the reminder that launched the app.
  Future<void> _afterSplash() async {
    _firstRun();
    final target = await _reader?.reminders?.launchTarget();
    if (target != null && mounted) _openReminder(target);
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
      onGone: _afterSplash,
      child: _reader != null
          ? AppShell(key: appShell, reader: _reader!)
          : (_error ? const _ErrorScreen() : const SizedBox.shrink()),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TaysirColors.of(context).bg,
      body: Center(
        child: Text(
          'تعذّر تحميل البيانات',
          style: TzType.title.copyWith(color: TaysirColors.of(context).text),
        ),
      ),
    );
  }
}
