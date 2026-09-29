// lib/services/preferences_service.dart — SharedPreferences wrapper that mirrors the
// synchronous localStorage getLS/setLS pattern used across the JS modules. Everything is
// stored as a string (exactly like localStorage), loaded once at boot, then read
// synchronously; writes are fire-and-forget.
import 'package:shared_preferences/shared_preferences.dart';

class Prefs {
  final SharedPreferences _sp;
  Prefs._(this._sp);

  static Future<Prefs> create() async =>
      Prefs._(await SharedPreferences.getInstance());

  /// ported from getLS(k, def) used in audio.js / page-viewer.js
  String getLS(String k, String def) => _sp.getString(k) ?? def;

  /// ported from setLS(k, v)
  void setLS(String k, String v) {
    _sp.setString(k, v);
  }

  String? getString(String k) => _sp.getString(k);
  void setString(String k, String v) => _sp.setString(k, v);
}
