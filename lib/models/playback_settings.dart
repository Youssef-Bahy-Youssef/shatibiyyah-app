// lib/models/playback_settings.dart — option sets + persisted-state keys.
// ported from audio.js: REP_OPTS / SPEED_OPTS / PAUSE_OPTS and the K{} key map.
import 'dart:math' as math;

// ported from audio.js: export const REP_OPTS = [1,2,3,4,5,10,Infinity];
const List<double> kRepOpts = [1, 2, 3, 4, 5, 10, double.infinity];
// ported from audio.js: export const SPEED_OPTS = [0.5,0.75,1,1.25,1.5,1.75,2];
const List<double> kSpeedOpts = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
// ported from audio.js: export const PAUSE_OPTS = [0,1,2,3,5,10];
const List<int> kPauseOpts = [0, 1, 2, 3, 5, 10];

/// ported from audio.js: const K = {...} (localStorage keys, kept verbatim).
class K {
  static const mode = 'shatibiyyah_mode';
  static const chapter = 'shatibiyyah_chapter_idx';
  static const from = 'shatibiyyah_from';
  static const to = 'shatibiyyah_to';
  static const vrep = 'shatibiyyah_verse_reps';
  static const srep = 'shatibiyyah_section_reps';
  static const speed = 'shatibiyyah_speed';
  static const pause = 'shatibiyyah_pause';
  // page-viewer.js K{}
  static const night = 'shatibiyyah_night';
  static const bright = 'shatibiyyah_brightness';
  static const boxes = 'shatibiyyah_showboxes';
  // app.js keys
  static const session = 'shatibiyyah_last_session';
  static const keepControls = 'keepControlsVisible';
  static const immersiveHint = 'immersiveHintShown';
}

// ported from audio.js: repToStore() / repFromStore()
String repToStore(double v) => v == double.infinity ? 'inf' : _intStr(v);
double repFromStore(String? s, double def) {
  if (s == null) return def;
  if (s == 'inf' || s == 'Infinity') return double.infinity;
  final n = double.tryParse(s);
  return (n != null && n.isFinite) ? n : def;
}

String _intStr(double v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

double clampd(double v, double a, double b) => math.min(b, math.max(a, v));
