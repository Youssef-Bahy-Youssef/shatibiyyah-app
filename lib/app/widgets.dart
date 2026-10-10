// lib/app/widgets.dart — the home-screen widgets' side of the app (plan 6.1, ADRs 0017, 0025).
//
// «تابع» shows the current verse and plays or pauses it. The app tells the widget
// the reader's state when it changes, at most once in five seconds: the first
// change goes out at once, and the last one of a burst goes out when the five
// seconds end, so the widget never rests on an older verse. There is no timer
// while nothing changes.
//
// The widget's taps come back as requests: ▶ and ❚❚ act on the reader as the lock
// screen's buttons do; a tap on the verse or on «تنزيل» is handed to the shell to
// open. A request made while the app was not running is taken at start.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/settings_store.dart';
import '../domain/widget_state.dart';
import '../ui/design/app_theme.dart';
import '../ui/reader/reader_controller.dart';

/// What a tap on a widget asks for.
@immutable
class WidgetRequest {
  final String name;
  final int? verse;
  const WidgetRequest.play() : name = 'play', verse = null;
  const WidgetRequest.pause() : name = 'pause', verse = null;
  const WidgetRequest.openVerse(int this.verse) : name = 'verse';
  const WidgetRequest.openDownloads() : name = 'downloads', verse = null;

  /// The request the platform sent, or null for one this build does not know.
  static WidgetRequest? parse(Object? raw) {
    if (raw is! Map) return null;
    final verse = raw['verse'];
    return switch (raw['do']) {
      'play' => const WidgetRequest.play(),
      'pause' => const WidgetRequest.pause(),
      'downloads' => const WidgetRequest.openDownloads(),
      'verse' when verse is int => WidgetRequest.openVerse(verse),
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) => other is WidgetRequest && other.name == name && other.verse == verse;
  @override
  int get hashCode => Object.hash(name, verse);
  @override
  String toString() => verse == null ? 'WidgetRequest($name)' : 'WidgetRequest($name $verse)';
}

/// The platform side of the widgets.
abstract class WidgetPort {
  /// Stores [state] (a [ResumeWidgetState] encoded) and redraws «تابع».
  Future<void> publish(String state);

  /// The requests made while the app was not running, oldest first; taking them clears them.
  Future<List<WidgetRequest>> takePending();

  /// The requests made while it runs.
  Stream<WidgetRequest> get requests;
}

/// What the widgets are told about [reader] now.
ResumeWidgetState resumeWidgetState(ReaderController reader) => ResumeWidgetState(
      verse: reader.verse,
      playing: reader.audioAvailable && reader.playing,
      audio: reader.audioAvailable,
      recording: reader.recording.id,
      theme: switch (reader.themeChoice) {
        ThemeChoice.paper => 'paper',
        ThemeChoice.night => 'night',
        ThemeChoice.auto => 'auto',
      },
      ink: reader.nightInk.id,
      rubric: reader.showRubric,
    );

class HomeWidgets {
  final WidgetPort port;
  final ReaderController reader;

  /// Opens what a tap asked to see: a verse, or the downloads.
  final void Function(WidgetRequest request) open;

  /// The least time between two publications.
  final Duration interval;

  HomeWidgets({
    required this.port,
    required this.reader,
    required this.open,
    this.interval = const Duration(seconds: 5),
  });

  String? _sent; // the state the widget has
  Timer? _quiet; // runs for [interval] after a publication; a change inside it waits for its end
  StreamSubscription<WidgetRequest>? _requests;

  Future<void> start() async {
    // What was asked while the app was not running comes first, before the reader is
    // listened to: a ▶ pressed then is part of the first state the widget is told,
    // not a second one held back for five seconds.
    try {
      final pending = await port.takePending();
      for (final request in pending) {
        await _handle(request);
      }
      // The engine reports that it plays on its stream, a turn later.
      if (pending.isNotEmpty) await Future<void>.delayed(Duration.zero);
    } catch (_) {} // no widgets on this platform
    reader.addListener(_changed);
    appThemeChoice.addListener(_changed);
    _requests = port.requests.listen(_handle);
    _changed();
  }

  void dispose() {
    reader.removeListener(_changed);
    appThemeChoice.removeListener(_changed);
    _requests?.cancel();
    _quiet?.cancel();
    _quiet = null;
  }

  void _changed() {
    if (_quiet != null) return; // the end of the five seconds publishes what is true then
    if (!_publish()) return;
    _quiet = Timer(interval, () {
      _quiet = null;
      _changed();
    });
  }

  /// Tells the widget the state now, if it differs from what it has.
  bool _publish() {
    final state = resumeWidgetState(reader).encode();
    if (state == _sent) return false;
    _sent = state;
    unawaited(port.publish(state).catchError((Object _) {})); // a widget that cannot be told is not the reader's problem
    return true;
  }

  /// The app is leaving the screen: the widget is told where the reader stands at once,
  /// since the app may be closed before the five seconds end. This happens once per
  /// leaving, not in bursts.
  void publishNow() => _publish();

  Future<void> _handle(WidgetRequest request) async {
    switch (request.name) {
      case 'play':
        if (!reader.playing) await reader.playPause();
      case 'pause':
        if (reader.playing) await reader.playPause();
      default:
        open(request);
    }
  }
}

/// The Android side: `taysir/widgets` in MainActivity and the widget's own receiver.
class PlatformWidgetPort implements WidgetPort {
  static const MethodChannel _channel = MethodChannel('taysir/widgets');
  // Not a broadcast stream: a request that arrives before [HomeWidgets.start] listens is kept.
  final StreamController<WidgetRequest> _incoming = StreamController();

  PlatformWidgetPort() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'request') return;
      final request = WidgetRequest.parse(call.arguments);
      if (request != null) _incoming.add(request);
    });
  }

  @override
  Future<void> publish(String state) => _channel.invokeMethod<void>('publish', state);

  @override
  Future<List<WidgetRequest>> takePending() async {
    final raw = await _channel.invokeListMethod<Object?>('takePending') ?? const [];
    return [for (final r in raw) ?WidgetRequest.parse(r)];
  }

  @override
  Stream<WidgetRequest> get requests => _incoming.stream;
}
