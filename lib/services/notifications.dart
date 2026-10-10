// lib/services/notifications.dart — local notifications for the reminders, over
// flutter_local_notifications. Scheduling is inexact (no exact-alarm permission):
// a reminder may come a few minutes late, which suits it. The plugin keeps what
// is scheduled across reboots (the boot receiver in AndroidManifest.xml).
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../ui/design/tokens.g.dart';

/// A notification to show at [when] (local time).
class PlannedNotification {
  final int id;
  final DateTime when;
  final String title;
  final String body;
  final String? longBody; // expanded text, when the body is cut short
  final String payload; // what a tap opens (lib/app/reminders.dart)
  const PlannedNotification(this.id, this.when, this.title, this.body, this.payload, {this.longBody});
}

/// What the reminders need of the platform; faked in tests.
abstract class NotificationPort {
  /// Sets up the plugin; [onTap] gets the payload of a tapped notification.
  Future<void> init(void Function(String payload) onTap);

  /// The payload of the notification that launched the app, if one did.
  Future<String?> launchPayload();

  /// Asks for the notification permission (Android 13+); true when granted.
  Future<bool> requestPermission();

  /// Removes every scheduled reminder (not the ones already shown).
  Future<void> cancelScheduled();

  /// Removes the notification [id], scheduled or shown.
  Future<void> cancel(int id);

  Future<void> schedule(PlannedNotification n);

  /// Shows [n] at once, ignoring its time (the debug build's «جرّب الآن»).
  Future<void> showNow(PlannedNotification n);
}

class LocalNotifications implements NotificationPort {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static final _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'app.shatibiyyah.hirz.channel.reminders',
      'التنبيهات',
      channelDescription: 'تذكير الباب',
      icon: 'ic_stat_taysir',
      color: TzColors.paper.action,
    ),
  );

  @override
  Future<void> init(void Function(String payload) onTap) async {
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC); // an unknown zone: times are still right relative to now
    }
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_taysir')),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload case final p?) onTap(p);
      },
    );
    _ready = true;
  }

  @override
  Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    return details?.didNotificationLaunchApp == true ? details?.notificationResponse?.payload : null;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> requestPermission() async {
    final android = _android;
    if (android == null) return false; // iOS is not wired yet (Q5)
    return await android.requestNotificationsPermission() ?? await android.areNotificationsEnabled() ?? false;
  }

  @override
  Future<void> cancelScheduled() async {
    if (_ready) await _plugin.cancelAllPendingNotifications();
  }

  @override
  Future<void> cancel(int id) async {
    if (_ready) await _plugin.cancel(id: id);
  }

  static NotificationDetails _detailsFor(PlannedNotification n) => n.longBody == null
      ? _details
      : NotificationDetails(
          android: AndroidNotificationDetails(
            'app.shatibiyyah.hirz.channel.reminders',
            'التنبيهات',
            channelDescription: 'تذكير الباب',
            icon: 'ic_stat_taysir',
            color: TzColors.paper.action,
            styleInformation: BigTextStyleInformation(n.longBody!),
          ),
        );

  @override
  Future<void> showNow(PlannedNotification n) async {
    if (!_ready) return;
    await _plugin.show(
      id: n.id + 500, // not the scheduled one's id
      title: n.title,
      body: n.body,
      notificationDetails: _detailsFor(n),
      payload: n.payload,
    );
  }

  @override
  Future<void> schedule(PlannedNotification n) async {
    if (!_ready) return;
    await _plugin.zonedSchedule(
      id: n.id,
      scheduledDate: tz.TZDateTime.from(n.when, tz.local),
      notificationDetails: _detailsFor(n),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: n.title,
      body: n.body,
      payload: n.payload,
    );
  }
}
