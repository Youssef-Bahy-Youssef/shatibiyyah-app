// lib/app/reader_boot.dart — builds the v3 reader: content, player, personal data, session.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/app_content.dart';
import '../data/legacy_adapter.dart';
import '../data/legacy_prefs.dart';
import '../data/settings_store.dart';
import '../data/user_store.dart';
import '../domain/playback_plan.dart';
import '../models/playback_settings.dart' show K;
import '../services/device_storage.dart';
import '../services/background_transfer.dart';
import '../services/download_manager.dart';
import '../services/notifications.dart';
import '../services/preferences_service.dart';
import '../ui/commentary/commentary_screen.dart';
import '../ui/reader/reader_controller.dart';
import '../ui/widgets/page_viewer.dart';
import 'audio_library.dart';
import 'app_update.dart';
import 'personal_data.dart';
import 'rating.dart';
import 'reminders.dart';

/// The verse the reader was on (restored at launch).
const String kSessionVerse = 'v2.session.verse';

/// Builds the reader. [supportDir] is where the app keeps its files (the
/// platform's, unless a test gives one).
Future<ReaderController> bootReader({Directory? supportDir}) async {
  // What needs nothing from one another starts together: the bundled content, the
  // preferences, the student's own data and the download service each wait on a
  // different part of the platform, so the launch takes the longest of them, not
  // their sum.
  final files = supportDir == null ? getApplicationSupportDirectory() : Future.value(supportDir);
  final (support, content, prefs, user, background) = await (
    files,
    files.then((dir) => AppContent.open(supportDir: dir)),
    Prefs.create(),
    files.then((dir) => UserStore.open(directory: dir.path)),
    _startBackgroundTransfer(),
  ).wait;
  migrateLegacyPrefs(prefs, content.matn);

  final library = AudioLibrary(
    content: content,
    prefs: prefs,
    downloads: DownloadManager(
      supportDir: support,
      freeBytes: deviceFreeBytes,
      onUnmeteredNetwork: deviceOnUnmeteredNetwork,
      online: deviceOnline,
      transfer: background,
    ),
  );
  final personal = PersonalData(user);
  // The bookmarks and notes are read while the recordings on the device are looked at.
  await (library.refresh(), personal.load()).wait;
  if (background != null) {
    background.onUnattendedComplete = library.backgroundFinished;
    // A download still running since before the app was closed: show it again.
    for (final r in library.recordings) {
      // A paused one stays paused until «متابعة».
      if (!library.isOnDevice(r) &&
          !library.isPaused(r) &&
          await background.isActive(library.downloads.partFileFor(r))) {
        unawaited(library.download(r));
      }
    }
  }
  final recording = library.current;
  final windows = await content.windowsOrNull(recording); // null: no audio for an unusable one (F-41)

  final initial = _restoreVerse(prefs, content.matn.lastVerse);
  // The notifications are set up while the player opens the recording. Until
  // there is a reader, its verse is the one it will open on.
  ReaderController? shown;
  final reminders = Reminders(
    prefs: prefs,
    port: LocalNotifications(),
    content: content,
    verse: () => shown?.verse ?? initial,
  );
  // No notifications on this platform: the reader works without them.
  final remindersStarted = reminders.start().then((_) => true, onError: (Object _) => false);

  final chapter = content.matn.chapterOfVerse(initial);
  final engine = windows == null
      ? null
      : await library.openCurrent(
          PlaybackPlan(windows, PlaybackScope(chapter.fromVerse, chapter.toVerse), const PlaybackSettings()),
        );

  final viewer = PageViewerController(legacyData(content, windows), prefs);
  final reader = shown = ReaderController(
    content: content,
    recording: recording,
    viewer: viewer,
    engine: engine,
    user: user,
    store: SettingsStore(prefs),
    initialVerse: initial,
  );
  library.attach(reader);
  final rating = RatingPrompt(prefs: prefs, port: InAppReviewPort());
  reader.rating = rating;
  if (Platform.isAndroid) {
    final update = AppUpdate(PlayUpdatePort());
    reader.update = update;
    unawaited(update.check()); // the banner appears when Play answers
  }
  reader.personal = personal;
  CommentaryScreen.onOpened = () => unawaited(rating.used());
  void ribbons() => viewer.setRibbons({for (final e in personal.ribbons.entries) e.key: e.value.index});
  personal.addListener(ribbons);
  ribbons();
  if (await remindersStarted) reader.reminders = reminders;
  var saved = initial;
  reader.addListener(() {
    if (reader.verse != saved) {
      saved = reader.verse;
      prefs.setString(kSessionVerse, '$saved');
    }
  });
  return reader;
}

/// Downloads carry on in the background where the platform allows it (Android);
/// elsewhere, or if the service does not start, they run while the app runs.
Future<BackgroundTransfer?> _startBackgroundTransfer() async {
  if (!Platform.isAndroid) return null;
  try {
    return await BackgroundTransfer.start();
  } catch (_) {
    return null;
  }
}

int _restoreVerse(Prefs prefs, int lastVerse) {
  final v2 = int.tryParse(prefs.getString(kSessionVerse) ?? '');
  if (v2 != null) return v2.clamp(1, lastVerse);
  try {
    final legacy = json.decode(prefs.getString(K.session) ?? '') as Map<String, dynamic>;
    return ((legacy['verseId'] as num?)?.toInt() ?? 1).clamp(1, lastVerse);
  } catch (_) {
    return 1;
  }
}
