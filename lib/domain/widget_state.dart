// lib/domain/widget_state.dart — what the home-screen widgets are told (ADRs 0017, 0025).
//
// Plain Dart, so the iOS widgets (plan 7.4) are told the same thing. It is the
// reader's own state only. The verse's text, its chapter and the reciter's name are
// content: a widget reads them from the content snapshot itself (ADR 0001), so it
// can draw a verse while the app is not running.
import 'dart:convert';

/// What the widgets show of the reader: «تابع» the verse and its recitation, both of
/// them the theme, «بيت اليوم» the rubric.
class ResumeWidgetState {
  /// The current verse.
  final int verse;

  /// Whether it is being recited now.
  final bool playing;

  /// Whether the chosen recording can play (it is on the device). Without it the
  /// widget offers «تنزيل» in place of ▶.
  final bool audio;

  /// The chosen recording's id.
  final String recording;

  /// «المظهر»: `paper`, `night`, or `auto` (the widget follows the system).
  final String theme;

  /// The night ink's id (ADR 0020): the rubric of «بيت اليوم» at night.
  final String ink;

  /// Whether reader names and symbols are set in the rubric ink («إبراز رموز القراء وأسمائهم»).
  final bool rubric;

  const ResumeWidgetState({
    required this.verse,
    required this.playing,
    required this.audio,
    required this.recording,
    required this.theme,
    required this.ink,
    required this.rubric,
  });

  Map<String, Object?> toJson() => {
        'v': 1,
        'verse': verse,
        'playing': playing,
        'audio': audio,
        'recording': recording,
        'theme': theme,
        'ink': ink,
        'rubric': rubric,
      };

  /// The form that is published and compared: two equal states encode alike.
  String encode() => json.encode(toJson());
}
