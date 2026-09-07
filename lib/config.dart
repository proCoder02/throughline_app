/// Backend location. Defaults to the Oracle Cloud deployment over real
/// HTTPS -- as of 2026-08-30, `129-213-21-239.sslip.io` (free wildcard DNS
/// that resolves straight to the instance's own IP, no domain purchase
/// needed) has a real Let's Encrypt certificate via nginx/certbot on that
/// box. This exists specifically because Swiggy MCP's OAuth (Cognitive
/// Commerce, see SWIGGY_MCP_COGNITIVE_COMMERCE_PLAN.md) requires a real
/// https:// redirect URI in production -- a bare IP over plain HTTP can't
/// complete that login at all. The old bare-IP HTTP address still works
/// unchanged for anything else (nginx serves both), so this is additive,
/// not a breaking change to the backend itself.
///
/// Override at build/run time for a different target, e.g.:
///   flutter run --dart-define=API_BASE_URL=http://192.168.0.107:5000    # local dev backend (see scripts/backend-start.ps1)
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000         # Android emulator, against local dev backend
///   flutter run --dart-define=API_BASE_URL=http://localhost:5000        # iOS simulator, against local dev backend
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://129-213-21-239.sslip.io',
  );

  static String get wsBase => baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
}
