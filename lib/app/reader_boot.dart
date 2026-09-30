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

Future<ReaderController> bootReader() async {
  final content = await AppContent.open();
  final prefs = await Prefs.create();
  migrateLegacyPrefs(prefs, content.matn);
  final support = await getApplicationSupportDirectory();

  final user = await UserStore.open(directory: support.path);
  // Downloads carry on in the background where the platform allows it (Android);
  // elsewhere, or if the service does not start, they run while the app runs.
  BackgroundTransfer? background;
  if (Platform.isAndroid) {
    try {
      background = await BackgroundTransfer.start();
    } catch (_) {}
  }
  final library = AudioLibrary(
    content: content,
    prefs: prefs,
    user: user,
    downloads: DownloadManager(
      supportDir: support,
      freeBytes: deviceFreeBytes,
      onUnmeteredNetwork: deviceOnUnmeteredNetwork,
      transfer: background,
    ),
  );
  await library.refresh();
  if (background != null) {
    background.onUnattendedComplete = library.backgroundFinished;
    // A download still running since before the app was closed: show it again.
    for (final r in library.recordings) {
      if (!library.isOnDevice(r) && await background.isActive(library.downloads.partFileFor(r))) {
        unawaited(library.download(r));
      }
    }
  }
  final recording = library.current;
  final windows = await content.windowsFor(recording);

  final initial = _restoreVerse(prefs, content.matn.lastVerse);
  final chapter = content.matn.chapterOfVerse(initial);
  final engine = await library.openCurrent(
    PlaybackPlan(windows, PlaybackScope(chapter.fromVerse, chapter.toVerse), const PlaybackSettings()),
  );

  final viewer = PageViewerController(legacyData(content, windows), prefs);
  final reader = ReaderController(
    content: content,
    recording: recording,
    viewer: viewer,
    engine: engine,
    user: user,
    store: SettingsStore(prefs),
    initialVerse: initial,
  );
  library.attach(reader);
  reader.rating = RatingPrompt(prefs: prefs, port: InAppReviewPort());
  if (Platform.isAndroid) {
    final update = AppUpdate(PlayUpdatePort());
    reader.update = update;
    unawaited(update.check()); // the banner appears when Play answers
  }
  final personal = PersonalData(user);
  await personal.load();
  reader.personal = personal;
  CommentaryScreen.onRead = personal.logCommentary;
  void ribbons() => viewer.setRibbons(personal.ribbons);
  personal.addListener(ribbons);
  ribbons();
  final reminders = Reminders(prefs: prefs, port: LocalNotifications(), content: content, verse: () => reader.verse);
  try {
    await reminders.start();
    reader.reminders = reminders;
  } catch (_) {} // no notifications on this platform: the reader works without them
  var saved = initial;
  reader.addListener(() {
    if (reader.verse != saved) {
      saved = reader.verse;
      prefs.setString(kSessionVerse, '$saved');
    }
  });
  return reader;
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
