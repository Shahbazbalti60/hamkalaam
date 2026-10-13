/// Single place to switch between testing environments.
///
/// - Chrome/web testing (same machine as the Flask backend):
///     'http://127.0.0.1:5000'
/// - Physical phone testing (phone on the SAME WiFi network as the
///   laptop running the backend):
///     'http://<laptop-LAN-IP>:5000'   e.g. 'http://192.168.100.58:5000'
///
/// Find your laptop's current LAN IP with `ipconfig` in PowerShell —
/// look for "IPv4 Address" under your WiFi adapter. It can change
/// between sessions/networks, so re-check it if phone requests
/// suddenly stop connecting.
class AppConfig {
  static const String apiHost = 'http://127.0.0.1:5000';
}