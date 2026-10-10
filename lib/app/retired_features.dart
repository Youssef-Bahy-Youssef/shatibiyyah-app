// lib/app/retired_features.dart — what the removed features left on a device
// (ADR 0008), cleared once on the first launch after the update: the pending
// «فائدة اليوم» notifications and their settings, and the dead per-chapter
// listening progress of the JSON-era app. This is the only file that still names
// them (test/removed_features_test.dart).
import '../services/notifications.dart';
import '../services/preferences_service.dart';

/// Set once the clean-up has run.
const String kRetiredFeaturesDone = 'v2.retired_features_done';

/// The daily benefit's notifications: 14 days ahead, ids 1000–1013.
const List<int> kRetiredNotificationIds = [
  1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011, 1012, 1013, //
];

const List<String> kRetiredPrefKeys = [
  'v2.reminders.benefit', // «فائدة اليوم» on or off
  'v2.reminders.benefit_time', // its time, "HH:MM"
  'shatibiyyah_chap_prog', // per-chapter listening progress (JSON-era app)
];

/// Cancels the retired notifications and deletes the retired settings, once.
Future<void> clearRetiredFeatures(Prefs prefs, NotificationPort port) async {
  if (prefs.getString(kRetiredFeaturesDone) == '1') return;
  for (final id in kRetiredNotificationIds) {
    await port.cancel(id);
  }
  for (final key in kRetiredPrefKeys) {
    prefs.remove(key);
  }
  prefs.setString(kRetiredFeaturesDone, '1');
}
