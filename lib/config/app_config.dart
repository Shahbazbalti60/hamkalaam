import 'package:shared_preferences/shared_preferences.dart';

/// The address of the HamKalaam server (the Flask backend).
///
/// The address can be changed inside the app (Sign In screen -> server icon)
/// and is remembered on the phone, so changing network (home Wi-Fi,
/// university Wi-Fi, PC hotspot) needs no rebuild.
///
/// Find the PC's address with `ipconfig` in PowerShell (IPv4 Address under
/// the Wi-Fi adapter). Use  http://<that address>:5000
class AppConfig {
  /// Used until another address is saved.
  static const String defaultHost = 'http://192.168.100.58:5000';

  static const String _key = 'server_host';

  /// The address in use right now (every service reads this).
  static String apiHost = defaultHost;

  /// Reads the saved address. Call once when the app starts.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved != null && saved.trim().isNotEmpty) apiHost = saved.trim();
    } catch (_) {
      // keep the default
    }
  }

  /// Turns what the person typed into a clean address:
  /// "192.168.1.25" -> "http://192.168.1.25:5000".
  static String normalise(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return defaultHost;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    final noScheme = s.replaceFirst(RegExp(r'^https?://'), '');
    if (!noScheme.contains(':') && s.startsWith('http://')) {
      s = '$s:5000';
    }
    return s;
  }

  static Future<void> save(String host) async {
    apiHost = normalise(host);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, apiHost);
    } catch (_) {}
  }

  static Future<void> reset() async {
    apiHost = defaultHost;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
