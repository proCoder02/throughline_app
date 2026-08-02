/// Backend location. Defaults to the local dev backend (see
/// scripts/backend-start.ps1 in the speech2text repo) since production on
/// AWS is being decommissioned -- dev now happens entirely against local.
///
/// 192.168.0.107 is this dev machine's current LAN IP, required for a
/// physical device over Wi-Fi (what's actually been used for testing this
/// app) -- it can change if the machine reconnects to Wi-Fi or DHCP
/// reassigns it, so re-check with `ipconfig` if requests start failing.
///
/// Override at build/run time for a different target, e.g.:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000       # Android emulator
///   flutter run --dart-define=API_BASE_URL=http://localhost:5000      # iOS simulator
///   flutter run --dart-define=API_BASE_URL=https://rapexapi.nodexdata.click  # old prod, while it still exists
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.0.107:5000',
  );

  static String get wsBase => baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
}
