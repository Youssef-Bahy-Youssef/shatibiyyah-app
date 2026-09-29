// lib/app/reader_boot.dart — builds the v3 reader: content, player, personal data, session.
import 'dart:convert';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/app_content.dart';
import '../data/legacy_adapter.dart';
import '../data/legacy_prefs.dart';
import '../data/recording_repository.dart';
import '../data/user_store.dart';
import '../domain/playback_engine.dart';
import '../domain/playback_plan.dart';
import '../models/playback_settings.dart' show K;
import '../services/just_audio_port.dart';
import '../services/preferences_service.dart';
import '../ui/reader/reader_controller.dart';
import '../ui/widgets/page_viewer.dart';

/// The verse the reader was on (restored at launch).
const String kSessionVerse = 'v2.session.verse';

Future<ReaderController> bootReader() async {
  final content = await AppContent.open();
  final prefs = await Prefs.create();
  migrateLegacyPrefs(prefs, content.matn);
  final support = await getApplicationSupportDirectory();

  final recording = content.recordings.defaultRecording;
  final windows = await content.windowsFor(recording);
  final user = await UserStore.open(directory: support.path);

  final initial = _restoreVerse(prefs, content.matn.lastVerse);
  final chapter = content.matn.chapterOfVerse(initial);
  final plan = PlaybackPlan(windows, PlaybackScope(chapter.fromVerse, chapter.toVerse), const PlaybackSettings());

  PlaybackEngine? engine;
  final file = File(p.join(support.path, RecordingRepository.localFileName(recording)));
  if (await file.exists() && await file.length() == recording.audioBytes) {
    final port = JustAudioPort(AudioPlayer());
    await port.load(
      file.path,
      MediaItem(id: recording.id, title: 'تيسير الشاطبية', album: 'تيسير الشاطبية', artist: recording.reciterName),
    );
    engine = PlaybackEngine(port, plan, onVerseCompleted: ReaderController.listenRecorder(user, recording));
  }

  final viewer = PageViewerController(legacyData(content, windows), prefs);
  final reader = ReaderController(
    content: content,
    recording: recording,
    windows: windows,
    viewer: viewer,
    engine: engine,
    user: user,
    settings: plan.settings,
    initialVerse: initial,
  );
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
