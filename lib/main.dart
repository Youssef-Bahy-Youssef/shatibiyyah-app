// lib/main.dart — «تيسير الشاطبية».
//
// Boots the v3 reader (lib/app/reader_boot.dart) under the launch splash. Content
// comes from assets/content/content.sqlite, built by `spd app-snapshot` in
// shatibiyyah-data; the 94 manuscript pages are assets/pages/page001–094.webp.
// No recording is bundled: one plays from a file on the device. The only audio in
// the app is «بيت الافتتاح», the verse recited as it opens (ADR 0027). The theme
// (night or paper) is app-wide and switched from the tools sheet.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:audio_service/audio_service.dart';

import 'app/opening_recitation.dart';
import 'app/reader_boot.dart';
import 'app/reminders.dart';
import 'app/routes.dart';
import 'app/widgets.dart';
import 'services/audio_focus.dart';
import 'services/lock_screen.dart';
import 'services/opening_audio.dart';
import 'services/preferences_service.dart';
import 'ui/design/tokens.g.dart';
import 'data/settings_store.dart';
import 'ui/design/app_theme.dart';
import 'ui/design/components/dock.dart' show DockTab;
import 'ui/shell/app_shell.dart';
import 'ui/design/tz_theme.dart';
import 'ui/reader/reader_controller.dart';
import 'ui/shell/boot_splash.dart';
import 'ui/shell/tour_screen.dart';
import 'ui/widgets/page_viewer.dart';
import 'ui/design/taysir_colors.dart';

/// The lock-screen handler, once the platform service has started; null when it
/// could not.
Future<LockScreenHandler?> lockScreen = Future.value();

/// The app's navigator: a tapped reminder opens its verse from outside the tree.
final GlobalKey<NavigatorState> appNavigator = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Asked for now, so a headset button or a widget that started the process is
  // heard as early as before; the first frame does not wait for the answer.
  lockScreen = _startLockScreen();
  applyOrientationPolicy();
  runApp(const ShatibiyyahApp());
  // The window's size may be known only once the first frame is laid out.
  WidgetsBinding.instance.addPostFrameCallback((_) => applyOrientationPolicy());
}

/// Lock screen, notification and headset buttons. Never let an init failure here
/// blank the whole app — the in-app player works regardless.
Future<LockScreenHandler?> _startLockScreen() async {
  try {
    return await AudioService.init(
      builder: LockScreenHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'app.shatibiyyah.hirz.channel.audio',
        androidNotificationChannelName: 'تيسير الشاطبية',
        androidNotificationOngoing: true,
      ),
    );
  } catch (_) {
    return null;
  }
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

class ShatibiyyahApp extends StatefulWidget {
  const ShatibiyyahApp({super.key});

  @override
  State<ShatibiyyahApp> createState() => _ShatibiyyahAppState();
}

class _ShatibiyyahAppState extends State<ShatibiyyahApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    applyThemeChoice(appThemeChoice.value); // the splash is already in the system's palette
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// «تلقائي» follows the system as it changes, the app open or not.
  @override
  void didChangePlatformBrightness() => applyThemeChoice(appThemeChoice.value);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([appTheme, appNightInk]),
      builder: (context, _) => _app(appTheme.value),
    );
  }

  Widget _app(ReaderTheme theme) => MaterialApp(
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
        theme: tzThemeData(tzThemeFor(theme, ink: appNightInk.value)),
        // Status and navigation bar icons follow the theme: light on night, dark on paper.
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: theme == ReaderTheme.paper ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
          child: Directionality(textDirection: TextDirection.rtl, child: child!),
        ),
        home: const _Boot(),
      );
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
  HomeWidgets? _widgets;
  WidgetRequest? _openWhenShown; // a widget's tap that started the app, until the splash is gone

  /// «بيت الافتتاح»: starts under the splash and goes on over the reader (ADR 0027).
  final OpeningRecitation _opening = OpeningRecitation(JustAudioOpening());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reciteOpening();
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _taps?.cancel();
    _widgets?.dispose();
    unawaited(_opening.stop());
    super.dispose();
  }

  /// Leaving the app moves «تذكير الباب» to three days from now, on the current
  /// verse, ends the opening verse, and tells the home-screen widgets where the
  /// reader stands without waiting.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _opening.lifecycle(state);
    if (state == AppLifecycleState.paused) {
      _reader?.reminders?.reschedule();
      _widgets?.publishNow();
    }
  }

  /// The verse does not wait for the reader: only for its switch, read here from
  /// the preferences, and for the app to be on screen.
  void _reciteOpening() {
    if (Platform.isIOS) {
      AudioFocus.sessionHold = _opening.done.whenComplete(() => AudioFocus.sessionHold = null);
    }
    _opening.lifecycle(WidgetsBinding.instance.lifecycleState);
    unawaited(_opening.start(enabled: Prefs.create().then((prefs) => SettingsStore(prefs).playOpening)));
  }

  Future<void> _init() async {
    try {
      // The page the reader opens on is decoded while the rest is prepared, so the
      // splash never lifts on an empty sheet that the scan then pops into.
      Future<void>? firstPage;
      final reader = await bootReader(
        onFirstPage: (page) => firstPage = mounted ? PageViewer.warm(context, page) : null,
      );
      // A recitation takes over from the opening verse, and its switch going off ends it.
      reader.addListener(() {
        if (reader.playing || !reader.playOpening) unawaited(_opening.stop());
      });
      unawaited(lockScreen.then((handler) => handler?.attach(reader)));
      _taps = reader.reminders?.taps.listen(_openReminder);
      // The home-screen widgets (Android; iOS in plan 7.4). Started here, not after the
      // splash: the widget's ▶ starts the app with no screen, and no frame is ever drawn.
      if (Platform.isAndroid) {
        _widgets = HomeWidgets(port: PlatformWidgetPort(), reader: reader, open: _openFromWidget);
        unawaited(_widgets!.start());
      }
      await firstPage;
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
    reader.goToVerse(target.verse);
    appShell.currentState?.select(DockTab.matn);
  }

  /// A tap on a home-screen widget: the reader on its verse, or the downloads.
  void _openFromWidget(WidgetRequest request) {
    final reader = _reader;
    final navigator = appNavigator.currentState;
    if (reader == null || navigator == null || appShell.currentState == null) {
      _openWhenShown = request; // the app is still starting
      return;
    }
    navigator.popUntil((r) => r.isFirst);
    if (request.verse case final verse?) {
      // The widget shows the current verse: only a widget that is behind moves the reader.
      if (verse != reader.verse) reader.goToVerse(verse);
      appShell.currentState?.select(DockTab.matn);
    } else {
      navigator.push(MaterialPageRoute<void>(builder: (_) => AppRoute.downloads.build(reader)));
    }
  }

  /// After the splash: the tour on the first run, else what launched the app (a widget's
  /// tap, or a reminder).
  Future<void> _afterSplash() async {
    _firstRun();
    final fromWidget = _openWhenShown;
    _openWhenShown = null;
    if (fromWidget != null) _openFromWidget(fromWidget);
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
