// lib/domain/playback_plan.dart — what to play next. Pure, deterministic, no I/O.
//
// The engine asks the plan for an action, carries it out on the audio player and
// asks again when it finishes. All repeat / scope / gap / spoken-title logic lives
// here, so it is tested with plain unit tests (test/playback_plan_test.dart).
//
// The rules (ADRs 0003, 0004):
//   * each verse plays N times, then the next one; after the section's last verse
//     the section starts again from its first verse, for M rounds;
//   * the gap separates every two plays: two verses, two plays of the same verse
//     (time to recite it back), one round and the next. Nothing waits after the last;
//   * a round restarts as the section first started: with the spoken title if it
//     began from it. A verse repeat never replays a title;
//   * a jump resets both counters. Nothing else does.
// New:
//   * windows come from PlaybackWindows (cues + spoken titles), so a verse ends where
//     the next chapter's title begins;
//   * spoken titles are played when crossing into a chapter, or skipped by a jump;
//   * a jump to a verse starts `preRollMs` early (never inside a title).
import 'playback_windows.dart';

/// How far playback runs («الاستماع إلى؟»): a verse, to the end of the chapter,
/// to the end of the poem, or a selected range.
class PlaybackScope {
  final int fromVerse;
  final int toVerse;

  /// Start at the chapter's spoken title (a chapter played from its heading).
  final bool fromChapterTitle;
  const PlaybackScope(this.fromVerse, this.toVerse, {this.fromChapterTitle = false})
      : assert(fromVerse <= toVerse);
}

class PlaybackSettings {
  /// Plays of each verse; null = repeat forever.
  final int? verseRepeats;

  /// Plays of the whole scope; null = repeat forever.
  final int? sectionRepeats;

  /// Silence between two different verses.
  final int gapMs;

  /// Play the spoken chapter titles when crossing into a chapter.
  final bool playTitles;

  /// Lead before a verse when playback jumps to it (ADR 0005): 50 ms, so the
  /// first syllable is whole and nothing of the verse before is heard again.
  final int preRollMs;

  const PlaybackSettings({
    this.verseRepeats = 1,
    this.sectionRepeats = 1,
    this.gapMs = 0,
    this.playTitles = true,
    this.preRollMs = 50,
  });

  static const _keep = Object();

  /// A copy with some fields replaced. Repeats are nullable (null = ∞), so an
  /// omitted argument is told apart from an explicit null.
  PlaybackSettings copyWith({
    Object? verseRepeats = _keep,
    Object? sectionRepeats = _keep,
    int? gapMs,
    bool? playTitles,
    int? preRollMs,
  }) =>
      PlaybackSettings(
        verseRepeats: identical(verseRepeats, _keep) ? this.verseRepeats : verseRepeats as int?,
        sectionRepeats: identical(sectionRepeats, _keep) ? this.sectionRepeats : sectionRepeats as int?,
        gapMs: gapMs ?? this.gapMs,
        playTitles: playTitles ?? this.playTitles,
        preRollMs: preRollMs ?? this.preRollMs,
      );
}

sealed class PlanAction {
  const PlanAction();
}

/// Play [fromMs, toMs). The audible verse is [verse]; before [titleEndMs] (if set)
/// its chapter's spoken title plays. [continuous] means the player is already at
/// [fromMs] (the previous action ended there), so no seek is needed.
class PlayRange extends PlanAction {
  final int verse;
  final int fromMs;
  final int toMs;
  final int? titleEndMs;
  final bool continuous;
  const PlayRange(this.verse, this.fromMs, this.toMs, {this.titleEndMs, this.continuous = false});
  @override
  String toString() =>
      'PlayRange(v$verse, $fromMs→$toMs${titleEndMs != null ? ', title→$titleEndMs' : ''}${continuous ? ', cont' : ''})';
}

/// Stay silent for [ms] (the gap between verses), then ask again.
class Silence extends PlanAction {
  final int ms;
  const Silence(this.ms);
  @override
  String toString() => 'Silence($ms)';
}

/// The scope and its repeats are done.
class Finished extends PlanAction {
  const Finished();
  @override
  String toString() => 'Finished';
}

class PlaybackPlan {
  final PlaybackWindows windows;
  PlaybackSettings settings;
  PlaybackScope scope;

  int _verse;
  int _verseRepsDone = 0; // completed plays of the current verse
  int _sectionRepsDone = 0; // completed passes over the scope
  _After _afterGap = _After.nothing; // what the silence in hand is before
  int? _lastEndMs;

  PlaybackPlan(this.windows, this.scope, this.settings) : _verse = scope.fromVerse;

  int get verse => _verse;

  /// 1-based counters for the UI («البيت ٢/٥», the section ring).
  int get verseRepetition => _verseRepsDone + 1;
  int get sectionRepetition => _sectionRepsDone + 1;

  /// First action: play from [verse] (inside the scope), or from the scope's start.
  PlanAction start([int? verse]) {
    _verseRepsDone = 0;
    _sectionRepsDone = 0;
    _afterGap = _After.nothing;
    final v = (verse ?? scope.fromVerse).clamp(scope.fromVerse, scope.toVerse);
    return _playFromStartOf(v, atScopeStart: verse == null || v == scope.fromVerse);
  }

  /// The current action finished (a PlayRange reached its end, or a Silence elapsed).
  PlanAction advance() {
    final after = _afterGap;
    if (after != _After.nothing) {
      _afterGap = _After.nothing;
      return switch (after) {
        _After.sameVerse => _replay(_verse),
        _After.nextVerse => _enterNextVerse(),
        _ => _playFromStartOf(scope.fromVerse, atScopeStart: true),
      };
    }
    _verseRepsDone++;
    final repeats = settings.verseRepeats;
    if (repeats == null || _verseRepsDone < repeats) {
      return _gapBefore(_After.sameVerse) ?? _replay(_verse);
    }
    _verseRepsDone = 0;
    if (_verse < scope.toVerse) {
      return _gapBefore(_After.nextVerse) ?? _enterNextVerse();
    }
    _sectionRepsDone++;
    final sections = settings.sectionRepeats;
    if (sections == null || _sectionRepsDone < sections) {
      return _gapBefore(_After.nextRound) ?? _playFromStartOf(scope.fromVerse, atScopeStart: true);
    }
    _sectionRepsDone = 0;
    return const Finished();
  }

  /// The gap, if there is one, before [then].
  PlanAction? _gapBefore(_After then) {
    if (settings.gapMs <= 0) return null;
    _afterGap = then;
    return Silence(settings.gapMs);
  }

  /// A user jump (tap on a verse, next/previous): both counters start again.
  PlanAction jumpTo(int verse) {
    _verseRepsDone = 0;
    _sectionRepsDone = 0;
    _afterGap = _After.nothing;
    return _playFromStartOf(verse.clamp(scope.fromVerse, scope.toVerse), atScopeStart: false);
  }

  PlanAction _replay(int v) {
    _lastEndMs = windows.verseEnd(v);
    return PlayRange(v, windows.seekStart(v, preRollMs: settings.preRollMs), _lastEndMs!);
  }

  PlanAction _playFromStartOf(int v, {required bool atScopeStart}) {
    _verse = v;
    final end = windows.verseEnd(v);
    if (atScopeStart && scope.fromChapterTitle && settings.playTitles) {
      final start = windows.chapterStart(v);
      _lastEndMs = end;
      return PlayRange(v, start, end, titleEndMs: start < windows.cue(v) ? windows.cue(v) : null);
    }
    _lastEndMs = end;
    return PlayRange(v, windows.seekStart(v, preRollMs: settings.preRollMs), end);
  }

  PlanAction _enterNextVerse() {
    final previousEnd = _lastEndMs;
    final next = _verse + 1;
    _verse = next;
    final end = windows.verseEnd(next);
    _lastEndMs = end;
    final hasTitle = windows.titleFollows(next - 1);
    if (hasTitle && settings.playTitles) {
      // The title fills [end(v), cue(v+1)); play it straight on.
      final from = windows.verseEnd(next - 1);
      return PlayRange(next, from, end, titleEndMs: windows.cue(next), continuous: from == previousEnd);
    }
    final from = windows.cue(next);
    return PlayRange(next, from, end, continuous: from == previousEnd);
  }
}

/// What comes after the silence between two plays.
enum _After { nothing, sameVerse, nextVerse, nextRound }
