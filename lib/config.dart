/// Backend location. Override at build/run time with:
///   flutter run --dart-define=API_BASE_URL=http://192.168.x.x:5000
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://rapexapi.nodexdata.click',
  );

  static String get wsBase => baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
}
