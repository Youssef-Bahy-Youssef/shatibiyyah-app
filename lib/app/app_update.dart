// lib/app/app_update.dart — «إصدار جديد» (features-v3 app-update-and-review): Google
// Play's in-app update. Checked once per launch; when Play offers an update the
// home screen shows a banner (and only the home screen). «تحديث» hands over to
// Play's update screen; «إخفاء» hides the banner until the next launch. A build
// not installed from Play (debug, side-loaded) simply has no banner.
import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// The platform's update service; faked in tests.
abstract class UpdatePort {
  /// Whether the store has a newer version this device can install now.
  Future<bool> available();

  /// Starts the store's update flow.
  Future<void> update();
}

class PlayUpdatePort implements UpdatePort {
  bool _immediate = true;

  @override
  Future<bool> available() async {
    final info = await InAppUpdate.checkForUpdate();
    _immediate = info.immediateUpdateAllowed;
    return info.updateAvailability == UpdateAvailability.updateAvailable &&
        (info.immediateUpdateAllowed || info.flexibleUpdateAllowed);
  }

  @override
  Future<void> update() async {
    if (_immediate) {
      await InAppUpdate.performImmediateUpdate();
    } else if (await InAppUpdate.startFlexibleUpdate() == AppUpdateResult.success) {
      await InAppUpdate.completeFlexibleUpdate(); // installs and restarts the app
    }
  }
}

class AppUpdate extends ChangeNotifier {
  final UpdatePort port;
  AppUpdate(this.port);

  bool _available = false;
  bool _dismissed = false;

  /// Whether the banner shows.
  bool get showBanner => _available && !_dismissed;

  Future<void> check() async {
    try {
      _available = await port.available();
    } catch (_) {
      _available = false; // not from Play, no network: no banner, no error
    }
    notifyListeners();
  }

  Future<void> update() async {
    try {
      await port.update();
    } catch (_) {
      // The user backed out of Play's screen or it failed: the banner stays.
    }
  }

  void dismiss() {
    _dismissed = true;
    notifyListeners();
  }
}
