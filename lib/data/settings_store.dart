// lib/data/settings_store.dart — the v3 reader's settings, persisted under `v2.*` keys.
//
// Option sets are the v3 ones (features-v3: advanced-control-cards, playback-speed):
// verse repeat 1/3/5/∞, section repeat 1/2/3/5/∞ (∞ kept from the old app, plan Q9),
// gap off/1/2/3 s, speed 0.75–1.5 remembered per reciter. Page night mode and
// brightness stay with the page viewer.
import '../services/preferences_service.dart';

/// The palette on screen: night (`dark`) or paper.
enum ReaderTheme { dark, paper }

/// «المظهر»: paper, night, or whichever the system is in (`auto`, a new install's).
enum ThemeChoice { paper, night, auto }

/// The night ink's preference (ADR 0020; the same name as tokens.json's `preference`).
const String kNightInkPref = 'v2.night.page_accent';

const List<int?> kVerseRepeatOptions = [1, 2, 3, 4, 5, null]; // null = ∞
const List<int?> kSectionRepeatOptions = [1, 2, 3, 4, 5, null];
const List<int> kGapOptionsMs = [0, 1000, 2000, 3000];
const List<double> kSpeedOptions = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
const List<double> kTextScaleOptions = [0.75, 1, 1.25, 1.5, 1.75, 2];

class SettingsStore {
  final Prefs prefs;
  SettingsStore(this.prefs);

  static int? _repeat(String? raw, List<int?> options, int? fallback) {
    if (raw == 'inf') return null; // only the explicit value means ∞
    final n = int.tryParse(raw ?? '');
    // `null` is itself an option (∞), so an absent or unparsable value must not reach contains().
    return n != null && options.contains(n) ? n : fallback;
  }

  static String _repeatString(int? n) => n == null ? 'inf' : '$n';

  /// Stored as `paper`, `dark` (night; the name the two-theme app wrote) or `auto`.
  ThemeChoice get themeChoice => switch (prefs.getString('v2.theme')) {
        'paper' => ThemeChoice.paper,
        'dark' => ThemeChoice.night,
        _ => ThemeChoice.auto,
      };
  set themeChoice(ThemeChoice c) => prefs.setString('v2.theme', c == ThemeChoice.night ? 'dark' : c.name);

  /// The chosen night ink's id as stored: the reader of it decides what an
  /// unknown one means (jade; `nightInkById`).
  String? get nightInk => prefs.getString(kNightInkPref);
  set nightInk(String? id) => id == null ? prefs.remove(kNightInkPref) : prefs.setString(kNightInkPref, id);

  bool get textMode => prefs.getString('v2.reader.view') == 'text';
  set textMode(bool on) => prefs.setString('v2.reader.view', on ? 'text' : 'scan');

  double get textScale {
    final v = double.tryParse(prefs.getString('v2.text.scale') ?? '');
    return v != null && v >= 0.75 && v <= 2 ? v : 1;
  }

  set textScale(double v) => prefs.setString('v2.text.scale', '${v.clamp(0.75, 2)}');

  int? get verseRepeats => _repeat(prefs.getString('v2.repeat.verse'), kVerseRepeatOptions, 1);
  set verseRepeats(int? n) => prefs.setString('v2.repeat.verse', _repeatString(n));

  int? get sectionRepeats => _repeat(prefs.getString('v2.repeat.section'), kSectionRepeatOptions, 1);
  set sectionRepeats(int? n) => prefs.setString('v2.repeat.section', _repeatString(n));

  int get gapMs {
    final v = int.tryParse(prefs.getString('v2.gap_ms') ?? '');
    return kGapOptionsMs.contains(v) ? v! : 0;
  }

  set gapMs(int v) => prefs.setString('v2.gap_ms', '$v');

  bool get playTitles => prefs.getString('v2.titles.play') != '0';
  set playTitles(bool on) => prefs.setString('v2.titles.play', on ? '1' : '0');

  /// Speed is remembered per reciter (features-v3 playback-speed).
  double speedFor(String recordingId) {
    final v = double.tryParse(prefs.getString('v2.speed.$recordingId') ?? '');
    return kSpeedOptions.contains(v) ? v! : 1;
  }

  void setSpeedFor(String recordingId, double v) => prefs.setString('v2.speed.$recordingId', '$v');

  /// The tablet split (plan P8): the page's share of the width, kept per orientation.
  double splitFraction({required bool landscape}) {
    final v = double.tryParse(prefs.getString('v2.split.${landscape ? 'landscape' : 'portrait'}') ?? '');
    return v == null ? kSplitDefault : v.clamp(kSplitMin, kSplitMax).toDouble();
  }

  void setSplitFraction(double v, {required bool landscape}) =>
      prefs.setString('v2.split.${landscape ? 'landscape' : 'portrait'}', v.clamp(kSplitMin, kSplitMax).toStringAsFixed(3));

  /// The split panel's text size («حجم الخط»), one of [kSplitTextScales].
  double get splitTextScale {
    final v = double.tryParse(prefs.getString('v2.split.text_scale') ?? '');
    return kSplitTextScales.contains(v) ? v! : 1;
  }

  set splitTextScale(double v) => prefs.setString('v2.split.text_scale', '$v');
}

/// The page's share of the width in the split: the divider moves between 30 % and 70 %.
const double kSplitMin = 0.3;
const double kSplitMax = 0.7;
const double kSplitDefault = 0.45;
const List<double> kSplitTextScales = [1, 1.15, 1.3];

/// The next value in [options] after [current] (wrapping), for tap-to-cycle cards.
T cycle<T>(List<T> options, T current) => options[(options.indexOf(current) + 1) % options.length];
