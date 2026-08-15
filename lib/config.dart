/// Backend location. Defaults to the Oracle Cloud deployment (see
/// speech2text/infra/terraform) -- plain HTTP for now since it's reachable
/// only by IP until a domain is pointed at it for HTTPS (see infra/README.md
/// step 4); res/xml/network_security_config.xml scopes the Android
/// cleartext-traffic exception to just this IP.
///
/// Override at build/run time for a different target, e.g.:
///   flutter run --dart-define=API_BASE_URL=http://192.168.0.107:5000    # local dev backend (see scripts/backend-start.ps1)
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000         # Android emulator, against local dev backend
///   flutter run --dart-define=API_BASE_URL=http://localhost:5000        # iOS simulator, against local dev backend
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://129.213.21.239',
  );

  static String get wsBase => baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
}
